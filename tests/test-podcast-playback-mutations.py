#!/usr/bin/env python3
"""Verify podcast resolver and bitrate regressions are caught by contract tests."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "music/Spot/MMSpotify.m").read_text()
runner = root / "tests/test-podcast-playback-contract.py"
mutants = {
    "episode metadata is resolved as a track": (
        'return [NSString stringWithFormat:@"hm://metadata/4/%@/%@",mediaType,gidHex];',
        'return [NSString stringWithFormat:@"hm://metadata/4/track/%@",gidHex];',
    ),
    "episode streaming reads music quality": (
        'if([mediaType isEqual:@"episode"]) return [MMMediaQuality podcastStreamingBitrateForCurrentNetwork];',
        'if([mediaType isEqual:@"episode"]) return [MMMediaQuality streamingBitrateForCurrentNetwork];',
    ),
    "episode downloads read music quality": (
        'if([mediaType isEqual:@"episode"]) return [MMMediaQuality podcastDownloadBitrateForCurrentNetwork];',
        'if([mediaType isEqual:@"episode"]) return [MMMediaQuality downloadBitrateForCurrentNetwork];',
    ),
    "episode download queue loses its media type": (
        'return isEpisodeQueueID(tid)?@"episode":@"track";',
        'return @"track";',
    ),
    "show episodes use the rate-limited user token endpoint": (
        'return showPath && episodeList;',
        'return NO;',
    ),
    "show episode routes skip the developer Web API": (
        'usesWebAPIForUserGET(path)',
        '[path hasPrefix:@"search?"]',
    ),
}

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-playback-mutants-") as directory:
    temp = Path(directory)
    for number, (name, (old, new)) in enumerate(mutants.items()):
        if old not in source:
            raise SystemExit(f"mutation target not found: {name}")
        mutated = temp / f"mutant-{number}.m"
        mutated.write_text(source.replace(old, new, 1))
        env = dict(os.environ, MMSPOTIFY_SOURCE_OVERRIDE=str(mutated))
        result = subprocess.run([sys.executable, str(runner)], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode == 0:
            raise SystemExit(f"SURVIVED: {name}")
        print(f"KILLED: {name}")
