#!/usr/bin/env python3
"""Verify episode download tests detect a broken atomic publication step."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "music/Spot/MMSpotify.m").read_text()
old = "rename(partial.fileSystemRepresentation,path.fileSystemRepresentation)!=0"
new = "unlink(partial.fileSystemRepresentation)!=0"
if old not in source:
    raise SystemExit("mutation target not found: atomic episode publication")

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-download-mutant-") as directory:
    mutant = Path(directory) / "MMSpotify.m"
    mutant.write_text(source.replace(old, new, 1))
    env = dict(os.environ, MMSPOTIFY_SOURCE_OVERRIDE=str(mutant))
    result = subprocess.run([sys.executable, str(root / "tests/test-podcast-download-stream.py")],
                            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode == 0:
        raise SystemExit("SURVIVED: episode file publication does not rename the completed file")
    print("KILLED: episode file publication does not rename the completed file")
