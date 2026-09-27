#!/usr/bin/env python3
"""Compile, run, and verify the Java examples through BendJVM.

Run from the project root:
  python3 scripts/examples.py
  python3 scripts/examples.py --only ObjectsAndDispatch --only Exceptions
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"
DEFAULT_RUNNER = ROOT / "scripts" / "run.py"

EXPECTED_OUTPUT = {
    "ArithmeticAndBranches": "37\n55\n24\ntrue\n",
    "ArraysAndStrings": "array sum\n14\ntrue\nBend\n",
    "CollectionsAndText": "BendJVM\n2\ntrue\n2\ntrue\ntrue\n",
    "Exceptions": "5\n0\n4\nbad\n",
    "FilesAndTryWithResources": "true\n65\nhi\n-2\n",
    "HelloWorld": "Hello from BendJVM\n42\n",
    "ObjectsAndDispatch": "10\n11\n4\ntrue\nfalse\n",
    "ReflectionAndConfiguration": "true\ntrue\n12\n10\nBendJVM\n",
    "StaticInitialization": "6\n12\n18\n",
    "TcpLoopback": "66\ntrue\n",
}

def execute(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.update(BEND_NO_TELEMETRY="1", NO_COLOR="1")
    return subprocess.run(
        command,
        cwd=ROOT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def fail(message: str) -> None:
    raise RuntimeError(message)


def arguments() -> argparse.Namespace:
    names = tuple(path.stem for path in sorted(EXAMPLES.glob("*.java")))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", action="append", choices=names, help="run only these examples")
    parser.add_argument("--timeout", type=float, default=120.0, help="per subprocess timeout in seconds")
    parser.add_argument("--runner", default=os.environ.get("BEND", str(DEFAULT_RUNNER)))
    parser.add_argument("--javac", default=os.environ.get("JAVAC", "javac"))
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return args


def runner_command(path: str) -> list[str]:
    if path.endswith(".py"):
        return [sys.executable, path]
    return [path]


def main() -> int:
    args = arguments()
    try:
        sources = sorted(EXAMPLES.glob("*.java"))
        if not sources:
            fail(f"no Java examples found in {EXAMPLES}")
        selected = [path for path in sources if not args.only or path.stem in args.only]
        if args.only and len(selected) != len(set(args.only)):
            fail("one or more selected examples are missing")
        javac = shutil.which(args.javac) or args.javac
        require_runner = Path(args.runner) if Path(args.runner).is_absolute() else ROOT / args.runner
        if not require_runner.is_file() and shutil.which(args.runner) is None:
            fail(f"runner not found: {args.runner}")
        if shutil.which(javac) is None and not Path(javac).is_file():
            fail(f"javac not found: {args.javac}")
        with tempfile.TemporaryDirectory(prefix="bendjvm-examples-") as temporary:
            workspace = Path(temporary)
            classes = workspace / "classes"
            classes.mkdir()
            compilation = execute(
                [javac, "--release", "8", "-encoding", "UTF-8", "-g:none", "-d", str(classes), *map(str, sources)],
                args.timeout,
            )
            if compilation.returncode != 0:
                print(compilation.stdout, end="")
                print(compilation.stderr, end="", file=sys.stderr)
                return compilation.returncode
            command = runner_command(args.runner)
            passed = 0
            for source in selected:
                extra: list[str] = []
                if source.stem == "FilesAndTryWithResources":
                    extra = [str(workspace / "example.bin")]
                result = execute([*command, str(classes / f"{source.stem}.class"), *extra], args.timeout)
                if result.returncode != 0:
                    print(f"FAIL {source.stem}", file=sys.stderr)
                    print(textwrap.indent(result.stdout, "  "), end="", file=sys.stderr)
                    print(textwrap.indent(result.stderr, "  "), end="", file=sys.stderr)
                    return 1
                expected = EXPECTED_OUTPUT.get(source.stem)
                if expected is None:
                    print(f"FAIL {source.stem}: missing expected output", file=sys.stderr)
                    return 1
                if result.stdout != expected:
                    print(f"FAIL {source.stem}: output mismatch", file=sys.stderr)
                    print(f"expected: {expected!r}", file=sys.stderr)
                    print(f"actual:   {result.stdout!r}", file=sys.stderr)
                    return 1
                print(f"PASS {source.stem}")
                if result.stdout:
                    print(textwrap.indent(result.stdout, "  "), end="")
                passed += 1
            print(f"{passed} examples passed")
            return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL examples: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
