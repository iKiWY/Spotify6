#!/usr/bin/env python3
"""Exercise production podcast chunk decryption and atomic file publication."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = Path(os.environ.get("MMSPOTIFY_SOURCE_OVERRIDE", root / "music/Spot/MMSpotify.m"))
source = source_path.read_text()
marker = source.index("// Podcast episodes can be much larger than a song")
start = source.index("+ (BOOL)downloadDecryptEpisode:", marker)
end = source.index("\n}\n\n+ (NSData *)loadAudioData", start) + 2
production = source[start:end]
harness = r'''
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSData.h>
#import <Foundation/NSError.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSException.h>
#import <Foundation/NSAutoreleasePool.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
typedef struct { int unused; } MMCtr;
static MMCtr *ctrNew(const void *key) { (void)key; return calloc(1,sizeof(MMCtr)); }
static void ctrRun(MMCtr *ctr,const void *in,void *out,size_t n) { (void)ctr; memcpy(out,in,n); }
static void ctrFree(MMCtr *ctr) { free(ctr); }
static NSData *fixture;
static long long fixtureLength;
static long long availableBytes=1024LL*1024*1024;
static BOOL cancelFixture;
static NSMutableData *cdnFetchEx(NSString *url,NSError **err,void(^progress)(double),BOOL(^onResponse)(long long),BOOL(^onChunk)(NSData*),BOOL(^cancel)(void)) {
    (void)url; (void)progress;
    if(!onResponse(fixtureLength)){ if(err)*err=[NSError errorWithDomain:@"test" code:1 userInfo:nil]; return nil; }
    NSUInteger offset=0;
    while(offset<fixture.length){
        if(cancelFixture || (cancel && cancel())){ if(err)*err=[NSError errorWithDomain:@"test" code:2 userInfo:nil]; return nil; }
        NSUInteger n=MIN((NSUInteger)7,fixture.length-offset);
        NSData *chunk=[fixture subdataWithRange:NSMakeRange(offset,n)];
        if(!onChunk(chunk)){ if(err)*err=[NSError errorWithDomain:@"test" code:3 userInfo:nil]; return nil; }
        offset+=n;
    }
    return [NSMutableData data];
}
@interface MMSpotify : NSObject
+ (long long)freeDiskBytes;
+ (BOOL)downloadDecryptEpisode:(NSString *)cdn key:(NSData *)keyData toPath:(NSString *)path err:(NSString **)err cancel:(BOOL(^)(void))cancel;
@end
@implementation MMSpotify
+ (long long)freeDiskBytes { return availableBytes; }
PRODUCTION
@end
static void check(NSString *name,BOOL condition){ if(!condition){ fprintf(stderr,"FAIL %s\n",[name UTF8String]); abort(); } printf("PASS %s\n",[name UTF8String]); }
int main(void){
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    char directory[]="/tmp/spotify6-podcast-dl-XXXXXX"; mkdtemp(directory);
    NSString *path=[[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:@"episode.ogg"];
    fixture=[@"podcast bytes split across several network chunks" dataUsingEncoding:NSUTF8StringEncoding]; fixtureLength=fixture.length;
    NSString *error=nil;
    check(@"podcast chunks decrypt directly to final file",[MMSpotify downloadDecryptEpisode:@"https://cdn" key:[NSData data] toPath:path err:&error cancel:nil]);
    NSData *saved=[NSData dataWithContentsOfFile:path];
    check(@"published file contains complete decrypted payload",[saved isEqualToData:fixture]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    cancelFixture=YES; error=nil;
    check(@"cancelled podcast stream is rejected",![MMSpotify downloadDecryptEpisode:@"https://cdn" key:[NSData data] toPath:path err:&error cancel:nil]);
    check(@"cancelled podcast leaves no partial file",![[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingString:@".partial"]]);
    cancelFixture=NO; fixtureLength=-1; error=nil;
    check(@"unknown podcast size is rejected without buffering",![MMSpotify downloadDecryptEpisode:@"https://cdn" key:[NSData data] toPath:path err:&error cancel:nil]);
    check(@"unknown size leaves no partial file",![[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingString:@".partial"]]);
    [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithUTF8String:directory] error:NULL];
    [pool drain]; return 0;
}
'''.replace("PRODUCTION", production)

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-download-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    (path / "objc").mkdir()
    (path / "objc/blocks_runtime.h").symlink_to("/usr/include/Block.h")
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    objc_include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
    subprocess.run(["clang", *flags, "-fblocks", "-I", str(path), "-I", objc_include,
                    str(path / "test.m"), "-o", str(path / "test"), *libs, "-lBlocksRuntime"], check=True)
    subprocess.run([str(path / "test")], check=True)
