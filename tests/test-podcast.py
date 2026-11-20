#!/usr/bin/env python3
"""Run podcast regression contracts followed by their mutation checks."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
suite = [
    "test-podcast-quality.py",
    "test-podcast-playback-contract.py",
    "test-podcast-stream-buffer.py",
    "test-podcast-download-stream.py",
    "test-podcast-download-queue.py",
    "test-podcast-quality-mutations.py",
    "test-podcast-playback-mutations.py",
    "test-podcast-stream-buffer-mutations.py",
    "test-podcast-download-stream-mutations.py",
    "test-podcast-download-queue-mutations.py",
]
for script in suite:
    print(f"=== {script} ===", flush=True)
    subprocess.run([sys.executable, str(root / "tests" / script)], check=True)
