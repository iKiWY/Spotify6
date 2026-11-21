#!/usr/bin/env python3
"""Run the production liked-download selector against repeat, offline, and budget cases."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = Path(os.environ.get("TRACKLIST_SOURCE_OVERRIDE", root / "music/UI/MMTrackListController.m"))
source = source_path.read_text()
start = source.index("static NSDictionary *likedDownloadSelection(")
end = source.index("\n@implementation MMTrackListController", start)
production = source[start:end]
renew_start = source.index("- (void)renewLiked {")
renew_end = source.index("\nenum { kAlertRemove", renew_start)
renew = source[renew_start:renew_end]
if "likedDownloadSelection(pool,history,allow,downloaded,budget,spaceBudget,estimateKbps)" not in renew:
    raise SystemExit("liked-song renewal must use the tested selector with the repeat, offline, and budget inputs")
if "[MMSpotify downloadedTracks]" not in renew or "candidates.count<pool.count" in renew:
    raise SystemExit("renewal must exclude already-downloaded songs and never fall back to repeats")
harness = r'''
#import <Foundation/Foundation.h>
PRODUCTION
static void check(NSString *label, BOOL condition) {
    NSCAssert(condition, @"%@", label);
    printf("PASS %s\n", [label UTF8String]);
}
static NSArray *ids(NSDictionary *selection) {
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *item in [selection objectForKey:@"items"]) [result addObject:[item objectForKey:@"id"]];
    return result;
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSArray *tracks=@[@{@"id":@"a",@"dur":@1000},@{@"id":@"b",@"dur":@1000},@{@"id":@"c",@"dur":@1000}];
    NSArray *history=@[@[@"a"]];
    NSDictionary *noRepeat=likedDownloadSelection(tracks,history,NO,[NSSet setWithObject:@"c"],LLONG_MAX,LLONG_MAX,160);
    check(@"repeat off excludes history and already-downloaded tracks",[ids(noRepeat) isEqual:@[@"b"]]);
    NSDictionary *repeat=likedDownloadSelection(tracks,history,YES,[NSSet setWithObject:@"c"],LLONG_MAX,LLONG_MAX,160);
    check(@"repeat on may choose old selections but never picks a file already offline",[[NSSet setWithArray:ids(repeat)] isEqual:[NSSet setWithArray:@[@"a",@"b"]]]);
    NSDictionary *empty=likedDownloadSelection(tracks,@[@[@"a",@"b"]],NO,[NSSet setWithObject:@"c"],LLONG_MAX,LLONG_MAX,160);
    check(@"repeat off reports no candidates instead of adding repeats back",[ids(empty) count]==0);
    NSDictionary *budget=likedDownloadSelection(tracks,@[],YES,[NSSet set],25000,LLONG_MAX,160);
    check(@"daily byte limit caps new selections",[ids(budget) count]==1 && [[budget objectForKey:@"bytes"] longLongValue]==20000);
    NSDictionary *space=likedDownloadSelection(tracks,@[],YES,[NSSet set],LLONG_MAX,20000,160);
    check(@"free-space reserve caps new selections",[ids(space) count]==1 && [[space objectForKey:@"newBytes"] longLongValue]==20000);
    [pool drain]; return 0;
}
'''.replace("PRODUCTION", production)

with tempfile.TemporaryDirectory(prefix="spotify6-liked-select-") as directory:
    path=Path(directory)
    (path / "test.m").write_text(harness)
    flags=shlex.split(subprocess.check_output(["gnustep-config","--objc-flags"],text=True))
    libs=shlex.split(subprocess.check_output(["gnustep-config","--base-libs"],text=True))
    objc_include=subprocess.check_output(["gcc","-print-file-name=include"],text=True).strip()
    subprocess.run(["clang",*flags,"-I",objc_include,str(path/"test.m"),"-o",str(path/"test"),*libs],check=True)
    subprocess.run([str(path/"test")],check=True)
