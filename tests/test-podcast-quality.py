#!/usr/bin/env python3
"""Compile the production MMMediaQuality implementation against GNUstep Foundation."""
from pathlib import Path
import shlex
import subprocess
import tempfile
import os

root = Path(__file__).resolve().parents[1]
source_path = Path(os.environ.get("MMQUALITY_SOURCE_OVERRIDE", root / "music/Spot/MMMediaQuality.m"))
source = source_path.read_text()
start = source.index("static NSString *const MMStreamWiFiKey")
end = source.rindex("@end") + len("@end")
production = source[start:end]
harness = r'''
#import <Foundation/Foundation.h>
#import "MMMediaQuality.h"
static BOOL testWiFi = YES;
@interface MMSpotify : NSObject
+ (BOOL)wifiReachable;
+ (void)resumeQueuedDownloads;
@end
@implementation MMSpotify
+ (BOOL)wifiReachable { return testWiFi; }
+ (void)resumeQueuedDownloads {}
@end
PRODUCTION
static void check(NSString *label, BOOL condition) {
    NSCAssert(condition, @"%@", label);
    printf("PASS %s\n", [label UTF8String]);
}
int main(void) { NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSArray *keys=@[@"podcastQuality.stream.wifi", @"podcastQuality.stream.mobile",
                    @"podcastQuality.download.wifi", @"podcastQuality.download.mobile",
                    @"mediaQuality.stream.wifi", @"mediaQuality.stream.mobile",
                    @"mediaQuality.download.wifi", @"mediaQuality.download.mobile"];
    for(NSString *key in keys) [defaults removeObjectForKey:key];
    check(@"podcast streaming defaults", [MMMediaQuality podcastStreamingBitrateForWiFi] == 160 && [MMMediaQuality podcastStreamingBitrateForMobile] == 96);
    check(@"podcast download defaults", [MMMediaQuality podcastDownloadBitrateForWiFi] == 160 && [MMMediaQuality podcastDownloadBitrateForMobile] == 0);
    [MMMediaQuality setPodcastStreamingBitrate:320 forWiFi:YES];
    [MMMediaQuality setPodcastStreamingBitrate:96 forWiFi:NO];
    [MMMediaQuality setPodcastDownloadBitrate:160 forWiFi:YES];
    [MMMediaQuality setPodcastDownloadBitrate:0 forWiFi:NO];
    check(@"podcast choices persist", [MMMediaQuality podcastStreamingBitrateForWiFi] == 320 && [MMMediaQuality podcastStreamingBitrateForMobile] == 96 && [MMMediaQuality podcastDownloadBitrateForWiFi] == 160 && [MMMediaQuality podcastDownloadBitrateForMobile] == 0);
    check(@"music preferences remain unchanged", [MMMediaQuality streamingBitrateForWiFi] == 160 && [MMMediaQuality streamingBitrateForMobile] == 96 && [MMMediaQuality downloadBitrateForWiFi] == 320 && [MMMediaQuality downloadBitrateForMobile] == 0);
    testWiFi=YES;
    check(@"stream selection follows Wi-Fi", [MMMediaQuality podcastStreamingBitrateForCurrentNetwork] == 320);
    testWiFi=NO;
    check(@"stream selection follows mobile", [MMMediaQuality podcastStreamingBitrateForCurrentNetwork] == 96);
    check(@"download selection follows mobile Off", [MMMediaQuality podcastDownloadBitrateForCurrentNetwork] == 0);
    [MMMediaQuality setPodcastStreamingBitrate:777 forWiFi:YES];
    check(@"unsupported values normalize", [MMMediaQuality podcastStreamingBitrateForWiFi] == 160);
    [pool drain]; return 0;
}
'''.replace("PRODUCTION", production)

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-quality-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    objc_include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
    subprocess.run(["clang", *flags, "-I", str(root / "music/Spot"), "-I", objc_include,
                    str(path / "test.m"), "-o", str(path / "test"), *libs], check=True)
    subprocess.run([str(path / "test")], check=True)
