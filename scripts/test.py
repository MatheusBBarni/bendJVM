#!/usr/bin/env python3
"""End-to-end JVM differential checks using only the Python standard library.

Requirements: Python 3.10+, JDK 9+ (javac --release 8 and java), Bend 2.
Run from the project root: python3 scripts/test.py --fast
Full corpus and 24 generated programs: python3 scripts/test.py --full
Select fixtures: python3 scripts/test.py --only Arithmetic --only IntArray
Select named checks: python3 scripts/test.py --check resources/url --check AccessRules
Override tools with --bend, --java, --javac or BEND, JAVA, JAVAC.
Compilation and mutated class files live in a temporary directory outside the repo.
"""

import argparse
import difflib
import os
import random
import re
import shutil
import signal
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import warnings
import zipfile
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path

import jre_audit
import tls_fixtures
from indy_fixtures import BOOTSTRAP_SOURCE, generated_classes

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "bendjvm" / "tests" / "fixtures"
DEFAULT_BEND = str(ROOT / "scripts" / "run.py")
# The isolated classes the class loader check serves only as "*.bytes" resources.
ISOLATED = ("Payload", "Helper", "Tag", "Box", "Reader", "Serial")
MAIN = str(ROOT / "bendjvm" / "main.bend")
# Working directory for every oracle and Bend subprocess. main() points it at a
# scratch directory so fixtures that write relative files never touch the repo.
WORKDIR = ROOT
NAMED = (
    "HelloInteger", "Arithmetic", "Branching", "WhileLoop", "ForLoop",
    "StaticMethod", "RecursiveMethod", "MultipleArguments", "ObjectCreation",
    "Fields", "VirtualMethod", "IntArray", "ObjectArray", "StringConstant",
    "Println", "ExceptionCaught", "ExceptionUncaught", "MetadataFixture",
    "AnnotationParserBoundaries", "ReflectionAccess", "RepeatableAnnotation",
    "InheritedAnnotation", "EnumAnnotation", "ProxyIntegration", "ProxyExceptions",
    "DynamicLoadingFailure", "ReflectionIntegration", "CrossPackageReflection",
    "WideAllocationLimit", "WideSwitchFixture", "WideStackForms", "SwitchFixture", "VerifierFixture",
    "MethodHandleFixture", "LambdaFixture", "GenericSignature", "ReflectionFixture",
    "DoubleFormatting", "HostCallbacks", "InitSemantics", "ParameterReflection", "ComparableValues", "ArraySemantics", "NestedClasses", "GenericDeclarations", "ReflectionStrings", "PrivilegedActions", "AccessRules", "DefaultMethodProxy", "AnnotationFormatting", "AnnotatedTypes", "SubclassProxies", "SerializationStreams", "SerializationEvolution", "SerializationHooks",
    "ThreadLifecycle", "MonitorSemantics", "VolatilePublication", "ConcurrentTcp", "DaemonExit",
    "NetAddresses", "ThreadGroups", "ApiSurface",
)
EXTENDED = (
    "FloatOperations", "FloatArray", "InheritedFields", "ClassInitialization",
    "SignedArithmetic", "RuntimeExceptions", "ReferenceTypes", "Utf16Strings",
    "ObjectStringInteger", "Collections", "MemoryStreams",
    "ArrayCopy", "FileRoundtrip", "InterfaceCollections",
    "LineReader", "TryWithResources", "TcpEcho", "TcpAccept",
    "TcpRefused", "TcpTimeout", "SuppressionTWR", "NioSelectorEcho",
)
SUPPORT = ("FuelLimit", "HeapLimit", "MutationTarget", "TlsFixture", "MainHandled", "LockOrderDeadlock",
           "FuelWithBlockedThreads", "ThreadPriorities")
# Launcher flags for fixtures whose threads spin on purpose (plan 05).
FIXTURE_FLAGS = {
    "ThreadLifecycle": ("--fuel", "60000000"),
    "MonitorSemantics": ("--fuel", "60000000"),
    "VolatilePublication": ("--fuel", "60000000"),
    "ConcurrentTcp": ("--fuel", "60000000"),
    "NioSelectorEcho": ("--fuel", "60000000"),
    "DaemonExit": ("--fuel", "60000000"),
    "ThreadGroups": ("--fuel", "60000000"),
    "ApiSurface": ("--fuel", "60000000"),
}
NATIVE = FIXTURES / "native"
WEB_EXAMPLE = ROOT / "examples" / "webserver"
PLUGIN_HEADER = ROOT / "bendjvm" / "native"
NATIVE_EXPECTED = """add: 42 -2147483648
mulWide: 21000000000 -9223372036854775808
scale: -3.375
fill: 126 127 -128 -127 -126
sum: 400006
greet: hello, Bend \u263a!
counter: 42 43
closed handle: invalid native handle
forged handle: invalid native handle
mapped failure: plugin said no
unregistered failure: java.lang.IllegalStateException
null buffer: buffer
unbound: NativeDemo.unbound(I)I
disallowed load: java.lang.UnsatisfiedLinkError
unknown library: no unknownlib in java.library.path
progress during slow call: true
locked: 3 holds after: false
crash contained: native helper terminated
after crash: java.lang.UnsatisfiedLinkError
done
"""


def shared_library_name(stem: str) -> str:
    return f"lib{stem}.dylib" if sys.platform == "darwin" else f"lib{stem}.so"


def compile_plugin(source: Path, output: Path) -> Path:
    compiler = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    require(compiler is not None, "a C compiler (cc) is required for native plugin checks")
    flags = ["-dynamiclib"] if sys.platform == "darwin" else ["-shared", "-fPIC"]
    result = subprocess.run([compiler, *flags, "-Wall", "-Wextra", "-Werror", "-I", str(PLUGIN_HEADER),
                             "-o", str(output), str(source)], capture_output=True, text=True, check=False)
    require(result.returncode == 0, f"plugin compilation failed\n{result.stdout}{result.stderr}")
    return output


def helper_processes() -> set[int]:
    """Native helper processes alive on this machine (supervision checks)."""
    result = subprocess.run(["pgrep", "-f", "bendjvm-cache/native-helper-"], capture_output=True, text=True, check=False)
    return {int(pid) for pid in result.stdout.split()}
FIXTURE_DEPENDENCIES = {
    "CrossPackageReflection": ("CrossPackageTarget.java", "CrossPackageSubclass.java"),
    "ProxyIntegration": ("ProxyHidden.java", "ProxyOtherHidden.java"),
    "AccessRules": ("AccessRulesBase.java", "AccessRulesSub.java"),
}

FixtureValue = bytes | bytearray | memoryview | str
FixtureEntries = Mapping[str, FixtureValue]


def _fixture_bytes(value: FixtureValue) -> bytes:
    if isinstance(value, str):
        return value.encode("utf-8")
    if isinstance(value, (bytes, bytearray, memoryview)):
        return bytes(value)
    raise TypeError(f"fixture entry must be text or bytes, got {type(value).__name__}")


def _fixture_name(name: str) -> str:
    if not isinstance(name, str) or not name:
        raise ValueError("fixture entry names must be non-empty strings")
    if "\\" in name or name.startswith("/"):
        raise ValueError(f"unsafe fixture entry name: {name!r}")
    parts = name.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"unsafe fixture entry name: {name!r}")
    return name


def _merged_fixture_entries(entries: FixtureEntries | None,
                            resources: FixtureEntries | None) -> dict[str, bytes]:
    merged: dict[str, bytes] = {}
    for source in (entries or {}, resources or {}):
        for name, value in source.items():
            normalized = _fixture_name(name)
            if normalized in merged:
                raise ValueError(f"duplicate fixture entry: {normalized!r}")
            merged[normalized] = _fixture_bytes(value)
    return merged


def write_fixture_directory(root: Path, entries: FixtureEntries | None = None,
                            *, resources: FixtureEntries | None = None) -> Path:
    """Write deterministic class/resource entries below a classpath directory."""
    destination = Path(root)
    destination.mkdir(parents=True, exist_ok=True)
    for name, contents in sorted(_merged_fixture_entries(entries, resources).items()):
        path = destination.joinpath(*name.split("/"))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
    return destination


def manifest_bytes(*, main_class: str | None = None,
                   class_path: Iterable[str] = (),
                   attributes: Mapping[str, str] | None = None,
                   line_ending: str = "\r\n") -> bytes:
    """Return a deterministic UTF-8 manifest with an optional main section."""
    if line_ending not in ("\r\n", "\n"):
        raise ValueError("manifest line ending must be CRLF or LF")
    values = dict(attributes or {})
    names = {name.lower(): name for name in values}
    if len(names) != len(values):
        raise ValueError("manifest attribute names must be unique case-insensitively")
    values[names.get("manifest-version", "Manifest-Version")] = "1.0"
    if main_class is not None:
        values[names.get("main-class", "Main-Class")] = main_class
    paths = tuple(class_path)
    if paths:
        values[names.get("class-path", "Class-Path")] = " ".join(paths)
    for name, value in values.items():
        if not name or "\r" in name or "\n" in name or ":" in name:
            raise ValueError(f"invalid manifest attribute name: {name!r}")
        if "\r" in str(value) or "\n" in str(value):
            raise ValueError(f"invalid manifest attribute value for {name!r}")
    manifest_name = names.get("manifest-version", "Manifest-Version")
    ordered = [manifest_name] + sorted(
        (name for name in values if name != manifest_name),
        key=lambda name: (name.lower(), name),
    )
    lines: list[str] = []
    for name in ordered:
        value = str(values[name])
        prefix = f"{name}: "
        current = prefix
        for character in value:
            if len((current + character).encode("utf-8")) > 70 and current != prefix:
                lines.append(current)
                current = " "
            current += character
        lines.append(current)
    return (line_ending.join(lines) + line_ending + line_ending).encode("utf-8")


def write_manifest(path: Path, **kwargs: object) -> Path:
    """Write :func:`manifest_bytes` to a file and return its path."""
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(manifest_bytes(**kwargs))
    return destination


def write_fixture_archive(path: Path, entries: FixtureEntries | None = None,
                          *, resources: FixtureEntries | None = None,
                          manifest: bytes | None = None,
                          compression: int = zipfile.ZIP_DEFLATED) -> Path:
    """Write a reproducible JAR/ZIP fixture without filesystem extraction."""
    if compression not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        raise ValueError("fixture archives support only stored or deflated entries")
    merged = _merged_fixture_entries(entries, resources)
    if manifest is not None:
        manifest_name = "META-INF/MANIFEST.MF"
        if manifest_name in merged:
            raise ValueError(f"duplicate fixture entry: {manifest_name!r}")
        merged[manifest_name] = _fixture_bytes(manifest)
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=compression,
                         allowZip64=False) as archive:
        for name in sorted(merged):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = compression
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, merged[name])
    return destination


def write_fixture_jar(path: Path, entries: FixtureEntries | None = None,
                      **kwargs: object) -> Path:
    """Write a deterministic JAR fixture; arguments match write_fixture_archive."""
    return write_fixture_archive(path, entries, **kwargs)


def write_fixture_zip(path: Path, entries: FixtureEntries | None = None,
                      **kwargs: object) -> Path:
    """Write a deterministic ZIP fixture; arguments match write_fixture_archive."""
    return write_fixture_archive(path, entries, **kwargs)


class Failure(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Failure(message)


def compiler_output(text: str) -> str:
    # Remove only the compiler's leading banner, never arbitrary program lines.
    prefix = "All terms check.\n"
    return text.removeprefix(prefix)


@dataclass
class Run:
    command: list[str]
    code: int
    stdout: str
    stderr: str

    def detail(self) -> str:
        return (f"command: {self.command!r}\nexit: {self.code}\n"
                f"stdout: {self.stdout!r}\nstderr: {self.stderr!r}")


def execute(command: list[str], timeout: float, bend: bool = False) -> Run:
    environment = os.environ.copy()
    environment.update(BEND_NO_TELEMETRY="1", NO_COLOR="1")
    # Avoid inherited JVM flags contaminating reference output or changing semantics.
    for key in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS"):
        environment.pop(key, None)
    try:
        process = subprocess.Popen(command, cwd=WORKDIR, env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=os.name == "posix")
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            if os.name == "posix":
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            else:
                process.kill()
            try:
                stdout, stderr = process.communicate(timeout=2.0)
            except subprocess.TimeoutExpired:
                if os.name == "posix":
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                else:
                    process.kill()
                stdout, stderr = process.communicate()
            raise Failure(f"timeout after {timeout}s: {command!r}\n"
                          f"stdout: {stdout!r}\nstderr: {stderr!r}") from error
    except OSError as error:
        raise Failure(f"cannot run {command[0]}: {error}") from error
    try:
        out = stdout.decode("utf-8").replace("\r\n", "\n")
        err = stderr.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as error:
        raise Failure(f"non-UTF-8 process output: {command!r}: {error}") from error
    if bend:
        out, err = compiler_output(out), compiler_output(err)
    return Run(command, process.returncode, out, err)


def same_output(expected: str, actual: str, context: str) -> None:
    if expected != actual:
        difference = "".join(difflib.unified_diff(
            expected.splitlines(keepends=True), actual.splitlines(keepends=True),
            fromfile="reference java", tofile="BendJVM"))
        raise Failure(f"stdout mismatch\n{difference}\n"
                      f"expected: {expected!r}\nactual: {actual!r}\n{context}")


def exception_class(output: str) -> str | None:
    # Accept java.lang subpackages such as java.lang.invoke.WrongMethodTypeException.
    found = re.search(r"java[/.]lang[/.](?:[a-z]+[/.])*([A-Za-z]+(?:Exception|Error))\b", output)
    return found.group(1) if found else None


def generated_source(index: int, rng: random.Random) -> tuple[str, str]:
    name = f"GeneratedInteger{index:03d}"
    edges = [-2147483648, -2147483647, -65537, -33, -1, 0, 1, 31, 65535, 2147483647]
    a = rng.choice(edges) if index % 2 == 0 else rng.randint(-2147483648, 2147483647)
    b = rng.randint(-2147483648, 2147483647)
    multiplier = rng.randrange(1, 65536, 2)
    divisor = rng.choice([-31, -7, -3, -1, 1, 3, 7, 31])
    shift = rng.choice([-33, -1, 0, 1, 31, 32, 33, 63])
    rounds = rng.randint(3, 13)
    operations = [
        f"x += y * {multiplier};", f"x ^= y >>> {shift};",
        f"x -= y << {shift};", f"x = (x / {divisor}) + (y % {divisor});",
        f"x = (x >> {shift}) | (y & {multiplier});", "x = -x + y;",
    ]
    rng.shuffle(operations)
    body = "\n            ".join(operations)
    return name, f"""public class {name} {{
    static int mix(int x, int y) {{
        if (x < y) x ^= y; else x += y;
        {body}
        return x;
    }}
    public static void main(String[] args) {{
        int x = {a}, y = {b};
        for (int i = 0; i < {rounds}; i++) {{
            x = mix(x, y);
            if ((x & 1) == 0) y += x; else y -= x;
            System.out.println(x);
        }}
        System.out.println(y);
    }}
}}
"""


@dataclass
class CodeAttribute:
    length_offset: int
    payload_start: int
    payload_end: int
    max_locals: int


@dataclass
class ClassLayout:
    pool: dict[int, tuple[int, int, int]]
    utf: dict[int, str]
    this_class_offset: int
    methods: dict[str, CodeAttribute]
    attributes: dict[str, list[tuple[int, int]]]
    method_headers: dict[str, tuple[int, int, int]]


def u2(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def u4(data: bytes, offset: int) -> int:
    return struct.unpack_from(">I", data, offset)[0]


def class_layout(data: bytes) -> ClassLayout:
    """Locate mutation sites in a javac-produced file, without relying on offsets."""
    require(data[:4] == bytes.fromhex("cafebabe"), "javac output has invalid magic")
    count, position, index = u2(data, 8), 10, 1
    pool, utf = {}, {}
    sizes = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4,
             11: 4, 12: 4, 15: 3, 16: 2, 18: 4}
    while index < count:
        start, tag = position, data[position]
        position += 1
        if tag == 1:
            size = u2(data, position)
            position += 2
            # MutationTarget has ASCII names; this is not a modified-UTF8 decoder.
            utf[index] = data[position:position + size].decode("ascii")
            position += size
        else:
            require(tag in sizes, f"unexpected javac constant-pool tag {tag}")
            position += sizes[tag]
        pool[index] = (tag, start, position)
        index += 2 if tag in (5, 6) else 1
    this_class_offset = position + 2
    position += 6
    interfaces = u2(data, position)
    position += 2 + interfaces * 2
    methods = {}
    method_headers: dict[str, tuple[int, int, int]] = {}
    attributes: dict[str, list[tuple[int, int]]] = {}
    for section in ("fields", "methods"):
        members = u2(data, position)
        position += 2
        for _ in range(members):
            member_start = position
            name = utf[u2(data, member_start + 2)]
            descriptor_index = u2(data, member_start + 4)
            attribute_count = u2(data, member_start + 6)
            if section == "methods":
                method_headers[name] = (member_start, member_start + 4, descriptor_index)
            position += 8
            for _ in range(attribute_count):
                attribute_name = utf[u2(data, position)]
                length_offset = position + 2
                length = u4(data, length_offset)
                payload_start = position + 6
                position = payload_start + length
                attributes.setdefault(attribute_name, []).append((payload_start, length))
                if section == "methods" and attribute_name == "Code":
                    methods[name] = CodeAttribute(length_offset, payload_start,
                                                  position, u2(data, payload_start + 2))
    class_attribute_count = u2(data, position)
    position += 2
    for _ in range(class_attribute_count):
        attribute_name = utf[u2(data, position)]
        length = u4(data, position + 2)
        payload_start = position + 6
        position = payload_start + length
        attributes.setdefault(attribute_name, []).append((payload_start, length))
    return ClassLayout(pool, utf, this_class_offset, methods, attributes, method_headers)


def patch(data: bytes, offset: int, replacement: bytes) -> bytes:
    return data[:offset] + replacement + data[offset + len(replacement):]


def replace_main(data: bytes, site: CodeAttribute, code: bytes, max_stack: int = 2) -> bytes:
    # Replace the complete Code attribute, removing stale line tables and stack maps.
    payload = struct.pack(">HHI", max_stack, site.max_locals, len(code)) + code + b"\0\0\0\0"
    return (data[:site.length_offset] + struct.pack(">I", len(payload)) + payload
            + data[site.payload_end:])

def class_constant_index(data: bytes, layout: ClassLayout, name: str) -> int:
    for index, (tag, start, _end) in layout.pool.items():
        if tag == 7 and layout.utf.get(u2(data, start + 1)) == name:
            return index
    raise Failure(f"class constant not found: {name}")


def member_reference_index(data: bytes, layout: ClassLayout, tag: int,
                           owner: str, name: str, descriptor: str) -> int:
    for index, (entry_tag, start, _end) in layout.pool.items():
        if entry_tag != tag:
            continue
        owner_index = u2(data, start + 1)
        owner_entry = layout.pool.get(owner_index)
        name_type_index = u2(data, start + 3)
        name_type = layout.pool.get(name_type_index)
        if owner_entry is None or name_type is None or name_type[0] != 12:
            continue
        actual_owner = layout.utf.get(u2(data, owner_entry[1] + 1))
        actual_name = layout.utf.get(u2(data, name_type[1] + 1))
        actual_descriptor = layout.utf.get(u2(data, name_type[1] + 3))
        if (actual_owner, actual_name, actual_descriptor) == (owner, name, descriptor):
            return index
    raise Failure(f"member reference not found: {owner}.{name}{descriptor}")


def replace_method_code(data: bytes, site: CodeAttribute, code: bytes,
                        max_stack: int, max_locals: int, *,
                        exception_entries: tuple[bytes, ...] = (),
                        nested_attributes: tuple[bytes, ...] = ()) -> bytes:
    payload = (struct.pack(">HHI", max_stack, max_locals, len(code)) + code +
               struct.pack(">H", len(exception_entries)) + b"".join(exception_entries) +
               struct.pack(">H", len(nested_attributes)) + b"".join(nested_attributes))
    return (data[:site.length_offset] + struct.pack(">I", len(payload)) + payload
            + data[site.payload_end:])


def malformed_cases(original: bytes, full: bool) -> list[tuple[str, bytes, str]]:
    layout = class_layout(original)
    site = layout.methods["main"]
    first_pool = layout.pool[1]
    utf_index = next(i for i, item in layout.pool.items() if item[0] == 1)
    class_index = u2(original, layout.this_class_offset)
    class_entry = layout.pool[class_index]
    invalid_pool = r"InvalidConstantPool|VerifyError"
    cases = [
        ("magic", patch(original, 0, b"\x00"), r"InvalidMagic"),
        ("truncated-header", original[:7], r"InvalidClassFile"),
        ("truncated-pool", original[:first_pool[2] - 1], r"InvalidClassFile|InvalidConstantPool"),
        ("truncated-code", original[:site.payload_start + 8], r"InvalidClassFile"),
        ("pool-tag", patch(original, first_pool[1], b"\x02"), r"InvalidConstantPool"),
        ("pool-class-index", patch(original, class_entry[1] + 1, b"\x00\x00"), invalid_pool),
        ("stack-underflow", replace_main(original, site, b"\x57\xb1"), r"VerifyError"),
        ("stack-overflow", replace_main(original, site, b"\x03\x57\xb1", 0), r"VerifyError"),
        ("local-index", replace_main(original, site, b"\x15\xff\x57\xb1"), r"VerifyError"),
        ("branch-operand", replace_main(original, site, b"\xa7\x00\x01\xb1"), r"InvalidBytecode|VerifyError"),
        ("instruction-truncated", replace_main(original, site, b"\x11\x01"), r"InvalidBytecode"),
        ("opcode-unsupported", replace_main(original, site, b"\xa8\x00\x00\xb1"), r"UnsupportedOpcode"),
        ("monitorenter-empty-stack", replace_main(original, site, b"\xc2\xb1"), r"VerifyError"),
        ("field-pool-zero", replace_main(original, site, b"\xb2\x00\x00\x57\xb1"), invalid_pool),
        ("unreachable-field-pool-zero", replace_main(original, site, b"\xb1\xb2\x00\x00\x57\xb1"), invalid_pool),
        ("opcode-reserved", replace_main(original, site, b"\xcb\xb1"), r"InvalidOpcode"),
    ]
    if full:
        cases.extend([
            ("empty", b"", r"InvalidClassFile|InvalidMagic"),
            ("truncated-tail", original[:-1], r"InvalidClassFile"),
            ("class-version", patch(original, 6, struct.pack(">H", 65)), r"UnsupportedClassVersion"),
            ("pool-class-wrong-tag", patch(original, class_entry[1] + 1, struct.pack(">H", class_index)), invalid_pool),
            ("field-pool-wrong-tag", replace_main(original, site, b"\xb2" + struct.pack(">H", utf_index) + b"\x57\xb1"), invalid_pool),
            ("branch-outside", replace_main(original, site, b"\xa7\x00\x7f\xb1"), r"InvalidBytecode|VerifyError"),
            ("stack-merge", replace_main(original, site, b"\x03\x99\x00\x07\x04\xa7\x00\x03\xb1"), r"VerifyError"),
        ])
    return cases


class Suite:
    def __init__(self, args: argparse.Namespace, classes: Path):
        self.args = args
        self.classes = classes
        self.passed = 0
        self.failed = 0

    def bend(self, classfile: Path, *flags: str) -> Run:
        return execute([self.args.bend, MAIN, "--", *flags, str(classfile)],
                       self.args.timeout, bend=True)

    def check(self, name: str, action: Callable[[], None]) -> None:
        if self.args.check and not any(pattern in name for pattern in self.args.check):
            return
        started = time.monotonic()
        try:
            action()
        except Failure as error:
            self.failed += 1
            print(f"FAIL {name}\n{error}", flush=True)
            if self.args.fail_fast:
                raise
        else:
            self.passed += 1
            print(f"PASS {name} ({time.monotonic() - started:.2f}s)", flush=True)
    def tcp_echo(self) -> None:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        server.listen(2)
        port = str(server.getsockname()[1])

        def serve() -> None:
            for _ in range(2):
                conn, _addr = server.accept()
                try:
                    data = conn.recv(1)
                    if data:
                        conn.sendall(bytes([(data[0] + 1) & 255]))
                finally:
                    conn.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        try:
            reference = execute([self.args.java, "-Dfile.encoding=UTF-8", "-cp", str(self.classes), "TcpEcho", port],
                                self.args.timeout)
            actual = execute([self.args.bend, MAIN, "--", str(self.classes / "TcpEcho.class"), port],
                             self.args.timeout, bend=True)
            require(reference.code == 0, f"reference failed\n{reference.detail()}")
            require(actual.code == 0, f"Bend failed\n{actual.detail()}")
            same_output(reference.stdout, actual.stdout, actual.detail())
            require(not reference.stderr, f"reference stderr\n{reference.detail()}")
            require(not actual.stderr, f"unexpected Bend stderr\n{actual.detail()}")
        finally:
            server.close()

    def tcp_accept(self) -> None:
        def probe(command: list[str]) -> bytes:
            binder = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            binder.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            binder.bind(("127.0.0.1", 0))
            port = binder.getsockname()[1]
            binder.close()
            proc = subprocess.Popen(command + [str(port)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + self.args.timeout
                data = b""
                while time.monotonic() < deadline:
                    try:
                        client = socket.create_connection(("127.0.0.1", port), 0.2)
                        try:
                            client.sendall(b"A")
                            client.settimeout(self.args.timeout)
                            data = client.recv(1)
                        finally:
                            client.close()
                        break
                    except OSError:
                        if proc.poll() is not None:
                            stdout, stderr = proc.communicate()
                            raise Failure(f"server exited early\ncode={proc.returncode}\nstdout={stdout!r}\nstderr={stderr!r}")
                        time.sleep(0.05)
                else:
                    proc.kill()
                    raise Failure("server did not accept")
                code = proc.wait(timeout=self.args.timeout)
                stdout, stderr = proc.communicate()
                require(code == 0, f"server failed code={code} stdout={stdout!r} stderr={stderr!r}")
                require(data == b"B", f"expected echoed B, got {data!r}")
                return data
            except Exception:
                proc.kill()
                raise

        probe([self.args.java, "-Dfile.encoding=UTF-8", "-cp", str(self.classes), "TcpAccept"])
        probe([self.args.bend, MAIN, "--", str(self.classes / "TcpAccept.class")])

    def parameter_names(self, directory: Path) -> None:
        """ParameterReflection again, compiled with javac -parameters (MethodParameters names)."""
        output = directory / "parameter-names"
        compilation = execute(
            [self.args.javac, "--release", "8", "-parameters", "-encoding", "UTF-8", "-d", str(output),
             str(FIXTURES / "ParameterReflection.java")],
            self.args.timeout,
        )
        require(compilation.code == 0, f"parameter fixture compilation failed\n{compilation.detail()}")
        reference = execute([self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp", str(output),
                             "ParameterReflection"], self.args.timeout)
        require(reference.code == 0, f"Java failed\n{reference.detail()}")
        actual = execute([self.args.bend, MAIN, "--", "-cp", str(output), "ParameterReflection"],
                         self.args.timeout, bend=True)
        require(actual.code == 0, f"Bend failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())

    def differential(self, name: str) -> None:
        if name == "TcpEcho":
            self.tcp_echo()
            return
        if name == "TcpAccept":
            self.tcp_accept()
            return
        reference = execute([self.args.java, "-Dfile.encoding=UTF-8", "-cp", str(self.classes), name],
                            self.args.timeout)
        actual = self.bend(self.classes / f"{name}.class", *FIXTURE_FLAGS.get(name, ()))
        if name == "ExceptionUncaught":
            require(reference.code > 0, f"reference must throw\n{reference.detail()}")
            require(actual.code > 0, f"Bend must report an uncaught exception\n{actual.detail()}")
            expected_class = exception_class(reference.stderr)
            require(expected_class == "ArithmeticException", reference.detail())
            require(exception_class(actual.stderr + "\n" + actual.stdout) == expected_class,
                    f"wrong exception class\n{actual.detail()}")
            # Hosts may route the final VM diagnostic to stdout or stderr.
            require(actual.stdout.startswith(reference.stdout),
                    f"output before throwing differs\n{actual.detail()}")
            remainder = actual.stdout[len(reference.stdout):]
            require(not remainder or exception_class(remainder.splitlines()[0]) == expected_class,
                    f"unexpected stdout after throwing\n{actual.detail()}")
        else:
            require(reference.code == 0, f"reference failed\n{reference.detail()}")
            require(actual.code == 0, f"Bend failed\n{actual.detail()}")
            same_output(reference.stdout, actual.stdout, actual.detail())
            require(not reference.stderr, f"reference stderr\n{reference.detail()}")
            require(not actual.stderr, f"unexpected Bend stderr\n{actual.detail()}")

    def invokedynamic(self) -> None:
        failures = {
            "IndyExactMismatch": "BootstrapMethodError",
            "IndyNullCallSite": "BootstrapMethodError",
            "IndyWrongBootstrapResult": "BootstrapMethodError",
            "IndyWrongTarget": "BootstrapMethodError",
            "IndyBootstrapThrows": "BootstrapMethodError",
            "IndyInaccessibleBootstrap": "BootstrapMethodError",
            "IndyInaccessibleHandleArgument": "BootstrapMethodError",
            "IndyMissingMethodTypeArgument": "BootstrapMethodError",
            "MethodHandleInvokeExactMismatch": "WrongMethodTypeException",
        }
        # Java 8 (JVMS 6.5) wraps static-argument resolution failures in
        # BootstrapMethodError; JDK 11+ rethrows the LinkageError unwrapped. Bend
        # implements the Java 8 rule, so only the oracle may report either form.
        newer_oracle = {
            "IndyInaccessibleHandleArgument": "IllegalAccessError",
            "IndyMissingMethodTypeArgument": "NoClassDefFoundError",
            "IndyInaccessibleBootstrap": "IllegalAccessError",
        }
        for name in generated_classes():
            reference = execute(
                [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
                 str(self.classes), name], self.args.timeout)
            actual = self.bend(self.classes / f"{name}.class")
            if name in failures:
                expected = failures[name]
                observed = exception_class(reference.stderr + "\n" + reference.stdout)
                accepted = {expected} | ({newer_oracle[name]} if name in newer_oracle else set())
                require(reference.code > 0 and observed in accepted,
                        f"Java -Xverify:all failure differs\n{reference.detail()}")
                require(actual.code > 0 and
                        exception_class(actual.stderr + "\n" + actual.stdout) == expected,
                        f"Bend failure differs from Java\n{actual.detail()}")
                require(not actual.stdout, f"unexpected output before linkage failure\n{actual.detail()}")
            else:
                require(reference.code == 0, f"Java -Xverify:all failed\n{reference.detail()}")
                require(not reference.stderr, f"Java verifier/runtime stderr\n{reference.detail()}")
                require(actual.code == 0, f"Bend failed\n{actual.detail()}")
                same_output(reference.stdout, actual.stdout, actual.detail())
                require(not actual.stderr, f"unexpected Bend stderr\n{actual.detail()}")


    def verifier_edges(self, directory: Path) -> None:
        source_root = directory / "verifier-edge-source"
        class_root = directory / "verifier-edge-classes"
        source_root.mkdir()
        class_root.mkdir()
        sources = {
            "VerifierEdgeParent.java":
                "class VerifierEdgeParent { int inherited; VerifierEdgeParent() {} }\n",
            "VerifierPutfieldBad.java": """public class VerifierPutfieldBad extends VerifierEdgeParent {
    public VerifierPutfieldBad() { super(); }
    void assign() { inherited = 1; }
    public static void main(String[] args) {
        System.out.println(42);
        new VerifierPutfieldBad();
    }
}
""",
            "VerifierConstructorExceptionBad.java": """public class VerifierConstructorExceptionBad extends VerifierEdgeParent {
    public VerifierConstructorExceptionBad() { super(); }
    static void stackMapSeed() {
        try { throw new RuntimeException(); }
        catch (Throwable ignored) { if (ignored == null) return; }
    }
    public static void main(String[] args) { System.out.println(42); }
}
""",
            "VerifierFlowBad.java": """public class VerifierFlowBad {
    static int mismatch() { return 1; }
    static long pair(long value) { return value; }
    static Object identity(Object value) { return value; }
    static void escape() { identity(new Object()); }
    static int frame(int value) { return value == 0 ? 2 : 1; }
    static int branch(int value) { return value; }
    public static void main(String[] args) {
        System.out.println(42);
        System.out.println(frame(0));
        System.out.println(frame(1));
    }
}
""",
        }
        source_paths = []
        for name, text in sources.items():
            path = source_root / name
            path.write_text(text, encoding="utf-8")
            source_paths.append(path)
        parameters = ", ".join(f"int p{index}" for index in range(255))
        native_source = source_root / "VerifierNativeDescriptorLimit.java"
        native_source.write_text(
            "public class VerifierNativeDescriptorLimit { "
            f"public static native void bad({parameters}); "
            "public static void main(String[] args) { System.out.println(42); } }\n",
            encoding="utf-8",
        )
        source_paths.append(native_source)
        compilation = execute(
            [self.args.javac, "--release", "8", "-encoding", "UTF-8", "-g:none",
             "-d", str(class_root), *map(str, source_paths)],
            self.args.timeout,
        )
        require(compilation.code == 0,
                f"verifier edge fixture compilation failed\n{compilation.detail()}")

        putfield_path = class_root / "VerifierPutfieldBad.class"
        putfield = putfield_path.read_bytes()
        putfield_layout = class_layout(putfield)
        putfield_index = member_reference_index(
            putfield, putfield_layout, 9, "VerifierPutfieldBad", "inherited", "I")
        super_init = member_reference_index(
            putfield, putfield_layout, 10, "VerifierEdgeParent", "<init>", "()V")
        putfield_code = (b"\x2a\x04\xb5" + struct.pack(">H", putfield_index) +
                         b"\x2a\xb7" + struct.pack(">H", super_init) + b"\xb1")
        putfield_bad = replace_method_code(
            putfield, putfield_layout.methods["<init>"], putfield_code, 2, 1)

        constructor_path = class_root / "VerifierConstructorExceptionBad.class"
        constructor = constructor_path.read_bytes()
        constructor_layout = class_layout(constructor)
        constructor_super = member_reference_index(
            constructor, constructor_layout, 10, "VerifierEdgeParent", "<init>", "()V")
        throwable_index = class_constant_index(constructor, constructor_layout, "java/lang/Throwable")
        stack_map_name = next(
            index for index, text in constructor_layout.utf.items() if text == "StackMapTable")
        constructor_code = (b"\x2a\xb7" + struct.pack(">H", constructor_super) +
                            b"\xb1\x4c\xb1")
        stack_map = struct.pack(">HBHHBHBH", 1, 255, 5, 1, 0, 1, 7, throwable_index)
        stack_map_attribute = struct.pack(">HI", stack_map_name, len(stack_map)) + stack_map
        constructor_handler = struct.pack(">HHHH", 1, 4, 5, throwable_index)
        constructor_bad = replace_method_code(
            constructor, constructor_layout.methods["<init>"], constructor_code, 1, 2,
            exception_entries=(constructor_handler,), nested_attributes=(stack_map_attribute,))

        native_path = class_root / "VerifierNativeDescriptorLimit.class"
        native = native_path.read_bytes()
        native_layout = class_layout(native)
        flags_offset, _descriptor_offset, _descriptor_index = native_layout.method_headers["bad"]
        flags = u2(native, flags_offset)
        native_bad = patch(native, flags_offset, struct.pack(">H", flags & ~0x0008))
        flow_path = class_root / "VerifierFlowBad.class"
        flow = flow_path.read_bytes()
        flow_layout = class_layout(flow)
        flow_stack_map_name = next(
            index for index, text in flow_layout.utf.items() if text == "StackMapTable")
        flow_code = b"\x1a\x99\x00\x05\x04\xac\x05\xac"

        def frame_attribute(local_tag: int) -> bytes:
            info = struct.pack(">HBHHBH", 1, 255, 6, 1, local_tag, 0)
            return struct.pack(">HI", flow_stack_map_name, len(info)) + info

        valid_frame = replace_method_code(
            flow, flow_layout.methods["frame"], flow_code, 1, 1,
            nested_attributes=(frame_attribute(1),))
        valid_root = directory / "verifier-valid-stack-map"
        valid_root.mkdir()
        shutil.copytree(class_root, valid_root, dirs_exist_ok=True)
        (valid_root / "VerifierFlowBad.class").write_bytes(valid_frame)
        reference = execute(
            [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
             str(valid_root), "VerifierFlowBad"], self.args.timeout)
        actual = self.cli("-cp", str(valid_root), "VerifierFlowBad")
        require(reference.code == 0, f"OpenJDK rejected valid stack map control\n{reference.detail()}")
        require(actual.code == 0, f"Bend rejected valid stack map control\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())

        bad_frame = replace_method_code(
            flow, flow_layout.methods["frame"], flow_code, 1, 1,
            nested_attributes=(frame_attribute(2),))
        mismatch = replace_method_code(
            flow, flow_layout.methods["mismatch"], b"\x03\xad", 2, 0)
        pair_overlap = replace_method_code(
            flow, flow_layout.methods["pair"], b"\x03\x3c\x1e\xad", 2, 2)
        object_index = class_constant_index(flow, flow_layout, "java/lang/Object")
        identity_index = member_reference_index(
            flow, flow_layout, 10, "VerifierFlowBad", "identity",
            "(Ljava/lang/Object;)Ljava/lang/Object;")
        uninitialized_escape = replace_method_code(
            flow, flow_layout.methods["escape"],
            b"\xbb" + struct.pack(">H", object_index) +
            b"\xb8" + struct.pack(">H", identity_index) + b"\x57\xb1", 1, 0)
        branch_into_operand = replace_method_code(
            flow, flow_layout.methods["branch"], b"\x1a\x99\x00\x01\x10\x07\xac", 1, 1)

        def reject(class_name: str, contents: bytes, case_name: str | None = None,
                   bend_categories: tuple[str, ...] = ("VerifyError",)) -> None:
            variant = directory / f"verifier-edge-{case_name or class_name}"
            shutil.copytree(class_root, variant)
            (variant / f"{class_name}.class").write_bytes(contents)
            reference = execute(
                [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
                 str(variant), class_name],
                self.args.timeout,
            )
            java_error = reference.stdout + reference.stderr
            require(reference.code > 0 and
                    re.search(r"VerifyError|ClassFormatError", java_error),
                    f"OpenJDK accepted or misclassified {case_name or class_name}\n{reference.detail()}")
            actual = self.cli("-cp", str(variant), class_name)
            bend_error = actual.stdout + actual.stderr
            require(actual.code > 0 and
                    any(category in bend_error for category in bend_categories),
                    f"Bend accepted or misclassified {case_name or class_name}\n{actual.detail()}")
            require(not actual.stdout,
                    f"invalid {case_name or class_name} executed before verification\n{actual.detail()}")


        reject("VerifierConstructorExceptionBad", constructor_bad)
        reject("VerifierPutfieldBad", putfield_bad)
        reject("VerifierNativeDescriptorLimit", native_bad)
        reject("VerifierFlowBad", bad_frame, "bad-stack-map")
        reject("VerifierFlowBad", mismatch, "mismatched-return")
        reject("VerifierFlowBad", pair_overlap, "wide-local-overlap")
        reject("VerifierFlowBad", uninitialized_escape, "uninitialized-escape")
        reject("VerifierFlowBad", branch_into_operand, "branch-into-operand",
               ("InvalidBytecode", "VerifyError"))

    def switch_edges(self, directory: Path) -> None:
        original = (self.classes / "SwitchFixture.class").read_bytes()
        layout = class_layout(original)
        method = layout.methods["defaultOnly"]
        stack_map_name = next(
            index for index, text in layout.utf.items() if text == "StackMapTable")
        code = (b"\x1a\xab\x00\x00" + struct.pack(">ii", 11, 0) +
                b"\x10\x4d\xac")
        frame = b"\xff" + struct.pack(">H", 12) + struct.pack(">H", 1) + b"\x01" + struct.pack(">H", 0)
        stack_map = struct.pack(">H", 1) + frame
        stack_attribute = struct.pack(">HI", stack_map_name, len(stack_map)) + stack_map
        default_only = replace_method_code(
            original, method, code, 1, 1, nested_attributes=(stack_attribute,))
        positive = directory / "switch-default-only"
        positive.mkdir()
        (positive / "SwitchFixture.class").write_bytes(default_only)
        classpath = os.pathsep.join((str(positive), str(self.classes)))
        reference = execute(
            [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
             classpath, "SwitchFixture"], self.args.timeout)
        actual = self.cli("-cp", classpath, "SwitchFixture")
        require(reference.code == 0, f"OpenJDK rejected default-only lookupswitch\n{reference.detail()}")
        require(actual.code == 0, f"Bend rejected default-only lookupswitch\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(actual.stdout.splitlines()[:2] == ["77", "77"],
                f"default-only lookupswitch selected a case\n{actual.detail()}")

        malformed = (
            ("switch-nonzero-padding", b"\x1a\xab\x01"),
            ("switch-truncated-lookup", b"\x1a\xab\x00\x00\x00"),
            ("switch-invalid-table-range",
             b"\x1a\xaa\x00\x00" + struct.pack(">iii", 11, 1, 0)),
            ("switch-unsorted-lookup",
             b"\x1a\xab\x00\x00" + struct.pack(">ii", 27, 2) +
             struct.pack(">iiii", 2, 27, 1, 27) + b"\x10\x09\xac"),
            ("switch-target-into-operands",
             b"\x1a\xab\x00\x00" + struct.pack(">iiiii", 7, 1, 1, 7, 7) +
             b"\x10\x09\xac"),
        )
        for name, bad_code in malformed:
            bad_class = replace_method_code(original, method, bad_code, 1, 1)
            root = directory / name
            root.mkdir()
            (root / "SwitchFixture.class").write_bytes(bad_class)
            bad_classpath = os.pathsep.join((str(root), str(self.classes)))
            reference = execute(
                [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
                 bad_classpath, "SwitchFixture"], self.args.timeout)
            require(reference.code > 0 and
                    re.search(r"VerifyError|ClassFormatError", reference.stdout + reference.stderr),
                    f"OpenJDK accepted or misclassified {name}\n{reference.detail()}")
            actual = self.cli("-cp", bad_classpath, "SwitchFixture")
            require(actual.code > 0 and
                    re.search(r"InvalidBytecode|VerifyError|InvalidClass", actual.stdout + actual.stderr),
                    f"Bend accepted or misclassified {name}\n{actual.detail()}")
            require(not actual.stdout, f"malformed {name} executed before rejection\n{actual.detail()}")
    def stack_permutation_forms(self, directory: Path) -> None:
        original = (self.classes / "WideStackForms.class").read_bytes()
        specifications: dict[str, tuple[bytes, int, int]] = {
            "dupValue": (b"\x1a\x59\x60\xac", 2, 1),
            "popValue": (b"\x1a\x57\x10\x07\xac", 1, 1),
            "pop2Pair": (b"\x1a\x1b\x58\x10\x09\xac", 2, 2),
            "pop2Wide": (b"\x1e\x58\x1e\xad", 2, 2),
            "dupX1": (b"\x1a\x1b\x5a\x60\x60\xac", 3, 2),
            "dupX2Pair": (b"\x1a\x1b\x1c\x5b\x57\x58\xac", 4, 3),
            "dupX2Wide": (b"\x1e\x1c\x5b\x57\x58\xac", 4, 3),
            "dup2Wide": (b"\x1e\x5c\x58\xad", 4, 2),
            "dup2Pair": (b"\x1a\x1b\x5c\x60\x60\xac", 4, 2),
            "dup2X1Three": (b"\x1a\x1b\x1c\x5d\x60\x60\x5f\x57\x5f\x57\xac", 5, 3),
            "dup2X1Wide": (b"\x1a\x1f\x5d\x58\x57\xad", 5, 3),
            "dup2X2Four": (b"\x1a\x1b\x1c\x1d\x5e\x60\x60\x5f\x57\x5f\x57\xac", 6, 4),
            "dup2X2WideThenPair": (b"\x1e\x1c\x1d\x5e\x57\x57\x58\x58\x09\xad", 6, 4),
            "dup2X2PairThenWide": (b"\x1a\x1b\x20\x5e\x58\x58\xad", 6, 4),
            "dup2X2WidePair": (b"\x1e\x20\x5e\x58\x58\xad", 6, 4),
            "swap": (b"\x1a\x1b\x5f\x64\xac", 2, 2),
        }
        transformed = original
        for name, (code, max_stack, max_locals) in specifications.items():
            layout = class_layout(transformed)
            transformed = replace_method_code(
                transformed, layout.methods[name], code, max_stack, max_locals)

        positive = directory / "wide-stack-forms"
        positive.mkdir()
        (positive / "WideStackForms.class").write_bytes(transformed)
        classpath = os.pathsep.join((str(positive), str(self.classes)))
        reference = execute(
            [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
             classpath, "WideStackForms"], self.args.timeout)
        actual = self.cli("-cp", classpath, "WideStackForms")
        require(reference.code == 0, f"OpenJDK rejected legal stack forms\n{reference.detail()}")
        require(actual.code == 0, f"Bend rejected legal stack forms\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())

        malformed = {
            "pop": ("pop2Wide", b"\x1e\x57\x09\xad", 2, 2),
            "pop2": ("pop2Pair", b"\x1a\x58\x10\x09\xac", 2, 2),
            "dup": ("dup2Wide", b"\x1e\x59\x58\xad", 4, 2),
            "dup_x1": ("dupValue", b"\x1a\x5a\xac", 3, 1),
            "dup_x2": ("dupValue", b"\x1a\x5b\xac", 3, 1),
            "dup2": ("dupValue", b"\x1a\x5c\xac", 2, 1),
            "dup2_x1": ("dupValue", b"\x1a\x5d\xac", 3, 1),
            "dup2_x2": ("dupValue", b"\x1a\x5e\xac", 3, 1),
            "swap": ("dup2Wide", b"\x1e\x5f\xad", 2, 2),
        }
        for opcode, (method_name, code, max_stack, max_locals) in malformed.items():
            layout = class_layout(original)
            bad_class = replace_method_code(
                original, layout.methods[method_name], code, max_stack, max_locals)
            root = directory / f"wide-stack-invalid-{opcode}"
            root.mkdir()
            (root / "WideStackForms.class").write_bytes(bad_class)
            bad_classpath = os.pathsep.join((str(root), str(self.classes)))
            reference = execute(
                [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp",
                 bad_classpath, "WideStackForms"], self.args.timeout)
            require(reference.code > 0 and
                    "VerifyError" in reference.stdout + reference.stderr,
                    f"OpenJDK accepted invalid {opcode} shape\n{reference.detail()}")
            actual = self.cli("-cp", bad_classpath, "WideStackForms")
            require(actual.code > 0 and
                    "VerifyError" in actual.stdout + actual.stderr,
                    f"Bend accepted or misclassified invalid {opcode} shape\n{actual.detail()}")
            require(not actual.stdout,
                    f"invalid {opcode} shape ran application code\n{actual.detail()}")



    def metadata(self, directory: Path) -> None:
        probe = execute(
            [self.args.java, "-Dfile.encoding=UTF-8", "-cp", str(self.classes),
             "MetadataFixture$Probe"],
            self.args.timeout,
        )
        require(probe.code == 0, f"metadata probe failed\n{probe.detail()}")
        same_output("metadata-probe\n", probe.stdout, probe.detail())
        require(not probe.stderr, f"metadata probe stderr\n{probe.detail()}")
        actual = self.bend(self.classes / "MetadataFixture$Probe.class")
        require(actual.code == 0, f"Bend metadata probe failed\n{actual.detail()}")
        same_output(probe.stdout, actual.stdout, actual.detail())
        require(not actual.stderr, f"Bend metadata stderr\n{actual.detail()}")

        original_path = self.classes / "MetadataFixture$Annotated.class"
        original = original_path.read_bytes()
        layout = class_layout(original)
        required = (
            "RuntimeVisibleAnnotations", "RuntimeInvisibleAnnotations",
            "RuntimeVisibleTypeAnnotations", "RuntimeInvisibleTypeAnnotations",
            "RuntimeVisibleParameterAnnotations",
            "RuntimeInvisibleParameterAnnotations", "Exceptions",
        )
        for attribute_name in required:
            require(layout.attributes.get(attribute_name),
                    f"metadata fixture is missing {attribute_name}")
        defaults = class_layout((self.classes / "MetadataFixture$Visible.class").read_bytes())
        require(defaults.attributes.get("AnnotationDefault"),
                "metadata fixture is missing AnnotationDefault")
        visible = max(layout.attributes["RuntimeVisibleAnnotations"],
                     key=lambda item: item[1], default=None)
        require(visible is not None and visible[1] >= 9,
                "metadata fixture has no class annotation payload")
        payload_start, payload_length = visible
        require(payload_length >= 9 and u2(original, payload_start) == 1,
                "metadata fixture class annotation count changed")
        malformed = bytearray(original)
        malformed[payload_start + 8] = 0xFF
        malformed_root = directory / "metadata-malformed"
        malformed_root.mkdir()
        (malformed_root / original_path.name).write_bytes(malformed)
        rejected = execute(
            [self.args.java, "-Dfile.encoding=UTF-8", "-cp",
             os.pathsep.join((str(malformed_root), str(self.classes))),
             "MetadataFixture$Probe"],
            self.args.timeout,
        )
        require(rejected.code > 0, f"malformed annotation was accepted\n{rejected.detail()}")
        require("AnnotationFormatError" in rejected.stdout + "\n" + rejected.stderr,
                f"malformed annotation had the wrong rejection\n{rejected.detail()}")
        self.reject(malformed_root / original_path.name,
                    r"InvalidAnnotation|InvalidClass", "--dump-class")

    def reject(self, path: Path, category: str, *flags: str) -> None:
        result = self.bend(path, *flags)
        require(result.code > 0, f"expected rejection (not a signal crash)\n{result.detail()}")
        require(re.search(category, result.stdout + "\n" + result.stderr) is not None,
                f"expected error category {category!r}\n{result.detail()}")
        require("42\n" not in result.stdout, f"malformed class executed before rejection\n{result.detail()}")

    def fuel(self) -> None:
        self.reject(self.classes / "FuelLimit.class", r"OutOfFuel", "--fuel", "30")
        self.reject(self.classes / "HelloInteger.class", r"OutOfFuel", "--fuel", "0")
        result = self.bend(self.classes / "HelloInteger.class", "--fuel", "100")
        require(result.code == 0, result.detail())
        same_output("42\n", result.stdout, result.detail())

        bootstrap = self.bend(
            self.classes / "IndyFuelBootstrap.class", "--fuel", "150")
        require(bootstrap.code > 0 and
                "OutOfFuel" in bootstrap.stdout + "\n" + bootstrap.stderr,
                f"bootstrap bytecode should exhaust fuel\n{bootstrap.detail()}")
        require("bootstrap-entered\n" in bootstrap.stdout,
                f"fuel exhaustion happened before bootstrap execution\n{bootstrap.detail()}")

    def heap(self) -> None:
        self.reject(self.classes / "HeapLimit.class", r"OutOfMemoryError", "--max-heap", "16")
        result = self.bend(self.classes / "HeapLimit.class", "--max-heap", "256")
        require(result.code == 0, result.detail())
        same_output("100\n", result.stdout, result.detail())

        wide = self.bend(
            self.classes / "WideAllocationLimit.class", "--max-heap", "64")
        require(wide.code > 0 and
                "OutOfMemoryError" in wide.stdout + "\n" + wide.stderr,
                f"wide array allocation should exhaust the bounded heap\n{wide.detail()}")
        require(wide.stdout.startswith("before-wide-array\n"),
                f"wide allocation failed before reaching the allocation site\n{wide.detail()}")

    def capabilities(self) -> None:
        files = self.bend(self.classes / "FileRoundtrip.class", "--no-files")
        require(files.code > 0, f"--no-files must deny file effects\n{files.detail()}")
        require(re.search(r"IOException", files.stdout + "\n" + files.stderr) is not None,
                f"--no-files expected IOException\n{files.detail()}")
        net = execute([self.args.bend, MAIN, "--", "--no-net", str(self.classes / "TcpEcho.class"), "1"],
                      self.args.timeout, bend=True)
        require(net.code > 0, f"--no-net must deny TCP effects\n{net.detail()}")
        require(re.search(r"IOException|SocketException", net.stdout + "\n" + net.stderr) is not None,
                f"--no-net expected an IOException\n{net.detail()}")

    # ---- plan 05: concurrency, native plugins, NIO and TLS -------------------

    def compile_extra(self, directory: Path, name: str, *sources: Path) -> Path:
        output = directory / name
        output.mkdir(parents=True, exist_ok=True)
        compiled = execute([self.args.javac, "--release", "8", "-encoding", "UTF-8", "-g:none", "-Xlint:-options",
                            "-d", str(output), *map(str, sources)], self.args.timeout)
        require(compiled.code == 0, f"compilation failed\n{compiled.detail()}")
        return output

    def jre_references(self) -> None:
        missing = jre_audit.missing_references()
        require(not missing, "MiniJRE Java sources reference classes the MiniJRE lacks: "
                + ", ".join(f"{name} (from {', '.join(sorted(users))})" for name, users in sorted(missing.items())))

    def stack_traces(self, directory: Path) -> None:
        # Compiled with source and line tables, unlike the rest of the corpus.
        classes = directory / "debug-classes"
        classes.mkdir(exist_ok=True)
        compiled = execute([self.args.javac, "--release", "8", "-encoding", "UTF-8", "-Xlint:-options", "-d", str(classes),
                            str(FIXTURES / "StackTraces.java")], self.args.timeout)
        require(compiled.code == 0, compiled.detail())
        reference = execute([self.args.java, "-cp", str(classes), "StackTraces"], self.args.timeout)
        actual = self.bend(classes / "StackTraces.class")
        require(reference.code == 1 and actual.code == 1, f"uncaught main exits with 1\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        same_output(reference.stderr, actual.stderr, "stderr\n" + actual.detail())

    def native_frames(self, directory: Path) -> None:
        classes = directory / "native-frame-classes"
        classes.mkdir(exist_ok=True)
        compiled = execute([self.args.javac, "--release", "8", "-encoding", "UTF-8", "-Xlint:-options", "-d", str(classes),
                            str(FIXTURES / "NativeFrames.java")], self.args.timeout)
        require(compiled.code == 0, compiled.detail())
        result = self.bend(classes / "NativeFrames.class", "--fuel", "60000000")
        require(result.code == 0, result.detail())
        expected = [
            (r"java\.lang\.StringIndexOutOfBoundsException.*\n\tat java\.lang\.String\.charAt\(Unknown Source\)\n"
            r"\tat NativeFrames\.at\(NativeFrames\.java:8\)\n\tat NativeFrames\.main\(NativeFrames\.java:13\)\n"),
            (r"java\.io\.FileNotFoundException: /definitely/missing/bendjvm-file \(No such file or directory\)\n\tat java\.io\.FileInputStream\.<init>\(Unknown Source\)\n"
            r"\tat NativeFrames\.main\(NativeFrames\.java:18\)\n"),
            (r"java\.lang\.InterruptedException: sleep interrupted\n\tat java\.lang\.Thread\.sleep0\(Native Method\)\n"
            r"\tat java\.lang\.Thread\.sleep\(Thread\.java:\d+\)\n\tat NativeFrames\.main\(NativeFrames\.java:24\)\n"),
        ]
        for pattern in expected:
            require(re.search(pattern, result.stdout) is not None, f"missing frames /{pattern}/\n{result.detail()}")

    def priorities(self) -> None:
        result = self.bend(self.classes / "ThreadPriorities.class", "--fuel", "60000000")
        require(result.code == 0, result.detail())
        same_output("priorities: 10 1\nout of range rejected\nhigh ran more: true\n", result.stdout, result.detail())

    def main_handled(self) -> None:
        reference = execute([self.args.java, "-cp", str(self.classes), "MainHandled"], self.args.timeout)
        actual = self.bend(self.classes / "MainHandled.class")
        require(reference.code == 1 and actual.code == 1,
                f"a handled main exception exits with status 1\n{reference.detail()}\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not actual.stderr.strip(), f"the handler replaces the default report\n{actual.detail()}")

    def deadlock(self) -> None:
        result = self.bend(self.classes / "LockOrderDeadlock.class", "--fuel", "60000000")
        require(result.code > 0 and "Deadlock" in result.stderr,
                f"a closed wait-for cycle must be reported\n{result.detail()}")
        require(result.stderr.count("waiting to lock object") == 2, f"both threads are named\n{result.detail()}")

    def fuel_with_threads(self) -> None:
        started = time.monotonic()
        result = self.bend(self.classes / "FuelWithBlockedThreads.class", "--fuel", "200000")
        require(result.code > 0 and "OutOfFuel" in result.stderr,
                f"global fuel covers every thread\n{result.detail()}")
        require(time.monotonic() - started < 60, "fuel exhaustion must not wait for blocked threads")

    def schedule_variation(self) -> None:
        for name in ("MonitorSemantics", "VolatilePublication", "ThreadLifecycle"):
            reference = execute([self.args.java, "-cp", str(self.classes), name], self.args.timeout)
            require(reference.code == 0, reference.detail())
            for quantum in ("3", "37", "5000"):
                actual = self.bend(self.classes / f"{name}.class", "--fuel", "200000000", "--quantum", quantum)
                require(actual.code == 0, f"{name} quantum {quantum}\n{actual.detail()}")
                same_output(reference.stdout, actual.stdout, f"quantum {quantum}\n{actual.detail()}")

    def native_plugins(self, directory: Path) -> None:
        library = compile_plugin(NATIVE / "demo_plugin.c", directory / shared_library_name("bendjvmdemo"))
        classes = self.compile_extra(directory, "native-classes", NATIVE / "NativeDemo.java")
        before = helper_processes()
        result = self.bend(classes / "NativeDemo.class", "--fuel", "60000000",
                           "--native-library", f"bendjvmdemo={library}")
        require(result.code == 0, result.detail())
        same_output(NATIVE_EXPECTED, result.stdout, result.detail())
        require(helper_processes() <= before, "the native helper must be reaped at VM exit")
        # Without configuration native loading is disabled.
        disabled = self.bend(classes / "NativeDemo.class")
        require(disabled.code > 0 and "UnsatisfiedLinkError" in disabled.stderr,
                f"loadLibrary without --native-library must fail\n{disabled.detail()}")
        relative = self.bend(classes / "NativeDemo.class", "--native-library", "bendjvmdemo=relative.so")
        require(relative.code == 2, f"--native-library needs an absolute path\n{relative.detail()}")
        # A library without the registration symbol, and one with a wrong ABI version.
        (directory / "bad_abi.c").write_text(
            '#include "bendjvm_plugin.h"\nstatic const bendjvm_registration r = {99, 1, 0, 0, 0, 0};\n'
            "const bendjvm_registration *bendjvm_register_v1(void) { return &r; }\n", encoding="utf-8")
        bad = compile_plugin(directory / "bad_abi.c", directory / shared_library_name("badabi"))
        wrong = self.bend(classes / "NativeDemo.class", "--native-library", f"bendjvmdemo={bad}")
        require(wrong.code > 0 and "unsupported plugin ABI version" in wrong.stderr, wrong.detail())

    def tls_material(self, directory: Path) -> tls_fixtures.TlsMaterial:
        keytool = str(Path(shutil.which(self.args.java) or self.args.java).resolve().with_name("keytool"))
        try:
            return tls_fixtures.generate(Path(tempfile.mkdtemp(prefix="tls-", dir=directory)), keytool)
        except subprocess.CalledProcessError as error:
            raise Failure(f"TLS material generation failed: {error}\n{error.stderr}") from error

    def tls(self, directory: Path) -> None:
        material = self.tls_material(directory)
        peers = [tls_fixtures.Peer(material.identity_cert, material.identity_key, material.ca),
                 tls_fixtures.Peer(material.untrusted_cert, material.untrusted_key),
                 tls_fixtures.Peer(material.expired_cert, material.identity_key),
                 tls_fixtures.Peer(material.wrong_host_cert, material.identity_key)]
        try:
            runs = []
            for runner in ("java", "bend"):
                port = tls_fixtures.free_port()
                arguments = [str(peer.port) for peer in peers] + [str(port)]
                results: list[str] = []
                clients = threading.Thread(target=tls_fixtures.connect_clients, args=(port, material, results))
                clients.start()
                if runner == "java":
                    run = execute([self.args.java, f"-Djavax.net.ssl.trustStore={material.trust_store}",
                                   f"-Djavax.net.ssl.trustStorePassword={tls_fixtures.PASSWORD}",
                                   f"-Djavax.net.ssl.keyStore={material.key_store}",
                                   f"-Djavax.net.ssl.keyStorePassword={tls_fixtures.PASSWORD}",
                                   "-cp", str(self.classes), "TlsFixture", *arguments], self.args.timeout)
                else:
                    run = execute([self.args.bend, MAIN, "--", "--fuel", "300000000",
                                   "--tls-trust", str(material.ca), "--tls-key", str(material.identity_key),
                                   "--tls-cert", str(material.identity_cert),
                                   str(self.classes / "TlsFixture.class"), *arguments], self.args.timeout, bend=True)
                clients.join(timeout=150)
                runs.append((run, results))
            (reference, expected_clients), (actual, actual_clients) = runs
            require(reference.code == 0, reference.detail())
            require(actual.code == 0, actual.detail())
            same_output(reference.stdout, actual.stdout, actual.detail())
            require(expected_clients == actual_clients == ["harness client 0: refused", "harness client 1: served hi harness"],
                    f"independent clients: {expected_clients} vs {actual_clients}")
        finally:
            for peer in peers:
                peer.close()
        # Inconsistent identity material is rejected before Java runs.
        mismatch = self.bend(self.classes / "TlsFixture.class", "--tls-key", str(material.untrusted_key),
                             "--tls-cert", str(material.identity_cert), "--tls-trust", str(material.ca))
        require(mismatch.code > 0 and "InvalidTlsConfiguration" in mismatch.stderr, mismatch.detail())
        unreadable = self.bend(self.classes / "TlsFixture.class", "--tls-trust", str(directory / "missing.pem"))
        require(unreadable.code == 2, unreadable.detail())

    def https_example(self, directory: Path) -> None:
        material = self.tls_material(directory)
        library = compile_plugin(WEB_EXAMPLE / "native" / "web_checksum.c", directory / shared_library_name("webchecksum"))
        classes = self.compile_extra(directory, "web-classes", *sorted((WEB_EXAMPLE / "example" / "web").glob("*.java")))
        jar = directory / "web.jar"
        write_fixture_jar(jar, {str(path.relative_to(classes)): path.read_bytes() for path in classes.rglob("*.class")},
                          manifest=manifest_bytes(main_class="example.web.HttpsServer"))
        command = [self.args.bend, "--fuel", "2000000000", "--tls-trust", str(material.ca),
                   "--tls-key", str(material.identity_key), "--tls-cert", str(material.identity_cert),
                   "--native-library", f"webchecksum={library}", "-jar", str(jar)]
        before = helper_processes()
        process = subprocess.Popen(command, cwd=WORKDIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=os.name == "posix")
        try:
            line = process.stdout.readline()
            match = re.match(r"listening on (\d+)", line)
            require(match is not None, f"server did not start: {line!r} {process.stderr.read() if process.poll() is not None else ''}")
            port = int(match.group(1))
            context = ssl.create_default_context(cafile=str(material.ca))

            def request(method: str, path: str, body: bytes = b"") -> str:
                with socket.create_connection(("127.0.0.1", port), timeout=120) as raw, \
                        context.wrap_socket(raw, server_hostname="localhost") as tls:
                    head = f"{method} {path} HTTP/1.1\r\nHost: localhost\r\nContent-Length: {len(body)}\r\n\r\n"
                    tls.sendall(head.encode() + body)
                    data = b""
                    while True:
                        chunk = tls.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    return data.decode()

            # A slow client holds one worker mid-request while the others serve.
            slow_raw = socket.create_connection(("127.0.0.1", port), timeout=120)
            slow = context.wrap_socket(slow_raw, server_hostname="localhost")
            slow.sendall(b"GET /hel")
            results: dict[str, str] = {}

            def fetch(key: str, method: str, path: str, body: bytes = b"") -> None:
                results[key] = request(method, path, body)

            payload = b"BendJVM over TLS"
            expected_hash = 2166136261
            for byte in payload:
                expected_hash = ((expected_hash ^ byte) * 16777619) & 0xFFFFFFFF
            workers = [threading.Thread(target=fetch, args=(f"hello{i}", "GET", "/hello")) for i in range(3)]
            workers.append(threading.Thread(target=fetch, args=("checksum", "POST", "/checksum", payload)))
            workers.append(threading.Thread(target=fetch, args=("missing", "GET", "/nope")))
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(timeout=300)
            for i in range(3):
                require(results.get(f"hello{i}", "").startswith("HTTP/1.1 200 OK") and "hello from worker over true" in results[f"hello{i}"],
                        f"hello {i}: {results.get(f'hello{i}')!r}")
            require(f"fnv1a {expected_hash:x}" in results.get("checksum", ""), f"checksum: {results.get('checksum')!r}")
            require(results.get("missing", "").startswith("HTTP/1.1 404"), f"404: {results.get('missing')!r}")
            slow.sendall(b"lo HTTP/1.1\r\nHost: localhost\r\n\r\n")
            reply = b""
            while True:
                chunk = slow.recv(4096)
                if not chunk:
                    break
                reply += chunk
            slow.close()
            require(b"hello from worker over true" in reply, f"slow client: {reply!r}")
            stats = request("GET", "/stats")
            require("served 6" in stats, f"stats: {stats!r}")
            require("bye" in request("POST", "/shutdown"), "shutdown request")
            stdout, stderr = process.communicate(timeout=180)
            require(process.returncode == 0, f"server exit {process.returncode}\n{stdout}\n{stderr}")
            require("stopped after 8 requests" in stdout, f"server output: {stdout!r} {stderr!r}")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL) if os.name == "posix" else process.kill()
                process.communicate()
        require(helper_processes() <= before, "the native helper must be reaped at VM exit")

    def debug(self, mode: str) -> None:
        result = self.bend(self.classes / "HelloInteger.class", mode)
        require(result.code == 0, result.detail())
        combined = result.stdout + "\n" + result.stderr
        if mode == "--dump-class":
            for pattern in (r"HelloInteger", r"\b52\b", r"(?i)constant[ _-]?pool",
                            r"(?i)fields", r"(?i)methods", r"(?i)attributes", r"main"):
                require(re.search(pattern, combined) is not None,
                        f"class dump missing {pattern!r}\n{result.detail()}")
            require(re.search(r"(?m)^42$", result.stdout) is None,
                    f"dump unexpectedly executed main\n{result.detail()}")
        elif mode == "--disassemble":
            for pattern in (r"HelloInteger", r"main", r"\(\[Ljava/lang/String;\)V",
                            r"\bgetstatic\b", r"\bbipush\b", r"\binvokevirtual\b", r"\breturn\b"):
                require(re.search(pattern, combined) is not None,
                        f"disassembly missing {pattern!r}\n{result.detail()}")
            for offset, mnemonic in ((0, "getstatic"), (3, "bipush"), (5, "invokevirtual"), (8, "return")):
                require(re.search(rf"(?m)^\s*{offset}\s*[: ]\s*{mnemonic}\b", combined) is not None,
                        f"missing original byte offset {offset} for {mnemonic}\n{result.detail()}")
        else:
            same_output("42\n", result.stdout, result.detail())
            for pattern in (r"HelloInteger", r"main", r"pc\s*=\s*0\b", r"\bgetstatic\b", r"(?i)stack"):
                require(re.search(pattern, result.stderr) is not None,
                        f"trace missing {pattern!r}\n{result.detail()}")

    def cli(self, *arguments: str) -> Run:
        return execute([self.args.bend, *arguments], self.args.timeout, bend=True)

    def reflective_app(self, directory: Path) -> None:
        output = directory / "reflective-app-compiled"
        output.mkdir()
        compilation = execute(
            [self.args.javac, "--release", "8", "-encoding", "UTF-8", "-g:none",
             "-d", str(output), str(FIXTURES / "ReflectiveContainer.java"),
             str(FIXTURES / "ConfiguredComponent.java")], self.args.timeout)
        require(compilation.code == 0, f"reflective app compilation failed\n{compilation.detail()}")
        classes = {
            path.relative_to(output).as_posix(): path.read_bytes()
            for path in output.rglob("*.class")
        }
        component_name = "fixture/container/ConfiguredComponent.class"
        component = {component_name: classes.pop(component_name)}
        first = write_fixture_jar(
            directory / "components first é.jar", component,
            resources={"components.properties":
                       "component=fixture.container.ConfiguredComponent\nbase=7\n"})
        second = write_fixture_jar(
            directory / "components second.jar",
            resources={"components.properties":
                       "component=fixture.container.ConfiguredComponent\nbase=11\n"})
        app = write_fixture_jar(
            directory / "reflective-container.jar", classes,
            manifest=manifest_bytes(
                main_class="fixture.container.ReflectiveContainer",
                class_path=(first.name.replace(" ", "%20"), second.name.replace(" ", "%20"))))
        reference = execute([self.args.java, "-Dfile.encoding=UTF-8", "-jar", str(app)],
                            self.args.timeout)
        actual = self.cli("-jar", str(app))
        require(reference.code == 0, f"reference reflective app failed\n{reference.detail()}")
        require(actual.code == 0, f"Bend reflective app failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not reference.stderr and not actual.stderr,
                f"reflective app stderr\n{reference.detail()}\n{actual.detail()}")
        same_output("closed\nconfigured\n13\ntrue\ntarget-failure\n"
                    "closed\nconfigured\n17\ntrue\ntarget-failure\n2\n",
                    actual.stdout, actual.detail())

    def resource_contracts(self, directory: Path) -> None:
        output = directory / "resource-contracts-compiled"
        output.mkdir()
        compilation = execute(
            [self.args.javac, "--release", "8", "-g:none", "-d", str(output),
             str(FIXTURES / "ResourceContracts.java")], self.args.timeout)
        require(compilation.code == 0, f"resource contract compilation failed\n{compilation.detail()}")
        first = write_fixture_jar(directory / "contracts first.jar",
                                  resources={"empty": b"", "duplicate": b"ab"})
        second = write_fixture_jar(directory / "contracts second.jar",
                                   resources={"duplicate": b"z"})
        classpath = os.pathsep.join(map(str, (output, first, second)))
        reference = execute(
            [self.args.java, "-Dfile.encoding=UTF-8", "-cp", classpath,
             "fixture.resource.ResourceContracts"], self.args.timeout)
        actual = self.cli("-cp", classpath, "fixture.resource.ResourceContracts")
        require(reference.code == 0, f"reference resources failed\n{reference.detail()}")
        require(actual.code == 0, f"Bend resources failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not reference.stderr and not actual.stderr,
                f"resource contract stderr\n{reference.detail()}\n{actual.detail()}")

    def resource_urls(self, directory: Path) -> None:
        """Resource URLs percent-escape directory and jar paths as URLClassLoader does."""
        # Canonical paths: the JDK canonicalizes class path entries (/var -> /private/var).
        root = directory.resolve()
        output = root / "resource urls classes"
        output.mkdir()
        compilation = execute(
            [self.args.javac, "--release", "8", "-g:none", "-encoding", "UTF-8", "-d", str(output),
             str(FIXTURES / "ResourceUrls.java")], self.args.timeout)
        require(compilation.code == 0, f"resource URL compilation failed\n{compilation.detail()}")
        names = ["plain.txt", "with space.txt", "hash#percent%question?.txt",
                 "reserved!$&'()*+,;=:@.txt", "brackets[]{}^`|\"<>~.txt",
                 "caf\u00e9 \u4e2d\U0001f600.txt", "nested dir/inner file.txt", "shared.txt"]
        for name in names:
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"dir")
        archive = write_fixture_jar(root / "resources jar \u00e9.jar",
                                    resources={"shared.txt": b"jar", "with space.txt": b"jar"})
        classpath = os.pathsep.join(map(str, (output, archive)))
        reference = execute(
            [self.args.java, "-Dfile.encoding=UTF-8", "-cp", classpath,
             "fixture.resource.ResourceUrls"], self.args.timeout)
        actual = self.cli("-cp", classpath, "fixture.resource.ResourceUrls")
        require(reference.code == 0, f"reference resource URLs failed\n{reference.detail()}")
        require(actual.code == 0, f"Bend resource URLs failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not reference.stderr and not actual.stderr,
                f"resource URL stderr\n{reference.detail()}\n{actual.detail()}")

    def package_scanning(self, directory: Path) -> None:
        """Component scanning as Spring's PathMatchingResourcePatternResolver does it."""
        root = directory.resolve()
        classes = root / "scan classes"
        archive_classes = root / "scan archive classes"
        for output, sources in ((classes, ("PackageScanning.java", "scan/Alpha.java", "scan/Beta.java",
                                           "scan/Gamma.java", "scan/SharedDir.java")),
                                (archive_classes, ("scan/Delta.java", "scan/SharedJar.java"))):
            output.mkdir()
            compilation = execute(
                [self.args.javac, "--release", "8", "-g:none", "-d", str(output),
                 *(str(FIXTURES / source) for source in sources)], self.args.timeout)
            require(compilation.code == 0, f"package scanning compilation failed\n{compilation.detail()}")
        archive = root / "scan jar.jar"
        # Explicit directory entries, as Maven and Gradle write them.
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as jar:
            for name in ("META-INF/", "fixture/", "fixture/scan/", "fixture/scan/jar/", "fixture/scan/shared/"):
                jar.writestr(zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0)), b"")
            for path in sorted(archive_classes.rglob("*.class")):
                info = zipfile.ZipInfo(path.relative_to(archive_classes).as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
                jar.writestr(info, path.read_bytes())
        classpath = os.pathsep.join(map(str, (classes, archive)))
        reference = execute(
            [self.args.java, "-Dfile.encoding=UTF-8", "-cp", classpath, "fixture.scan.PackageScanning"],
            self.args.timeout)
        actual = self.cli("-cp", classpath, "fixture.scan.PackageScanning")
        require(reference.code == 0, f"reference package scanning failed\n{reference.detail()}")
        require(actual.code == 0, f"Bend package scanning failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not reference.stderr and not actual.stderr,
                f"package scanning stderr\n{reference.detail()}\n{actual.detail()}")

    def class_loaders(self, directory: Path) -> None:
        """User class loaders over classes the application loader cannot see."""
        app = directory / "loaders-app"
        isolated = directory / "loaders-isolated"
        for output, sources in ((app, ("ClassLoaders.java",)),
                                (isolated, tuple(f"isolated/{name}.java" for name in ISOLATED))):
            output.mkdir()
            compilation = execute(
                [self.args.javac, "--release", "8", "-g:none", "-d", str(output),
                 *(str(FIXTURES / source) for source in sources)], self.args.timeout)
            require(compilation.code == 0, f"class loader compilation failed\n{compilation.detail()}")
        # The isolated classes are resources ("*.bytes"), not loadable classes.
        (app / "isolated").mkdir()
        for name in ISOLATED:
            (app / "isolated" / f"{name}.bytes").write_bytes((isolated / "isolated" / f"{name}.class").read_bytes())
        reference = execute(
            [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-cp", str(app), "ClassLoaders"],
            self.args.timeout)
        actual = self.cli("-cp", str(app), "ClassLoaders")
        require(reference.code == 0, f"reference class loaders failed\n{reference.detail()}")
        require(actual.code == 0, f"Bend class loaders failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not reference.stderr and not actual.stderr,
                f"class loader stderr\n{reference.detail()}\n{actual.detail()}")

    def runtime_app(self, directory: Path) -> None:
        output = directory / "runtime-app-compiled"
        output.mkdir(parents=True, exist_ok=True)
        compilation = execute(
            [self.args.javac, "--release", "8", "-encoding", "UTF-8", "-g:none",
             "-d", str(output), str(FIXTURES / "RuntimeExpansionApp.java")],
            self.args.timeout,
        )
        require(compilation.code == 0, f"runtime app compilation failed\n{compilation.detail()}")
        classes = {
            path.relative_to(output).as_posix(): path.read_bytes()
            for path in output.rglob("*.class")
        }
        app_jar = write_fixture_jar(
            directory / "runtime-expansion.jar",
            classes,
            resources={"fixture-resource.bin": bytes((9,))},
            manifest=manifest_bytes(main_class="RuntimeExpansionApp"),
        )
        file_path = directory / "runtime-app.bin"
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        server.listen(2)
        port = str(server.getsockname()[1])

        def serve() -> None:
            for _ in range(2):
                conn, _addr = server.accept()
                try:
                    data = conn.recv(1)
                    if data:
                        conn.sendall(bytes([(data[0] + 1) & 255]))
                finally:
                    conn.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        try:
            reference = execute(
                [self.args.java, "-Dfile.encoding=UTF-8", "-jar", str(app_jar), str(file_path), port],
                self.args.timeout,
            )
            actual = self.cli("-jar", str(app_jar), str(file_path), port)
            require(reference.code == 0, f"reference runtime app failed\n{reference.detail()}")
            require(actual.code == 0, f"Bend runtime app failed\n{actual.detail()}")
            same_output(reference.stdout, actual.stdout, actual.detail())
            require(not reference.stderr, f"reference stderr\n{reference.detail()}")
            require(not actual.stderr, f"unexpected Bend stderr\n{actual.detail()}")
            same_output("9ok\n65\n67\n-2\n", actual.stdout, actual.detail())
        finally:
            server.close()
            thread.join(timeout=2)
    def broader_app(self, directory: Path) -> None:
        output = directory / "broader-app-compiled"
        support = directory / "IndySupport.java"
        support.write_text(BOOTSTRAP_SOURCE, encoding="utf-8")
        # IndyConstant has no Java source (javac cannot emit custom invokedynamic),
        # so the generated class file is placed on the compile classpath.
        generated = directory / "broader-app-generated"
        generated.mkdir()
        (generated / "IndyConstant.class").write_bytes(generated_classes()["IndyConstant"])
        compilation = execute(
            [self.args.javac, "--release", "8", "-encoding", "UTF-8", "-g:none",
             "-cp", str(generated), "-d", str(output),
             str(FIXTURES / "BroaderJvmApp.java"), str(support)],
            self.args.timeout,
        )
        require(compilation.code == 0, f"broader app compilation failed\n{compilation.detail()}")
        classes = {
            path.relative_to(output).as_posix(): path.read_bytes()
            for path in output.rglob("*.class")
        }
        classes["IndyConstant.class"] = generated_classes()["IndyConstant"]
        app_jar = write_fixture_jar(
            directory / "broader-jvm-app.jar",
            classes,
            resources={"broader-resource.bin": bytes((37,))},
            manifest=manifest_bytes(main_class="BroaderJvmApp"),
        )
        reference = execute(
            [self.args.java, "-Xverify:all", "-Dfile.encoding=UTF-8", "-jar", str(app_jar)],
            self.args.timeout,
        )
        actual = self.cli("-jar", str(app_jar))
        require(reference.code == 0, f"reference broader app failed\n{reference.detail()}")
        require(actual.code == 0, f"Bend broader app failed\n{actual.detail()}")
        same_output(reference.stdout, actual.stdout, actual.detail())
        require(not reference.stderr, f"reference broader app stderr\n{reference.detail()}")
        require(not actual.stderr, f"Bend broader app stderr\n{actual.detail()}")



    def classpath(self, directory: Path) -> None:
        def compile_sources(output: Path, *sources: Path) -> dict[str, bytes]:
            output.mkdir(parents=True, exist_ok=True)
            result = execute([self.args.javac, "--release", "8", "-encoding", "UTF-8",
                              "-g:none", "-d", str(output), *map(str, sources)], self.args.timeout)
            require(result.code == 0, f"classpath fixture compilation failed\n{result.detail()}")
            return {
                path.relative_to(output).as_posix(): path.read_bytes()
                for path in output.rglob("*.class")
            }

        fixture = FIXTURES / "classpath"
        packaged = compile_sources(
            directory / "packaged-compiled",
            fixture / "PackagedMain.java",
            fixture / "Dependency.java",
            fixture / "TransitiveHelper.java",
        )
        packaged_main = {name: value for name, value in packaged.items() if name.endswith("PackagedMain.class")}
        packaged_dependency = {
            name: value for name, value in packaged.items() if not name.endswith("PackagedMain.class")
        }
        app_dir = write_fixture_directory(directory / "packaged-app", packaged_main)
        dep_dir = write_fixture_directory(directory / "packaged-dep", packaged_dependency)
        expected = "packaged-dependency\n"
        for name, entries in (
            ("directory", None),
            ("jar", write_fixture_jar(directory / "dependency.jar", packaged_dependency)),
            ("zip", write_fixture_zip(directory / "dependency.zip", packaged_dependency)),
        ):
            dependency = dep_dir if entries is None else entries
            result = self.cli("-cp", os.pathsep.join((str(app_dir), str(dependency))),
                              "fixture.packaged.PackagedMain")
            require(result.code == 0, f"classpath/{name} failed\n{result.detail()}")
            same_output(expected, result.stdout, result.detail())

        dynamic_source = directory / "DynamicLookup.java"
        dynamic_source.write_text(
            "package fixture.dynamic; public class DynamicLookup { "
            "public static void main(String[] args) throws Exception { "
            "System.out.println(Class.forName(\"fixture.dynamic.ConfigOnly\").getName()); } }",
            encoding="utf-8",
        )
        dynamic = compile_sources(directory / "dynamic-compiled", dynamic_source)
        dynamic_app = write_fixture_directory(
            directory / "dynamic-app",
            {name: value for name, value in dynamic.items() if name.endswith("DynamicLookup.class")},
        )
        dynamic_dependency_source = directory / "ConfigOnly.java"
        dynamic_dependency_source.write_text(
            "package fixture.dynamic; public class ConfigOnly { }",
            encoding="utf-8",
        )
        dynamic_dependency = compile_sources(directory / "dynamic-dependency-compiled", dynamic_dependency_source)
        dynamic_archive = write_fixture_jar(directory / "dynamic dependency.jar", dynamic_dependency)
        result = self.cli("-cp", os.pathsep.join((str(dynamic_app), str(dynamic_archive))), "fixture.dynamic.DynamicLookup")
        require(result.code == 0, f"classpath/configuration-only loading failed\n{result.detail()}")
        same_output("fixture.dynamic.ConfigOnly\n", result.stdout, result.detail())

        duplicate_main = compile_sources(
            directory / "duplicate-compiled",
            fixture / "DuplicatePrecedenceMain.java",
            fixture / "duplicate-first" / "Provider.java",
        )
        second = compile_sources(
            directory / "duplicate-second-compiled",
            fixture / "duplicate-second" / "Provider.java",
        )
        duplicate_app = write_fixture_directory(
            directory / "duplicate-app",
            {name: value for name, value in duplicate_main.items() if name.endswith("DuplicatePrecedenceMain.class")},
        )
        first_provider = write_fixture_directory(
            directory / "duplicate-first-root",
            {name: value for name, value in duplicate_main.items() if name.endswith("Provider.class")},
        )
        second_provider = write_fixture_directory(directory / "duplicate-second-root", second)
        for roots, output in (
            ((first_provider, second_provider, duplicate_app), "first\n"),
            ((second_provider, first_provider, duplicate_app), "second\n"),
        ):
            result = self.cli("-cp", os.pathsep.join(map(str, roots)), "fixture.duplicate.app.DuplicatePrecedenceMain")
            require(result.code == 0, f"classpath/precedence failed\n{result.detail()}")
            same_output(output, result.stdout, result.detail())

        resource = compile_sources(directory / "resource-compiled", fixture / "ResourceConsumer.java")
        resource_app = write_fixture_directory(directory / "resource-app", resource)
        resource_archive = write_fixture_jar(
            directory / "resource dependency.jar",
            resources={"fixture-resource.bin": bytes((0, 1, 127, 128, 255))},
        )
        result = self.cli("-cp", os.pathsep.join((str(resource_app), str(resource_archive))),
                          "fixture.resource.ResourceConsumer")
        require(result.code == 0, f"classpath/resource failed\n{result.detail()}")
        same_output("0\n1\n127\n128\n255\n", result.stdout, result.detail())
        enumeration_source = directory / "ResourceEnumerationConsumer.java"
        enumeration_source.write_text(
            "package fixture.resource; import java.io.InputStream; import java.net.URL; "
            "import java.util.Enumeration; "
            "public class ResourceEnumerationConsumer { "
            "static boolean escaped(String text, char first, char second) { "
            "for (int i = 0; i + 2 < text.length(); i++) "
            "if (text.charAt(i) == '%' && text.charAt(i + 1) == first && text.charAt(i + 2) == second) return true; "
            "return false; } "
            "public static void main(String[] args) throws Exception { "
            "Enumeration<URL> resources = ClassLoader.getSystemResources(\"fixture-resource.bin\"); "
            "while (resources.hasMoreElements()) { URL url = resources.nextElement(); "
            "System.out.println(url.getProtocol().equals(\"jar\")); "
            "System.out.println(url.toExternalForm().charAt(0)); "
            "System.out.println(escaped(url.toExternalForm(), '2', '0')); "
            "System.out.println(escaped(url.toExternalForm(), 'c', '3')); "
            "InputStream stream = url.openStream(); System.out.println(stream.read()); stream.close(); } } }",
            encoding="utf-8",
        )
        enumeration = compile_sources(directory / "resource-enumeration-compiled", enumeration_source)
        enumeration_app = write_fixture_directory(directory / "resource-enumeration-app", enumeration)
        first_archive = write_fixture_jar(
            directory / "resource first é.jar",
            resources={"fixture-resource.bin": bytes((9,))},
        )
        second_archive = write_fixture_jar(
            directory / "resource-second.jar",
            resources={"fixture-resource.bin": bytes((8,))},
        )
        result = self.cli(
            "-cp",
            os.pathsep.join((str(enumeration_app), str(first_archive), str(second_archive))),
            "fixture.resource.ResourceEnumerationConsumer",
        )
        require(result.code == 0, f"classpath/resource enumeration failed\n{result.detail()}")
        same_output("true\nj\ntrue\ntrue\n9\ntrue\nj\nfalse\nfalse\n8\n", result.stdout, result.detail())
        properties_source = directory / "PropertiesConsumer.java"
        properties_source.write_text(
            "package fixture.resource; import java.io.InputStream; import java.io.InputStreamReader; import java.io.Reader; import java.util.Properties; "
            "public class PropertiesConsumer { public static void main(String[] args) throws Exception { "
            "InputStream stream = ClassLoader.getSystemResourceAsStream(\"fixture.properties\"); "
            "Properties properties = new Properties(); properties.load(stream); stream.close(); "
            "System.out.println(properties.getProperty(\"accent\")); "
            "System.out.println(properties.getProperty(\"unicode\")); "
            "System.out.println(properties.getProperty(\"joined\")); "
            "System.out.println(properties.getProperty(\"escaped:key\")); "
            "System.out.println(properties.getProperty(\"duplicate\")); "
            "System.out.println(properties.getProperty(\"missing\", \"fallback\")); "
            "InputStream malformed = ClassLoader.getSystemResourceAsStream(\"bad.properties\"); "
            "try { new Properties().load(malformed); System.out.println(false); } "
            "catch (IllegalArgumentException error) { System.out.println(true); } "
            "Reader reader = new InputStreamReader(ClassLoader.getSystemResourceAsStream(\"reader.properties\"), \"UTF-8\"); "
            "Properties readerProperties = new Properties(); readerProperties.load(reader); "
            "System.out.println(readerProperties.getProperty(\"accent\")); "
            "System.out.println(readerProperties.getProperty(\"unicode\")); } }",
            encoding="utf-8",
        )
        properties = compile_sources(directory / "properties-compiled", properties_source)
        properties_app = write_fixture_directory(directory / "properties-app", properties)
        properties_archive = write_fixture_jar(
            directory / "properties.jar",
            resources={"fixture.properties": b"# comment\naccent=caf\xe9\nunicode=\\u263A\njoined=hello\\\n  world\nescaped\\:key=value\\=x\nduplicate=first\nduplicate=second\n", "bad.properties": b"bad=\\u12G4\n", "reader.properties": "accent=café\nunicode=☃\n".encode()},
        )
        result = self.cli(
            "-cp",
            os.pathsep.join((str(properties_app), str(properties_archive))),
            "fixture.resource.PropertiesConsumer",
        )
        require(result.code == 0, f"classpath/properties failed\n{result.detail()}")
        same_output("café\n☺\nhelloworld\nvalue=x\nsecond\nfallback\ntrue\ncafé\n☃\n", result.stdout, result.detail())
        class_resource_source = directory / "ClassResourceConsumer.java"
        class_resource_source.write_text(
            "package fixture.resource; import java.io.InputStream; "
            "public class ClassResourceConsumer { public static void main(String[] args) throws Exception { "
            "InputStream relative = ClassResourceConsumer.class.getResourceAsStream(\"class.properties\"); "
            "InputStream dot = ClassResourceConsumer.class.getResourceAsStream(\"./class.properties\"); "
            "InputStream parent = ClassResourceConsumer.class.getResourceAsStream(\"../resource/class.properties\"); "
            "InputStream absolute = ClassResourceConsumer.class.getResourceAsStream(\"/fixture/resource/class.properties\"); "
            "InputStream root = ClassResourceConsumer.class.getResourceAsStream(\"/root.properties\"); "
            "System.out.println(relative == null); System.out.println(dot == null); "
            "System.out.println(parent == null); System.out.println(absolute == null); System.out.println(root == null); "
            "if (relative != null) System.out.println(relative.read()); "
            "if (dot != null) System.out.println(dot.read()); "
            "if (parent != null) System.out.println(parent.read()); "
            "if (absolute != null) System.out.println(absolute.read()); "
            "if (root != null) System.out.println(root.read()); } }",
            encoding="utf-8",
        )
        class_resource = compile_sources(directory / "class-resource-compiled", class_resource_source)
        class_resource_app = write_fixture_directory(directory / "class-resource-app", class_resource)
        class_resource_archive = write_fixture_jar(
            directory / "class-resource.jar",
            resources={"fixture/resource/class.properties": b"r", "root.properties": b"root"},
        )
        result = self.cli(
            "-cp",
            os.pathsep.join((str(class_resource_app), str(class_resource_archive))),
            "fixture.resource.ClassResourceConsumer",
        )
        require(result.code == 0, f"classpath/class-relative resource failed\n{result.detail()}")
        same_output("false\nfalse\nfalse\nfalse\nfalse\n114\n114\n114\n114\n114\n", result.stdout, result.detail())
        manifest = compile_sources(
            directory / "manifest-compiled",
            fixture / "ManifestMain.java",
            fixture / "ManifestDependency.java",
        )
        manifest_main = {name: value for name, value in manifest.items() if name.endswith("ManifestMain.class")}
        manifest_dependency = {
            name: value for name, value in manifest.items() if name.endswith("ManifestDependency.class")
        }
        dependency_jar = write_fixture_jar(directory / "manifest lib.jar", manifest_dependency)
        app_jar = write_fixture_jar(
            directory / "manifest app.jar",
            manifest_main,
            manifest=manifest_bytes(
                main_class="fixture.manifest.ManifestMain",
                class_path=(dependency_jar.name.replace(" ", "%20"),),
                line_ending="\n",
            ),
        )
        result = self.cli("-jar", str(app_jar), "manifest argument")
        require(result.code == 0, f"classpath/manifest failed\n{result.detail()}")
        same_output("manifest-startup\n", result.stdout, result.detail())

        missing_manifest = write_fixture_jar(directory / "missing-main.jar", manifest_main)
        result = self.cli("-jar", str(missing_manifest))
        require(result.code > 0 and "Main-Class" in result.stderr,
                f"missing manifest metadata was not rejected\n{result.detail()}")

        missing = self.cli("-cp", str(app_dir), "fixture.packaged.PackagedMain")
        require(missing.code > 0 and "MissingClass" in missing.stderr and "fixture/packaged/PackagedMain" in missing.stderr,
                f"missing dependency was not reported\n{missing.detail()}")

        polluted = write_fixture_directory(
            directory / "polluted-app",
            {**packaged_main, "Broken.class": b"not-a-class"},
        )
        result = self.cli("-cp", os.pathsep.join((str(polluted), str(dep_dir))), "fixture.packaged.PackagedMain")
        require(result.code == 0, f"unrelated malformed class broke startup\n{result.detail()}")
        same_output(expected, result.stdout, result.detail())

        cycle_sources = directory / "cycle-src"
        cycle_sources.mkdir()
        (cycle_sources / "CycleA.java").write_text(
            "package fixture.cycle; public class CycleA {"
            " public static int value() { return CycleB.other(); }"
            " public static int other() { return 1; }"
            " public static void main(String[] args) { System.out.println(CycleA.value() + CycleB.value()); }"
            "}",
            encoding="utf-8",
        )
        (cycle_sources / "CycleB.java").write_text(
            "package fixture.cycle; public class CycleB {"
            " public static int value() { return CycleA.other(); }"
            " public static int other() { return 6; }"
            "}",
            encoding="utf-8",
        )
        cycle = compile_sources(directory / "cycle-compiled", cycle_sources / "CycleA.java", cycle_sources / "CycleB.java")
        cycle_dir = write_fixture_directory(directory / "cycle-app", cycle)
        result = self.cli("-cp", str(cycle_dir), "fixture.cycle.CycleA")
        require(result.code == 0, f"cyclic dependencies failed\n{result.detail()}")
        same_output("7\n", result.stdout, result.detail())

        empty_archive = write_fixture_jar(directory / "empty-resource.jar", resources={"fixture-resource.bin": b""})
        result = self.cli("-cp", os.pathsep.join((str(resource_app), str(empty_archive))),
                          "fixture.resource.ResourceConsumer")
        require(result.code == 0, f"empty resource failed\n{result.detail()}")
        same_output("-1\n-1\n-1\n-1\n-1\n", result.stdout, result.detail())

        result = self.cli("-cp", str(resource_app), "fixture.resource.ResourceConsumer")
        require(result.code == 0, f"missing resource failed\n{result.detail()}")
        same_output("missing\n", result.stdout, result.detail())

        remote = write_fixture_jar(
            directory / "remote.jar",
            manifest_main,
            manifest=manifest_bytes(main_class="fixture.manifest.ManifestMain", class_path=("http://example.com/x.jar",)),
        )
        result = self.cli("-jar", str(remote))
        require(result.code > 0 and "scheme" in result.stderr,
                f"remote manifest Class-Path was not rejected\n{result.detail()}")

        duplicate = directory / "duplicate-entry.jar"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(duplicate, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
                payload = next(iter(packaged_main.values()))
                archive.writestr("fixture/packaged/PackagedMain.class", payload)
                archive.writestr("fixture/packaged/PackagedMain.class", payload)
        result = self.cli("-cp", str(duplicate), "fixture.packaged.PackagedMain")
        require(result.code > 0 and "duplicate" in result.stderr,
                f"duplicate archive entry was not rejected\n{result.detail()}")

        closed_source = directory / "ClosedStream.java"
        closed_source.write_text(
            "package fixture.resource; import java.io.InputStream; import java.io.IOException;"
            " public class ClosedStream { public static void main(String[] args) throws Exception {"
            " InputStream stream = ClassLoader.getSystemResourceAsStream(\"fixture-resource.bin\");"
            " stream.close(); try { System.out.println(stream.read()); }"
            " catch (IOException closed) { System.out.println(\"closed\"); } } }",
            encoding="utf-8",
        )
        closed = compile_sources(directory / "closed-compiled", closed_source)
        closed_dir = write_fixture_directory(directory / "closed-app", closed)
        closed_cp = os.pathsep.join((str(closed_dir), str(resource_archive)))
        reference = execute([self.args.java, "-Dfile.encoding=UTF-8", "-cp", closed_cp,
                             "fixture.resource.ClosedStream"], self.args.timeout)
        result = self.cli("-cp", closed_cp, "fixture.resource.ClosedStream")
        require(reference.code == 0, f"reference closed stream failed\n{reference.detail()}")
        require(result.code == 0, f"closed stream failed\n{result.detail()}")
        same_output(reference.stdout, result.stdout, result.detail())


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--fast", action="store_true", help="named spec fixtures and 3 generated programs (default)")
    mode.add_argument("--full", action="store_true", help="all fixtures, extended corruptions, 24 generated programs")
    parser.add_argument("--only", action="append", choices=NAMED + EXTENDED,
                        help="run only these differential fixtures, skipping limit/debug/malformed checks")
    parser.add_argument("--check", action="append", metavar="SUBSTRING",
                        help="run only checks whose name contains SUBSTRING (repeatable)")
    parser.add_argument("--generated", type=int, help="generated program count; defaults to 3 fast, 24 full, 0 with --only")
    parser.add_argument("--seed", type=lambda text: int(text, 0), default=0xB3D2026)
    parser.add_argument("--timeout", type=float, default=120.0, help="per subprocess timeout in seconds")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--bend", default=os.environ.get("BEND", DEFAULT_BEND))
    parser.add_argument("--java", default=os.environ.get("JAVA", "java"))
    parser.add_argument("--javac", default=os.environ.get("JAVAC", "javac"))
    args = parser.parse_args()
    if args.generated is None:
        args.generated = 0 if args.only else 24 if args.full else 3
    if args.generated < 0 or args.timeout <= 0:
        parser.error("--generated must be nonnegative and --timeout must be positive")
    return args


def main() -> int:
    args = arguments()
    # Subprocesses run outside the repository, so a path-like runner must be absolute.
    if os.sep in args.bend:
        args.bend = str(Path(args.bend).resolve())
    try:
        for name, executable in (("Bend", args.bend), ("java", args.java), ("javac", args.javac)):
            require(shutil.which(executable) is not None,
                    f"{name} executable not found: {executable!r}; see --help for tool overrides")
        require((ROOT / "bendjvm" / "main.bend").is_file(), "missing bendjvm/main.bend")
        if Path(args.bend).resolve() == (ROOT / "scripts" / "run.py").resolve():
            preparation = execute([args.bend, "--prepare"], max(args.timeout, 2400.0))
            require(preparation.code == 0, f"Bend runner preparation failed\n{preparation.detail()}")
        selected = list(dict.fromkeys(args.only)) if args.only else list(NAMED + (EXTENDED if args.full else ()))
        print(f"seed={args.seed:#x}; generated={args.generated}; mode={'full' if args.full else 'fast'}", flush=True)
        with tempfile.TemporaryDirectory(prefix="bendjvm-tests-") as temporary:
            directory = Path(temporary)
            global WORKDIR
            WORKDIR = directory / "cwd"
            WORKDIR.mkdir()
            classes, sources = directory / "classes", directory / "sources"
            classes.mkdir()
            sources.mkdir()
            inputs = [FIXTURES / f"{name}.java" for name in selected]
            for name in selected:
                inputs.extend(FIXTURES / dependency for dependency in FIXTURE_DEPENDENCIES.get(name, ()))
            if not args.only:
                inputs.extend(FIXTURES / f"{name}.java" for name in SUPPORT)
                indy_support = sources / "IndySupport.java"
                indy_support.write_text(BOOTSTRAP_SOURCE, encoding="utf-8")
                inputs.append(indy_support)
            rng = random.Random(args.seed)
            for index in range(args.generated):
                name, source = generated_source(index, rng)
                path = sources / f"{name}.java"
                path.write_text(source, encoding="utf-8")
                inputs.append(path)
                selected.append(name)
            compilation = execute([args.javac, "--release", "8", "-encoding", "UTF-8", "-g:none",
                                   "-d", str(classes), *map(str, inputs)], args.timeout)
            require(compilation.code == 0, f"fixture compilation failed\n{compilation.detail()}")
            if not args.only:
                for class_name, class_bytes in generated_classes().items():
                    (classes / f"{class_name}.class").write_bytes(class_bytes)
            suite = Suite(args, classes)
            for name in selected:
                if name != "MetadataFixture":
                    suite.check(name, lambda name=name: suite.differential(name))
            if "MetadataFixture" in selected:
                suite.check("metadata/retention-defaults-malformed",
                            lambda: suite.metadata(directory))
            if not args.only:
                suite.check("invokedynamic/custom-bootstrap", suite.invokedynamic)
                suite.check("verifier/constructor-and-descriptor-edges",
                            lambda: suite.verifier_edges(directory))
                suite.check("switch/default-only-and-malformed",
                            lambda: suite.switch_edges(directory))
                suite.check("verifier/category-sensitive-stack-forms",
                            lambda: suite.stack_permutation_forms(directory))
                suite.check("reflection/parameter-names", lambda: suite.parameter_names(directory))
                suite.check("classpath/archive-manifest-resource", lambda: suite.classpath(directory))
                suite.check("reflection/packaged-component-container",
                            lambda: suite.reflective_app(directory))
                suite.check("resources/ownership-missing-hierarchy",
                            lambda: suite.resource_contracts(directory))
                suite.check("resources/url-escaping",
                            lambda: suite.resource_urls(directory))
                suite.check("resources/package-scanning",
                            lambda: suite.package_scanning(directory))
                suite.check("loaders/user-class-loaders",
                            lambda: suite.class_loaders(directory))
            if not args.only:
                suite.check("jre/reference-audit", suite.jre_references)
                suite.check("threads/main-uncaught-handler", suite.main_handled)
                suite.check("threads/stack-traces", lambda: suite.stack_traces(directory))
                suite.check("threads/priorities", suite.priorities)
                suite.check("threads/native-frames", lambda: suite.native_frames(directory))
                suite.check("threads/deadlock-diagnostic", suite.deadlock)
                suite.check("threads/fuel-with-blocked-threads", suite.fuel_with_threads)
            if args.full and not args.only:
                suite.check("threads/schedule-variation", suite.schedule_variation)
                suite.check("native/plugin-bridge", lambda: suite.native_plugins(directory))
                suite.check("tls/client-server-interop", lambda: suite.tls(directory))
                suite.check("web/https-example", lambda: suite.https_example(directory))
            if args.full and not args.only:
                suite.check("runtime-expansion-app", lambda: suite.runtime_app(directory))
                suite.check("broader-bytecode-packaged-app",
                            lambda: suite.broader_app(directory))
            if not args.only:
                original = (classes / "MutationTarget.class").read_bytes()
                for name, contents, category in malformed_cases(original, args.full):
                    destination = directory / name
                    destination.mkdir()
                    path = destination / "MutationTarget.class"
                    path.write_bytes(contents)
                    suite.check(f"malformed/{name}", lambda path=path, category=category: suite.reject(path, category))
                suite.check("cli/fuel", suite.fuel)
                suite.check("cli/max-heap", suite.heap)
                if args.full:
                    suite.check("cli/capabilities", suite.capabilities)
                for mode in ("--dump-class", "--disassemble", "--trace"):
                    suite.check(f"cli/{mode[2:]}", lambda mode=mode: suite.debug(mode))
            print(f"{suite.passed} passed, {suite.failed} failed", flush=True)
            return 1 if suite.failed else 0
    except (Failure, OSError, ValueError, KeyError, struct.error) as error:
        print(f"FAIL harness: {error}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
