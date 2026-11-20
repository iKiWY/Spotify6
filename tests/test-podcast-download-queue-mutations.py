#!/usr/bin/env python3
"""Confirm queue tests catch episodes being enqueued as ordinary tracks."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "music/Spot/MMSpotify.m").read_text()
old = 'return [mediaType isEqual:@"episode"]?[ @"episode:" stringByAppendingString:mediaId]:mediaId;'
new = 'return mediaId;'
if old not in source:
    raise SystemExit("mutation target not found: episode queue type")

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-queue-mutant-") as directory:
    mutant = Path(directory) / "MMSpotify.m"
    mutant.write_text(source.replace(old, new, 1))
    env = dict(os.environ, MMSPOTIFY_SOURCE_OVERRIDE=str(mutant))
    result = subprocess.run([sys.executable, str(root / "tests/test-podcast-download-queue.py")],
                            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode == 0:
        raise SystemExit("SURVIVED: episodes enter the download queue as tracks")
    print("KILLED: episodes enter the download queue as tracks")
