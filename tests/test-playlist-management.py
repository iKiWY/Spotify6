#!/usr/bin/env python3
"""Exercise production playlist creation/rename with mocked transport, on macOS."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'music/Spot/MMSpotify.m').read_text()
helper = source[source.index('static BOOL playlistChange('):source.index('+ (void)isPlaylistSaved:')]
methods = source[source.index('+ (void)createPlaylist:'):source.index('// Web-API mit Methode', source.index('+ (void)createPlaylist:'))]
harness = r'''
#import <Foundation/Foundation.h>
static NSMutableArray *responses, *requests;
static NSString *spUser(void) { return @"test-user"; }
static NSData *spReq(NSString *method, NSString *path, NSData *body, NSString *ctype, NSString *accept, int *status) {
    NSCAssert(responses.count>0,@"unexpected request %@",path);
    NSDictionary *response=responses[0]; [responses removeObjectAtIndex:0];
    NSMutableDictionary *request=[@{@"method":method,@"path":path} mutableCopy];
    if(body) request[@"json"]=[NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    [requests addObject:request];
    *status=[response[@"status"] intValue];
    return response[@"json"]?[NSJSONSerialization dataWithJSONObject:response[@"json"] options:0 error:NULL]:nil;
}
static NSDictionary *spJSON(NSString *path,int *status) {
    NSData *d=spReq(@"GET",path,nil,nil,@"application/json",status);
    return d?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
}
@interface MMSpotify : NSObject
+ (void)createPlaylist:(NSString *)name completion:(void(^)(NSDictionary *,NSInteger))done;
+ (void)renamePlaylist:(NSString *)pid name:(NSString *)name completion:(void(^)(BOOL))done;
@end
@implementation MMSpotify
PRODUCTION_HELPER
PRODUCTION_METHODS
@end
static void setup(NSArray *fixtures) { responses=[fixtures mutableCopy]; requests=[NSMutableArray array]; }
static void waitFor(BOOL *finished) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!*finished && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSCAssert(*finished && responses.count==0,@"missing completion or unconsumed response");
}
static void creation(NSString *label,NSArray *fixtures,BOOL created,BOOL saved,NSInteger status) {
    setup(fixtures); __block BOOL finished=NO;
    [MMSpotify createPlaylist:@"Música á & +" completion:^(NSDictionary *p,NSInteger st) {
        NSCAssert([NSThread isMainThread],@"callback must run on main thread");
        NSCAssert(st==status && (p!=nil)==created,@"incorrect creation result");
        if(created) NSCAssert([p[@"id"] isEqual:@"test-id"] && [p[@"saved"] boolValue]==saved,@"incorrect saved result");
        finished=YES;
    }]; waitFor(&finished);
    NSCAssert(requests.count==fixtures.count,@"mutations must not be retried");
    NSCAssert([requests[0][@"path"] isEqual:@"/playlist/v2/playlist"],@"creation must use internal endpoint");
    NSDictionary *op=requests[0][@"json"][@"ops"][0];
    NSCAssert([op[@"updateListAttributes"][@"newAttributes"][@"values"][@"name"] isEqual:@"Música á & +"],@"name was corrupted");
    if(requests.count>1) {
        NSDictionary *item=requests[1][@"json"][@"deltas"][0][@"ops"][0][@"add"][@"items"][0];
        NSCAssert([item[@"uri"] isEqual:@"spotify:playlist:test-id"] && ![item[@"attributes"][@"public"] boolValue],@"new playlist must be saved without profile publication");
    }
    printf("PASS %s\n",label.UTF8String);
}
int main(void) { @autoreleasepool {
    NSDictionary *created=@{@"status":@200,@"json":@{@"uri":@"spotify:playlist:test-id"}};
    creation(@"create and save preserves Unicode name",@[created,@{@"status":@200}],YES,YES,200);
    creation(@"creation failure does not attempt rootlist write",@[@{@"status":@503}],NO,NO,503);
    creation(@"missing URI does not invent a playlist",@[@{@"status":@200,@"json":@{}}],NO,NO,200);
    creation(@"library failure retains created ID without retrying creation",@[created,@{@"status":@503}],YES,NO,200);
    setup(@[@{@"status":@200,@"json":@{@"ownerUsername":@"someone-else"}}]);
    __block BOOL finished=NO;
    [MMSpotify renamePlaylist:@"test-id" name:@"changed" completion:^(BOOL ok){ NSCAssert(!ok,@"foreign playlist renamed"); finished=YES; }];
    waitFor(&finished); NSCAssert(requests.count==1,@"must not write to another owner's playlist");
    printf("PASS rename refuses foreign owner\n");
    setup(@[@{@"status":@200,@"json":@{@"ownerUsername":@"test-user",@"revision":@"revision-one"}},@{@"status":@200}]);
    finished=NO;
    [MMSpotify renamePlaylist:@"test-id" name:@"changed" completion:^(BOOL ok){ NSCAssert(ok,@"owned rename failed"); finished=YES; }];
    waitFor(&finished);
    NSCAssert([requests[1][@"json"][@"baseRevision"] isEqual:@"revision-one"],@"rename must preserve revision guard");
    printf("PASS owned rename uses fetched revision\n");
} return 0; }
'''.replace('PRODUCTION_HELPER', helper).replace('PRODUCTION_METHODS', methods)
with tempfile.TemporaryDirectory(prefix='spotify6-playlists-') as directory:
    path = Path(directory)
    (path / 'test.m').write_text(harness)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Werror', '-Wno-deprecated-declarations', '-framework', 'Foundation', str(path / 'test.m'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
