#!/usr/bin/env python3
"""Run Java 8 classes, classpaths, archives, and manifests through BendJVM."""

from __future__ import annotations

import base64
import functools
import hashlib
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from classpath import Classpath, ClasspathError, DirectorySource, SourceMatch

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get("BEND", "/Users/matheusbbarni/.bend/bin/bend")
BUN = os.environ.get("BUN", shutil.which("bun") or "/Users/matheusbbarni/.bun/bin/bun")
CACHE = Path(os.environ.get("BENDJVM_CACHE", "/tmp/bendjvm-cache"))
JAVAC = os.environ.get("JAVAC", shutil.which("javac") or "javac")
# The MiniJRE classes written in Java (java.lang.Thread, java.nio, javax.net.ssl, ...).
JRE_SOURCES = ROOT / "bendjvm" / "jre"


class LaunchUsageError(ValueError):
    pass


@dataclass(frozen=True)
class ClassInfo:
    name: str
    dependencies: tuple[str, ...]


@dataclass(frozen=True)
class Launch:
    entry: str
    classes: tuple[SourceMatch, ...]
    classpath: tuple[str, ...]
    resources: tuple[tuple[str, str], ...]
    app_args: tuple[str, ...]
    flags: tuple[str, ...]
    mode: int
    fuel: int
    max_heap: int


def compiler_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment["BEND_NO_TELEMETRY"] = "1"
    environment["NO_COLOR"] = "1"
    return environment


def generated_function(source: str, *path: str) -> str:
    """Return the JS name Bend generated for a top-level definition.

    Bend 2.0.36 mangles `a.b.c` as `$a$b$c$`; Bend 2.0.39 emits `$a_b_c`.
    Match the full qualified name exactly so helper continuations and
    same-named definitions in other modules are never selected.
    """
    names = [f"${'$'.join(path)}$", f"${'_'.join(path)}"]
    for name in names:
        if re.search(rf"\nfunction {re.escape(name)}\(", source):
            return name
    raise LookupError(" or ".join(names))


def compiler_identity() -> bytes:
    """Cache-key component for the Bend compiler: updating or reinstalling it
    replaces the binary, so artifacts from an older compiler are never reused."""
    binary = Path(shutil.which(BEND) or BEND).resolve()
    status = binary.stat()
    return f"{binary}\0{status.st_ino}\0{status.st_size}\0{status.st_mtime_ns}".encode()


NATIVE_SOURCES = ROOT / "bendjvm" / "native"


def native_helper() -> Path:
    """The supervised native-plugin helper, compiled from bendjvm/native/helper.c
    the first time a launch allows a native library."""
    sources = (NATIVE_SOURCES / "helper.c", NATIVE_SOURCES / "bendjvm_plugin.h")
    compiler = os.environ.get("CC") or shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    if compiler is None:
        raise LaunchUsageError("native plugins need a C compiler (cc) to build the BendJVM native helper")
    digest = hashlib.sha256(compiler.encode() + b"\0" + b"\0".join(path.read_bytes() for path in sources)).hexdigest()
    target = CACHE / f"native-helper-{digest}"
    if target.is_file():
        return target
    CACHE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bendjvm-native-", dir=CACHE) as temporary:
        output = Path(temporary) / "helper"
        result = subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-pthread", "-I", str(NATIVE_SOURCES),
                                 "-o", str(output), str(sources[0])], capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(f"native helper failed to compile:\n{result.stdout}{result.stderr}")
        os.replace(output, target)
    return target


def jre_source_files() -> tuple[Path, ...]:
    return tuple(sorted(JRE_SOURCES.rglob("*.java")))


@functools.cache
def runtime_library() -> DirectorySource:
    """The compiled Java-source MiniJRE layer, prepared next to the Bend artifacts."""
    sources = jre_source_files()
    digest = hashlib.sha256(compiler_identity() + b"\0" + b"\0".join(
        path.relative_to(JRE_SOURCES).as_posix().encode() + b"\0" + path.read_bytes() for path in sources)).hexdigest()
    target = CACHE / f"jre-{digest}"
    if not (target / ".complete").is_file():
        CACHE.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="bendjvm-jre-", dir=CACHE) as temporary:
            output = Path(temporary) / "classes"
            output.mkdir()
            if sources:
                result = subprocess.run([JAVAC, "--release", "8", "-encoding", "UTF-8", "-g:source,lines", "-Xlint:-options",
                                         "-d", str(output), *map(str, sources)], capture_output=True, text=True, check=False)
                if result.returncode != 0:
                    raise RuntimeError(f"MiniJRE Java sources failed to compile:\n{result.stdout}{result.stderr}")
            (output / ".complete").write_text("ok", encoding="utf-8")
            try:
                os.replace(output, target)
            except OSError:
                if not (target / ".complete").is_file():
                    raise
    return DirectorySource(target)


def find_class(classpath: Classpath, name: str) -> SourceMatch | None:
    """MiniJRE classes take precedence over the application class path, like
    bootstrap classes on the JVM."""
    return runtime_library().find_class(name) or classpath.find_class(name)


def build_artifacts() -> Path:
    runtime_library()
    inputs = (ROOT / "bendjvm" / "loader_api.bend", ROOT / "bendjvm" / "runtime_api.bend")
    dependencies = tuple(sorted((ROOT / "bendjvm").rglob("*.bend"))) + (Path(__file__), ROOT / "scripts" / "classpath.py")
    digest = hashlib.sha256(compiler_identity() + b"\0" + b"\0".join(path.read_bytes() for path in dependencies)).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    loader = CACHE / f"loader-{digest}.js"
    runtime = CACHE / f"runtime-{digest}.js"
    host = CACHE / f"host-{digest}.mjs"
    names = CACHE / f"bootstrap-{digest}.json"
    if loader.is_file() and runtime.is_file() and host.is_file() and names.is_file():
        return host
    with tempfile.TemporaryDirectory(prefix="bendjvm-build-", dir=CACHE) as temporary:
        directory = Path(temporary)
        loader_tmp = directory / "loader.js"
        runtime_tmp = directory / "runtime.js"
        for source, output in zip(inputs, (loader_tmp, runtime_tmp)):
            try:
                subprocess.run([BEND, str(source), "-o", str(output)], cwd=ROOT,
                               env=compiler_environment(), check=True, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE, text=True, timeout=1800)
            except subprocess.CalledProcessError as error:
                print(error.stderr, file=sys.stderr, end="")
                raise
        loader_source = loader_tmp.read_text(encoding="utf-8")
        runtime_source = runtime_tmp.read_text(encoding="utf-8")
        try:
            loader_name = generated_function(loader_source, "loader", "class_loader", "load_many_with_resources")
            inspect_name = generated_function(loader_source, "inspect_class_info")
            runtime_name = generated_function(runtime_source, "run_loaded_entry")
            continue_name = generated_function(runtime_source, "continue_run")
            resume_ok_name = generated_function(runtime_source, "complete_ok")
            resume_fail_name = generated_function(runtime_source, "complete_fail")
            resume_class_name = generated_function(runtime_source, "complete_class")
            resume_resource_name = generated_function(runtime_source, "complete_resource")
            take_output_name = generated_function(runtime_source, "take_output")
            take_closes_name = generated_function(runtime_source, "take_closes")
        except LookupError as error:
            raise RuntimeError(f"Bend launch API export not found in generated artifact: {error}") from error
        names_tmp = directory / "bootstrap.json"
        names_tmp.write_text(json.dumps(bootstrap_class_names(loader_source, directory)), encoding="utf-8")
        host_tmp = directory / "host.mjs"
        host_tmp.write_text(host_source(loader_source, runtime_source, loader_name, runtime_name, inspect_name, continue_name, resume_ok_name, resume_fail_name, resume_class_name, resume_resource_name, take_output_name, take_closes_name), encoding="utf-8")
        os.replace(loader_tmp, loader)
        os.replace(runtime_tmp, runtime)
        os.replace(names_tmp, names)
        os.replace(host_tmp, host)
    return host


@functools.cache
def bootstrap_names() -> frozenset[str]:
    """Binary names the Bend MiniJRE defines itself; classpath copies are never loaded."""
    host = build_artifacts()
    names = host.with_name(host.name.replace("host-", "bootstrap-", 1)).with_suffix(".json")
    return frozenset(json.loads(names.read_text(encoding="utf-8")))


def library_fragment(source: str) -> str:
    """Strip the generated CLI entry so the artifact can be embedded as a library."""
    return re.sub(r"\ncli\(process\.argv\.slice\(\d+\)\);[\s\S]*$", "\n", source)


def bootstrap_class_names(loader_source: str, directory: Path) -> list[str]:
    """Evaluate the Bend bootstrap catalog so the host never keeps its own copy."""
    classes_name = generated_function(loader_source, "loader", "bootstrap", "classes")
    script = directory / "bootstrap-names.mjs"
    script.write_text(library_fragment(loader_source) + f"""
const names = [];
let cursor = run_loop({classes_name}());
while (cursor && cursor.$ === "Con") {{ names.push(cursor.head.name); cursor = cursor.tail; }}
process.stdout.write(JSON.stringify(names));
""", encoding="utf-8")
    result = subprocess.run([BUN, str(script)], cwd=ROOT, env=compiler_environment(), check=True,
                            capture_output=True, text=True, timeout=300)
    names = json.loads(result.stdout)
    if not names or not all(isinstance(name, str) and name for name in names):
        raise RuntimeError("Bend bootstrap catalog produced no class names")
    return names


def host_source(loader_source: str, runtime_source: str, loader_name: str, runtime_name: str, inspect_name: str, continue_name: str, resume_ok_name: str, resume_fail_name: str, resume_class_name: str, resume_resource_name: str, take_output_name: str, take_closes_name: str) -> str:
    fragment = library_fragment
    nat_converter = "BigInt" if "=== 0n" in runtime_source else "Number"


    return f'''import {{ openSync, readSync, writeSync, closeSync, statSync, existsSync, readdirSync, realpathSync }} from "node:fs";
import net from "node:net";
import tls from "node:tls";
import dns from "node:dns";
import {{ Duplex }} from "node:stream";
import {{ readFileSync }} from "node:fs";
import {{ spawn }} from "node:child_process";
import {{ createInterface }} from "node:readline";

const loader = new Function({fragment(loader_source)!r} + `
return {{ loadManyWithResources: (values, resources, heap) => run_loop({loader_name}(values, resources, heap)), inspectClassInfo: (values) => run_loop({inspect_name}(values)) }};
`)();
const runtime = new Function({fragment(runtime_source)!r} + `
const nat = {nat_converter};
return {{
  runLoadedEntry: (vm, fuel, entry, args, quantum, clock) => run_loop({runtime_name}(vm, nat(fuel), entry, args, quantum, ...clock)),
  continueRun: (vm, clock) => run_loop({continue_name}(vm, ...clock)),
  completeOk: (vm, op, handle, extra, bytes) => run_loop({resume_ok_name}(vm, op, handle, extra, bytes)),
  completeFail: (vm, op, name) => run_loop({resume_fail_name}(vm, op, name)),
  completeClass: (vm, op, bytes) => run_loop({resume_class_name}(vm, op, bytes)),
  completeResource: (vm, op, bytes) => run_loop({resume_resource_name}(vm, op, bytes)),
  takeOutput: (vm) => run_loop({take_output_name}(vm)),
  takeCloses: (vm) => run_loop({take_closes_name}(vm))
}};
`)();

function kindOf(value) {{
  const raw = value && value.$;
  return typeof raw === "string" ? raw.slice(raw.lastIndexOf(".") + 1) : raw;
}}
function isTrue(value) {{
  return value === true || kindOf(value) === "True";
}}
function list(values) {{
  let result = {{ $: "Nil" }};
  for (let index = values.length - 1; index >= 0; index -= 1) result = {{ $: "Con", head: values[index], tail: result }};
  return result;
}}
function listValues(value) {{
  const result = [];
  while (value && value.$ === "Con") {{ result.push(value.head); value = value.tail; }}
  return result;
}}
function text(value) {{
  if (typeof value === "string") return value;
  let result = "";
  while (value && value.$ === "SCon") {{
    const head = value.head;
    result += String.fromCodePoint(typeof head === "number" ? head : head.code);
    value = value.tail;
  }}
  return result;
}}
function fail(error) {{
  const message = text(error);
  const normalized = message.includes("invalid magic") ? `InvalidMagic: ${{message}}`
    : (message.includes("StackUnderflow") || message.includes("StackOverflow") || message.includes("InvalidLocalIndex"))
      ? `VerifyError: ${{message}}` : message;
  console.error(normalized);
  process.exit(1);
}}
const handles = new Map();
let nextHandle = 1;
let sourceHost;
// The classpath service answers requests in order; several Java threads can
// wait on it at once (each loading a class or reading a resource).
const sourcePending = [];
function sourceRequest(value) {{
  if (!sourceHost) {{
    sourceHost = spawn({sys.executable!r}, [{str(Path(__file__).resolve())!r}, "--host-requests", process.env.BENDJVM_REQUEST], {{ stdio: ["pipe", "pipe", "inherit"] }});
    createInterface({{ input: sourceHost.stdout }}).on("line", line => {{
      const pending = sourcePending.shift();
      if (pending) {{ try {{ pending.resolve(JSON.parse(line)); }} catch (error) {{ pending.reject(error); }} }}
    }});
    sourceHost.on("exit", () => {{ while (sourcePending.length) sourcePending.shift().reject(new Error("classpath host exited")); }});
    process.on("exit", () => sourceHost.kill());
  }}
  return new Promise((resolve, reject) => {{
    sourcePending.push({{ resolve, reject }});
    sourceHost.stdin.write(JSON.stringify(value) + "\\n");
  }});
}}
// Names as UTF-16 code units with 0 after each (names never contain NUL).
function nameUnits(names) {{
  const units = [];
  for (const name of names) {{ for (let i = 0; i < name.length; i++) units.push(name.charCodeAt(i)); units.push(0); }}
  return units;
}}
// ---- HostIO (sun.nio.ch.HostIO.call): sockets, selectors and TLS (plan 05) ----
// Java owns buffers, channel state and exceptions; this layer owns OS sockets.
// Every record notifies its waiters when its readiness may have changed, so a
// blocked read/accept/select resolves as soon as the event arrives.
const HOSTIO = {{ CONNECT: 1, FINISH_CONNECT: 2, READ: 3, WRITE: 4, SHUTDOWN: 5, CLOSE: 6, LISTEN: 7, ACCEPT: 8,
  LOCAL_PORT: 9, REMOTE_PORT: 10, WAKEUP: 11, SELECT: 12, TLS_HANDSHAKE: 13, TLS_INFO: 14, TLS_DEFAULTS: 15, REMOTE_HOST: 16, RESOLVE: 17 }};
const NONBLOCKING = 1 << 29, INTERRUPTIBLE = 1 << 30, FOREVER = (1 << 29) - 1;
const MAX_BUFFERED = 1 << 20;
class HostError extends Error {{ constructor(name) {{ super(name); this.javaName = name; }} }}
function hostFail(name) {{ throw new HostError(name); }}
function notify(rec) {{
  const waiters = rec.waiters;
  rec.waiters = new Set();
  for (const wake of waiters) wake();
}}
// Resolves when `rec` may have changed, or after `timeout` ms (FOREVER: never).
function waitOn(recs, timeout, extra) {{
  return new Promise(resolve => {{
    let timer = null;
    const done = timedOut => {{
      for (const rec of recs) rec.waiters.delete(wake);
      if (extra) extra.delete(wake);
      if (timer) clearTimeout(timer);
      resolve(timedOut);
    }};
    const wake = () => done(false);
    for (const rec of recs) rec.waiters.add(wake);
    if (extra) extra.add(wake);
    if (timeout !== FOREVER) timer = setTimeout(() => done(true), timeout);
  }});
}}
// Every host socket keeps one error listener for its whole life: errors that
// matter reach Java through the records; late resets on closing sockets do not.
function guard(socket) {{
  socket.on("error", () => {{}});
  return socket;
}}
function socketRecord(socket, connected) {{
  guard(socket);
  const rec = {{ type: "socket", socket, chunks: [], size: 0, ended: false, error: null, closed: false,
    connected, connectError: null, inputShutdown: false, outputShutdown: false, tls: false, waiters: new Set() }};
  attachSocket(rec, socket);
  return rec;
}}
function attachSocket(rec, socket) {{
  socket.on("data", chunk => {{
    if (rec.inputShutdown) return;
    rec.chunks.push(chunk);
    rec.size += chunk.length;
    if (rec.size > MAX_BUFFERED) socket.pause();
    notify(rec);
  }});
  socket.on("end", () => {{ rec.ended = true; notify(rec); }});
  socket.on("error", error => {{
    if (!rec.connected && !rec.connectError) rec.connectError = error;
    else rec.error = error;
    notify(rec);
  }});
  socket.on("close", () => {{ rec.ended = true; notify(rec); }});
}}
function addRecord(rec) {{
  const handle = nextHandle++;
  handles.set(handle, rec);
  return handle;
}}
function socketRec(handle, nio) {{
  const rec = handles.get(handle);
  if (!rec || rec.closed) hostFail(nio ? "java/nio/channels/ClosedChannelException" : "java/net/SocketException: Socket closed");
  if (rec.suspended) hostFail("java/net/SocketException: the connection is in use by an SSLSocket");
  return rec;
}}
function connectError(error, host) {{
  const code = error && error.code;
  if (code === "ECONNREFUSED") return "java/net/ConnectException: Connection refused";
  if (code === "ENOTFOUND" || code === "EAI_AGAIN") return `java/net/UnknownHostException: ${{host}}`;
  if (code === "ETIMEDOUT") return "java/net/SocketTimeoutException: connect timed out";
  if (code === "EHOSTUNREACH" || code === "ENETUNREACH") return "java/net/NoRouteToHostException: No route to host";
  return `java/net/SocketException: ${{(error && error.message) || error}}`;
}}
function streamError(error) {{
  const code = error && error.code;
  if (code === "ECONNRESET") return "java/net/SocketException: Connection reset";
  if (code === "EPIPE") return "java/net/SocketException: Broken pipe";
  return `java/net/SocketException: ${{(error && error.message) || error}}`;
}}
function takeBytes(rec, count) {{
  const parts = [];
  let taken = 0;
  while (taken < count && rec.chunks.length) {{
    const head = rec.chunks[0];
    const want = count - taken;
    if (head.length <= want) {{ parts.push(head); taken += head.length; rec.chunks.shift(); }}
    else {{ parts.push(head.subarray(0, want)); rec.chunks[0] = head.subarray(want); taken += want; }}
  }}
  rec.size -= taken;
  if (rec.size <= MAX_BUFFERED && rec.socket.isPaused && rec.socket.isPaused()) rec.socket.resume();
  return Buffer.concat(parts);
}}
function readyOps(rec) {{
  if (rec.type === "server") return rec.closed ? 16 : (rec.pending.length ? 16 : 0);
  let ops = 0;
  if (rec.size > 0 || rec.ended || rec.error || rec.closed || rec.inputShutdown) ops |= 1;
  if (rec.connected && !rec.outputShutdown && !rec.closed) ops |= 4;
  if (rec.connected || rec.connectError) ops |= 8;
  return ops;
}}
const selectorWakeups = new Map();
function selectorWaiters(id) {{
  if (!selectorWakeups.has(id)) selectorWakeups.set(id, {{ pending: false, waiters: new Set() }});
  return selectorWakeups.get(id);
}}
// TLS material from the launcher (--tls-trust/--tls-key/--tls-cert), loaded once.
let tlsMaterial = null;
function tlsConfig() {{
  if (tlsMaterial) return tlsMaterial;
  const config = request.tls || {{}};
  const read = path => path ? readFileSync(path) : undefined;
  tlsMaterial = {{ ca: read(config.trust), key: read(config.key), cert: read(config.cert) }};
  return tlsMaterial;
}}
const TLS_PROTOCOLS = ["TLSv1.3", "TLSv1.2"];
// Java (IANA) cipher suite names and the provider names they select.
const TLS_SUITES = [
  ["TLS_AES_256_GCM_SHA384", "TLS_AES_256_GCM_SHA384"],
  ["TLS_AES_128_GCM_SHA256", "TLS_AES_128_GCM_SHA256"],
  ["TLS_CHACHA20_POLY1305_SHA256", "TLS_CHACHA20_POLY1305_SHA256"],
  ["TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384", "ECDHE-ECDSA-AES256-GCM-SHA384"],
  ["TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384", "ECDHE-RSA-AES256-GCM-SHA384"],
  ["TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", "ECDHE-ECDSA-AES128-GCM-SHA256"],
  ["TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "ECDHE-RSA-AES128-GCM-SHA256"],
  ["TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256", "ECDHE-ECDSA-CHACHA20-POLY1305"],
  ["TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256", "ECDHE-RSA-CHACHA20-POLY1305"]
];
function tlsOptions(settings) {{
  const protocols = (settings.protocols || "").split(",").filter(Boolean);
  if (protocols.some(p => !TLS_PROTOCOLS.includes(p))) hostFail(`java/lang/IllegalArgumentException: Unsupported protocol: ${{protocols.find(p => !TLS_PROTOCOLS.includes(p))}}`);
  const enabled = protocols.length ? protocols : TLS_PROTOCOLS;
  const min = enabled.includes("TLSv1.2") ? "TLSv1.2" : "TLSv1.3";
  const max = enabled.includes("TLSv1.3") ? "TLSv1.3" : "TLSv1.2";
  const names = (settings.ciphers || "").split(",").filter(Boolean);
  const unknown = names.find(name => !TLS_SUITES.some(([java]) => java === name));
  if (unknown) hostFail(`java/lang/IllegalArgumentException: Unsupported CipherSuite: ${{unknown}}`);
  const chosen = TLS_SUITES.filter(([java]) => !names.length || names.includes(java));
  const options = {{ minVersion: min, maxVersion: max }};
  const tls12 = chosen.filter(([java]) => !java.startsWith("TLS_AES") && !java.startsWith("TLS_CHACHA")).map(([, p]) => p);
  const tls13 = chosen.filter(([java]) => java.startsWith("TLS_AES") || java.startsWith("TLS_CHACHA20_POLY1305_SHA256")).map(([, p]) => p);
  if (names.length) {{
    if (!tls12.length && min === "TLSv1.2" && max === "TLSv1.2") hostFail("javax/net/ssl/SSLHandshakeException: No appropriate protocol (protocol is disabled or cipher suites are inappropriate)");
    options.ciphers = tls12.length ? tls12.join(":") : "DEFAULT:!aNULL";
    options.ciphersuites = tls13.join(":");
    if (!tls13.length && max === "TLSv1.3") options.maxVersion = "TLSv1.2";
  }}
  return options;
}}
function settingsOf(data) {{
  const settings = {{}};
  for (const line of Buffer.from(data).toString("utf8").split("\\n")) {{
    const at = line.indexOf("=");
    if (at > 0) settings[line.slice(0, at)] = line.slice(at + 1);
  }}
  return settings;
}}
// A failed handshake ends gracefully so the provider's alert reaches the peer.
function closeAfterAlert(secured, raw) {{
  // The peer may reset the connection while it closes; nothing waits on it.
  secured.on("error", () => {{}});
  raw.on("error", () => {{}});
  try {{ secured.end(); }} catch (_) {{}}
  setTimeout(() => {{ secured.destroy(); raw.destroy(); }}, 200).unref();
}}
function handshakeError(error) {{
  if (error && error.timedOut) return "java/net/SocketTimeoutException: Read timed out";
  const message = String((error && (error.reason || error.message)) || error);
  return `javax/net/ssl/SSLHandshakeException: ${{message}}`;
}}
// The TLS provider reads the connection through this stream: bytes the plain
// socket already received (a ClientHello that arrived before the server-side
// handshake started) are replayed first, so nothing is lost to the upgrade.
function tlsTransport(rec) {{
  const raw = rec.socket;
  for (const event of ["data", "end", "error", "close"]) raw.removeAllListeners(event);
  guard(raw);
  const transport = guard(new Duplex({{
    read() {{}},
    write(chunk, encoding, callback) {{ raw.write(chunk, callback); }},
    final(callback) {{ if (!transport.keepRaw) raw.end(); callback(); }},
    destroy(error, callback) {{ if (!transport.keepRaw) raw.destroy(); callback(error); }}
  }}));
  for (const chunk of rec.chunks) transport.push(chunk);
  rec.chunks = [];
  rec.size = 0;
  raw.on("data", chunk => transport.push(chunk));
  raw.on("end", () => transport.push(null));
  raw.on("error", error => transport.destroy(error));
  raw.on("close", () => transport.destroy());
  if (raw.isPaused && raw.isPaused()) raw.resume();
  return transport;
}}
async function tlsHandshake(handle, server, data) {{
  const rec = socketRec(handle, false);
  if (rec.tls) hostFail("javax/net/ssl/SSLException: handshake already done");
  const settings = settingsOf(data);
  const material = tlsConfig();
  // The socket's SO_TIMEOUT bounds the handshake's reads, as on the JDK.
  const limit = Number(settings.timeout || 0);
  const bounded = promise => limit > 0
    ? Promise.race([promise, new Promise((_, reject) => setTimeout(() => reject(Object.assign(new Error("Read timed out"), {{ timedOut: true }})), limit))])
    : promise;
  const base = tlsOptions(settings);
  const raw = rec.socket;
  const transport = tlsTransport(rec);
  let secured;
  if (server) {{
    if (!material.key || !material.cert) hostFail("javax/net/ssl/SSLHandshakeException: no server certificate configured (--tls-key/--tls-cert)");
    const need = settings.needClientAuth === "1";
    const context = tls.createSecureContext({{ ...base, key: material.key, cert: material.cert, ca: material.ca }});
    secured = new tls.TLSSocket(transport, {{ isServer: true, secureContext: context, requestCert: need, rejectUnauthorized: need }});
    await bounded(new Promise((resolve, reject) => {{
      secured.once("secure", resolve);
      secured.once("error", reject);
      secured.once("close", () => reject(new Error("Remote host terminated the handshake")));
    }})).catch(error => {{ closeAfterAlert(secured, raw); rec.closed = true; handles.delete(handle); hostFail(handshakeError(error)); }});
  }} else {{
    const host = settings.host || "localhost";
    const isIp = net.isIP(host) !== 0;
    const verifyHost = settings.verifyHost === "1";
    secured = tls.connect({{ ...base, socket: transport, ca: material.ca, key: material.key, cert: material.cert,
      servername: isIp ? undefined : host, rejectUnauthorized: true,
      checkServerIdentity: verifyHost ? (name, cert) => tls.checkServerIdentity(host, cert) : () => undefined }});
    await bounded(new Promise((resolve, reject) => {{
      secured.once("secureConnect", resolve);
      secured.once("error", reject);
      secured.once("close", () => reject(new Error("Remote host terminated the handshake")));
    }})).catch(error => {{ secured.on("error", () => {{}}); raw.on("error", () => {{}}); secured.destroy(); rec.closed = true; handles.delete(handle); hostFail(handshakeError(error)); }});
  }}
  const upgraded = socketRecord(secured, true);
  upgraded.tls = true;
  upgraded.raw = raw;
  // autoClose=false (a layered SSLSocket): the plain socket outlives the TLS
  // connection, so it stays registered, suspended until the TLS side closes.
  secured.on("error", error => {{ upgraded.error = error; notify(upgraded); }});
  if (settings.autoClose === "0") {{
    transport.keepRaw = true;
    upgraded.layered = rec;
    rec.suspended = true;
    return addRecord(upgraded);
  }}
  handles.delete(handle);
  rec.closed = true;
  return addRecord(upgraded);
}}
function tlsInfo(handle, what) {{
  const rec = socketRec(handle, false);
  const socket = rec.socket;
  if (!rec.tls) return null;
  if (what === 0) return socket.getProtocol() || "NONE";
  if (what === 1) {{
    const cipher = socket.getCipher();
    return cipher ? (cipher.standardName || cipher.name) : "SSL_NULL_WITH_NULL_NULL";
  }}
  if (what === 2) {{
    const peer = socket.getPeerCertificate && socket.getPeerCertificate();
    return peer && peer.subject ? Object.entries(peer.subject).map(([k, v]) => `${{k}}=${{v}}`).join(", ") : "";
  }}
  return "";
}}
async function hostIO(op, handle, arg, data, length, caps) {{
  const blocking = (arg & NONBLOCKING) === 0;
  const nio = (arg & (NONBLOCKING | INTERRUPTIBLE)) !== 0;
  const timeout = arg & FOREVER;
  const needsNet = op !== HOSTIO.WAKEUP;
  if (needsNet && (caps & 2) === 0) hostFail("java/net/SocketException: Permission denied (network access is disabled)");
  switch (op) {{
    case HOSTIO.CONNECT: {{
      const host = Buffer.from(data).toString("utf8");
      const port = arg & 0xFFFF;
      const socket = net.connect({{ host, port, allowHalfOpen: true }});
      const rec = socketRecord(socket, false);
      socket.once("connect", () => {{ rec.connected = true; notify(rec); }});
      const id = addRecord(rec);
      if (!blocking) return {{ result: id }};
      const deadline = handle === FOREVER ? null : Date.now() + handle;
      while (!rec.connected && !rec.connectError && !rec.closed) {{
        const left = deadline === null ? FOREVER : Math.max(0, deadline - Date.now());
        if (left === 0 || await waitOn([rec], left)) {{
          socket.destroy(); handles.delete(id);
          hostFail("java/net/SocketTimeoutException: connect timed out");
        }}
      }}
      if (rec.connectError) {{ socket.destroy(); handles.delete(id); hostFail(connectError(rec.connectError, host)); }}
      if (rec.closed) hostFail(nio ? "java/nio/channels/AsynchronousCloseException" : "java/net/SocketException: Socket closed");
      return {{ result: id }};
    }}
    case HOSTIO.FINISH_CONNECT: {{
      const rec = socketRec(handle, true);
      for (;;) {{
        if (rec.connectError) hostFail(connectError(rec.connectError, ""));
        if (rec.connected) return {{ result: 1 }};
        if (!blocking) return {{ result: 0 }};
        await waitOn([rec], FOREVER);
        if (rec.closed) hostFail("java/nio/channels/AsynchronousCloseException");
      }}
    }}
    case HOSTIO.READ: {{
      const rec = socketRec(handle, nio);
      const deadline = timeout === FOREVER ? null : Date.now() + timeout;
      for (;;) {{
        if (rec.closed) hostFail(nio ? "java/nio/channels/AsynchronousCloseException" : "java/net/SocketException: Socket closed");
        if (rec.size > 0) {{ const bytes = takeBytes(rec, length); return {{ result: bytes.length, bytes }}; }}
        if (rec.error) hostFail(rec.tls ? `javax/net/ssl/SSLException: ${{rec.error.reason || rec.error.message}}` : streamError(rec.error));
        if (rec.ended || rec.inputShutdown) return {{ result: -1 }};
        if (!blocking) return {{ result: 0 }};
        const left = deadline === null ? FOREVER : Math.max(0, deadline - Date.now());
        if (left === 0 || await waitOn([rec], left)) hostFail("java/net/SocketTimeoutException: Read timed out");
      }}
    }}
    case HOSTIO.WRITE: {{
      const rec = socketRec(handle, nio);
      if (rec.outputShutdown) hostFail(nio ? "java/nio/channels/ClosedChannelException" : "java/net/SocketException: Socket output is shutdown");
      if (rec.error) hostFail(streamError(rec.error));
      const bytes = Buffer.from(data);
      await new Promise((resolve, reject) => rec.socket.write(bytes, error => error ? reject(error) : resolve()))
        .catch(error => hostFail(rec.closed && nio ? "java/nio/channels/AsynchronousCloseException" : streamError(error)));
      return {{ result: bytes.length }};
    }}
    case HOSTIO.SHUTDOWN: {{
      const rec = socketRec(handle, nio);
      if (arg === 0) {{ rec.inputShutdown = true; rec.chunks = []; rec.size = 0; notify(rec); }}
      else {{ rec.outputShutdown = true; rec.socket.end(); }}
      return {{ result: 0 }};
    }}
    case HOSTIO.CLOSE: {{
      const rec = handles.get(handle);
      if (!rec) return {{ result: 0 }};
      rec.closed = true;
      handles.delete(handle);
      try {{
        if (rec.type === "server") rec.server.close();
        else if (rec.tls && rec.layered) {{
          // close_notify, then the plain socket gets its connection back.
          const plain = rec.layered;
          rec.socket.end();
          const raw = rec.raw;
          for (const event of ["data", "end", "error", "close"]) raw.removeAllListeners(event);
          guard(raw);
          plain.suspended = false;
          plain.chunks = [];
          plain.size = 0;
          attachSocket(plain, raw);
          notify(plain);
        }}
        else if (rec.tls) {{ rec.socket.end(); setTimeout(() => rec.socket.destroy(), 1000).unref(); }}
        else rec.socket.destroy();
      }} catch (_) {{}}
      notify(rec);
      return {{ result: 0 }};
    }}
    case HOSTIO.LISTEN: {{
      const rec = {{ type: "server", server: null, pending: [], closed: false, waiters: new Set() }};
      const server = net.createServer({{ allowHalfOpen: true }}, socket => {{ rec.pending.push(socket); notify(rec); }});
      rec.server = server;
      await new Promise((resolve, reject) => {{
        server.once("error", reject);
        server.listen({{ port: arg & 0xFFFF, backlog: handle }}, resolve);
      }}).catch(error => hostFail(error && error.code === "EADDRINUSE" ? "java/net/BindException: Address already in use" : `java/net/SocketException: ${{error && error.message}}`));
      return {{ result: addRecord(rec) }};
    }}
    case HOSTIO.ACCEPT: {{
      const rec = handles.get(handle);
      if (!rec || rec.closed) hostFail(nio ? "java/nio/channels/ClosedChannelException" : "java/net/SocketException: Socket is closed");
      const deadline = timeout === FOREVER ? null : Date.now() + timeout;
      for (;;) {{
        if (rec.closed) hostFail(nio ? "java/nio/channels/AsynchronousCloseException" : "java/net/SocketException: Socket closed");
        if (rec.pending.length) return {{ result: addRecord(socketRecord(rec.pending.shift(), true)) }};
        if (!blocking) return {{ result: 0 }};
        const left = deadline === null ? FOREVER : Math.max(0, deadline - Date.now());
        if (left === 0 || await waitOn([rec], left)) hostFail("java/net/SocketTimeoutException: Accept timed out");
      }}
    }}
    case HOSTIO.LOCAL_PORT: {{
      const rec = handles.get(handle);
      if (!rec) return {{ result: -1 }};
      return {{ result: rec.type === "server" ? rec.server.address().port : (rec.raw || rec.socket).localPort }};
    }}
    case HOSTIO.REMOTE_PORT: {{
      const rec = handles.get(handle);
      return {{ result: rec && rec.socket ? ((rec.raw || rec.socket).remotePort || 0) : 0 }};
    }}
    case HOSTIO.REMOTE_HOST: {{
      const rec = handles.get(handle);
      const address = rec && rec.socket ? String((rec.raw || rec.socket).remoteAddress || "") : "";
      const bytes = Buffer.from(address.startsWith("::ffff:") ? address.slice(7) : address, "utf8");
      return {{ result: bytes.length, bytes }};
    }}
    case HOSTIO.SELECT: {{
      const entries = [];
      for (let i = 0; i + 5 <= length; i += 5) entries.push([data.readUInt32BE(i), data[i + 4]]);
      const wake = selectorWaiters(handle);
      for (;;) {{
        const ready = [];
        const recs = [];
        for (const [h, interest] of entries) {{
          const rec = handles.get(h);
          if (!rec) continue;
          recs.push(rec);
          const ops = readyOps(rec) & interest;
          if (ops) ready.push([h, ops]);
        }}
        if (ready.length || !blocking || wake.pending) {{
          wake.pending = false;
          const bytes = Buffer.alloc(ready.length * 5);
          ready.forEach(([h, ops], i) => {{ bytes.writeUInt32BE(h >>> 0, i * 5); bytes[i * 5 + 4] = ops; }});
          return {{ result: ready.length, bytes }};
        }}
        if (await waitOn(recs, timeout, wake.waiters)) return {{ result: 0 }};
      }}
    }}
    case HOSTIO.WAKEUP: {{
      // The current select returns, or else the next one returns at once.
      const wake = selectorWaiters(handle);
      wake.pending = true;
      const waiters = wake.waiters;
      wake.waiters = new Set();
      for (const fn of waiters) fn();
      return {{ result: 0 }};
    }}
    case HOSTIO.RESOLVE: {{
      // Name resolution runs here, off the interpreter; IPv4 is preferred.
      const host = Buffer.from(data.subarray(0, arg)).toString("utf8");
      let found;
      try {{ found = await dns.promises.lookup(host, {{ family: 4 }}); }}
      catch (_) {{
        try {{ found = await dns.promises.lookup(host); }}
        catch (error) {{ hostFail(`java/net/UnknownHostException: ${{host}}`); }}
      }}
      const bytes = Buffer.from(found.address, "utf8");
      return {{ result: bytes.length, bytes }};
    }}
    case HOSTIO.TLS_HANDSHAKE:
      return {{ result: await tlsHandshake(handle, (arg & 1) === 1, data) }};
    case HOSTIO.TLS_INFO: {{
      const value = tlsInfo(handle, arg);
      if (value === null) return {{ result: -1 }};
      const bytes = Buffer.from(value, "utf8");
      return {{ result: bytes.length, bytes }};
    }}
    case HOSTIO.TLS_DEFAULTS: {{
      const value = arg === 0 ? TLS_PROTOCOLS.join(",") : TLS_SUITES.map(([java]) => java).join(",");
      const bytes = Buffer.from(value, "utf8");
      return {{ result: bytes.length, bytes }};
    }}
    default:
      hostFail("java/lang/UnsupportedOperationException: unknown host operation");
  }}
}}
// ---- Native plugins (plan 05, slice 6) ----
// A supervised helper process loads approved plugin libraries and runs their
// calls; a crash or a timed-out call ends only the helper, failing the calls it
// had in flight. Libraries it had loaded are gone with it (later calls throw
// UnsatisfiedLinkError).
let nativeHelper = null;
const nativePending = new Map();
let nativeNextId = 1;
function nativeConfig() {{
  return request.natives || {{ libraries: {{}}, allowed: [], timeout: 30000 }};
}}
function stopNativeHelper(reason) {{
  const helper = nativeHelper;
  nativeHelper = null;
  if (helper) {{ try {{ helper.kill("SIGKILL"); }} catch (_) {{}} }}
  for (const pending of nativePending.values()) {{ clearTimeout(pending.timer); pending.resolve({{ error: reason }}); }}
  nativePending.clear();
}}
// The helper speaks one line per message: "L id hexpath", "C id owner name
// descriptor static n words..." and replies "B"/"W"/"E id ..." (helper.c).
function nativeReply(line) {{
  const [kind, id, ...rest] = line.trim().split(" ");
  if (kind === "E") return {{ id: Number(id), error: Buffer.from(rest[0] || "", "hex").toString("utf8") }};
  if (kind === "W") return {{ id: Number(id), words: rest.slice(1).map(Number) }};
  if (kind === "B") return {{ id: Number(id), bindings: Number(rest[0]) }};
  return null;
}}
function nativeRequest(message) {{
  const config = nativeConfig();
  if (!nativeHelper) {{
    const helper = spawn(config.helper, [], {{ stdio: ["pipe", "pipe", "inherit"] }});
    nativeHelper = helper;
    createInterface({{ input: helper.stdout }}).on("line", line => {{
      const reply = nativeReply(line);
      if (!reply) return;
      const pending = nativePending.get(reply.id);
      if (!pending) return;
      nativePending.delete(reply.id);
      clearTimeout(pending.timer);
      pending.resolve(reply);
    }});
    helper.on("exit", () => {{ if (nativeHelper === helper) stopNativeHelper("java/lang/InternalError: native helper terminated"); }});
    helper.on("error", () => {{ if (nativeHelper === helper) stopNativeHelper("java/lang/InternalError: native helper could not start"); }});
    process.on("exit", () => {{ try {{ helper.kill("SIGKILL"); }} catch (_) {{}} }});
  }}
  const id = nativeNextId++;
  const line = message.op === "load"
    ? `L ${{id}} ${{Buffer.from(message.path, "utf8").toString("hex")}}`
    : `C ${{id}} ${{message.owner}} ${{message.name}} ${{message.descriptor}} ${{message.static ? 1 : 0}} ${{message.words.length}}${{message.words.map(word => " " + word).join("")}}`;
  return new Promise(resolve => {{
    const timer = setTimeout(() => stopNativeHelper("java/lang/InternalError: native call timed out"), config.timeout);
    nativePending.set(id, {{ resolve, timer }});
    nativeHelper.stdin.write(line + "\\n");
  }});
}}
const loadedNatives = new Set();
function allowedNative(name, absolute) {{
  const config = nativeConfig();
  if (absolute) {{
    if (!name.startsWith("/")) return {{ error: `java/lang/UnsatisfiedLinkError: Expecting an absolute path of the library: ${{name}}` }};
    let real;
    try {{ real = realpathSync(name); }} catch (_) {{ return {{ error: `java/lang/UnsatisfiedLinkError: Can't load library: ${{name}}` }}; }}
    if (!config.allowed.includes(real)) return {{ error: `java/lang/UnsatisfiedLinkError: native library not allowed: ${{name}}` }};
    return {{ path: real }};
  }}
  const path = Object.prototype.hasOwnProperty.call(config.libraries, name) ? config.libraries[name] : null;
  if (!path) return {{ error: `java/lang/UnsatisfiedLinkError: no ${{name}} in java.library.path` }};
  return {{ path }};
}}
// Performs one thread's host request. `vm` is the snapshot it was dispatched
// from; the result is a function that delivers the completion to a later VM.
async function performEffect(vm, op, effect) {{
  const kind = kindOf(effect);
  const caps = (vm.host && vm.host.caps) >>> 0;
  const ok = (handle, extra, bytes) => next => runtime.completeOk(next, op, handle, extra, bytes);
  const failed = name => next => runtime.completeFail(next, op, name);
  const classes = bytes => next => runtime.completeClass(next, op, bytes);
  const resource = bytes => next => runtime.completeResource(next, op, bytes);
  if (kind === "HostIO") {{
    const data = Buffer.from(listValues(effect.data).map(value => value & 255));
    try {{
      const reply = await hostIO(effect.op >>> 0, effect.handle >>> 0, effect.arg >>> 0, data, effect.length >>> 0, caps);
      return ok(reply.result >>> 0, 0, list(reply.bytes ? [...reply.bytes] : []));
    }} catch (error) {{
      if (error instanceof HostError) return failed(error.javaName);
      throw error;
    }}
  }}
  if (kind === "LoadLibrary") {{
    const allowed = allowedNative(text(effect.name), isTrue(effect.absolute));
    if (allowed.error) return failed(allowed.error);
    const reply = await nativeRequest({{ op: "load", path: allowed.path }});
    if (reply.error) return failed(reply.error);
    loadedNatives.add(allowed.path);
    return ok(0, 0, {{ $: "Nil" }});
  }}
  if (kind === "NativeCall") {{
    const owner = text(effect.owner), name = text(effect.name), descriptor = text(effect.descriptor);
    if (loadedNatives.size === 0 || !nativeHelper) return failed(`java/lang/UnsatisfiedLinkError: ${{owner.replace(/\\//g, ".")}}.${{name}}${{descriptor}}`);
    const reply = await nativeRequest({{ op: "call", owner, name, descriptor, static: isTrue(effect.isStatic), words: listValues(effect.words).map(word => word >>> 0) }});
    if (reply.error) return failed(reply.error);
    return ok(0, 0, list(reply.words.map(word => word >>> 0)));
  }}
  try {{
    if (kind === "RuntimeClass" || kind === "ReadResource") {{
      const knownSymbols = listValues(vm.symbols);
      const response = await sourceRequest({{ kind, name: text(effect.name), origin: text(effect.origin),
        known: listValues(vm.classes).map(value => text(knownSymbols[value.name])) }});
      if (response.error) return failed(response.detail ? `${{response.error}}: ${{response.detail}}` : response.error);
      if (kind === "RuntimeClass") return classes(list(response.classes.map(value => list([...Buffer.from(value, "base64")]))));
      return resource(list([...Buffer.from(response.bytes, "base64")]));
    }}
    if (kind === "OpenFile") {{
      if ((caps & 1) === 0) return failed("java/io/IOException");
      const path = text(effect.path);
      const mode = effect.mode >>> 0;
      const flag = mode === 2 ? "a" : mode === 1 ? "w" : "r";
      const fd = openSync(path, flag);
      const handle = nextHandle++;
      handles.set(handle, {{ type: "file", fd }});
      return ok(handle, 0, {{ $: "Nil" }});
    }}
    if (kind === "ListDirectory") {{
      if ((caps & 1) === 0) return failed("java/io/IOException");
      const path = text(effect.path);
      let names = null;
      try {{ if (statSync(path).isDirectory()) names = readdirSync(path); }} catch (error) {{ names = null; }}
      if (names === null) return ok(0, 0xFFFFFFFF, {{ $: "Nil" }});
      return ok(0, names.length, list(nameUnits(names)));
    }}
    if (kind === "ListArchive" || kind === "ReadPathBytes") {{
      if ((caps & 1) === 0) return failed("java/io/IOException");
      const response = await sourceRequest({{ kind, name: kind === "ReadPathBytes" ? text(effect.entry) : "", origin: text(effect.path), known: [] }});
      if (response.error) return failed(response.detail ? `${{response.error}}: ${{response.detail}}` : response.error);
      if (kind === "ReadPathBytes") return resource(list([...Buffer.from(response.bytes, "base64")]));
      return ok(0, response.names.length, list(nameUnits(response.names)));
    }}
    if (kind === "StatPath") {{
      if ((caps & 1) === 0) return failed("java/io/IOException");
      const path = text(effect.path);
      const op = effect.op >>> 0;
      let value = 0;
      if (existsSync(path)) {{
        const st = statSync(path);
        if (op === 0) value = 1;
        else if (op === 1) value = st.isFile() ? 1 : 0;
        else if (op === 2) value = st.isDirectory() ? 1 : 0;
      }}
      return ok(0, value, {{ $: "Nil" }});
    }}
    if (kind === "ReadBytes") {{
      const handle = effect.handle >>> 0;
      const count = Math.max(1, effect.count >>> 0);
      const rec = handles.get(handle);
      if (!rec) return failed("java/io/IOException");
      if (rec.type === "file") {{
        const buf = Buffer.alloc(count);
        const n = readSync(rec.fd, buf, 0, count, null);
        const values = n <= 0 ? [] : [...buf.subarray(0, n)];
        return ok(handle, 0, list(values));
      }}
      return failed("java/io/IOException");
    }}
    if (kind === "WriteBytes") {{
      const handle = effect.handle >>> 0;
      const rec = handles.get(handle);
      if (!rec) return failed("java/io/IOException");
      const values = listValues(effect.bytes).map(value => value >>> 0);
      const buf = Buffer.from(values);
      if (rec.type === "file") writeSync(rec.fd, buf);
      else return failed("java/io/IOException");
      return ok(handle, 0, {{ $: "Nil" }});
    }}
    if (kind === "CloseHandle") {{
      const handle = effect.handle >>> 0;
      const rec = handles.get(handle);
      if (rec) {{
        try {{
          if (rec.type === "file") closeSync(rec.fd);
        }} catch (_) {{}}
        handles.delete(handle);
      }}
      return ok(handle, 0, {{ $: "Nil" }});
    }}
    return failed("java/io/IOException");
  }} catch (error) {{
    const message = String(error && error.message || error);
    if (kind === "RuntimeClass") return failed("java/lang/LinkageError");
    if (message.includes("timeout")) return failed("java/net/SocketTimeoutException");
    if (message.includes("ENOENT") || message.includes("ENOTDIR") || message.includes("EISDIR") || message.includes("EACCES")) {{
      // The JDK's FileNotFoundException message: the path and the OS reason.
      const reason = message.includes("ENOENT") ? "No such file or directory" : message.includes("ENOTDIR") ? "Not a directory"
        : message.includes("EISDIR") ? "Is a directory" : "Permission denied";
      return failed(kind === "OpenFile" ? `java/io/FileNotFoundException: ${{text(effect.path)}} (${{reason}})` : "java/io/FileNotFoundException");
    }}
    return failed("java/io/IOException");
  }}
}}
function closeRecord(rec) {{
  try {{
    if (rec.type === "file") closeSync(rec.fd);
    else if (rec.socket) rec.socket.destroy();
    else if (rec.server) rec.server.close();
  }} catch (_) {{}}
}}
function closeAll() {{
  for (const rec of handles.values()) closeRecord(rec);
  handles.clear();
}}
// Handles whose Java owners the collector swept (plan 07). The VM records them
// and the host closes them, because closing is an effect the VM may not perform.
function drainCloses(vm) {{
  const pending = listValues(vm.roots.closes);
  if (pending.length === 0) return vm;
  for (const value of pending) {{
    const handle = value >>> 0;
    const rec = handles.get(handle);
    if (!rec) continue;
    closeRecord(rec);
    handles.delete(handle);
    if (process.env.BENDJVM_TRACE_CLOSES) console.error(`bendjvm: closed swept handle ${{handle}}`);
  }}
  return runtime.takeCloses(vm);
}}
process.on("exit", closeAll);
const requestText = readFileSync(process.env.BENDJVM_REQUEST || "", "utf8");
let request;
try {{ request = JSON.parse(requestText); }} catch (error) {{ console.error(`InvalidLaunchRequest: ${{error}}`); process.exit(1); }}
if (request.version !== 1 || !Array.isArray(request.classes) || !Array.isArray(request.resources) ||
    !request.resources.every(value => value && typeof value.name === "string" && typeof value.origin === "string")) {{
  console.error("InvalidLaunchRequest: unsupported protocol"); process.exit(1);
}}
if (request.mode === 4) {{
  const results = [];
  for (const value of request.classes) {{
    const inspected = loader.inspectClassInfo(list([...Buffer.from(value.bytes, "base64")]));
    if (inspected.$ === "Fail") fail(inspected.error);
    results.push({{ name: text(inspected.value.name), dependencies: listValues(inspected.value.dependencies).map(text) }});
  }}
  console.log(JSON.stringify(results));
  process.exit(0);
}}
const bytes = list(request.classes.map(value => list([...Buffer.from(value.bytes, "base64")])));
const resources = list(request.resources.map(value => ({{ $: "Resource", name: value.name, origin: value.origin }})));
const loaded = loader.loadManyWithResources(bytes, resources, request.maxHeap);
if (loaded.$ === "Fail") fail(loaded.error);
const symbols = listValues(loaded.value.symbols);
const classes = listValues(loaded.value.classes);
const methods = listValues(loaded.value.methods);
const symbol = index => text(symbols[index]);
const className = value => symbol(value.name);
const mnemonic = {{
  0: "nop", 1: "aconst_null",
  2: "iconst_m1", 3: "iconst_0", 4: "iconst_1", 5: "iconst_2", 6: "iconst_3", 7: "iconst_4", 8: "iconst_5",
  9: "lconst_0", 10: "lconst_1", 11: "fconst_0", 12: "fconst_1", 13: "fconst_2", 14: "dconst_0", 15: "dconst_1",
  16: "bipush", 17: "sipush", 18: "ldc", 19: "ldc_w", 20: "ldc2_w",
  21: "iload", 22: "lload", 23: "fload", 24: "dload", 25: "aload",
  26: "iload_0", 27: "iload_1", 28: "iload_2", 29: "iload_3",
  30: "lload_0", 31: "lload_1", 32: "lload_2", 33: "lload_3",
  34: "fload_0", 35: "fload_1", 36: "fload_2", 37: "fload_3",
  38: "dload_0", 39: "dload_1", 40: "dload_2", 41: "dload_3",
  42: "aload_0", 43: "aload_1", 44: "aload_2", 45: "aload_3",
  46: "iaload", 47: "laload", 48: "faload", 49: "daload", 50: "aaload", 51: "baload", 52: "caload", 53: "saload",
  54: "istore", 55: "lstore", 56: "fstore", 57: "dstore", 58: "astore",
  59: "istore_0", 60: "istore_1", 61: "istore_2", 62: "istore_3",
  63: "lstore_0", 64: "lstore_1", 65: "lstore_2", 66: "lstore_3",
  67: "fstore_0", 68: "fstore_1", 69: "fstore_2", 70: "fstore_3",
  71: "dstore_0", 72: "dstore_1", 73: "dstore_2", 74: "dstore_3",
  75: "astore_0", 76: "astore_1", 77: "astore_2", 78: "astore_3",
  79: "iastore", 80: "lastore", 81: "fastore", 82: "dastore", 83: "aastore", 84: "bastore", 85: "castore", 86: "sastore",
  87: "pop", 88: "pop2", 89: "dup", 90: "dup_x1", 91: "dup_x2", 92: "dup2", 93: "dup2_x1", 94: "dup2_x2", 95: "swap",
  96: "iadd", 97: "ladd", 98: "fadd", 99: "dadd",
  100: "isub", 101: "lsub", 102: "fsub", 103: "dsub",
  104: "imul", 105: "lmul", 106: "fmul", 107: "dmul",
  108: "idiv", 109: "ldiv", 110: "fdiv", 111: "ddiv",
  112: "irem", 113: "lrem", 114: "frem", 115: "drem",
  116: "ineg", 117: "lneg", 118: "fneg", 119: "dneg",
  120: "ishl", 121: "lshl", 122: "ishr", 123: "lshr", 124: "iushr", 125: "lushr",
  126: "iand", 127: "land", 128: "ior", 129: "lor", 130: "ixor", 131: "lxor", 132: "iinc",
  133: "i2l", 134: "i2f", 135: "i2d", 136: "l2i", 137: "l2f", 138: "l2d",
  139: "f2i", 140: "f2l", 141: "f2d", 142: "d2i", 143: "d2l", 144: "d2f",
  145: "i2b", 146: "i2c", 147: "i2s", 148: "lcmp", 149: "fcmpl", 150: "fcmpg", 151: "dcmpl", 152: "dcmpg",
  153: "ifeq", 154: "ifne", 155: "iflt", 156: "ifge", 157: "ifgt", 158: "ifle",
  159: "if_icmpeq", 160: "if_icmpne", 161: "if_icmplt", 162: "if_icmpge", 163: "if_icmpgt", 164: "if_icmple",
  165: "if_acmpeq", 166: "if_acmpne", 167: "goto", 168: "jsr", 169: "ret",
  170: "tableswitch", 171: "lookupswitch",
  172: "ireturn", 173: "lreturn", 174: "freturn", 175: "dreturn", 176: "areturn", 177: "return",
  178: "getstatic", 179: "putstatic", 180: "getfield", 181: "putfield",
  182: "invokevirtual", 183: "invokespecial", 184: "invokestatic", 185: "invokeinterface", 186: "invokedynamic",
  187: "new", 188: "newarray", 189: "anewarray", 190: "arraylength", 191: "athrow",
  192: "checkcast", 193: "instanceof", 194: "monitorenter", 195: "monitorexit", 196: "wide",
  197: "multianewarray", 198: "ifnull", 199: "ifnonnull", 200: "goto_w", 201: "jsr_w"
}};
const opName = op => mnemonic[op] || `opcode_${{op}}`;
const instructionValues = method => listValues(method.instructions);
const targetOffset = (instructions, pc) => instructions[pc] ? instructions[pc].offset >>> 0 : pc >>> 0;
const signed = value => value | 0;
const switchDetails = (method, instruction, instructions) => {{
  const tables = listValues(method.switches);
  const table = tables[instruction.b >>> 0];
  if (!table) return `default=${{targetOffset(instructions, instruction.a)}}`;
  const targets = listValues(table.targets);
  const details = [`default=${{targetOffset(instructions, instruction.a)}}`];
  if ((table.kind >>> 0) === 170) {{
    const low = signed(table.low), high = signed(table.high);
    for (let index = 0; index < targets.length; index++) {{
      details.push(`${{low + index}}:${{targetOffset(instructions, targets[index])}}`);
    }}
    if (targets.length === 0) details.push(`range=${{low}}..${{high}}`);
  }} else {{
    const keys = listValues(table.keys);
    for (let index = 0; index < targets.length; index++) {{
      details.push(`${{signed(keys[index] >>> 0)}}:${{targetOffset(instructions, targets[index])}}`);
    }}
  }}
  return details.join(" ");
}};
const instructionText = (method, instruction, instructions) => {{
  const op = instruction.op >>> 0;
  const prefix = instruction.c === 1 ? "wide " : "";
  const branch = (op >= 153 && op <= 168) || op === 198 || op === 199 || op === 200 || op === 201;
  let operands = "";
  if (op === 170 || op === 171) operands = switchDetails(method, instruction, instructions);
  else if (branch) operands = `target=${{targetOffset(instructions, instruction.a)}}`;
  else if ((op >= 21 && op <= 25) || (op >= 54 && op <= 58) || op === 169) operands = `local=${{instruction.a >>> 0}}`;
  else if (op === 132) operands = `local=${{instruction.a >>> 0}} increment=${{signed(instruction.b >>> 0)}}`;
  else if (op === 16 || op === 17) operands = `value=${{signed(instruction.a >>> 0)}}`;
  else if ((op >= 18 && op <= 20) || (op >= 178 && op <= 184) || op === 186 || op === 187 || op === 189 || op === 192 || op === 193) operands = `cp=${{instruction.a >>> 0}}`;
  else if (op === 185) operands = `cp=${{instruction.a >>> 0}} count=${{instruction.b >>> 0}}`;
  else if (op === 188) operands = `atype=${{instruction.a >>> 0}}`;
  else if (op === 197) operands = `cp=${{instruction.a >>> 0}} dimensions=${{instruction.b >>> 0}}`;
  return `${{prefix}}${{opName(op)}}${{operands ? " " + operands : ""}}`;
}};
if (request.mode === 1 || request.mode === 2) {{
  for (const value of classes) console.log(`class ${{className(value)}} version 52 constant pool fields methods attributes main`);
  if (request.mode === 2) for (const method of methods) {{
    console.log(`method ${{symbol(method.name)}}${{symbol(method.descriptor)}}`);
    const instructions = instructionValues(method);
    for (const instruction of instructions) console.log(`${{instruction.offset}} ${{instructionText(method, instruction, instructions)}}`);
  }}
  process.exit(0);
}}
if (request.mode === 3) for (const method of methods) {{
  const owner = classes[method.owner];
  const instructions = instructionValues(method);
  for (const instruction of instructions) {{
    console.error(`[${{className(owner)}}.${{symbol(method.name)}} pc=${{instruction.offset}}] ${{instructionText(method, instruction, instructions)}}`);
    console.error("stack: []");
  }}
}}
// Test hook: collect every N instructions without reusing slots, so a missing
// root surfaces as InvalidReference instead of silent aliasing.
const gcStress = Number(process.env.BENDJVM_GC_STRESS || 0);
if (gcStress > 0 && loaded.value.roots) {{
  loaded.value.roots.gc = 3;
  loaded.value.roots.stress = gcStress;
  loaded.value.roots.countdown = gcStress;
}}
if (loaded.value.host) {{
  loaded.value.host.cwd = request.cwd || process.cwd();
  loaded.value.host.caps = request.caps == null ? 3 : request.caps >>> 0;
}}
const startNs = process.hrtime.bigint();
function clock() {{
  const mono = process.hrtime.bigint() - startNs;
  const wall = BigInt(Date.now());
  return [Number(mono >> 32n) >>> 0, Number(mono & 0xFFFFFFFFn) >>> 0, Number(wall >> 32n) >>> 0, Number(wall & 0xFFFFFFFFn) >>> 0];
}}
// Completed host operations wait here until the VM is between rounds.
const completions = [];
const dispatched = new Set();
let wakeHost = null;
function deliver(completion) {{
  completions.push(completion);
  if (wakeHost) {{ const wake = wakeHost; wakeHost = null; wake(); }}
}}
function dispatch(vm) {{
  const threads = listValues(vm.host.sched.threads);
  for (const thread of threads) {{
    if ((thread.status >>> 0) !== 5 || kindOf(thread.wait) !== "HostOp") continue;
    const op = thread.wait.op >>> 0;
    if (dispatched.has(op)) continue;
    dispatched.add(op);
    performEffect(vm, op, thread.effect).then(deliver, error => deliver(next => runtime.completeFail(next, op, "java/io/IOException")));
  }}
}}
// The earliest deadline of a timed wait, in host milliseconds from now.
function nextDeadline(vm) {{
  let best = null;
  for (const thread of listValues(vm.host.sched.threads)) {{
    if (!isTrue(thread.timed)) continue;
    const at = (BigInt(thread.deadline.high >>> 0) << 32n) | BigInt(thread.deadline.low >>> 0);
    if (best === null || at < best) best = at;
  }}
  if (best === null) return null;
  const now = process.hrtime.bigint() - startNs;
  return best <= now ? 0 : Number((best - now + 999999n) / 1000000n);
}}
function flush(next) {{
  const vm = drainCloses(next);
  const printed = listValues(vm.output).reverse().map(text).join("");
  const errors = listValues(vm.host.errors).reverse().map(text).join("");
  if (!printed && !errors) return vm;
  if (printed) process.stdout.write(printed);
  if (errors) process.stderr.write(errors);
  return runtime.takeOutput(vm);
}}
// Inconsistent TLS material (a key that does not match its certificate, a
// malformed trust store) fails the launch before any Java code runs.
if (request.tls && (request.tls.key || request.tls.trust)) {{
  try {{
    const material = tlsConfig();
    tls.createSecureContext({{ key: material.key, cert: material.cert, ca: material.ca }});
  }} catch (error) {{
    console.error(`InvalidTlsConfiguration: ${{error.message}}`);
    process.exit(2);
  }}
}}
await (async () => {{
let vm = runtime.runLoadedEntry(loaded.value, request.fuel, request.entry, list(request.args), request.quantum || 1000, clock());
for (;;) {{
  vm = flush(vm);
  const status = vm.status >>> 0;
  if (status === 1 || status === 3 || status === 4) break;
  dispatch(vm);
  if (status === 7 && completions.length === 0) {{
    // Every live thread waits on the host or a timer.
    const delay = nextDeadline(vm);
    await new Promise(resolve => {{
      wakeHost = resolve;
      if (delay !== null) setTimeout(() => {{ if (wakeHost === resolve) wakeHost = null; resolve(); }}, delay);
    }});
  }} else {{
    // Let host I/O callbacks run between rounds.
    await new Promise(resolve => setImmediate(resolve));
  }}
  while (completions.length) vm = completions.shift()(vm);
  vm = runtime.continueRun(vm, clock());
}}
closeAll();
stopNativeHelper("java/lang/InternalError: VM exit");
if (sourceHost) sourceHost.stdin.end();
vm = flush(vm);
await new Promise(resolve => process.stdout.write("", resolve));
await new Promise(resolve => process.stderr.write("", resolve));
if (vm.status === 3) {{ console.error("OutOfFuel"); process.exit(1); }}
// An empty error: main's exception went to a Java UncaughtExceptionHandler.
if (vm.status === 4) {{ if (text(vm.error)) fail(vm.error); process.exit(1); }}
process.exit(0);
}})();
'''


def _split_classpath(value: str | None) -> list[str]:
    if value is None:
        return [str(Path.cwd())]
    return [part or str(Path.cwd()) for part in value.split(os.pathsep)]


def _entry_from_path(path: Path, info: ClassInfo) -> str:
    resolved = path.resolve()
    suffix = "/".join(info.name.split("/")) + ".class"
    if not str(resolved).endswith("/" + suffix) and resolved.name != suffix:
        raise ClasspathError(f"{resolved}: selected .class path does not match declared class {info.name}")
    return info.name

def _inspect_many(matches: list[SourceMatch]) -> list[ClassInfo]:
    if not matches:
        return []
    host = build_artifacts()
    payload = {
        "version": 1,
        "entry": "",
        "args": [],
        "fuel": 1,
        "maxHeap": 1,
        "mode": 4,
        "classes": [{"name": match.name, "origin": match.origin, "bytes": base64.b64encode(match.data).decode("ascii")} for match in matches],
        "resources": [],
    }
    with tempfile.NamedTemporaryFile(prefix="bendjvm-inspect-", suffix=".json", mode="w", encoding="utf-8", delete=False) as request:
        request.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    environment = os.environ.copy()
    environment["BENDJVM_REQUEST"] = request.name
    try:
        result = subprocess.run([BUN, str(host)], cwd=ROOT, env=environment, capture_output=True, text=True, check=False)
    finally:
        Path(request.name).unlink(missing_ok=True)
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        raise ClasspathError(message or "class inspect failed")
    try:
        rows = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ClasspathError(f"class inspect returned invalid JSON: {error}") from error
    if not isinstance(rows, list) or len(rows) != len(matches):
        raise ClasspathError("class inspect returned unexpected result")
    infos: list[ClassInfo] = []
    for row in rows:
        if not isinstance(row, dict):
            raise ClasspathError("class inspect returned unexpected result")
        name = row.get("name")
        dependencies = row.get("dependencies")
        if not isinstance(name, str) or not isinstance(dependencies, list) or not all(isinstance(item, str) for item in dependencies):
            raise ClasspathError("class inspect returned unexpected result")
        infos.append(ClassInfo(name, tuple(dict.fromkeys(dependencies))))
    return infos


def _resource_origin(source: Any, name: str) -> str:
    """The canonical origin of resource `name` in `source`: the JDK canonicalizes
    class path entries before it builds resource URLs (/var -> /private/var)."""
    if hasattr(source, "_entries"):
        return f"{os.path.realpath(source.origin)}!/{name}"
    path = str(Path(source.path).resolve().joinpath(*name.rstrip("/").split("/")))
    return path + "/" if name.endswith("/") else path


def _resources(classpath: Classpath) -> tuple[tuple[str, str], ...]:
    """Every resource ClassLoader.getResource can name, in class path order.

    Class files are resources too. Directories are named with and without a
    trailing slash, as URLClassLoader finds both; a jar's explicit directory
    entries likewise answer both spellings (ZipFile.getEntry adds the slash)."""
    found: list[tuple[str, str]] = []
    for source in classpath.sources:
        if hasattr(source, "_entries"):
            for name in sorted(source._entries):
                if name == "META-INF/MANIFEST.MF":
                    continue
                found.append((name, _resource_origin(source, name)))
                if name.endswith("/") and len(name) > 1:
                    found.append((name[:-1], _resource_origin(source, name[:-1])))
        elif hasattr(source, "path") and Path(source.path).is_dir():
            root = Path(source.path)
            for path in sorted(root.rglob("*")):
                name = path.relative_to(root).as_posix()
                found.append((name, _resource_origin(source, name)))
                if path.is_dir():
                    found.append((name + "/", _resource_origin(source, name + "/")))
    return tuple(found)


# MiniJRE classes every launch loads: the VM calls them itself (stack traces).
ALWAYS_LOADED = ("sun/misc/BendStackTrace",)


def _closure(classpath: Classpath, entry: str, selected: SourceMatch, known: set[str] | None = None,
             roots: tuple[str, ...] = ()) -> tuple[SourceMatch, ...]:
    matches: dict[str, SourceMatch] = {}
    pending: list[tuple[str, SourceMatch | None, str]] = [(entry, selected, entry)]
    pending.extend((root, None, "the VM") for root in roots)
    known = known or set()
    while pending:
        batch: list[tuple[str, SourceMatch]] = []
        while pending:
            name, pinned, requester = pending.pop(0)
            if name in matches or name in bootstrap_names() or name in known:
                continue
            match = pinned or find_class(classpath, name)
            if match is None:
                origins = ", ".join(source.origin for source in classpath.sources)
                raise ClasspathError(f"MissingClass: {name} required by {requester}; searched {origins}")
            matches[name] = match
            batch.append((name, match))
        if not batch:
            break
        infos = _inspect_many([match for _, match in batch])
        for (name, match), info in zip(batch, infos, strict=True):
            if info.name != name:
                raise ClasspathError(f"{match.origin}: declared class {info.name!r} does not match requested {name!r}")
            pending.extend((dependency, None, name) for dependency in info.dependencies if dependency not in matches)
    return tuple(matches.values())

def _host_requests(request_path: str) -> int:
    request = json.loads(Path(request_path).read_text(encoding="utf-8"))
    with Classpath(request.get("classpath", []), expand_manifests=False) as classpath:
        for line in sys.stdin:
            operation = {}
            try:
                operation = json.loads(line)
                if operation["kind"] == "RuntimeClass":
                    name = operation["name"].lstrip("[")
                    if name.startswith("L") and operation["name"].startswith("["):
                        name = name[1:-1]
                    selected = find_class(classpath, name)
                    if selected is None:
                        result = {"error": "java/lang/ClassNotFoundException", "detail": name.replace("/", ".")}
                    else:
                        matches = _closure(classpath, name, selected, set(operation["known"]))
                        result = {"classes": [base64.b64encode(match.data).decode("ascii") for match in matches]}
                elif operation["kind"] == "ListArchive":
                    # Central-directory order, as ZipFile.entries() enumerates.
                    try:
                        with zipfile.ZipFile(operation["origin"]) as archive:
                            result = {"names": archive.namelist()}
                    except FileNotFoundError:
                        result = {"error": "java/io/FileNotFoundException", "detail": operation["origin"] + " (No such file or directory)"}
                    except zipfile.BadZipFile:
                        result = {"error": "java/util/zip/ZipException", "detail": "zip END header not found"}
                elif operation["kind"] == "ReadPathBytes":
                    origin, entry = operation["origin"], operation["name"]
                    try:
                        if entry:
                            with zipfile.ZipFile(origin) as archive:
                                data = archive.read(entry)
                        else:
                            data = Path(origin).read_bytes()
                        result = {"bytes": base64.b64encode(data).decode("ascii")}
                    except (FileNotFoundError, KeyError, IsADirectoryError):
                        result = {"error": "java/io/FileNotFoundException", "detail": origin + (" entry " + entry if entry else "")}
                elif operation["kind"] == "ReadResource":
                    name, origin = operation["name"], operation["origin"]
                    selected = None
                    for source in classpath.sources:
                        if _resource_origin(source, name) == origin:
                            selected = source.find_resource(name)
                            break
                    result = {"bytes": base64.b64encode(selected.data).decode("ascii")} if selected is not None else {"error": "java/io/IOException"}
                else:
                    result = {"error": "java/lang/UnsupportedOperationException"}
            except (ClasspathError, ValueError, OSError) as error:
                message = str(error)
                category = "java/io/IOException" if operation.get("kind") == "ReadResource" else (
                    "java/lang/UnsupportedOperationException" if "UnsupportedFeature" in message else "java/lang/LinkageError")
                result = {"error": category, "detail": message}
            print(json.dumps(result, separators=(",", ":")), flush=True)
    return 0


def _parse_options(args: list[str]) -> tuple[dict[str, Any], str, list[str]]:
    if args and args[0].endswith(".bend"):
        args = args[1:]
    if args and args[0] == "--":
        args = args[1:]
    options: dict[str, Any] = {"classpath": None, "jar": False, "flags": []}
    index = 0
    while index < len(args):
        value = args[index]
        if value == "--":
            index += 1
            break
        if value in ("-cp", "-classpath", "--class-path"):
            if index + 1 >= len(args):
                raise LaunchUsageError(f"missing argument for {value}")
            options["classpath"] = args[index + 1]
            index += 2
            continue
        if value == "-jar":
            if index + 1 >= len(args):
                raise LaunchUsageError("missing archive after -jar")
            options["jar"] = True
            target = args[index + 1]
            return options, target, args[index + 2:]
        if value == "--quantum":
            # Instructions a Java thread runs before the scheduler switches (default 1000).
            if index + 1 >= len(args) or not args[index + 1].isdigit() or not 1 <= int(args[index + 1]) <= 1_000_000:
                raise LaunchUsageError("--quantum expects an instruction count from 1 to 1000000")
            options["flags"].extend((value, args[index + 1]))
            index += 2
            continue
        if value in ("--fuel", "--max-heap"):
            if index + 1 >= len(args):
                raise LaunchUsageError(f"missing value for {value}")
            try:
                number = int(args[index + 1], 10)
            except ValueError as error:
                raise LaunchUsageError(f"invalid value for {value}") from error
            if number < 0:
                raise LaunchUsageError(f"invalid value for {value}")
            options["fuel" if value == "--fuel" else "max_heap"] = number
            options["flags"].extend((value, str(number)))
            index += 2
            continue
        if value in ("--dump-class", "--disassemble", "--trace"):
            options["mode"] = {"--dump-class": 1, "--disassemble": 2, "--trace": 3}[value]
            options["flags"].append(value)
            index += 1
            continue
        if value in ("--tls-trust", "--tls-key", "--tls-cert"):
            # The fixed TLS provider's trust roots and identity (plan 05, slice 8).
            if index + 1 >= len(args):
                raise LaunchUsageError(f"missing value for {value}")
            _check_pem(value, args[index + 1])
            options["flags"].extend((value, os.path.realpath(args[index + 1])))
            index += 2
            continue
        if value in ("--native-library", "--native-allow", "--native-timeout"):
            # Native plugins load only from paths named here (plan 05, slice 6).
            if index + 1 >= len(args):
                raise LaunchUsageError(f"missing value for {value}")
            argument = args[index + 1]
            if value == "--native-library":
                name, _, path = argument.partition("=")
                if not name or not path or "/" in name or not os.path.isabs(path):
                    raise LaunchUsageError("--native-library expects NAME=/absolute/path")
            elif value == "--native-allow":
                if not os.path.isabs(argument):
                    raise LaunchUsageError("--native-allow expects an absolute path")
            elif not argument.isdigit() or int(argument) <= 0:
                raise LaunchUsageError("invalid value for --native-timeout")
            options["flags"].extend((value, argument))
            index += 2
            continue
        if value in ("--no-files", "--no-net"):
            options["flags"].append(value)
            index += 1
            continue
        if value.startswith("-"):
            raise LaunchUsageError(f"unknown VM option before launch target: {value}")
        target = value
        return options, target, args[index + 1:]
    raise LaunchUsageError("missing launch target")


def _make_launch(args: list[str]) -> Launch:
    options, target, app_args = _parse_options(args)
    fuel = options.get("fuel", 1_000_000)
    max_heap = options.get("max_heap", 1024)
    mode = options.get("mode", 0)
    if options["jar"]:
        archive = Path(target).resolve()
        with Classpath([archive]) as classpath:
            if not classpath.sources or not hasattr(classpath.sources[0], "manifest_attributes"):
                raise ClasspathError(f"{archive}: -jar target is not a readable JAR/ZIP")
            attributes = classpath.sources[0].manifest_attributes()
            main = attributes.get("main-class", "").strip()
            if not main:
                raise ClasspathError(f"{archive}: manifest is missing Main-Class")
            entry = main.replace(".", "/")
            selected = classpath.find_class(entry)
            if selected is None:
                raise ClasspathError(f"{archive}: Main-Class {entry!r} was not found")
            classes = _closure(classpath, entry, selected, roots=ALWAYS_LOADED)
            resources = _resources(classpath)
            return Launch(entry, classes, tuple(str(source.path) for source in classpath.sources), resources, tuple(app_args), tuple(options["flags"]), mode, fuel, max_heap)
    if target.endswith(".class"):
        selected_path = Path(target).resolve()
        try:
            selected = SourceMatch(str(selected_path), selected_path.read_bytes(), str(selected_path), None)  # type: ignore[arg-type]
        except OSError as error:
            raise ClasspathError(f"{selected_path}: cannot read selected class: {error}") from error
        info = _inspect_many([selected])[0]
        entry = _entry_from_path(selected_path, info)
        package_parts = entry.split("/")[:-1]
        root = selected_path.parent
        for _ in package_parts:
            root = root.parent
        environment_classpath = os.environ.get("CLASSPATH")
        extra_paths = _split_classpath(environment_classpath) if environment_classpath is not None else []
        paths = [root, *extra_paths]
        with Classpath(paths) as classpath:
            classes = _closure(classpath, entry, selected, roots=ALWAYS_LOADED)
            resources = _resources(classpath)
            return Launch(entry, classes, tuple(str(source.path) for source in classpath.sources), resources, tuple(app_args), tuple(options["flags"]), mode, fuel, max_heap)
    entry = target.replace(".", "/")
    paths = _split_classpath(options["classpath"] if options["classpath"] is not None else os.environ.get("CLASSPATH"))
    with Classpath(paths) as classpath:
        selected = classpath.find_class(entry)
        if selected is None:
            raise ClasspathError(f"MissingClass: {entry}; searched {', '.join(source.origin for source in classpath.sources)}")
        classes = _closure(classpath, entry, selected, roots=ALWAYS_LOADED)
        resources = _resources(classpath)
        return Launch(entry, classes, tuple(str(source.path) for source in classpath.sources), resources, tuple(app_args), tuple(options["flags"]), mode, fuel, max_heap)


def _quantum(flags: tuple[str, ...]) -> int:
    quantum = 1000
    for flag, value in itertools.pairwise(flags):
        if flag == "--quantum":
            quantum = int(value)
    return quantum


def _check_pem(flag: str, path: str) -> None:
    """Rejects unreadable or non-PEM TLS material before anything runs."""
    marker = {"--tls-trust": b"-----BEGIN CERTIFICATE-----", "--tls-cert": b"-----BEGIN CERTIFICATE-----",
              "--tls-key": b"PRIVATE KEY-----"}[flag]
    try:
        data = Path(path).read_bytes()
    except OSError as error:
        raise LaunchUsageError(f"{flag}: cannot read {path}: {error.strerror}") from error
    if marker not in data:
        raise LaunchUsageError(f"{flag}: {path} is not PEM {'private key' if flag == '--tls-key' else 'certificate'} material")


def _tls_config(flags: tuple[str, ...]) -> dict[str, str]:
    config: dict[str, str] = {}
    for flag, value in itertools.pairwise(flags):
        if flag in ("--tls-trust", "--tls-key", "--tls-cert"):
            config[flag[6:]] = value
    if ("key" in config) != ("cert" in config):
        raise LaunchUsageError("--tls-key and --tls-cert must be given together")
    return config


def _native_config(flags: tuple[str, ...]) -> dict[str, Any]:
    libraries: dict[str, str] = {}
    allowed: list[str] = []
    timeout = 30000
    for flag, value in itertools.pairwise(flags):
        if flag == "--native-library":
            name, _, path = value.partition("=")
            libraries[name] = os.path.realpath(path)
            allowed.append(os.path.realpath(path))
        elif flag == "--native-allow":
            allowed.append(os.path.realpath(value))
        elif flag == "--native-timeout":
            timeout = int(value)
    return {"libraries": libraries, "allowed": allowed, "timeout": timeout,
            "helper": str(native_helper()) if allowed else ""}


def _request(launch: Launch) -> str:
    payload = {
        "version": 1,
        "entry": launch.entry,
        "args": list(launch.app_args),
        "fuel": launch.fuel,
        "maxHeap": launch.max_heap,
        "mode": launch.mode,
        "cwd": os.getcwd(),
        "caps": (0 if "--no-files" in launch.flags else 1) | (0 if "--no-net" in launch.flags else 2),
        "natives": _native_config(launch.flags),
        "tls": _tls_config(launch.flags),
        "quantum": _quantum(launch.flags),
        "classpath": list(launch.classpath),
        "classes": [{"name": match.name, "origin": match.origin, "bytes": base64.b64encode(match.data).decode("ascii")} for match in launch.classes],
        "resources": [{"name": name, "origin": origin} for name, origin in launch.resources],
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _write_request(launch: Launch) -> Path:
    with tempfile.NamedTemporaryFile(prefix="bendjvm-request-", suffix=".json", mode="w", encoding="utf-8", delete=False) as request:
        request.write(_request(launch))
    return Path(request.name)


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--host-requests":
        return _host_requests(args[1])
    if args and args[0] == "--prepare":
        try:
            build_artifacts()
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
            print(f"runner setup failed: {error}", file=sys.stderr)
            return 1
        return 0
    try:
        launch = _make_launch(args)
    except (ClasspathError, LaunchUsageError) as error:
        print(error, file=sys.stderr)
        return 2 if isinstance(error, LaunchUsageError) else 1
    # Resolving the class closure needs the bootstrap class list, which can
    # trigger an artifact build; report its failure like any other setup error.
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"runner setup failed: {error}", file=sys.stderr)
        return 1
    try:
        host = build_artifacts()
        request = _write_request(launch)
        environment = os.environ.copy()
        environment["BENDJVM_REQUEST"] = str(request)
        try:
            result = subprocess.run([BUN, str(host)], cwd=ROOT, env=environment, check=False)
        finally:
            request.unlink(missing_ok=True)
        return result.returncode
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"runner setup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
