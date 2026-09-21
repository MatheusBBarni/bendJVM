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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def run(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)


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
            print(f"== {source.stem} ==")
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")

        sources = [
            PACKAGED / "example" / "hello" / "Main.java",
            PACKAGED / "example" / "lib" / "Answer.java",
        ]
        compile_java(packaged, sources)
        shutil.copyfile(PACKAGED / "banner.txt", packaged / "banner.txt")
        classpath = launch(directory, "-cp", str(packaged), "example.hello.Main", "Bend")
        print("== packaged classpath ==")
        print(classpath.stdout, end="" if classpath.stdout.endswith("\n") else "\n")

        archive = directory / "hello.jar"
        write_jar(archive, packaged)
        jar = launch(directory, "-jar", str(archive), "from-jar")
        print("== packaged -jar ==")
        print(jar.stdout, end="" if jar.stdout.endswith("\n") else "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
