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
        'return [path hasPrefix:@"shows/"];',
        'return NO;',
    ),
    "show episode routes skip the developer Web API": (
        'usesWebAPIForUserGET(path)',
        '[path hasPrefix:@"search?"]',
    ),
    "saved show URIs are discarded": (
        'if([uri hasPrefix:@"spotify:show:"] && !psub(it,3))',
        'if(NO && !psub(it,3))',
    ),
    "forbidden metadata lookup discards saved podcasts": (
        'show metadata batch unavailable HTTP %ld; keeping IDs',
        'show metadata batch unavailable HTTP %ld; dropping IDs',
    ),
    "saved podcast episode set is no longer read": (
        'ids=spEpisodeIdsInSet(setName,user,&st);',
        'ids=spShowIdsInSet(setName,user,&st);',
    ),
    "saved episodes are no longer resolved from catalog metadata": (
        'spExt(uris,12,status)',
        'spExt(uris,10,status)',
    ),
    "saved episode feed resolves the entire large collection": (
        'spEpisodes(recentIds,&metadataStatus)',
        'spEpisodes(ids,&metadataStatus)',
    ),
    "episode collection URIs are discarded": (
        'if([uri hasPrefix:@"spotify:episode:"] && !psub(it,3))',
        'if(NO && !psub(it,3))',
    ),
    "episode metadata reads the wrong title field": (
        'spStr(psub(ep,2))',
        'spStr(psub(ep,3))',
    ),
    "episode metadata loses its show relationship": (
        'NSData*show=psub(ep,71);',
        'NSData*show=psub(ep,1);',
    ),
    "podcast artwork chooses a large cover": (
        'if(size==1) return u;',
        'if(size==0) return u;',
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
