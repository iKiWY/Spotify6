#!/usr/bin/env python3
"""Seed realistic quality-policy defects and require the regression test to kill them."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "music/Spot/MMMediaQuality.m").read_text()
runner = root / "tests/test-podcast-quality.py"
mutants = {
    "Wi-Fi podcast setting aliases music setting": (
        "key:wifi?MMPodcastStreamWiFiKey:MMPodcastStreamMobileKey",
        "key:wifi?MMStreamWiFiKey:MMPodcastStreamMobileKey",
    ),
    "current-network selector reads music quality": (
        "+ (NSInteger)podcastStreamingBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self podcastStreamingBitrateForWiFi]:[self podcastStreamingBitrateForMobile]; }",
        "+ (NSInteger)podcastStreamingBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self streamingBitrateForWiFi]:[self streamingBitrateForMobile]; }",
    ),
    "mobile podcast download Off is rejected": (
        "[self setValue:bitrate key:wifi?MMPodcastDownloadWiFiKey:MMPodcastDownloadMobileKey allowOff:!wifi]",
        "[self setValue:bitrate key:wifi?MMPodcastDownloadWiFiKey:MMPodcastDownloadMobileKey allowOff:NO]",
    ),
}

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-mutants-") as directory:
    temp = Path(directory)
    for number, (name, (old, new)) in enumerate(mutants.items()):
        if old not in source:
            raise SystemExit(f"mutation target not found: {name}")
        mutated = temp / f"mutant-{number}.m"
        mutated.write_text(source.replace(old, new, 1))
        env = dict(os.environ, MMQUALITY_SOURCE_OVERRIDE=str(mutated))
        result = subprocess.run([sys.executable, str(runner)], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode == 0:
            raise SystemExit(f"SURVIVED: {name}")
        print(f"KILLED: {name}")
