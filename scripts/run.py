#!/usr/bin/env python3
"""Run class files through the isolated Bend loader and runtime artifacts."""

from __future__ import annotations

import hashlib
import os
import struct
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get("BEND", "/Users/matheusbbarni/.bend/bin/bend")
BUN = os.environ.get("BUN", shutil.which("bun") or "/Users/matheusbbarni/.bun/bin/bun")
CACHE = Path(os.environ.get("BENDJVM_CACHE", "/tmp/bendjvm-cache"))


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
        elif tag in (3, 4, 9, 10, 11, 12, 18):
            position += 4
        elif tag in (5, 6):
            position += 8
            index += 1
        elif tag in (7, 8, 16):
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
        if opcode in (153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 198, 199):
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
        if opcode in (153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 198, 199):
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
    dependencies = tuple(sorted((ROOT / "bendjvm").rglob("*.bend")))
    digest = hashlib.sha256(BEND.encode() + b"\0" + Path(__file__).read_bytes() + b"\0" + b"\0".join(path.read_bytes() for path in dependencies)).hexdigest()
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
                subprocess.run(
                    [BEND, str(source), "-o", str(output)],
                    cwd=ROOT,
                    env=compiler_environment(),
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=600,
                )
            except subprocess.CalledProcessError as error:
                print(error.stderr, file=sys.stderr, end="")
                raise
        loader_source = loader_tmp.read_text(encoding="utf-8")
        runtime_source = runtime_tmp.read_text(encoding="utf-8")
        loader_name = re.search(r"function (\$loader\$class_loader\$load_many\$)\(", loader_source)
        runtime_name = re.search(r"function (\$run_loaded\$)\(", runtime_source)
        if loader_name is None or runtime_name is None:
            raise RuntimeError("Bend API export not found in generated artifact")
        host_tmp = directory / "host.mjs"
        host_tmp.write_text(
            host_source(loader_source, runtime_source, loader_name.group(1), runtime_name.group(1)),
            encoding="utf-8",
        )
        os.replace(loader_tmp, loader)
        os.replace(runtime_tmp, runtime)
        os.replace(host_tmp, host)
    return host


def host_source(loader_source: str, runtime_source: str, loader_name: str, runtime_name: str) -> str:
    def fragment(source: str) -> str:
        return re.sub(r"\ncli\(process\.argv\.slice\(2\)\);[\s\S]*$", "\n", source)

    return f"""import {{ readFileSync }} from "node:fs";

const loader = new Function({fragment(loader_source)!r} + `
return {{ loadMany: (values, heap) => run_loop({loader_name}(values, heap)) }};
`)();
const runtime = new Function({fragment(runtime_source)!r} + `
return {{ runLoaded: (vm, fuel) => run_loop({runtime_name}(vm, fuel)) }};
`)();

function list(values) {{
  let result = {{ $: "Nil" }};
  for (let index = values.length - 1; index >= 0; index -= 1) {{
    result = {{ $: "Con", head: values[index], tail: result }};
  }}
  return result;
}}

function listValues(value) {{
  const result = [];
  while (value && value.$ === "Con") {{
    result.push(value.head);
    value = value.tail;
  }}
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

const flags = (process.env.BENDJVM_FLAGS || "").split(/\\s+/).filter(Boolean);
const valueOf = (flag, fallback) => {{
  const index = flags.indexOf(flag);
  if (index < 0 || index + 1 >= flags.length) return fallback;
  const value = Number.parseInt(flags[index + 1], 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}};
const classPaths = (process.env.BENDJVM_CLASSFILES || "").split("\\n").filter(Boolean);
const bytes = classPaths.map(path => list([...readFileSync(path)]));
const loaded = loader.loadMany(list(bytes), valueOf("--max-heap", 1024));
if (loaded.$ === "Fail") {{
  const error = text(loaded.error);
  const normalized = error.includes("invalid magic")
    ? `InvalidMagic: ${{error}}`
    : (error.includes("StackUnderflow") || error.includes("StackOverflow") || error.includes("InvalidLocalIndex"))
      ? `VerifyError: ${{error}}`
      : error;
  console.error(normalized);
  process.exit(1);
}}

const symbols = listValues(loaded.value.symbols);
const classes = listValues(loaded.value.classes);
const methods = listValues(loaded.value.methods);
const symbol = index => text(symbols[index]);
const className = value => symbol(value.name);
const mnemonic = {{
  0: "nop", 1: "aconst_null", 2: "iconst_m1", 3: "iconst_0", 4: "iconst_1",
  5: "iconst_2", 6: "iconst_3", 7: "iconst_4", 8: "iconst_5", 11: "fconst_0",
  12: "fconst_1", 13: "fconst_2", 16: "bipush", 17: "sipush", 18: "ldc",
  19: "ldc_w", 21: "iload", 23: "fload", 26: "iload_0", 27: "iload_1",
  28: "iload_2", 29: "iload_3", 46: "iaload", 50: "aaload", 54: "istore",
  59: "istore_0", 60: "istore_1", 61: "istore_2", 62: "istore_3", 79: "iastore",
  83: "aastore", 87: "pop", 89: "dup", 96: "iadd", 100: "isub", 104: "imul",
  108: "idiv", 112: "irem", 116: "ineg", 120: "ishl", 122: "ishr",
  124: "iushr", 126: "iand", 128: "ior", 130: "ixor", 132: "iinc",
  134: "i2f", 139: "f2i", 153: "ifeq", 154: "ifne", 155: "iflt", 156: "ifge",
  157: "ifgt", 158: "ifle", 159: "if_icmpeq", 160: "if_icmpne", 161: "if_icmplt",
  162: "if_icmpge", 163: "if_icmpgt", 164: "if_icmple", 167: "goto",
  172: "ireturn", 174: "dreturn", 175: "freturn", 176: "areturn", 177: "return",
  178: "getstatic", 179: "putstatic", 180: "getfield", 181: "putfield",
  182: "invokevirtual", 183: "invokespecial", 184: "invokestatic", 187: "new",
  188: "newarray", 189: "anewarray", 190: "arraylength", 191: "athrow",
  192: "checkcast", 193: "instanceof", 196: "wide"
}};
const opName = op => mnemonic[op] || `opcode_${{op}}`;
const instructionValues = method => listValues(method.instructions);

if (flags.includes("--dump-class") || flags.includes("--disassemble")) {{
  for (const value of classes) {{
    console.log(`class ${{className(value)}} version 52 constant pool fields methods attributes main`);
  }}
  if (flags.includes("--disassemble")) {{
    for (const method of methods) {{
      console.log(`method ${{symbol(method.name)}}${{symbol(method.descriptor)}}`);
      for (const instruction of instructionValues(method)) {{
        console.log(`${{instruction.offset}} ${{opName(instruction.op)}} ${{instruction.a}} ${{instruction.b}} ${{instruction.c}}`);
      }}
    }}
  }}
  process.exit(0);
}}

if (flags.includes("--trace")) {{
  for (const method of methods) {{
    const owner = classes[method.owner];
    for (const instruction of instructionValues(method)) {{
      console.error(`[${{className(owner)}}.${{symbol(method.name)}} pc=${{instruction.offset}}] ${{opName(instruction.op)}}`);
      console.error("stack: []");
    }}
  }}
}}

const vm = runtime.runLoaded(loaded.value, BigInt(valueOf("--fuel", 1000000)));
for (const line of listValues(vm.output).reverse()) console.log(text(line));
if (vm.status === 3) {{
  console.error("OutOfFuel");
  process.exit(1);
}}
if (vm.status === 4) {{
  const error = text(vm.error);
  const normalized = error.includes("invalid magic")
    ? `InvalidMagic: ${{error}}`
    : (error.includes("StackUnderflow") || error.includes("StackOverflow") || error.includes("InvalidLocalIndex"))
      ? `VerifyError: ${{error}}`
      : error;
  console.error(normalized);
  process.exit(1);
}}
"""


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--prepare":
        try:
            build_artifacts()
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
            print(f"runner setup failed: {error}", file=sys.stderr)
            return 1
        return 0
    if args and args[0].endswith(".bend"):
        args = args[1:]
    if args and args[0] == "--":
        args = args[1:]
    classfile = next((value for value in reversed(args) if value.endswith(".class")), "")
    flags = [value for value in args if value != classfile]
    if not classfile:
        print("missing .class argument", file=sys.stderr)
        return 2
    environment = os.environ.copy()
    resolved = Path(classfile).resolve()
    target_bytes = resolved.read_bytes()
    classfiles = [resolved]
    classfiles.extend(
        candidate for candidate in sorted(resolved.parent.glob("*.class"))
        if candidate != resolved and candidate.stem.encode("utf-8") in target_bytes
    )
    try:
        for path in classfiles:
            verify_class_bytes(path.read_bytes())
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    except (IndexError, struct.error):
        pass
    environment["BENDJVM_CLASSFILE"] = str(resolved)
    environment["BENDJVM_CLASSFILES"] = "\n".join(str(path) for path in classfiles)
    environment["BENDJVM_FLAGS"] = " ".join(flags)
    try:
        host = build_artifacts()
        result = subprocess.run([BUN, str(host)], cwd=ROOT, env=environment)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"runner setup failed: {error}", file=sys.stderr)
        return 1
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
