#!/usr/bin/env python3
"""Exercise production podcast endpoint and quality selection helpers via GNUstep."""
from pathlib import Path
import shlex
import subprocess
import tempfile
import os

root = Path(__file__).resolve().parents[1]
source = Path(os.environ.get("MMSPOTIFY_SOURCE_OVERRIDE", root / "music/Spot/MMSpotify.m")).read_text()
api_user_start = source.index("+ (void)apiUser:(NSString *)method path:")
api_user_end = source.index("// Stale-while-revalidate", api_user_start)
api_user_implementation = source[api_user_start:api_user_end]
if "usesWebAPIForUserGET(path)" not in api_user_implementation or "webAPIPathForUserGET(path)" not in api_user_implementation:
    raise SystemExit("show and search requests must route through the developer Web API token")
metadata_start = source.index("static NSString* metadataURIForMediaType")
metadata_end = source.index("\n}", metadata_start) + 2
quality_start = source.index("static NSInteger preferredBitrateForMediaType")
quality_end = source.index("\n}", quality_start) + 2
download_quality_start = source.index("static NSInteger preferredDownloadBitrateForMediaType")
download_quality_end = source.index("\n}", download_quality_start) + 2
queue_start = source.index("static BOOL isEpisodeQueueID")
queue_end = source.index("static NSString* diskPath", queue_start)
offline_start = source.index("static NSData* offlineMediaData")
offline_end = source.index("\n}", offline_start) + 2
web_api_start = source.index("static BOOL usesWebAPIForUserGET")
web_api_end = source.index("\n}", web_api_start) + 2
web_path_start = source.index("static NSString* webAPIPathForUserGET")
web_path_end = source.index("\n}", web_path_start) + 2
helpers = source[metadata_start:metadata_end] + "\n" + source[quality_start:quality_end] + "\n" + source[download_quality_start:download_quality_end] + "\n" + source[queue_start:queue_end] + "\n" + source[offline_start:offline_end] + "\n" + source[web_api_start:web_api_end] + "\n" + source[web_path_start:web_path_end]
harness = r'''
#import <Foundation/Foundation.h>
#import "MMMediaQuality.h"
@implementation MMMediaQuality
+ (NSInteger)streamingBitrateForCurrentNetwork { return 96; }
+ (NSInteger)podcastStreamingBitrateForCurrentNetwork { return 320; }
+ (NSInteger)downloadBitrateForCurrentNetwork { return 160; }
+ (NSInteger)podcastDownloadBitrateForCurrentNetwork { return 96; }
@end
HELPERS
static void check(NSString *name, BOOL condition) { NSCAssert(condition,@"%@",name); printf("PASS %s\n",[name UTF8String]); }
int main(void) { NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    check(@"track metadata endpoint stays track", [[metadataURIForMediaType(@"track",@"abc") description] isEqual:@"hm://metadata/4/track/abc"]);
    check(@"episode metadata endpoint uses episode type", [[metadataURIForMediaType(@"episode",@"def") description] isEqual:@"hm://metadata/4/episode/def"]);
    check(@"unknown media type is rejected", metadataURIForMediaType(@"show",@"abc")==nil);
    check(@"track keeps music streaming quality", preferredBitrateForMediaType(@"track")==96);
    check(@"episode uses podcast streaming quality", preferredBitrateForMediaType(@"episode")==320);
    check(@"unknown media type has no quality", preferredBitrateForMediaType(@"show")==0);
    check(@"track download uses music quality", preferredDownloadBitrateForMediaType(@"track")==160);
    check(@"episode download uses podcast quality", preferredDownloadBitrateForMediaType(@"episode")==96);
    check(@"unknown media type has no download quality", preferredDownloadBitrateForMediaType(@"show")==0);
    check(@"show episode lists use the developer Web API token", usesWebAPIForUserGET(@"shows/show-id/episodes?market=from_token"));
    check(@"search keeps its existing developer Web API route", usesWebAPIForUserGET(@"search?q=show&type=show"));
    check(@"ordinary account endpoints keep their user token route", !usesWebAPIForUserGET(@"me/tracks?limit=50"));
    check(@"from-token market is removed for the Web API", [webAPIPathForUserGET(@"shows/show-id/episodes?market=from_token") isEqual:@"shows/show-id/episodes"]);
    check(@"episode queue IDs retain media type", [queueIDForMedia(@"abc",@"episode") isEqual:@"episode:abc"] && isEpisodeQueueID(@"episode:abc") && [mediaIDFromQueueID(@"episode:abc") isEqual:@"abc"] && [mediaTypeFromQueueID(@"episode:abc") isEqual:@"episode"]);
    NSString *offlinePath=[NSTemporaryDirectory() stringByAppendingPathComponent:@"spotify6-podcast-offline-fixture.ogg"];
    NSData *payload=[@"mapped offline podcast" dataUsingEncoding:NSUTF8StringEncoding]; [payload writeToFile:offlinePath atomically:YES];
    check(@"offline episodes are read from the file-backed data path", [offlineMediaData(offlinePath,@"episode") isEqualToData:payload]);
    check(@"offline music keeps its existing data path", [offlineMediaData(offlinePath,@"track") isEqualToData:payload]);
    [[NSFileManager defaultManager] removeItemAtPath:offlinePath error:NULL];
    [pool drain]; return 0;
}
'''.replace("HELPERS", helpers)

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-playback-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    objc_include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
    subprocess.run(["clang", *flags, "-Wno-incomplete-implementation", "-I", str(root / "music/Spot"), "-I", objc_include,
                    str(path / "test.m"), "-o", str(path / "test"), *libs], check=True)
    subprocess.run([str(path / "test")], check=True)
