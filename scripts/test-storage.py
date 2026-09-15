#!/usr/bin/env python3
"""Test real AppState/PackManager writes and process-interruption recovery in isolated roots."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
subprocess.run(["swift", "build"], cwd=repo / "Core", check=True)
debug = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=repo / "Core", text=True).strip())
with tempfile.TemporaryDirectory(prefix="menumate-storage-tests-") as build:
    binary = Path(build) / "storage-tests"
    subprocess.run([
        "swiftc", "-parse-as-library", "-I", str(debug / "Modules"),
        *[str(repo / p) for p in ["App/AppState.swift", "App/Managers/PackManager.swift", "App/PackUsage.swift",
                                "scripts/tests/AppStateTestSupport.swift", "scripts/tests/StorageIntegration.swift"]],
        *map(str, sorted((debug / "MenuMateCore.build").glob("*.swift.o"))), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
