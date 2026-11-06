"""Ephemeral TLS material and independent TLS peers for the plan 05 TLS checks.

Everything is generated per run with the system `openssl` into a temporary
directory: a test CA, a CA-signed identity for localhost/127.0.0.1 (used as the
server certificate and as the client certificate), and three deliberately bad
server certificates (self-signed/untrusted, expired, wrong host). No key
material is committed. The peers use Python's maintained `ssl` module, so the
Java side always talks to an independent TLS implementation.
"""

from __future__ import annotations

import socket
import ssl
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path

PASSWORD = "changeit"


@dataclass(frozen=True)
class TlsMaterial:
    directory: Path
    ca: Path
    identity_cert: Path
    identity_key: Path
    untrusted_cert: Path
    untrusted_key: Path
    expired_cert: Path
    wrong_host_cert: Path
    trust_store: Path
    key_store: Path


def _openssl(*args: str, cwd: Path) -> None:
    subprocess.run(["openssl", *args], cwd=cwd, check=True, capture_output=True)


def _signed(directory: Path, name: str, subject: str, extensions: str, *dates: str) -> Path:
    _openssl("req", "-new", "-key", "leaf.key", "-subj", subject, "-out", f"{name}.csr", cwd=directory)
    (directory / f"{name}.ext").write_text(extensions, encoding="utf-8")
    _openssl("x509", "-req", "-in", f"{name}.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
             "-out", f"{name}.pem", "-extfile", f"{name}.ext", *dates, cwd=directory)
    return directory / f"{name}.pem"


def generate(directory: Path, keytool: str) -> TlsMaterial:
    directory.mkdir(parents=True, exist_ok=True)
    _openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem", "-days", "2",
             "-subj", "/CN=BendJVM Test CA", "-addext", "basicConstraints=critical,CA:TRUE",
             "-addext", "keyUsage=critical,keyCertSign,cRLSign", cwd=directory)
    _openssl("genrsa", "-out", "leaf.key", "2048", cwd=directory)
    usage = "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n"
    identity = _signed(directory, "identity", "/CN=localhost",
                       usage + "extendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n", "-days", "2")
    wrong = _signed(directory, "wrong", "/CN=wrong.example",
                    usage + "extendedKeyUsage=serverAuth\nsubjectAltName=DNS:wrong.example\n", "-days", "2")
    expired = _signed(directory, "expired", "/CN=localhost",
                      usage + "extendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n",
                      "-not_before", "20200101000000Z", "-not_after", "20200201000000Z")
    _openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "untrusted.key", "-out", "untrusted.pem",
             "-days", "2", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1", cwd=directory)
    # The reference JDK reads the same material from PKCS12 stores.
    _openssl("pkcs12", "-export", "-in", "identity.pem", "-inkey", "leaf.key", "-certfile", "ca.pem",
             "-name", "identity", "-out", "identity.p12", "-passout", f"pass:{PASSWORD}", cwd=directory)
    subprocess.run([keytool, "-importcert", "-noprompt", "-alias", "ca", "-file", "ca.pem", "-keystore", "trust.p12",
                    "-storetype", "PKCS12", "-storepass", PASSWORD], cwd=directory, check=True, capture_output=True)
    return TlsMaterial(directory, directory / "ca.pem", identity, directory / "leaf.key",
                       directory / "untrusted.pem", directory / "untrusted.key", expired, wrong,
                       directory / "trust.p12", directory / "identity.p12")


class Peer:
    """A TLS echo server on its own thread: answers each line "ping" with "pong"."""

    def __init__(self, cert: Path, key: Path, client_ca: Path | None = None):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(cert), str(key))
        if client_ca is not None:
            context.verify_mode = ssl.CERT_REQUIRED
            context.load_verify_locations(str(client_ca))
        self.context = context
        self.listener = socket.create_server(("127.0.0.1", 0))
        self.port = self.listener.getsockname()[1]
        self.closed = False
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self) -> None:
        while not self.closed:
            try:
                connection, _ = self.listener.accept()
            except OSError:
                return
            threading.Thread(target=self._echo, args=(connection,), daemon=True).start()

    def _echo(self, connection: socket.socket) -> None:
        try:
            connection.settimeout(30)
            with self.context.wrap_socket(connection, server_side=True) as tls:
                data = b""
                while not data.endswith(b"\n"):
                    chunk = tls.recv(64)
                    if not chunk:
                        return
                    data += chunk
                tls.sendall(b"pong\n")
        except (OSError, ssl.SSLError):
            connection.close()

    def close(self) -> None:
        self.closed = True
        self.listener.close()


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def connect_clients(port: int, material: TlsMaterial, results: list[str], deadline: float = 120.0) -> None:
    """Connects to a Java TLS server requiring client auth: first without a
    client certificate (must be refused), then with one (must be served)."""
    start = time.monotonic()
    for with_certificate in (False, True):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.load_verify_locations(str(material.ca))
        if with_certificate:
            context.load_cert_chain(str(material.identity_cert), str(material.identity_key))
        while True:
            try:
                raw = socket.create_connection(("127.0.0.1", port), timeout=30)
                break
            except OSError:
                if time.monotonic() - start > deadline:
                    results.append("harness: server never listened")
                    return
                time.sleep(0.2)
        try:
            with context.wrap_socket(raw, server_hostname="localhost") as tls:
                tls.sendall(b"harness\n")
                reply = tls.recv(64)
                # No reply at all: the server closed without serving the client.
                results.append(f"harness client {int(with_certificate)}: {'served ' + reply.decode().strip() if reply else 'refused'}")
        except (OSError, ssl.SSLError):
            # An alert or a reset: either way the server refused the client.
            results.append(f"harness client {int(with_certificate)}: refused")
