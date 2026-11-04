#!/usr/bin/env python3
"""Run the production pagination method with mocked HTTP on macOS Foundation."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "music/Spot/MMSpotify.m").read_text()
start = source.index("+ (void)apiUserAllItems:")
end = source.index("// ---- Login mit Code", start)
method = source[start:end]
harness = r'''
#import <Foundation/Foundation.h>
static NSDictionary *pages;
static NSMutableArray *requests;
@interface MMSpotify : NSObject
+ (void)apiUser:(NSString *)method path:(NSString *)path body:(NSData *)body completion:(void(^)(NSDictionary *,NSInteger))done;
+ (void)apiUserAllItems:(NSString *)path completion:(void(^)(NSArray *,NSInteger))done;
@end
@implementation MMSpotify
+ (void)apiUser:(NSString *)method path:(NSString *)path body:(NSData *)body completion:(void(^)(NSDictionary *,NSInteger))done {
    NSCAssert([method isEqual:@"GET"] && !body,@"pagination must only read");
    [requests addObject:path];
    NSDictionary *response=pages[path];
    NSCAssert(response!=nil,@"unexpected page: %@",path);
    done(response[@"json"],[response[@"status"] integerValue]);
}
PRODUCTION_METHOD
@end
static void check(NSString *label, NSDictionary *responses, NSArray *expected, NSInteger status, NSArray *paths) {
    pages=responses; requests=[NSMutableArray array]; __block NSUInteger calls=0;
    [MMSpotify apiUserAllItems:@"first" completion:^(NSArray *items,NSInteger st){
        calls++; NSCAssert(st==status,@"%@: status %ld",label,(long)st);
        NSCAssert((!items && !expected)||[items isEqual:expected],@"%@: wrong items %@",label,items);
    }];
    NSCAssert(calls==1,@"%@: completion called %lu times",label,(unsigned long)calls);
    NSCAssert([requests isEqual:paths],@"%@: wrong pages %@",label,requests);
    printf("PASS %s\n",label.UTF8String);
}
int main(void) { @autoreleasepool {
    check(@"rootlist spans pages",@{
        @"first":@{@"status":@200,@"json":@{@"items":@[@{@"id":@"one"}],@"next":@"https://api.spotify.com/v1/second?offset=100"}},
        @"second?offset=100":@{@"status":@200,@"json":@{@"items":@[@{@"id":@"two"}],@"next":[NSNull null]}}
    },@[@{@"id":@"one"},@{@"id":@"two"}],200,@[@"first",@"second?offset=100"]);
    check(@"playlist nested pages",@{
        @"first":@{@"status":@200,@"json":@{@"tracks":@{@"items":@[@1],@"next":@"playlists/p?offset=50"}}},
        @"playlists/p?offset=50":@{@"status":@200,@"json":@{@"tracks":@{@"items":@[@2],@"next":[NSNull null]}}}
    },@[@1,@2],200,@[@"first",@"playlists/p?offset=50"]);
    for(NSNumber *status in @[@401,@429,@503]) {
        check([NSString stringWithFormat:@"later page %@ never returns partial success",status],@{
            @"first":@{@"status":@200,@"json":@{@"items":@[@1],@"next":@"second"}},
            @"second":@{@"status":status}
        },nil,status.integerValue,@[@"first",@"second"]);
    }
    check(@"missing items is not an empty library",@{@"first":@{@"status":@200,@"json":@{}}},nil,502,@[@"first"]);
    check(@"empty playlist is valid",@{@"first":@{@"status":@200,@"json":@{@"tracks":@{@"items":@[],@"next":[NSNull null]}}}},@[],200,@[@"first"]);
} return 0; }
'''.replace("PRODUCTION_METHOD", method)
with tempfile.TemporaryDirectory(prefix="spotify6-pagination-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Werror",
                    "-framework", "Foundation", str(path / "test.m"), "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test")], check=True)
