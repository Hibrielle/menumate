#!/usr/bin/env python3
"""Exercise production runner/history persistence using an isolated filesystem root."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
subprocess.run(["swift", "build"], cwd=repo / "Core", check=True)
debug = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=repo / "Core", text=True).strip())
with tempfile.TemporaryDirectory(prefix="menumate-history-tests-") as build:
    binary = Path(build) / "history-tests"
    subprocess.run([
        "swiftc", "-parse-as-library", "-I", str(debug / "Modules"),
        str(repo / "App/ActionRunner.swift"), str(repo / "App/PackUsage.swift"), str(repo / "App/ExecutionLog.swift"),
        str(repo / "scripts/tests/ExecutionHistoryIntegration.swift"),
        *map(str, sorted((debug / "MenuMateCore.build").glob("*.swift.o"))),
        "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
