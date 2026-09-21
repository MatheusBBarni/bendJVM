#!/usr/bin/env python3
"""End-to-end JVM differential checks using only the Python standard library.

Requirements: Python 3.10+, JDK 9+ (javac --release 8 and java), Bend 2.
Run from the project root: python3 scripts/test.py --fast
Full corpus and 24 generated programs: python3 scripts/test.py --full
Select fixtures: python3 scripts/test.py --only Arithmetic --only IntArray
Override tools with --bend, --java, --javac or BEND, JAVA, JAVAC.
Compilation and mutated class files live in a temporary directory outside the repo.
"""

import argparse
from dataclasses import dataclass
import difflib
import os
from pathlib import Path
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "bendjvm" / "tests" / "fixtures"
DEFAULT_BEND = str(ROOT / "scripts" / "run.py")
NAMED = (
    "HelloInteger", "Arithmetic", "Branching", "WhileLoop", "ForLoop",
    "StaticMethod", "RecursiveMethod", "MultipleArguments", "ObjectCreation",
    "Fields", "VirtualMethod", "IntArray", "ObjectArray", "StringConstant",
    "Println", "ExceptionCaught", "ExceptionUncaught",
)
EXTENDED = (
    "FloatOperations", "FloatArray", "InheritedFields", "ClassInitialization",
    "SignedArithmetic", "RuntimeExceptions", "ReferenceTypes", "Utf16Strings",
)
SUPPORT = ("FuelLimit", "HeapLimit", "MutationTarget")


class Failure(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Failure(message)


def compiler_output(text: str) -> str:
    # Remove only the compiler's leading banner, never arbitrary program lines.
    prefix = "All terms check.\n"
    return text[len(prefix):] if text.startswith(prefix) else text


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
        result = subprocess.run(command, cwd=ROOT, env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise Failure(f"timeout after {timeout}s: {command!r}\n"
                      f"stdout: {error.stdout!r}\nstderr: {error.stderr!r}") from error
    except OSError as error:
        raise Failure(f"cannot run {command[0]}: {error}") from error
    try:
        out = result.stdout.decode("utf-8").replace("\r\n", "\n")
        err = result.stderr.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as error:
        raise Failure(f"non-UTF-8 process output: {command!r}: {error}") from error
    if bend:
        out, err = compiler_output(out), compiler_output(err)
    return Run(command, result.returncode, out, err)


def same_output(expected: str, actual: str, context: str) -> None:
    if expected != actual:
        difference = "".join(difflib.unified_diff(
            expected.splitlines(keepends=True), actual.splitlines(keepends=True),
            fromfile="reference java", tofile="BendJVM"))
        raise Failure(f"stdout mismatch\n{difference}\n"
                      f"expected: {expected!r}\nactual: {actual!r}\n{context}")


def exception_class(output: str) -> str | None:
    found = re.search(r"java[/.]lang[/.]([A-Za-z]+(?:Exception|Error))\b", output)
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
    for section in ("fields", "methods"):
        members = u2(data, position)
        position += 2
        for _ in range(members):
            name = utf[u2(data, position + 2)]
            attributes = u2(data, position + 6)
            position += 8
            for _ in range(attributes):
                attribute_name = utf[u2(data, position)]
                length_offset = position + 2
                length = u4(data, length_offset)
                payload_start = position + 6
                position = payload_start + length
                if section == "methods" and attribute_name == "Code":
                    methods[name] = CodeAttribute(length_offset, payload_start,
                                                  position, u2(data, payload_start + 2))
    return ClassLayout(pool, utf, this_class_offset, methods)


def patch(data: bytes, offset: int, replacement: bytes) -> bytes:
    return data[:offset] + replacement + data[offset + len(replacement):]


def replace_main(data: bytes, site: CodeAttribute, code: bytes, max_stack: int = 2) -> bytes:
    # Replace the complete Code attribute, removing stale line tables and stack maps.
    payload = struct.pack(">HHI", max_stack, site.max_locals, len(code)) + code + b"\0\0\0\0"
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
        ("opcode-unsupported", replace_main(original, site, b"\x0e\xb1"), r"UnsupportedOpcode"),
        ("field-pool-zero", replace_main(original, site, b"\xb2\x00\x00\x57\xb1"), invalid_pool),
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
        return execute([self.args.bend, "bendjvm/main.bend", "--", *flags, str(classfile)],
                       self.args.timeout, bend=True)

    def check(self, name: str, action: Callable[[], None]) -> None:
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

    def differential(self, name: str) -> None:
        reference = execute([self.args.java, "-Dfile.encoding=UTF-8", "-cp", str(self.classes), name],
                            self.args.timeout)
        actual = self.bend(self.classes / f"{name}.class")
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

    def heap(self) -> None:
        self.reject(self.classes / "HeapLimit.class", r"OutOfMemoryError", "--max-heap", "16")
        result = self.bend(self.classes / "HeapLimit.class", "--max-heap", "256")
        require(result.code == 0, result.detail())
        same_output("100\n", result.stdout, result.detail())

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


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--fast", action="store_true", help="named spec fixtures and 3 generated programs (default)")
    mode.add_argument("--full", action="store_true", help="all fixtures, extended corruptions, 24 generated programs")
    parser.add_argument("--only", action="append", choices=NAMED + EXTENDED,
                        help="run only these differential fixtures, skipping limit/debug/malformed checks")
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
    try:
        for name, executable in (("Bend", args.bend), ("java", args.java), ("javac", args.javac)):
            require(shutil.which(executable) is not None,
                    f"{name} executable not found: {executable!r}; see --help for tool overrides")
        require((ROOT / "bendjvm" / "main.bend").is_file(), "missing bendjvm/main.bend")
        if Path(args.bend).resolve() == (ROOT / "scripts" / "run.py").resolve():
            preparation = execute([args.bend, "--prepare"], max(args.timeout, 600.0))
            require(preparation.code == 0, f"Bend runner preparation failed\n{preparation.detail()}")
        selected = list(dict.fromkeys(args.only)) if args.only else list(NAMED + (EXTENDED if args.full else ()))
        print(f"seed={args.seed:#x}; generated={args.generated}; mode={'full' if args.full else 'fast'}", flush=True)
        with tempfile.TemporaryDirectory(prefix="bendjvm-tests-") as temporary:
            directory = Path(temporary)
            classes, sources = directory / "classes", directory / "sources"
            classes.mkdir()
            sources.mkdir()
            inputs = [FIXTURES / f"{name}.java" for name in selected]
            if not args.only:
                inputs.extend(FIXTURES / f"{name}.java" for name in SUPPORT)
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
            suite = Suite(args, classes)
            for name in selected:
                suite.check(name, lambda name=name: suite.differential(name))
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
                for mode in ("--dump-class", "--disassemble", "--trace"):
                    suite.check(f"cli/{mode[2:]}", lambda mode=mode: suite.debug(mode))
            print(f"{suite.passed} passed, {suite.failed} failed", flush=True)
            return 1 if suite.failed else 0
    except (Failure, OSError, ValueError, KeyError, struct.error) as error:
        print(f"FAIL harness: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
