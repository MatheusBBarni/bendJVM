#!/usr/bin/env python3
"""Checks that the Java-source MiniJRE layer only references classes the MiniJRE
defines (the Bend bootstrap catalog or bendjvm/jre itself). javac compiles the
layer against the JDK 8 API, so a missing class would otherwise surface only at
launch as MissingClass."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run

CLASS_REF = re.compile(r"= Class\s+#\d+\s+//\s+(\S+)")


def missing_references() -> dict[str, set[str]]:
    jre = run.runtime_library().path
    bootstrap = run.bootstrap_names()
    defined = {path.relative_to(jre).as_posix()[:-len(".class")] for path in jre.rglob("*.class")}
    missing: dict[str, set[str]] = {}
    javap = str(Path(run.JAVAC).with_name("javap")) if "/" in run.JAVAC else "javap"
    for path in sorted(jre.rglob("*.class")):
        listing = subprocess.run([javap, "-v", str(path)], capture_output=True, text=True, check=True).stdout
        for name in CLASS_REF.findall(listing):
            base = name.strip('"').lstrip("[")
            if base.startswith("L") and base.endswith(";"):
                base = base[1:-1]
            if len(base) == 1 or base in bootstrap or base in defined:
                continue
            missing.setdefault(base, set()).add(path.relative_to(jre).as_posix())
    return missing


if __name__ == "__main__":
    problems = missing_references()
    for name, users in sorted(problems.items()):
        print(f"{name} <- {', '.join(sorted(users))}")
    sys.exit(1 if problems else 0)
