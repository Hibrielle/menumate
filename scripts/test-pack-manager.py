#!/usr/bin/env python3
"""Run the production PackManager against isolated storage and a local Git fixture."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
subprocess.run(["swift", "build"], cwd=repo / "Core", check=True)
debug = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=repo / "Core", text=True).strip())
with tempfile.TemporaryDirectory(prefix="menumate-manager-tests-") as build:
    binary = Path(build) / "pack-manager-tests"
    subprocess.run([
        "swiftc", "-parse-as-library", "-I", str(debug / "Modules"),
        str(repo / "App/Managers/PackManager.swift"), str(repo / "App/AppState.swift"),
        str(repo / "App/PackUsage.swift"), str(repo / "scripts/tests/AppStateTestSupport.swift"),
        str(repo / "scripts/tests/PackManagerIntegration.swift"),
        *map(str, sorted((debug / "MenuMateCore.build").glob("*.swift.o"))),
        "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
