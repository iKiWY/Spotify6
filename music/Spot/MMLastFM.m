#import "MMLastFM.h"
#import "MMSpotify.h"
#import <mbedtls/md5.h>

#if __has_include("MMLastFMAppConfig.local.h")
#import "MMLastFMAppConfig.local.h"
#else
#define MMLASTFM_API_KEY @""
#define MMLASTFM_API_SECRET @""
#endif

static NSString * const kLFKey = @"lastFmAPIKey";
static NSString * const kLFSec = @"lastFmAPISecret";
static NSString * const kLFSession = @"lastFmSessionKey";
static NSString * const kLFUser = @"lastFmUsername";
static NSString * const kLFToken = @"lastFmPendingToken";
static NSString * const kLFQueue = @"lastFmScrobbleQueue";

static dispatch_queue_t lfQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q=dispatch_queue_create("mesh.lastfm", DISPATCH_QUEUE_SERIAL); });
    return q;
}
static NSString *lfString(id x) { return [x isKindOfClass:[NSString class]]?x:@""; }
static NSString *lfMD5(NSString *s) {
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding]; unsigned char out[16];
    mbedtls_md5(d.bytes,d.length,out);
    NSMutableString *hex=[NSMutableString stringWithCapacity:32];
    for(int i=0;i<16;i++) [hex appendFormat:@"%02x",out[i]];
    return hex;
}
static NSString *lfFormValue(NSString *s) {
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding]; const unsigned char *b=d.bytes;
    NSMutableString *out=[NSMutableString string];
    for(NSUInteger i=0;i<d.length;i++){
        unsigned char c=b[i];
        if((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='-'||c=='_'||c=='.'||c=='~') [out appendFormat:@"%c",c];
        else [out appendFormat:@"%%%02X",c];
    }
    return out;
}
static NSString *lfSignature(NSDictionary *params, NSString *secret) {
    NSArray *keys=[[params allKeys] sortedArrayUsingSelector:@selector(compare:)]; NSMutableString *s=[NSMutableString string];
    for(NSString *key in keys) if(![key isEqualToString:@"format"] && ![key isEqualToString:@"callback"] && ![key isEqualToString:@"api_sig"])
        [s appendFormat:@"%@%@",key,params[key]];
    [s appendString:secret?:@""];
    return lfMD5(s);
}
static NSString *lfFormBody(NSDictionary *params) {
    NSArray *keys=[[params allKeys] sortedArrayUsingSelector:@selector(compare:)]; NSMutableArray *parts=[NSMutableArray array];
    for(NSString *key in keys) [parts addObject:[NSString stringWithFormat:@"%@=%@",lfFormValue(key),lfFormValue([params[key] description])]];
    return [parts componentsJoinedByString:@"&"];
}
static NSDictionary *lfCall(NSDictionary *params, NSInteger *httpStatus) {
    NSMutableDictionary *p=[params mutableCopy];
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults]; NSString *key=[MMLASTFM_API_KEY length]?MMLASTFM_API_KEY:([ud stringForKey:kLFKey]?:@"");
    NSString *secret=[MMLASTFM_API_SECRET length]?MMLASTFM_API_SECRET:([ud stringForKey:kLFSec]?:@"");
    p[@"api_key"]=key; p[@"format"]=@"json"; p[@"api_sig"]=lfSignature(p,secret);
    NSInteger st=0; NSDictionary *json=[MMSpotify lastFMPost:lfFormBody(p) status:&st];
    if(httpStatus) *httpStatus=st;
    return json;
}
static NSMutableArray *lfPending(void) {
    id q=[[NSUserDefaults standardUserDefaults] objectForKey:kLFQueue];
    return [q isKindOfClass:[NSArray class]]?[q mutableCopy]:[NSMutableArray array];
}
static void lfSavePending(NSArray *q) {
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults]; [ud setObject:q forKey:kLFQueue]; [ud synchronize];
}
static BOOL lfTemporaryError(NSDictionary *j) {
    NSInteger code=[j[@"error"] integerValue]; return code==11||code==16||code==29;
}

@implementation MMLastFM
+ (BOOL)hasAppCredentials { return [MMLASTFM_API_KEY length]==32 && [MMLASTFM_API_SECRET length]>0; }
+ (BOOL)isConnected { return [[NSUserDefaults standardUserDefaults] stringForKey:kLFSession].length>0; }
+ (NSString *)connectedUsername { return [[NSUserDefaults standardUserDefaults] stringForKey:kLFUser]?:@""; }
+ (NSString *)configuredAPIKey { return [MMLASTFM_API_KEY length]?MMLASTFM_API_KEY:([[NSUserDefaults standardUserDefaults] stringForKey:kLFKey]?:@""); }
+ (NSString *)configuredAPISecret { return [MMLASTFM_API_SECRET length]?MMLASTFM_API_SECRET:([[NSUserDefaults standardUserDefaults] stringForKey:kLFSec]?:@""); }
+ (NSString *)pendingAuthorizationURL {
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults]; NSString *token=[ud stringForKey:kLFToken]?:@"", *key=[self configuredAPIKey]?:@"";
    if(!token.length||!key.length)return nil;
    return [NSString stringWithFormat:@"https://www.last.fm/api/auth/?api_key=%@&token=%@",lfFormValue(key),lfFormValue(token)];
}

+ (void)beginAuthorizationWithAPIKey:(NSString *)apiKey secret:(NSString *)secret completion:(void (^)(NSString *, NSString *))done {
    NSString *key=[[apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    NSString *sec=[[secret stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    BOOL embedded=[self hasAppCredentials];
    if(embedded){ key=MMLASTFM_API_KEY; sec=MMLASTFM_API_SECRET; }
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    if(!embedded){ [ud setObject:key?:@"" forKey:kLFKey]; [ud setObject:sec?:@"" forKey:kLFSec]; }
    [ud removeObjectForKey:kLFSession]; [ud removeObjectForKey:kLFUser]; [ud synchronize];
    dispatch_async(lfQueue(), ^{
        if(key.length!=32||sec.length<1){ dispatch_async(dispatch_get_main_queue(), ^{ done(nil,@"Enter the 32-character Last.fm API key and its secret."); }); return; }
        NSInteger st=0; NSDictionary *j=lfCall(@{@"method":@"auth.getToken"},&st); NSString *token=lfString(j[@"token"]);
        if(st!=200||!token.length){ NSString *e=lfString(j[@"message"]); if(!e.length)e=[NSString stringWithFormat:@"Last.fm token request failed (HTTP %ld).",(long)st]; dispatch_async(dispatch_get_main_queue(), ^{ done(nil,e); }); return; }
        [[NSUserDefaults standardUserDefaults] setObject:token forKey:kLFToken]; [[NSUserDefaults standardUserDefaults] synchronize];
        NSString *url=[self pendingAuthorizationURL];
        dispatch_async(dispatch_get_main_queue(), ^{ done(url,nil); });
    });
}

+ (void)completeAuthorization:(void (^)(BOOL, NSString *, NSString *))done {
    dispatch_async(lfQueue(), ^{
        NSString *token=[[NSUserDefaults standardUserDefaults] stringForKey:kLFToken]?:@""; NSInteger st=0;
        NSDictionary *j=token.length?lfCall(@{@"method":@"auth.getSession",@"token":token},&st):nil;
        NSDictionary *session=[j[@"session"] isKindOfClass:[NSDictionary class]]?j[@"session"]:nil;
        NSString *sk=lfString(session[@"key"]), *name=lfString(session[@"name"]);
        BOOL ok=st==200&&sk.length>0;
        if(ok){ NSUserDefaults *ud=[NSUserDefaults standardUserDefaults]; [ud setObject:sk forKey:kLFSession]; [ud setObject:name forKey:kLFUser]; [ud removeObjectForKey:kLFToken]; [ud synchronize]; }
        NSString *err=ok?nil:(lfString(j[@"message"]).length?lfString(j[@"message"]):@"Authorization not completed. Approve the app in Safari, then retry.");
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(ok,name,err); });
    });
}
+ (void)disconnect {
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    for(NSString *k in @[kLFSession,kLFUser,kLFToken,kLFQueue]) [ud removeObjectForKey:k];
    [ud synchronize];
}

+ (void)updateNowPlayingTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album duration:(double)duration {
    if(![self isConnected]||!title.length||!artist.length) return;
    dispatch_async(lfQueue(), ^{
        NSMutableDictionary *p=[@{@"method":@"track.updateNowPlaying",@"sk":[[NSUserDefaults standardUserDefaults] stringForKey:kLFSession]?:@"",@"track":title,@"artist":artist} mutableCopy];
        if(album.length)p[@"album"]=album; if(duration>0)p[@"duration"]=[NSString stringWithFormat:@"%.0f",duration];
        NSInteger st=0; NSDictionary *j=lfCall(p,&st); if(st!=200||j[@"error"]) MMLog(@"Last.fm now-playing failed: HTTP %ld code %@",(long)st,j[@"error"]?:@"");
    });
}

+ (void)scrobbleTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album duration:(double)duration timestamp:(long long)timestamp {
    if(![self isConnected]||!title.length||!artist.length||timestamp<=0) return;
    NSMutableDictionary *item=[@{@"track":title,@"artist":artist,@"timestamp":[NSString stringWithFormat:@"%lld",timestamp]} mutableCopy];
    if(album.length)item[@"album"]=album; if(duration>0)item[@"duration"]=[NSString stringWithFormat:@"%.0f",duration];
    dispatch_async(lfQueue(), ^{
        NSMutableArray *queue=lfPending(); [queue addObject:item]; lfSavePending(queue);
        [self flushOnQueue];
    });
}
+ (void)flushQueuedScrobbles { dispatch_async(lfQueue(), ^{ [self flushOnQueue]; }); }
+ (void)flushOnQueue {
    if(![self isConnected]||![MMSpotify networkReachable]) return;
    while(YES){
        NSMutableArray *queue=lfPending(); if(!queue.count)return;
        NSDictionary *item=queue[0]; NSMutableDictionary *p=[@{@"method":@"track.scrobble",@"sk":[[NSUserDefaults standardUserDefaults] stringForKey:kLFSession]?:@"",@"track":item[@"track"],@"artist":item[@"artist"],@"timestamp":item[@"timestamp"]} mutableCopy];
        if([item[@"album"] length])p[@"album"]=item[@"album"]; if([item[@"duration"] length])p[@"duration"]=item[@"duration"];
        NSInteger st=0; NSDictionary *j=lfCall(p,&st); NSInteger code=[j[@"error"] integerValue];
        if(st==200 && !j[@"error"]){ [queue removeObjectAtIndex:0]; lfSavePending(queue); continue; }
        MMLog(@"Last.fm scrobble failed: HTTP %ld code %@",(long)st,j[@"error"]?:@"");
        if(lfTemporaryError(j)||st==0||st>=500) return;
        if(code==9){ NSUserDefaults *ud=[NSUserDefaults standardUserDefaults]; [ud removeObjectForKey:kLFSession]; [ud removeObjectForKey:kLFUser]; [ud synchronize]; return; }
        [queue removeObjectAtIndex:0]; lfSavePending(queue); // auth/format/permanent errors will not become valid by retrying
    }
}
@end
