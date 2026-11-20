#!/usr/bin/env python3
"""Ensure the buffer test catches regressions that move podcasts back to RAM."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "music/Spot/MMAudio.m").read_text()
old = "if(diskBacked){"
new = "if(diskBacked && NO){"
if old not in source:
    raise SystemExit("mutation target not found: disk-backed allocation")

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-buffer-mutant-") as directory:
    mutant = Path(directory) / "MMAudio.m"
    mutant.write_text(source.replace(old, new, 1))
    env = dict(os.environ, MMAUDIO_SOURCE_OVERRIDE=str(mutant))
    result = subprocess.run([sys.executable, str(root / "tests/test-podcast-stream-buffer.py")],
                            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode == 0:
        raise SystemExit("SURVIVED: podcast buffers use in-memory allocation")
    print("KILLED: podcast buffers use in-memory allocation")
