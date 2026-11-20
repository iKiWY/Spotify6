#!/usr/bin/env python3
"""Run the production episode queue adapter and persistence code on GNUstep."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = Path(os.environ.get("MMSPOTIFY_SOURCE_OVERRIDE", root / "music/Spot/MMSpotify.m"))
source = source_path.read_text()
queue_helpers_start = source.index("static BOOL isEpisodeQueueID")
queue_helpers_end = source.index("static NSString* diskPath", queue_helpers_start)
method_start = source.index("+ (void)queueDownloadEpisodes:")
method_end = source.index("\n+ (void)enqueueTracks:", method_start)
production = source[queue_helpers_start:queue_helpers_end] + source[method_start:method_end]
harness = r'''
#import <Foundation/Foundation.h>
static NSArray *queuedIDs;
@interface MMSpotify : NSObject
+ (void)queueDownloadEpisodes:(NSArray *)episodeIDs;
+ (void)enqueueTracks:(NSArray *)IDs automatic:(BOOL)automatic;
@end
@implementation MMSpotify
PRODUCTION
+ (void)enqueueTracks:(NSArray *)IDs automatic:(BOOL)automatic { (void)automatic; queuedIDs=[IDs copy]; }
@end
static void check(NSString *name,BOOL condition){ NSCAssert(condition,@"%@",name); printf("PASS %s\n",[name UTF8String]); }
int main(void){
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults]; [defaults removeObjectForKey:@"podcastOfflineIDs"];
    [MMSpotify queueDownloadEpisodes:@[@"abc",@"def",@42]];
    check(@"episodes are enqueued with their media type",[queuedIDs isEqual:@[@"episode:abc",@"episode:def"]]);
    NSSet *saved=[NSSet setWithArray:[defaults objectForKey:@"podcastOfflineIDs"]];
    check(@"episode IDs persist for restart resume",[saved isEqual:[NSSet setWithArray:@[@"abc",@"def"]]]);
    [pool drain]; return 0;
}
'''.replace("PRODUCTION", production)

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-queue-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    objc_include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
    subprocess.run(["clang", *flags, "-I", objc_include, str(path / "test.m"), "-o", str(path / "test"), *libs], check=True)
    subprocess.run([str(path / "test")], check=True)
