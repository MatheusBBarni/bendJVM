#!/usr/bin/env python3
"""Run class files through the isolated Bend loader and runtime artifacts."""

from __future__ import annotations

import hashlib
import os
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
  console.error(text(loaded.error));
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
  console.error(text(vm.error));
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
