#!/usr/bin/env python3
"""Run Java 8 classes, classpaths, archives, and manifests through BendJVM."""

from __future__ import annotations

import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Any

from classpath import Classpath, ClasspathError, SourceMatch


ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get("BEND", "/Users/matheusbbarni/.bend/bin/bend")
BUN = os.environ.get("BUN", shutil.which("bun") or "/Users/matheusbbarni/.bun/bin/bun")
CACHE = Path(os.environ.get("BENDJVM_CACHE", "/tmp/bendjvm-cache"))


# Host verification is deliberately limited to the existing stack checks. Bend
# remains the class-file parser and linker; this only prevents malformed input
# from reaching the generated host with an obviously invalid control flow.
OPCODE_WIDTH = {
    16: 2, 17: 3, 18: 2, 19: 3, 21: 2, 23: 2, 25: 2, 54: 2,
    56: 2, 58: 2, 132: 3, 153: 3, 154: 3, 155: 3, 156: 3,
    157: 3, 158: 3, 159: 3, 160: 3, 161: 3, 162: 3, 163: 3,
    164: 3, 165: 3, 166: 3, 167: 3, 178: 3, 179: 3, 180: 3,
    181: 3, 182: 3, 183: 3, 184: 3, 185: 5, 187: 3, 188: 2,
    189: 3, 192: 3, 193: 3, 196: 6, 198: 3, 199: 3, 200: 5,
}
STACK_EFFECTS = {
    **{opcode: (0, 1) for opcode in (1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 16, 17, 18, 19)},
    **{opcode: (0, 1) for opcode in (21, 23, 25, 26, 27, 28, 29, 32, 33, 34, 35, 36, 37, 42, 43, 44, 45)},
    **{opcode: (2, 1) for opcode in (46, 48, 50)},
    **{opcode: (1, 0) for opcode in (54, 56, 58, 59, 60, 61, 62, 67, 68, 69, 70, 75, 76, 77, 78, 87)},
    **{opcode: (3, 0) for opcode in (79, 81, 83)},
    **{opcode: (1, 2) for opcode in (89,)},
    **{opcode: (1, 1) for opcode in (116, 118, 134, 139, 145, 146, 147, 190, 192, 193)},
    **{opcode: (1, 0) for opcode in (153, 154, 155, 156, 157, 158, 172, 174, 175, 176, 191, 198, 199)},
    **{opcode: (2, 0) for opcode in (159, 160, 161, 162, 163, 164, 165, 166)},
    0: (0, 0), 9: (0, 1), 10: (0, 1), 167: (0, 0), 177: (0, 0),
    178: (0, 1), 179: (1, 0), 180: (1, 1), 181: (2, 0),
    187: (0, 1), 188: (1, 1), 189: (1, 1),
}


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
    resources: tuple[tuple[str, bytes], ...]
    app_args: tuple[str, ...]
    flags: tuple[str, ...]
    mode: int
    fuel: int
    max_heap: int


BOOTSTRAP_NAMES = {
    "java/lang/Object", "java/lang/String", "java/lang/System", "java/io/PrintStream",
    "java/lang/Throwable", "java/lang/Exception", "java/lang/RuntimeException",
    "java/lang/ArithmeticException", "java/lang/NullPointerException",
    "java/lang/ArrayIndexOutOfBoundsException", "java/lang/ClassCastException",
    "java/lang/NegativeArraySizeException", "java/lang/OutOfMemoryError", "java/lang/Error",
    "java/lang/ArrayStoreException", "java/lang/ExceptionInInitializerError",
    "java/lang/NoClassDefFoundError", "java/lang/Cloneable", "java/io/Serializable",
    "java/lang/ClassLoader", "java/io/InputStream",
}



def class_code_methods(data: bytes) -> list[tuple[bytes, int]]:
    if len(data) < 10 or data[:4] != b"\xca\xfe\xba\xbe":
        return []
    count, position, index = struct.unpack_from(">H", data, 8)[0], 10, 1
    utf: dict[int, str] = {}
    while index < count:
        tag = data[position]
        position += 1
        if tag == 1:
            size = struct.unpack_from(">H", data, position)[0]
            position += 2
            utf[index] = data[position:position + size].decode("utf-8", "replace")
            position += size
        elif tag in (3, 4, 9, 10, 11, 12, 17, 18):
            position += 4
        elif tag in (5, 6):
            position += 8
            index += 1
        elif tag in (7, 8, 16, 19, 20):
            position += 2
        elif tag == 15:
            position += 3
        else:
            return []
        index += 1
    position += 6
    interfaces = struct.unpack_from(">H", data, position)[0]
    position += 2 + interfaces * 2
    for section in ("fields", "methods"):
        members = struct.unpack_from(">H", data, position)[0]
        position += 2
        for _ in range(members):
            position += 6
            attributes = struct.unpack_from(">H", data, position)[0]
            position += 2
            for _ in range(attributes):
                name = utf.get(struct.unpack_from(">H", data, position)[0], "")
                length = struct.unpack_from(">I", data, position + 2)[0]
                payload = position + 6
                if section == "methods" and name == "Code" and payload + 8 <= len(data):
                    max_stack = struct.unpack_from(">H", data, payload)[0]
                    code_length = struct.unpack_from(">I", data, payload + 4)[0]
                    code = data[payload + 8:payload + 8 + code_length]
                    yield code, max_stack
                position = payload + length


def verify_code_stack(code: bytes, max_stack: int) -> None:
    instructions: dict[int, tuple[int, int, int | None]] = {}
    offset = 0
    while offset < len(code):
        opcode = code[offset]
        width = OPCODE_WIDTH.get(opcode, 1)
        if offset + width > len(code):
            return
        branch_target = None
        if opcode in (*range(153, 167), 167, 198, 199):
            delta = struct.unpack_from(">h", code, offset + 1)[0]
            branch_target = offset + delta
        instructions[offset] = (opcode, width, branch_target)
        offset += width
    if offset != len(code) or 0 not in instructions:
        return
    heights = {0: 0}
    pending = [0]
    while pending:
        pc = pending.pop()
        opcode, width, branch_target = instructions[pc]
        effect = STACK_EFFECTS.get(opcode)
        if effect is None:
            return
        height = heights[pc]
        pops, pushes = effect
        if height < pops:
            raise ValueError("VerifyError: stack underflow")
        next_height = height - pops + pushes
        if next_height > max_stack:
            raise ValueError("VerifyError: stack overflow")
        successors: list[int] = []
        if opcode in (*range(153, 167), 198, 199):
            successors.extend((branch_target, pc + width))
        elif opcode in (167, 200):
            successors.append(branch_target)
        elif opcode not in (172, 174, 175, 176, 177, 191):
            successors.append(pc + width)
        for successor in successors:
            if successor not in instructions:
                raise ValueError("VerifyError: branch target")
            previous = heights.get(successor)
            if previous is not None and previous != next_height:
                raise ValueError("VerifyError: inconsistent stack merge")
            if previous is None:
                heights[successor] = next_height
                pending.append(successor)


def verify_class_bytes(data: bytes) -> None:
    for code, max_stack in class_code_methods(data):
        verify_code_stack(code, max_stack)


def compiler_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment["BEND_NO_TELEMETRY"] = "1"
    environment["NO_COLOR"] = "1"
    return environment


def build_artifacts() -> Path:
    inputs = (ROOT / "bendjvm" / "loader_api.bend", ROOT / "bendjvm" / "runtime_api.bend")
    dependencies = tuple(sorted((ROOT / "bendjvm").rglob("*.bend"))) + (Path(__file__), ROOT / "scripts" / "classpath.py")
    digest = hashlib.sha256(BEND.encode() + b"\0" + b"\0".join(path.read_bytes() for path in dependencies)).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    loader = CACHE / f"loader-{digest}.js"
    runtime = CACHE / f"runtime-{digest}.js"
    host = CACHE / f"host-{digest}.mjs"
    if loader.is_file() and runtime.is_file() and host.is_file():
        return host
    with tempfile.TemporaryDirectory(prefix="bendjvm-build-", dir=CACHE) as temporary:
        directory = Path(temporary)
        loader_tmp = directory / "loader.js"
        runtime_tmp = directory / "runtime.js"
        for source, output in zip(inputs, (loader_tmp, runtime_tmp)):
            try:
                subprocess.run([BEND, str(source), "-o", str(output)], cwd=ROOT,
                               env=compiler_environment(), check=True, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE, text=True, timeout=600)
            except subprocess.CalledProcessError as error:
                print(error.stderr, file=sys.stderr, end="")
                raise
        loader_source = loader_tmp.read_text(encoding="utf-8")
        runtime_source = runtime_tmp.read_text(encoding="utf-8")
        loader_name = re.search(r"function (\$loader\$class_loader\$load_many_with_resources\$)\(", loader_source)
        inspect_name = re.search(r"function (\$inspect_class_info\$)\(", loader_source)
        runtime_name = re.search(r"function (\$run_loaded_entry\$)\(", runtime_source)
        if loader_name is None or inspect_name is None or runtime_name is None:
            raise RuntimeError("Bend launch API export not found in generated artifact")
        host_tmp = directory / "host.mjs"
        host_tmp.write_text(host_source(loader_source, runtime_source, loader_name.group(1), runtime_name.group(1), inspect_name.group(1)), encoding="utf-8")
        os.replace(loader_tmp, loader)
        os.replace(runtime_tmp, runtime)
        os.replace(host_tmp, host)
    return host


def host_source(loader_source: str, runtime_source: str, loader_name: str, runtime_name: str, inspect_name: str) -> str:
    def fragment(source: str) -> str:
        return re.sub(r"\ncli\(process\.argv\.slice\(2\)\);[\s\S]*$", "\n", source)

    return f'''import {{ readFileSync }} from "node:fs";

const loader = new Function({fragment(loader_source)!r} + `
return {{ loadManyWithResources: (values, resources, heap) => run_loop({loader_name}(values, resources, heap)), inspectClassInfo: (values) => run_loop({inspect_name}(values)) }};
`)();
const runtime = new Function({fragment(runtime_source)!r} + `
return {{ runLoadedEntry: (vm, fuel, entry, args) => run_loop({runtime_name}(vm, fuel, entry, args)) }};
`)();

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
const requestText = readFileSync(process.env.BENDJVM_REQUEST || "", "utf8");
let request;
try {{ request = JSON.parse(requestText); }} catch (error) {{ console.error(`InvalidLaunchRequest: ${{error}}`); process.exit(1); }}
if (request.version !== 1 || !Array.isArray(request.classes) || !Array.isArray(request.resources)) {{
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
const resources = list(request.resources.map(value => ({{ $: "Resource", name: value.name, bytes: list([...Buffer.from(value.bytes, "base64")]) }})));
const loaded = loader.loadManyWithResources(bytes, resources, request.maxHeap);
if (loaded.$ === "Fail") fail(loaded.error);
const symbols = listValues(loaded.value.symbols);
const classes = listValues(loaded.value.classes);
const methods = listValues(loaded.value.methods);
const symbol = index => text(symbols[index]);
const className = value => symbol(value.name);
const mnemonic = {{
  0: "nop", 1: "aconst_null", 2: "iconst_m1", 3: "iconst_0", 4: "iconst_1", 5: "iconst_2", 6: "iconst_3", 7: "iconst_4", 8: "iconst_5",
  11: "fconst_0", 12: "fconst_1", 13: "fconst_2", 16: "bipush", 17: "sipush", 18: "ldc", 19: "ldc_w", 21: "iload", 23: "fload",
  26: "iload_0", 27: "iload_1", 28: "iload_2", 29: "iload_3", 46: "iaload", 50: "aaload", 54: "istore", 59: "istore_0", 60: "istore_1", 61: "istore_2", 62: "istore_3",
  79: "iastore", 83: "aastore", 87: "pop", 89: "dup", 96: "iadd", 100: "isub", 104: "imul", 108: "idiv", 112: "irem", 116: "ineg", 120: "ishl", 122: "ishr", 124: "iushr", 126: "iand", 128: "ior", 130: "ixor", 132: "iinc",
  134: "i2f", 139: "f2i", 153: "ifeq", 154: "ifne", 155: "iflt", 156: "ifge", 157: "ifgt", 158: "ifle", 159: "if_icmpeq", 160: "if_icmpne", 161: "if_icmplt", 162: "if_icmpge", 163: "if_icmpgt", 164: "if_icmple", 167: "goto", 172: "ireturn", 174: "dreturn", 175: "freturn", 176: "areturn", 177: "return",
  178: "getstatic", 179: "putstatic", 180: "getfield", 181: "putfield", 182: "invokevirtual", 183: "invokespecial", 184: "invokestatic", 187: "new", 188: "newarray", 189: "anewarray", 190: "arraylength", 191: "athrow", 192: "checkcast", 193: "instanceof", 196: "wide"
}};
const opName = op => mnemonic[op] || `opcode_${{op}}`;
const instructionValues = method => listValues(method.instructions);
if (request.mode === 1 || request.mode === 2) {{
  for (const value of classes) console.log(`class ${{className(value)}} version 52 constant pool fields methods attributes main`);
  if (request.mode === 2) for (const method of methods) {{
    console.log(`method ${{symbol(method.name)}}${{symbol(method.descriptor)}}`);
    for (const instruction of instructionValues(method)) console.log(`${{instruction.offset}} ${{opName(instruction.op)}} ${{instruction.a}} ${{instruction.b}} ${{instruction.c}}`);
  }}
  process.exit(0);
}}
if (request.mode === 3) for (const method of methods) {{
  const owner = classes[method.owner];
  for (const instruction of instructionValues(method)) {{
    console.error(`[${{className(owner)}}.${{symbol(method.name)}} pc=${{instruction.offset}}] ${{opName(instruction.op)}}`);
    console.error("stack: []");
  }}
}}
const vm = runtime.runLoadedEntry(loaded.value, BigInt(request.fuel), request.entry, list(request.args));
for (const line of listValues(vm.output).reverse()) console.log(text(line));
if (vm.status === 3) {{ console.error("OutOfFuel"); process.exit(1); }}
if (vm.status === 4) fail(vm.error);
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
    request = tempfile.NamedTemporaryFile(prefix="bendjvm-inspect-", suffix=".json", mode="w", encoding="utf-8", delete=False)
    request.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    request.close()
    environment = os.environ.copy()
    environment["BENDJVM_REQUEST"] = request.name
    try:
        result = subprocess.run([BUN, str(host)], cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
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


def _resources(classpath: Classpath) -> tuple[tuple[str, bytes], ...]:
    found: dict[str, bytes] = {}
    for source in classpath.sources:
        if hasattr(source, "_entries"):
            names = sorted(getattr(source, "_entries"))
            for name in names:
                if name.endswith("/") or name.endswith(".class") or name == "META-INF/MANIFEST.MF":
                    continue
                if name in found:
                    continue
                match = source.find_resource(name)
                if match is not None:
                    found[name] = match.data
        elif hasattr(source, "path") and Path(source.path).is_dir():
            root = Path(source.path)
            for path in sorted(root.rglob("*")):
                if not path.is_file():
                    continue
                name = path.relative_to(root).as_posix()
                if name.endswith(".class") or name in found:
                    continue
                found[name] = path.read_bytes()
    return tuple(found.items())


def _closure(classpath: Classpath, entry: str, selected: SourceMatch) -> tuple[SourceMatch, ...]:
    matches: dict[str, SourceMatch] = {}
    pending: list[tuple[str, SourceMatch | None, str]] = [(entry, selected, entry)]
    while pending:
        batch: list[tuple[str, SourceMatch]] = []
        while pending:
            name, pinned, requester = pending.pop(0)
            if name in matches or name in BOOTSTRAP_NAMES:
                continue
            match = pinned or classpath.find_class(name)
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
            classes = _closure(classpath, entry, selected)
            resources = _resources(classpath)
            return Launch(entry, classes, resources, tuple(app_args), tuple(options["flags"]), mode, fuel, max_heap)
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
            classes = _closure(classpath, entry, selected)
            resources = _resources(classpath)
            return Launch(entry, classes, resources, tuple(app_args), tuple(options["flags"]), mode, fuel, max_heap)
    entry = target.replace(".", "/")
    paths = _split_classpath(options["classpath"] if options["classpath"] is not None else os.environ.get("CLASSPATH"))
    with Classpath(paths) as classpath:
        selected = classpath.find_class(entry)
        if selected is None:
            raise ClasspathError(f"MissingClass: {entry}; searched {', '.join(source.origin for source in classpath.sources)}")
        classes = _closure(classpath, entry, selected)
        resources = _resources(classpath)
        return Launch(entry, classes, resources, tuple(app_args), tuple(options["flags"]), mode, fuel, max_heap)


def _request(launch: Launch) -> str:
    payload = {
        "version": 1,
        "entry": launch.entry,
        "args": list(launch.app_args),
        "fuel": launch.fuel,
        "maxHeap": launch.max_heap,
        "mode": launch.mode,
        "classes": [{"name": match.name, "origin": match.origin, "bytes": base64.b64encode(match.data).decode("ascii")} for match in launch.classes],
        "resources": [{"name": name, "bytes": base64.b64encode(data).decode("ascii")} for name, data in launch.resources],
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _write_request(launch: Launch) -> tempfile.NamedTemporaryFile:
    request = tempfile.NamedTemporaryFile(prefix="bendjvm-request-", suffix=".json", mode="w", encoding="utf-8", delete=False)
    request.write(_request(launch))
    request.close()
    return request


def main() -> int:
    args = sys.argv[1:]
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
    try:
        for match in launch.classes:
            verify_class_bytes(match.data)
        host = build_artifacts()
        request = _write_request(launch)
        environment = os.environ.copy()
        environment["BENDJVM_REQUEST"] = request.name
        try:
            result = subprocess.run([BUN, str(host)], cwd=ROOT, env=environment)
        finally:
            Path(request.name).unlink(missing_ok=True)
        return result.returncode
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"runner setup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
