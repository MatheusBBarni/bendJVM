#!/usr/bin/env python3
"""Compile and run the BendJVM examples through the practical runner."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = Path(__file__).resolve().parent
PACKAGED = EXAMPLES / "packaged"
RUNNER = ROOT / "scripts" / "run.py"
EXPECTED_OUTPUT = {
    "ArithmeticAndBranches": "37\n55\n24\ntrue\n",
    "ArraysAndStrings": "array sum\n14\ntrue\nBend\n",
    "CollectionsAndText": "BendJVM\n2\ntrue\n2\ntrue\ntrue\n",
    "Exceptions": "5\n0\n4\nbad\n",
    "FilesAndTryWithResources": "true\n65\nhi\n-2\n",
    "HelloWorld": "Hello from BendJVM\n42\narg=spaced arg\n",
    "ObjectsAndDispatch": "10\n11\n4\ntrue\nfalse\n",
    "ReflectionAndConfiguration": "true\ntrue\n12\n10\nBendJVM\n",
    "StaticInitialization": "6\n12\n18\n",
    "TcpLoopback": "66\ntrue\n",
}

PACKAGED_CLASSPATH_OUTPUT = "Bend\n42\n66\n"
PACKAGED_JAR_OUTPUT = "from-jar\n42\n66\n"



def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def run(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
            timeout=120,
        )
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"command timed out after 120 seconds: {' '.join(command)}") from error


def verify_output(label: str, result: subprocess.CompletedProcess[str], expected: str) -> None:
    require(
        result.stdout == expected,
        f"{label} output mismatch\nexpected: {expected!r}\nactual:   {result.stdout!r}",
    )


def compile_java(output: Path, sources: list[Path]) -> None:
    javac = os.environ.get("JAVAC", "javac")
    require(shutil.which(javac) is not None, f"javac not found: {javac!r}")
    result = run([javac, "--release", "8", "-encoding", "UTF-8", "-g:none",
                  "-d", str(output), *map(str, sources)])
    require(result.returncode == 0, f"javac failed\n{result.stderr}")


def launch(cwd: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    result = run([sys.executable, str(RUNNER), *arguments], cwd=cwd)
    require(result.returncode == 0, f"BendJVM failed: {' '.join(arguments)}\n"
            f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}")
    return result


def write_jar(path: Path, root: Path) -> None:
    manifest = b"Manifest-Version: 1.0\r\nMain-Class: example.hello.Main\r\n\r\n"
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=False) as archive:
        archive.writestr("META-INF/MANIFEST.MF", manifest)
        for file in sorted(root.rglob("*")):
            if file.is_file():
                archive.write(file, file.relative_to(root).as_posix())


def main() -> int:
    require(RUNNER.is_file(), "missing scripts/run.py")
    standalone_sources = sorted(EXAMPLES.glob("*.java"))
    require(bool(standalone_sources), f"no Java examples in {EXAMPLES}")
    with tempfile.TemporaryDirectory(prefix="bendjvm-examples-") as temporary:
        directory = Path(temporary)
        standalone = directory / "standalone"
        packaged = directory / "packaged"
        compile_java(standalone, standalone_sources)
        for source in standalone_sources:
            extra: list[str] = []
            if source.stem == "FilesAndTryWithResources":
                extra = [str(directory / "example.bin")]
            elif source.stem == "HelloWorld":
                extra = ["spaced arg"]
            result = launch(directory, str(standalone / f"{source.stem}.class"), *extra)
            expected = EXPECTED_OUTPUT.get(source.stem)
            require(expected is not None, f"missing expected output for {source.stem}")
            verify_output(source.stem, result, expected)
            print(f"== {source.stem} ==")
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")

        sources = [
            PACKAGED / "example" / "hello" / "Main.java",
            PACKAGED / "example" / "lib" / "Answer.java",
        ]
        compile_java(packaged, sources)
        shutil.copyfile(PACKAGED / "banner.txt", packaged / "banner.txt")
        classpath = launch(directory, "-cp", str(packaged), "example.hello.Main", "Bend")
        verify_output("packaged classpath", classpath, PACKAGED_CLASSPATH_OUTPUT)
        print("== packaged classpath ==")
        print(classpath.stdout, end="" if classpath.stdout.endswith("\n") else "\n")

        archive = directory / "hello.jar"
        write_jar(archive, packaged)
        jar = launch(directory, "-jar", str(archive), "from-jar")
        verify_output("packaged -jar", jar, PACKAGED_JAR_OUTPUT)
        print("== packaged -jar ==")
        print(jar.stdout, end="" if jar.stdout.endswith("\n") else "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
