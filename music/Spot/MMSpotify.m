#import "MMSpotify.h"
#import "MMAudio.h"
#import <libkern/OSAtomic.h>
#import "shannon.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netdb.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <fcntl.h>
#import <sys/sysctl.h>
#import <string.h>
#import <arpa/inet.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "mbedtls/bignum.h"
#import "mbedtls/ssl.h"
#import "mbedtls/net_sockets.h"
#import "mbedtls/ctr_drbg.h"
#import "mbedtls/entropy.h"
#import "mbedtls/aes.h"
#import "mbedtls/x509_crt.h"
#import "mbedtls/error.h"
#import "psa/crypto.h"
#import "MMCovers.h"

static const unsigned char DH_PRIME[96]={
 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xc9,0x0f,0xda,0xa2,0x21,0x68,0xc2,0x34,
 0xc4,0xc6,0x62,0x8b,0x80,0xdc,0x1c,0xd1,0x29,0x02,0x4e,0x08,0x8a,0x67,0xcc,0x74,
 0x02,0x0b,0xbe,0xa6,0x3b,0x13,0x9b,0x22,0x51,0x4a,0x08,0x79,0x8e,0x34,0x04,0xdd,
 0xef,0x95,0x19,0xb3,0xcd,0x3a,0x43,0x1b,0x30,0x2b,0x0a,0x6d,0xf2,0x5f,0x14,0x37,
 0x4f,0xe1,0x35,0x6d,0x6d,0x51,0xc2,0x45,0xe4,0x85,0xb5,0x76,0x62,0x5e,0x7e,0xc6,
 0xf4,0x4c,0x42,0xe9,0xa6,0x3a,0x36,0x20,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};

static void pvar(NSMutableData*d,uint64_t v){unsigned char b;do{b=v&0x7f;v>>=7;if(v)b|=0x80;[d appendBytes:&b length:1];}while(v);}
static void ptag(NSMutableData*d,int f,int wt){pvar(d,((uint64_t)f<<3)|wt);}
static void pbytes(NSMutableData*d,int f,NSData*v){ptag(d,f,2);pvar(d,v.length);[d appendData:v];}
static void pvarf(NSMutableData*d,int f,uint64_t v){ptag(d,f,0);pvar(d,v);}
static void pmsg(NSMutableData*d,int f,NSData*m){ptag(d,f,2);pvar(d,m.length);[d appendData:m];}
static uint64_t rvar(const unsigned char*b,NSUInteger len,NSUInteger*p){uint64_t r=0;int s=0;while(*p<len){unsigned char c=b[(*p)++];r|=(uint64_t)(c&0x7f)<<s;if(!(c&0x80))break;s+=7;}return r;}
static NSData* psub(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)return v;}
  else if(wt==0){rvar(b,len,&pos);}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return nil;}
static int rd_all(int s,unsigned char*b,int n){int t=0;while(t<n){int r=(int)read(s,b+t,n-t);if(r<=0)return -1;t+=r;}return 0;}

static void slog(NSString*fmt,...);

NSString *MMDataDir(void){
    static NSString*d; static dispatch_once_t o;
    dispatch_once(&o,^{ d=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Riff"];
        [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL]; });
    return d;
}
NSString *MMPath(NSString *relative){ return [MMDataDir() stringByAppendingPathComponent:relative]; }
void MMLog(NSString *fmt, ...){ va_list a; va_start(a,fmt); NSString*s=[[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a); slog(@"%@",s); }
static NSString*hexd(const unsigned char*b,int n);
static NSData* httpsReq(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut);
// Streaming: onHead(Status, Länge oder -1) einmal, dann onData je Häppchen (NO = abbrechen). Erfolg = leeres NSData, Fehler/Abbruch = nil
typedef void(^MMHttpHead)(NSInteger status,long long length);
typedef BOOL(^MMHttpData)(const void*bytes,size_t n);
static NSData* httpsReqEx(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut,MMHttpHead onHead,MMHttpData onData);
static NSString* b64std(NSData*data);
static const unsigned char AUDIO_IV[16]={0x72,0xe0,0x67,0xfb,0xdd,0xcb,0xcf,0x77,0xeb,0xe8,0xbc,0x64,0x3f,0x63,0x0d,0x93};
static void pstr(NSMutableData*d,int f,NSString*s){pbytes(d,f,[s dataUsingEncoding:NSUTF8StringEncoding]);}
static NSArray* psubs(NSData*m,int want){NSMutableArray*out=[NSMutableArray array];const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)[out addObject:v];}
  else if(wt==0){rvar(b,len,&pos);}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return out;}
static int64_t pvarval(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==0){uint64_t v=rvar(b,len,&pos);if(f==want)return v;}
  else if(wt==2){uint64_t l=rvar(b,len,&pos);pos+=l;}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return -1;}

// 16-Byte gid -> base62 (Umkehrung von base62ToGid, 22 Zeichen)
static NSString* gidToBase62(NSData*gid){
    if(gid.length!=16) return nil;
    const char*A="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    unsigned char n[16]; memcpy(n,gid.bytes,16); char out[23]; out[22]=0;
    for(int k=21;k>=0;k--){ int rem=0; for(int j=0;j<16;j++){ int v=(rem<<8)|n[j]; n[j]=v/62; rem=v%62; } out[k]=A[rem]; }
    return [NSString stringWithUTF8String:out];
}
static int fmtRank(int64_t fmt){ return fmt==1?3 : fmt==0?2 : fmt==2?1 : -1; }   // Audioformat-Vorzug (siehe resolveTrack)

// base62 -> 16-Byte gid (klein-zuerst-Alphabet!)
static void base62ToGid(NSString*b62,unsigned char gid[16]){
    const char*A="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    unsigned char acc[16]={0};
    for(NSUInteger i=0;i<b62.length;i++){const char*q=strchr(A,(char)[b62 characterAtIndex:i]);int d=q?(int)(q-A):0;int carry=d;
        for(int j=15;j>=0;j--){int v=acc[j]*62+carry;acc[j]=v&0xff;carry=v>>8;}}
    memcpy(gid,acc,16);
}

// ---- Session-Zustand (bleibt nach Login offen) ----
static int gSock=-1; static shn_ctx gSnd,gRcv; static uint32_t gSend=0,gRecv=0; static uint64_t gMercSeq=1;
static NSString*gToken=nil; static NSString*gClientToken=nil; static NSString*gSpclient=nil;
static BOOL gLoading=NO;
// TCP-Verbindung mit Zeitlimit (blockierendes connect() hängt bei gesperrtem Port ~75 s pro Server).
// Danach Lese-/Schreib-Zeitlimit, damit eine stumme Verbindung nie die ganze Wiedergabe blockiert.
#define AP_CONNECT_TIMEOUT 6
#define AP_IO_TIMEOUT 20
static int tcpConnect(const struct sockaddr_in*sa, NSString**why){
    int t=socket(AF_INET,SOCK_STREAM,0); if(t<0){ *why=@"socket"; return -1; }
    int fl=fcntl(t,F_GETFL,0); fcntl(t,F_SETFL,fl|O_NONBLOCK);
    int r=connect(t,(const struct sockaddr*)sa,sizeof(*sa));
    if(r!=0 && errno==EINPROGRESS){
        fd_set w; FD_ZERO(&w); FD_SET(t,&w); struct timeval tv={AP_CONNECT_TIMEOUT,0};
        r=select(t+1,NULL,&w,NULL,&tv);
        if(r==0){ *why=@"timeout"; close(t); return -1; }
        int e=0; socklen_t el=sizeof e; getsockopt(t,SOL_SOCKET,SO_ERROR,&e,&el);
        if(r<0 || e){ *why=[NSString stringWithFormat:@"error %d",e?:errno]; close(t); return -1; }
    } else if(r!=0){ *why=[NSString stringWithFormat:@"error %d",errno]; close(t); return -1; }
    fcntl(t,F_SETFL,fl);
    struct timeval io={AP_IO_TIMEOUT,0}; setsockopt(t,SOL_SOCKET,SO_RCVTIMEO,&io,sizeof io); setsockopt(t,SOL_SOCKET,SO_SNDTIMEO,&io,sizeof io);
    int one=1; setsockopt(t,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof one);
    return t;
}
// Konto-Art und Land kommen nach dem Login als eigene Pakete (0x50 ProductInfo, 0x1b Land)
static NSString*gProductType=nil, *gCountry=nil;
// Schlüssel-Verweigerung: seit Okt. 2026 gibt Spotify neu angelegten (Premium-/Probe-)Konten keine Song-Schlüssel mehr
// (Fehlercode 1). Erkennen: mehrere Verweigerungen hintereinander, ohne dass in dieser Sitzung je ein Schlüssel kam.
static NSInteger gKeyRefusedRow=0, gKeyRefusedTotal=0, gKeyLastCode=-1; static BOOL gKeyEverOK=NO;
static BOOL accountKeysRefused(void){ return !gKeyEverOK && gKeyRefusedRow>=3; }
static void postOnce(NSString*name){
    static NSMutableSet*sent; @synchronized([NSObject class]){ if(!sent) sent=[NSMutableSet set]; if([sent containsObject:name]) return; [sent addObject:name]; }
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil]; });
}
static void notePacket(int cmd, NSData*d){
    if(cmd==0x1b && d.length>=2){ gCountry=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; slog(@"country=%@",gCountry); }
    if(cmd==0x50){
        NSString*x=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        NSRange a=[x rangeOfString:@"<type>"], b=[x rangeOfString:@"</type>"];
        if(a.location!=NSNotFound && b.location!=NSNotFound && b.location>a.location+a.length){
            gProductType=[x substringWithRange:NSMakeRange(a.location+a.length,b.location-a.location-a.length)];
            slog(@"account type=%@",gProductType);
            if(![gProductType isEqualToString:@"premium"]) postOnce(@"MMSpotifyNotPremium");
        }
    }
}
static void sendpkt(int cmd,NSData*payload){
    NSMutableData*p=[NSMutableData data];unsigned char c=cmd;[p appendBytes:&c length:1];
    uint16_t l=htons((uint16_t)payload.length);[p appendBytes:&l length:2];[p appendData:payload];
    shn_nonce_u32(&gSnd,gSend++);shn_encrypt(&gSnd,p.mutableBytes,(int)p.length);
    unsigned char mac[4];shn_finish(&gSnd,mac,4);
    if(write(gSock,p.bytes,p.length)<0 || write(gSock,mac,4)<0){ slog(@"ap write failed (errno %d) -> close",errno); close(gSock); gSock=-1; }
}
static NSData* recvpkt(int*cmd){
    if(gSock<0) return nil;
    shn_nonce_u32(&gRcv,gRecv++);
    // Zeitlimit/abgerissen: Verbindung schließen (die Verschlüsselung ist danach aus dem Takt), der nächste Versuch verbindet neu
    unsigned char h[3];if(rd_all(gSock,h,3)){ slog(@"ap read timeout/closed -> close"); close(gSock); gSock=-1; return nil; }
    shn_decrypt(&gRcv,h,3);
    *cmd=h[0];int len=(h[1]<<8)|h[2];
    unsigned char*pay=malloc(len?len:1);if(len&&rd_all(gSock,pay,len)){free(pay); slog(@"ap read timeout/closed -> close"); close(gSock); gSock=-1; return nil;}
    if(len)shn_decrypt(&gRcv,pay,len);
    unsigned char mac[4];rd_all(gSock,mac,4);
    NSData*d=[NSData dataWithBytes:pay length:len];free(pay);
    notePacket(*cmd,d);
    return d;
}

// ---- Client-Token (HTTPS POST, Anti-Bot) ----
static NSString* getClientToken(void){
    NSMutableData*macos=[NSMutableData data];pstr(macos,1,@"13.4.0");pstr(macos,2,@"MacBookPro18,3");pstr(macos,3,@"arm64");
    NSMutableData*psd=[NSMutableData data];pmsg(psd,3,macos);
    NSMutableData*conn=[NSMutableData data];pmsg(conn,1,psd);pstr(conn,2,@"0123456789abcdef0123456789abcdef01234567");
    NSMutableData*cdr=[NSMutableData data];pstr(cdr,1,@"1.2.52.442.g01c3f6ee");pstr(cdr,2,@"65b708073fc0480ea92a077233ca87bd");pmsg(cdr,3,conn);
    NSMutableData*req=[NSMutableData data];pvarf(req,1,1);pmsg(req,2,cdr);
    // Über mbedTLS (geprüftes Zertifikat) statt NSURLConnection: das 9.3-SDK bindet NSURLConnection an CFNetwork, auf iOS 6 liegt es in Foundation.
    int st=0; NSData*resp=httpsReq(@"POST",@"clienttoken.spotify.com",@"/v1/clienttoken",@[@"Content-Type: application/x-protobuf",@"Accept: application/x-protobuf"],req,&st);
    if(st!=200){ slog(@"clienttoken HTTP %d",st); resp=nil; }
    NSData*granted=resp?psub(resp,2):nil; NSData*tok=granted?psub(granted,1):nil;
    return tok?[[NSString alloc] initWithData:tok encoding:NSUTF8StringEncoding]:nil;
}
// ---- spclient HTTPS GET mit Bearer + client-token ----
static NSData* spclientGet(NSString*path){
    NSString*host=gSpclient; NSRange c=[host rangeOfString:@":"]; if(c.location!=NSNotFound) host=[host substringToIndex:c.location];
    NSMutableArray*hdr=[NSMutableArray array];
    if(gToken.length)[hdr addObject:[@"Authorization: Bearer " stringByAppendingString:gToken]];
    if(gClientToken.length)[hdr addObject:[@"client-token: " stringByAppendingString:gClientToken]];
    int st=0; NSData*d=httpsReq(@"GET",host,path,hdr,nil,&st);
    if(st!=200){slog(@"[spclient] %@ -> HTTP %d",path,st);return nil;}
    return d;
}
// ---- Mercury GET über den AP-Kanal ----
static NSData* mercuryGet(NSString*uri){
    uint64_t seq=gMercSeq++;
    NSMutableData*hdr=[NSMutableData data];pstr(hdr,1,uri);pstr(hdr,3,@"GET");
    NSMutableData*pl=[NSMutableData data];
    uint16_t sl=htons(8);[pl appendBytes:&sl length:2];unsigned char sb[8];for(int i=0;i<8;i++)sb[i]=(seq>>(8*(7-i)))&0xff;[pl appendBytes:sb length:8];
    unsigned char flags=1;[pl appendBytes:&flags length:1];uint16_t cnt=htons(1);[pl appendBytes:&cnt length:2];
    uint16_t hl=htons((uint16_t)hdr.length);[pl appendBytes:&hl length:2];[pl appendData:hdr];
    sendpkt(0xb2,pl);
    for(int tries=0;tries<200;tries++){
        int cmd;NSData*r=recvpkt(&cmd);if(!r)return nil;
        if(cmd==0x04){sendpkt(0x49,r);continue;}
        if(cmd!=0xb2 && cmd!=0xb5)continue;
        const unsigned char*b=r.bytes;NSUInteger pos=0,len=r.length;
        int seqlen=(b[0]<<8)|b[1];pos=2;uint64_t rseq=0;for(int i=0;i<seqlen;i++)rseq=(rseq<<8)|b[pos++];
        pos++;int parts=(b[pos]<<8)|b[pos+1];pos+=2;
        NSMutableArray*pp=[NSMutableArray array];
        for(int i=0;i<parts && pos+2<=len;i++){int plen=(b[pos]<<8)|b[pos+1];pos+=2;[pp addObject:[r subdataWithRange:NSMakeRange(pos,plen)]];pos+=plen;}
        if(rseq!=seq)continue;
        if(pp.count>=2)return pp[1];
        if(pp.count>=1)return pp[0];
        return [NSData data];
    }
    return nil;
}

static NSMutableString*gLog=nil;
// Log: mehrere Threads schreiben gleichzeitig -> gesperrt; nur die letzten 64 KB behalten
static void slog(NSString*fmt,...){
    va_list a; va_start(a,fmt); NSString*s=[[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    static NSObject*lock; static dispatch_once_t o; dispatch_once(&o,^{ lock=[NSObject new]; });
    @synchronized(lock){
        if(!gLog) gLog=[NSMutableString string];
        [gLog appendFormat:@"%@\n",s];
        if(gLog.length>65536) [gLog deleteCharactersInRange:NSMakeRange(0,gLog.length-49152)];
        [gLog writeToFile:MMPath(@".spotify-log") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}
static NSString*hexd(const unsigned char*b,int n){NSMutableString*m=[NSMutableString string];for(int i=0;i<n;i++)[m appendFormat:@"%02x",b[i]];return m;}

@interface MMSpotify ()
+ (BOOL)resolveTrack:(NSString *)b62 cdn:(NSString **)cdnOut key:(NSData **)keyOut err:(NSString **)err;
+ (NSData *)downloadDecrypt:(NSString *)cdn key:(NSData *)keyData err:(NSString **)err;
+ (NSData *)downloadDecrypt:(NSString *)cdn key:(NSData *)keyData err:(NSString **)err progress:(void(^)(double frac))progress;
+ (NSData *)loadAudioData:(NSString *)b62 err:(NSString **)err;
+ (void)postDlProgress;
+ (void)dlStep;
+ (void)dlFinishTrack:(NSString *)tid;
+ (void)dlSkipUnavailable:(NSString *)tid;
@end

// Download mit Fortschritt: NSURLConnection auf dem Runloop des aufrufenden (Hintergrund-)Threads, bis fertig
@interface MMCdnLoad : NSObject { @public NSMutableData*data; long long expected, received; NSInteger status; NSError*error; BOOL done, chunked; double lastFrac;
    void(^progress)(double); BOOL(^onResponse)(long long expected); BOOL(^onChunk)(NSData*); BOOL responded; }
@end
@implementation MMCdnLoad
// onResponse sagt, ob der Aufrufer die Häppchen selbst nimmt (Wiedergabe während des Downloads); sonst wird gesammelt
// head/body: dieselbe Logik für NSURLConnection und den Download über das eigene TLS. NO = abbrechen (error ist gesetzt)
- (BOOL)head:(NSInteger)st length:(long long)len {
    if(responded && chunked){ error=[NSError errorWithDomain:@"CDN" code:-3 userInfo:@{NSLocalizedDescriptionKey:@"second response"}]; done=YES; return NO; }   // Puffer liegt schon an
    responded=YES; status=st; expected=len; received=0;
    chunked=(status==200 && onChunk && onResponse && expected<=60LL*1024*1024 && onResponse(expected));   // unsinnige Länge: normal laden
    data=chunked?nil:[NSMutableData dataWithCapacity:expected>0?(NSUInteger)expected:4<<20]; return YES; }
- (BOOL)body:(NSData *)d {
    received+=d.length;
    if(chunked){ if(!onChunk(d)){ error=[NSError errorWithDomain:@"CDN" code:-4 userInfo:@{NSLocalizedDescriptionKey:@"cancelled"}]; done=YES; return NO; } }   // überholt: abbrechen
    else [data appendData:d];
    if(progress && expected>0){ double f=(double)received/expected; if(f-lastFrac>=0.02 || f>=1){ lastFrac=f; progress(f); } }   // höchstens alle 2 %
    return YES; }
- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r {
    if(![self head:[r isKindOfClass:[NSHTTPURLResponse class]]?((NSHTTPURLResponse*)r).statusCode:200 length:r.expectedContentLength]) [c cancel]; }
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)d { if(![self body:d]) [c cancel]; }
- (void)connectionDidFinishLoading:(NSURLConnection *)c { done=YES; }
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)e { error=e; done=YES; }
@end
static NSMutableData* cdnFetchEx(NSString*url, NSError**err, void(^progress)(double), BOOL(^onResponse)(long long), BOOL(^onChunk)(NSData*));
static NSMutableData* cdnFetch(NSString*url, NSError**err, void(^progress)(double)){ return cdnFetchEx(url,err,progress,nil,nil); }
// Rückgabe nil + *err = Fehler; im Häppchen-Modus bei Erfolg ein leerer Puffer (die Daten hat onChunk bekommen)
static NSMutableData* cdnFetchEx(NSString*url, NSError**err, void(^progress)(double), BOOL(^onResponse)(long long), BOOL(^onChunk)(NSData*)){
    // 15 s ohne neue Daten = abbrechen (vorher hing ein stockender Download über 100 s und hielt alles dahinter auf)
    NSURLRequest*rq=[NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    MMCdnLoad*l=[MMCdnLoad new]; l->progress=progress; l->onResponse=onResponse; l->onChunk=onChunk;
    NSURLConnection*c=rq.URL?[[NSURLConnection alloc] initWithRequest:rq delegate:l startImmediately:NO]:nil;
    if(!c){ if(err)*err=[NSError errorWithDomain:@"CDN" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"bad CDN URL"}]; return nil; }
    // Lehnt iOS den CDN-Host ab (iOS 7 kennt dessen Zertifikate nicht), läuft derselbe Download über das eigene TLS; der Host merkt sich das
    static NSMutableSet*own; static dispatch_once_t oo; dispatch_once(&oo,^{ own=[NSMutableSet set]; });
    NSString*host=rq.URL.host?:@""; BOOL viaOwn; @synchronized(own){ viaOwn=[own containsObject:host]; }
    if(!viaOwn){
        [c scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode]; [c start];
        while(!l->done) @autoreleasepool { [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]]; }
        NSInteger ec=l->error.code; BOOL tlsRefused=!l->responded && ((ec<=-1200 && ec>=-1206) || (ec<=-9800 && ec>=-9850));   // Zertifikat/SSL, noch keine Antwort
        if(tlsRefused){ @synchronized(own){ [own addObject:host]; } slog(@"cdn: %@ via own TLS (iOS HTTPS refused: %ld)",host,(long)ec); viaOwn=YES; }
    }
    if(viaOwn){
        MMCdnLoad*l2=[MMCdnLoad new]; l2->progress=progress; l2->onResponse=onResponse; l2->onChunk=onChunk; l=l2;
        NSString*path=rq.URL.path.length?rq.URL.path:@"/"; if(rq.URL.query.length) path=[path stringByAppendingFormat:@"?%@",rq.URL.query];
        int hst=0; NSData*r=httpsReqEx(@"GET",host,path,@[],nil,&hst,
            ^(NSInteger st,long long len){ [l2 head:st length:len]; },
            ^BOOL(const void*b,size_t n){ return [l2 body:[NSData dataWithBytesNoCopy:(void*)b length:n freeWhenDone:NO]]; });
        if(!r && !l2->error) l2->error=[NSError errorWithDomain:@"CDN" code:-5 userInfo:@{NSLocalizedDescriptionKey:@"download over own TLS failed"}];
        l2->done=YES;
    }
    if(l->error){ if(err)*err=l->error; return nil; }
    if(l->status!=200){ if(err)*err=[NSError errorWithDomain:@"HTTP" code:l->status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"HTTP %ld",(long)l->status]}]; return nil; }
    if(l->chunked && l->expected>0 && l->received!=l->expected){ if(err)*err=[NSError errorWithDomain:@"CDN" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"download incomplete"}]; return nil; }
    return l->chunked?[NSMutableData data]:l->data;
}

@implementation MMSpotify

static BOOL gLoginRejected=NO;   // letzte Anmeldung von Spotify abgelehnt (nicht bloß keine Verbindung)
+ (NSString *)doLoginCred:(NSData *)credBlob err:(NSString **)err {
    gLoginRejected=NO;
    // DH-Keypair via mbedtls_mpi
    mbedtls_mpi P,G,X,GC,GS,SH; mbedtls_mpi_init(&P);mbedtls_mpi_init(&G);mbedtls_mpi_init(&X);mbedtls_mpi_init(&GC);mbedtls_mpi_init(&GS);mbedtls_mpi_init(&SH);
    mbedtls_mpi_read_binary(&P,DH_PRIME,96); mbedtls_mpi_lset(&G,2);
    unsigned char xb[95]; for(int i=0;i<95;i++)xb[i]=arc4random()&0xff; mbedtls_mpi_read_binary(&X,xb,95);
    mbedtls_mpi_exp_mod(&GC,&G,&X,&P,NULL); unsigned char gcb[96]; mbedtls_mpi_write_binary(&GC,gcb,96);

    // ClientHello
    NSMutableData*bi=[NSMutableData data];pvarf(bi,10,0);pvarf(bi,30,1);pvarf(bi,40,117300517);
    NSMutableData*dh=[NSMutableData data];pbytes(dh,10,[NSData dataWithBytes:gcb length:96]);pvarf(dh,20,1);
    NSMutableData*lch=[NSMutableData data];pmsg(lch,10,dh);
    unsigned char nn[16];for(int i=0;i<16;i++)nn[i]=arc4random()&0xff;
    NSMutableData*ch=[NSMutableData data];pmsg(ch,10,bi);pvarf(ch,30,0);pmsg(ch,50,lch);pbytes(ch,60,[NSData dataWithBytes:nn length:16]);unsigned char pad=0x1e;pbytes(ch,70,[NSData dataWithBytes:&pad length:1]);
    uint32_t size=2+4+(uint32_t)ch.length;NSMutableData*pkt=[NSMutableData data];unsigned char hd[2]={0,4};[pkt appendBytes:hd length:2];uint32_t be=htonl(size);[pkt appendBytes:&be length:4];[pkt appendData:ch];

    // AP-Verbindung
    slog(@"=== login %@", [NSDate date]);   // Log nicht leeren: Fehler vor dem Reconnect bleiben für "Fehlerinfos" sichtbar
    slog(@"cred.len=%lu", (unsigned long)credBlob.length);
    NSError*ae=nil;
    NSString*apURL=@"https://apresolve.spotify.com/?type=accesspoint";
#ifdef DEBUG
    if([[NSFileManager defaultManager] fileExistsAtPath:MMPath(@".noapresolve")]) apURL=@"https://apresolve.invalid/";   // Test: Rückfall auf ap.spotify.com
#endif
    NSData*ad=[NSData dataWithContentsOfURL:[NSURL URLWithString:apURL] options:0 error:&ae];
    slog(@"apresolve bytes=%lu%@", (unsigned long)ad.length, ae?[NSString stringWithFormat:@" error %@ %ld: %@",ae.domain,(long)ae.code,ae.localizedDescription]:@"");   // Grund für "No network" in den Fehlerinfos
    NSArray*aps=ad?[NSJSONSerialization JSONObjectWithData:ad options:0 error:NULL][@"accesspoint"]:nil;
    slog(@"ap count=%lu", (unsigned long)aps.count);
    // apresolve ist HTTPS über iOS: falsches Datum, alte Zertifikatsliste, Proxy oder Captive Portal lassen es scheitern.
    // Der AP-Login selbst braucht kein HTTPS -> wie librespot direkt ap.spotify.com versuchen
    NSString*apWhy=nil;
    if(![aps isKindOfClass:[NSArray class]] || !aps.count){
        apWhy=ae?([ae.domain isEqualToString:NSURLErrorDomain] && ae.code<=-1200 && ae.code>=-1206 ? @"certificate not accepted - check Settings > General > Date & Time" : ae.localizedDescription):@"no server list";
        slog(@"apresolve failed (%@) -> trying ap.spotify.com", apWhy);
        aps=@[@"ap.spotify.com:4070",@"ap.spotify.com:443",@"ap.spotify.com:80"];
    }
    // Server der Reihe nach, je höchstens AP_CONNECT_TIMEOUT s (Spotify bietet Ports 4070, 443 und 80 an)
    int s=-1; NSMutableArray*tried=[NSMutableArray array];
    for(NSString*ap in aps){
        NSArray*hp=[ap componentsSeparatedByString:@":"]; if(hp.count<2) continue;
        struct hostent*he=gethostbyname([hp[0] UTF8String]); if(!he){ [tried addObject:[NSString stringWithFormat:@"%@ dns",ap]]; continue; }
        struct sockaddr_in sa; memset(&sa,0,sizeof(sa)); sa.sin_family=AF_INET; sa.sin_port=htons([hp[1] intValue]); memcpy(&sa.sin_addr,he->h_addr,he->h_length);
        NSString*why=nil; int t=tcpConnect(&sa,&why);
        slog(@"ap try %@ -> %@", ap, t>=0?@"ok":why);
        if(t>=0){ s=t; break; }
        [tried addObject:[NSString stringWithFormat:@"%@ %@",ap,why]];
    }
    slog(@"ap socket=%d", s);
    if(s<0){   // apresolve (HTTPS) ging, aber kein Spotify-Server auf keinem Port: Netz sperrt die Ports
        slog(@"ap all failed: %@",[tried componentsJoinedByString:@", "]); if(!apWhy) postOnce(@"MMSpotifyPortsBlocked");   // ohne apresolve eher gar kein Netz als gesperrte Ports
        if(err)*err=apWhy?[NSString stringWithFormat:@"No network (%@)",apWhy]:@"Spotify server not reachable"; return nil; }
    write(s,pkt.bytes,pkt.length);NSMutableData*acc=[NSMutableData dataWithData:pkt];

    unsigned char lb[4];if(rd_all(s,lb,4)){close(s);if(err)*err=@"Handshake interrupted";return nil;}uint32_t blen=ntohl(*(uint32_t*)lb)-4;
    NSMutableData*body=[NSMutableData dataWithLength:blen];if(rd_all(s,body.mutableBytes,blen)){close(s);if(err)*err=@"Handshake-Body";return nil;}
    [acc appendBytes:lb length:4];[acc appendData:body];
    slog(@"handshake body=%u", blen);
    NSData*gs=psub(psub(psub(psub(body,10),10),10),10);if(!gs){close(s);if(err)*err=@"No server key";return nil;}
    slog(@"server gs.len=%lu", (unsigned long)gs.length);
    mbedtls_mpi_read_binary(&GS,gs.bytes,(int)gs.length); mbedtls_mpi_exp_mod(&SH,&GS,&X,&P,NULL); unsigned char shb[96]; mbedtls_mpi_write_binary(&SH,shb,96);

    NSMutableData*data=[NSMutableData data];for(unsigned char i=1;i<=5;i++){NSMutableData*m=[NSMutableData dataWithData:acc];[m appendBytes:&i length:1];unsigned char mac[20];CCHmac(kCCHmacAlgSHA1,shb,96,m.bytes,m.length,mac);[data appendBytes:mac length:20];}
    const unsigned char*dd=data.bytes;unsigned char cmac[20];CCHmac(kCCHmacAlgSHA1,dd,20,acc.bytes,acc.length,cmac);
    NSMutableData*dhr=[NSMutableData data];pbytes(dhr,10,[NSData dataWithBytes:cmac length:20]);NSMutableData*lcr=[NSMutableData data];pmsg(lcr,10,dhr);
    NSMutableData*resp=[NSMutableData data];pmsg(resp,10,lcr);pmsg(resp,20,[NSData data]);pmsg(resp,30,[NSData data]);
    uint32_t rsz=htonl(4+(uint32_t)resp.length);NSMutableData*rpkt=[NSMutableData data];[rpkt appendBytes:&rsz length:4];[rpkt appendData:resp];write(s,rpkt.bytes,rpkt.length);

    // Shannon + Login - Session-Kontext bleibt erhalten
    gSock=s; shn_key(&gSnd,dd+20,32);shn_key(&gRcv,dd+52,32);
    NSMutableData*sys=[NSMutableData data];pvarf(sys,10,0);pvarf(sys,60,3);  // os=IPHONE
    NSMutableData*cre=[NSMutableData data];pmsg(cre,10,credBlob);pmsg(cre,50,sys);
    NSMutableData*lp=[NSMutableData data];unsigned char cc=0xab;[lp appendBytes:&cc length:1];uint16_t pl=htons((uint16_t)cre.length);[lp appendBytes:&pl length:2];[lp appendData:cre];
    shn_nonce_u32(&gSnd,0);shn_encrypt(&gSnd,lp.mutableBytes,(int)lp.length);unsigned char sm[4];shn_finish(&gSnd,sm,4);write(s,lp.bytes,lp.length);write(s,sm,4);

    slog(@"login sent, waiting for reply");
    shn_nonce_u32(&gRcv,0);unsigned char h[3];if(rd_all(s,h,3)){close(s);gSock=-1;slog(@"no reply (rd_all h)");if(err)*err=@"No login reply";return nil;}shn_decrypt(&gRcv,h,3);
    int rcmd=h[0];int rlen=(h[1]<<8)|h[2]; slog(@"raw hdr %02x %02x %02x -> cmd=0x%02x len=%d",h[0],h[1],h[2],rcmd,rlen); if(rlen<0||rlen>8192){close(s);gSock=-1;if(err)*err=@"Implausible reply";return nil;}
    unsigned char*pay=malloc(rlen?rlen:1);if(rlen&&rd_all(s,pay,rlen)){free(pay);close(s);gSock=-1;if(err)*err=@"Reply interrupted";return nil;}
    if(rlen)shn_decrypt(&gRcv,pay,rlen);unsigned char rmac[4];rd_all(s,rmac,4);
    slog(@"resp cmd=0x%02x len=%d", rcmd, rlen);
    NSString*user=nil;
    if(rcmd==0xac){
        NSData*w=[NSData dataWithBytes:pay length:rlen]; NSData*u=psub(w,10); if(!u)u=psub(w,1);
        if(u)user=[[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding];
        if(!user.length)user=@"Spotify";   // Login OK auch ohne lesbaren Namen
        slog(@"APWelcome user=%@", user);
        // Wiederverwendbare Zugangsdaten sichern (Feld 40) -> nie wieder Passwort/Browser
        NSData*reusable=psub(w,40);
        // Anderer (oder unbekannter) Nutzer -> zwischengespeicherte Web-API-Daten des Vorgängers verwerfen
        NSString*prev=[[NSString stringWithContentsOfFile:MMPath(@".spotify-user") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(![prev isEqualToString:user]){
            NSFileManager*fm=[NSFileManager defaultManager];
            for(NSString*f in [fm contentsOfDirectoryAtPath:MMPath(@".spotcache") error:NULL]) if([f hasPrefix:@"api_"]) [fm removeItemAtPath:[MMPath(@".spotcache") stringByAppendingPathComponent:f] error:NULL];
            slog(@"User changed (%@ -> %@): API cache cleared", prev?:@"-", user);
        }
        if(reusable.length){ [reusable writeToFile:MMPath(@".spotify-creds") atomically:YES];
            [user writeToFile:MMPath(@".spotify-user") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            slog(@"reusable creds gesichert (%lu B)", (unsigned long)reusable.length); }
    }
    else if(rcmd==0xad){ gLoginRejected=YES; NSData*w=[NSData dataWithBytes:pay length:rlen]; slog(@"AuthFailure body=%@", hexd(w.bytes,(int)(w.length<32?w.length:32))); if(err)*err=@"Login rejected (token expired?)"; }
    else { if(err)*err=[NSString stringWithFormat:@"Unexpected reply (0x%02x)",rcmd]; }
    free(pay);
    mbedtls_mpi_free(&P);mbedtls_mpi_free(&G);mbedtls_mpi_free(&X);mbedtls_mpi_free(&GC);mbedtls_mpi_free(&GS);mbedtls_mpi_free(&SH);
    if(rcmd==0xac){ gSend=1; gRecv=1; return user; }  // Session offen lassen
    close(s); gSock=-1; return nil;
}

+ (BOOL)lastLoginRejected { return gLoginRejected; }

// Serielle Queue: die Session (Socket+Shannon) darf nur von EINEM Thread genutzt werden.
static dispatch_queue_t spotQ(void){
    static dispatch_queue_t q; static dispatch_once_t o;
    dispatch_once(&o, ^{ q=dispatch_queue_create("mesh.spot.session", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// LoginCredentials bauen: Feld 10=username, 20=typ (1=STORED,3=TOKEN), 30=auth_data.
static NSData* credStored(NSString*user,NSData*creds){ NSMutableData*c=[NSMutableData data]; pstr(c,10,user); pvarf(c,20,1); pbytes(c,30,creds); return c; }
static NSData* credToken(NSString*token){ NSMutableData*c=[NSMutableData data]; pvarf(c,20,3); pbytes(c,30,[token dataUsingEncoding:NSUTF8StringEncoding]); return c; }

+ (void)loginWithToken:(NSString *)token completion:(void(^)(BOOL,NSString*,NSString*))done {
    dispatch_async(spotQ(), ^{
        NSString *err=nil; NSString *user=[self doLoginCred:credToken(token) err:&err];
        if(user) gToken=token;
        dispatch_async(dispatch_get_main_queue(), ^{ done(user!=nil, user, err); });
    });
}

+ (BOOL)hasStoredCreds {
    NSData*c=[NSData dataWithContentsOfFile:MMPath(@".spotify-creds")];
    NSString*u=[NSString stringWithContentsOfFile:MMPath(@".spotify-user") encoding:NSUTF8StringEncoding error:NULL];
    return c.length>0 && u.length>0;
}

+ (void)loginStoredWithCompletion:(void(^)(BOOL,NSString*,NSString*))done {
    dispatch_async(spotQ(), ^{
        NSData*c=[NSData dataWithContentsOfFile:MMPath(@".spotify-creds")];
        NSString*su=[[NSString stringWithContentsOfFile:MMPath(@".spotify-user") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *err=nil, *u=nil;
        if(c.length && su.length) u=[self doLoginCred:credStored(su,c) err:&err];
        else err=@"No saved login";
        dispatch_async(dispatch_get_main_queue(), ^{ done(u!=nil, u, err); });
    });
}

// User-Token (Streaming + persönliche Daten) laden / über Refresh erneuern.
static void loadUserToken(void){
    NSString*ut=[[NSString stringWithContentsOfFile:MMPath(@".spotify-usertoken") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(ut.length) gToken=ut;
}
// Erneuert den Zugang über den Refresh-Token. Spotify tauscht den Refresh-Token dabei aus -> nie zwei Erneuerungen
// gleichzeitig: wer wartet und danach einen neuen Zugang vorfindet, nimmt den (sonst scheitert er mit dem alten Schlüssel).
static BOOL gRefreshDead=NO;            // Spotify hat den Refresh-Token abgelehnt -> nur dann neu koppeln
static NSTimeInterval gRefreshedAt=0;
static BOOL refreshUserToken(void){
    NSString*failed=gToken;                                   // der Zugang, der gerade abgelehnt wurde
    static NSObject*lock; static dispatch_once_t o; dispatch_once(&o,^{ lock=[NSObject new]; });
    @synchronized(lock){
        NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
        if(gToken.length && (![gToken isEqualToString:failed?:@""] || now-gRefreshedAt<20)) return YES;   // ein anderer war schneller
        NSString*rt=[[NSString stringWithContentsOfFile:MMPath(@".spotify-userrefresh") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(!rt.length){ gRefreshDead=YES; return NO; }
        // Playback-Token stammt vom librespot-Client (public PKCE) -> ohne Secret erneuern
        NSArray*hdr=@[@"Content-Type: application/x-www-form-urlencoded"];
        NSString*body=[NSString stringWithFormat:@"grant_type=refresh_token&refresh_token=%@&client_id=65b708073fc0480ea92a077233ca87bd",rt];
        int st=0; NSData*d=httpsReq(@"POST",@"accounts.spotify.com",@"/api/token",hdr,[body dataUsingEncoding:NSUTF8StringEncoding],&st);
        NSDictionary*j=d.length?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        NSString*at=[j isKindOfClass:[NSDictionary class]]?j[@"access_token"]:nil, *nrt=[j isKindOfClass:[NSDictionary class]]?j[@"refresh_token"]:nil;
        slog(@"refreshUserToken HTTP %d -> %@", st, at.length?@"ok":@"fail");
        if(at.length){
            if(nrt.length)[nrt writeToFile:MMPath(@".spotify-userrefresh") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [at writeToFile:MMPath(@".spotify-usertoken") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            gToken=at; gRefreshedAt=now; gRefreshDead=NO; return YES;
        }
        if(st==400||st==401) gRefreshDead=YES;                // abgelehnt (nicht: kein Netz)
        return NO;
    }
}

static BOOL ensureApi(NSString**err){
    if(gSock<0){ if(err)*err=@"not logged in"; return NO; }
    if(!gClientToken){ gClientToken=getClientToken(); }
    if(!gClientToken){ if(err)*err=@"No client token"; return NO; }
    if(!gSpclient){
        // Server für Titel/Schlüssel: erst über iOS, dann über das eigene TLS (iOS 7 und manche Netze lehnen das iOS-HTTPS ab),
        // zuletzt der allgemeine Name, der immer auf einen solchen Server zeigt. Vorher hieß das: kein Titel spielt ("No spclient host").
        NSData*spd=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=spclient"]];
        if(!spd.length){ int st=0; spd=httpsReq(@"GET",@"apresolve.spotify.com",@"/?type=spclient",@[],nil,&st); if(st!=200) spd=nil;
            slog(@"spclient: iOS HTTPS failed, own TLS %@",spd.length?@"ok":@"failed too"); }
        id j=spd.length?[NSJSONSerialization JSONObjectWithData:spd options:0 error:NULL]:nil;
        id list=[j isKindOfClass:[NSDictionary class]]?j[@"spclient"]:nil;
        gSpclient=([list isKindOfClass:[NSArray class]] && [list count] && [list[0] isKindOfClass:[NSString class]])?list[0]:nil;
        if(!gSpclient){ gSpclient=@"spclient.wg.spotify.com:443"; slog(@"spclient: apresolve unavailable, using %@",gSpclient); }
    }
    if(!gSpclient){ if(err)*err=@"No spclient host"; return NO; }
    return YES;
}

// Session neu aufbauen (gespeicherte Zugangsdaten), wenn die AP-Verbindung abgerissen ist.
static BOOL reconnectStored(void){
    NSData*c=[NSData dataWithContentsOfFile:MMPath(@".spotify-creds")];
    NSString*su=[[NSString stringWithContentsOfFile:MMPath(@".spotify-user") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!c.length||!su.length) return NO;
    if(gSock>=0){ close(gSock); gSock=-1; }
    NSString*e=nil; NSString*u=[MMSpotify doLoginCred:credStored(su,c) err:&e];
    slog(@"reconnect -> %@", u?u:@"fail");
    return u!=nil;
}
// Mercury mit Auto-Reconnect bei abgerissener Session.
static NSData* mercuryRC(NSString*uri){
    NSData*d=mercuryGet(uri);
    if(d.length) return d;
    slog(@"mercury empty -> reconnect");
    if(reconnectStored()) d=mercuryGet(uri);
    return d;
}

// Nur Metadaten (schnell) -> {title, artist, cover-URL}. Session muss offen sein.
+ (NSDictionary *)metaOnly:(NSString *)b62 err:(NSString **)err {
    if(gSock<0 && !reconnectStored()){ if(err)*err=@"not logged in"; return nil; }
    unsigned char gidb[16]; base62ToGid(b62,gidb);
    NSData*meta=mercuryRC([NSString stringWithFormat:@"hm://metadata/4/track/%@",hexd(gidb,16)]);
    if(!meta.length){ if(err)*err=@"No metadata"; return nil; }
    NSString*title=psub(meta,2)?[[NSString alloc] initWithData:psub(meta,2) encoding:NSUTF8StringEncoding]:@"?";
    NSString*artist=@""; NSArray*arts=psubs(meta,4); if(arts.count){NSData*an=psub(arts[0],2); if(an)artist=[[NSString alloc] initWithData:an encoding:NSUTF8StringEncoding];}
    NSString*cover=@""; NSData*album=psub(meta,3);
    if(album){NSData*cg=psub(album,17); if(cg){NSArray*imgs=psubs(cg,1); if(imgs.count){NSData*fid=psub(imgs.lastObject,1); if(fid)cover=[NSString stringWithFormat:@"https://i.scdn.co/image/%@",hexd(fid.bytes,(int)fid.length)];}}}
    NSMutableDictionary*info=[NSMutableDictionary dictionaryWithObjectsAndKeys:title,@"title",artist,@"artist",cover,@"cover",nil];
    NSString*alid=album?gidToBase62(psub(album,1)):nil; if(alid) info[@"albumId"]=alid;
    if(album&&psub(album,2)) info[@"album"]=[[NSString alloc] initWithData:psub(album,2) encoding:NSUTF8StringEncoding]?:@"";
    NSString*arid=arts.count?gidToBase62(psub(arts[0],1)):nil; if(arid) info[@"artistId"]=arid;
    int64_t zz=pvarval(meta,7); if(zz>0){ int64_t ms=(zz>>1)^-(zz&1); if(ms>0) info[@"durMs"]=@(ms); }   // Länge (sint32, ZigZag)
    return info;
}

// ---- Cache: mehrere vorab geladene/entschlüsselte Tracks (LRU) ----
#define CACHE_MAX 2
static NSMutableDictionary *gCache=nil;   // trackId -> NSData (entschlüsseltes Ogg)
static NSMutableArray *gCacheOrder=nil;    // LRU, ältester zuerst
static NSMutableSet *gInflight=nil;        // Tracks, die gerade vorgeladen werden
// Alle drei immer zusammen anlegen und nur über cacheLock() sperren. (Früher legte cacheGet gCache allein an; dann blieben
// LRU-Liste und Vorlade-Menge nil: jeder gespielte Song blieb im RAM, und "auf laufendes Vorladen warten" griff nie.)
static void cacheInit(void){ static dispatch_once_t once; dispatch_once(&once, ^{ gCache=[NSMutableDictionary dictionary]; gCacheOrder=[NSMutableArray array]; gInflight=[NSMutableSet set]; }); }
static id cacheLock(void){ cacheInit(); return gCache; }
static NSData* cacheGet(NSString*tid){ @synchronized(cacheLock()){ NSData*d=gCache[tid]; if(d){ [gCacheOrder removeObject:tid]; [gCacheOrder addObject:tid]; } return d; } }
static void cachePut(NSString*tid,NSData*d){ @synchronized(cacheLock()){ cacheInit(); if(gCache[tid])[gCacheOrder removeObject:tid]; gCache[tid]=d; [gCacheOrder addObject:tid]; while(gCacheOrder.count>CACHE_MAX){ NSString*old=gCacheOrder[0]; [gCacheOrder removeObjectAtIndex:0]; [gCache removeObjectForKey:old]; } } }
// ---- Offline-Disk-Cache (heruntergeladene Playlists) ----
static NSString* diskDir(void){ NSString*d=MMPath(@".spotcache"); [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL]; return d; }
static NSString* diskPath(NSString*tid){ return [NSString stringWithFormat:@"%@/%@.ogg", diskDir(), tid]; }
static BOOL diskHas(NSString*tid){ return tid.length && [[NSFileManager defaultManager] fileExistsAtPath:diskPath(tid)]; }

// ---- Song-Cache für gestreamte Titel ----
// Gestreamte Songs bleiben entschlüsselt in .spotcache/stream liegen: nochmal Abspielen braucht kein Netz.
// Höchstens 500 MB und nie so viel, dass weniger als 1 GB frei bleibt; der am längsten nicht gespielte fliegt zuerst.
// Offline-Downloads haben Vorrang: ein Song aus dem Cache wird dorthin verschoben, und bei voller Platte wird der Cache geleert.
#define STREAM_MAX   (500LL*1024*1024)
#define STREAM_FLOOR (1024LL*1024*1024)
static NSString* streamDir(void){ NSString*d=MMPath(@".spotcache/stream"); [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL]; return d; }
static NSString* streamPath(NSString*tid){ return [NSString stringWithFormat:@"%@/%@.ogg", streamDir(), tid]; }
static BOOL streamHas(NSString*tid){ return tid.length && [[NSFileManager defaultManager] fileExistsAtPath:streamPath(tid)]; }
static dispatch_queue_t streamQ(void){ static dispatch_queue_t q; static dispatch_once_t o; dispatch_once(&o,^{ q=dispatch_queue_create("spotify6.streamcache",DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(q,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0)); }); return q; }
// Älteste löschen, bis höchstens `max` Bytes belegt sind und STREAM_FLOOR frei bleibt. Nur auf streamQ.
static long long streamTrim(long long max, NSString*keep){
    NSString*dir=streamDir(); NSMutableArray*files=[NSMutableArray array]; long long total=0;
    for(NSString*f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]){
        if(![f hasSuffix:@".ogg"]) continue;
        struct stat st; NSString*p=[dir stringByAppendingPathComponent:f];
        if(stat(p.fileSystemRepresentation,&st)!=0) continue;
        total+=st.st_size; [files addObject:@[p,@(st.st_size),@(st.st_mtime)]];
    }
    [files sortUsingComparator:^NSComparisonResult(NSArray*a,NSArray*b){ return [a[2] compare:b[2]]; }];   // ältester zuerst
    long long freeB=[MMSpotify freeDiskBytes];
    for(NSArray*e in files){
        if(total<=max && freeB>=STREAM_FLOOR) break;
        if(keep && [[e[0] lastPathComponent] isEqualToString:[keep stringByAppendingString:@".ogg"]]) continue;
        if(unlink([e[0] fileSystemRepresentation])==0){ total-=[e[1] longLongValue]; freeB+=[e[1] longLongValue]; }
    }
    return total;
}
static void streamStore(NSString*tid, NSData*d){
    if(!tid.length || !d.length) return;
    dispatch_async(streamQ(), ^{ @autoreleasepool {
        if(diskHas(tid) || streamHas(tid)) return;   // Offline-Song oder schon im Cache
        if([MMSpotify freeDiskBytes]-(long long)d.length < STREAM_FLOOR){ streamTrim(STREAM_MAX,nil); if([MMSpotify freeDiskBytes]-(long long)d.length < STREAM_FLOOR) return; }
        if([d writeToFile:streamPath(tid) atomically:YES]) streamTrim(STREAM_MAX,tid);
    }});
}
static NSData* streamLoad(NSString*tid){
    if(!streamHas(tid)) return nil;
    NSString*p=streamPath(tid); NSData*d=[NSData dataWithContentsOfFile:p];
    if(d.length) utimes(p.fileSystemRepresentation,NULL);   // Änderungszeit = zuletzt gespielt
    return d;
}

// Volle Audio-Kette: Datei + AudioKey + CDN(voll) + Entschlüsseln -> entschlüsseltes Ogg (nil bei Fehler).
// Läuft IMMER auf spotQ (Socket ist single-threaded).
// Nur der SOCKET-Teil (Metadaten + AudioKey + CDN-Adresse). MUSS auf spotQ laufen (ein Socket).
static NSArray*gLastCdns;   // alle CDN-Adressen der letzten Auflösung (Diagnose)
// Liefert die CDN-URL + den 16-Byte-AES-Key. Der große Download passiert danach woanders.
+ (BOOL)resolveTrack:(NSString *)b62 cdn:(NSString **)cdnOut key:(NSData **)keyOut err:(NSString **)err {
    slog(@"resolve %@ (sock=%d)", b62, gSock);
    CFAbsoluteTime T0=CFAbsoluteTimeGetCurrent(), T=T0; NSMutableArray*steps=[NSMutableArray array];   // Zeit pro Schritt (zeigt, wo es hängt)
    #define STEP(name) do{ CFAbsoluteTime n_=CFAbsoluteTimeGetCurrent(); [steps addObject:[NSString stringWithFormat:@"%@ %.1fs",name,n_-T]]; T=n_; }while(0)
    #define STEPLOG() slog(@"resolve steps %@: %@ (total %.1fs)", b62, [steps componentsJoinedByString:@", "], CFAbsoluteTimeGetCurrent()-T0)
    if(gSock<0 && !reconnectStored()){ STEP(@"connect fail"); STEPLOG(); if(err)*err=@"not logged in"; return NO; }
    STEP(@"connect");
    if(!ensureApi(err)){ slog(@"resolve ensureApi fail"); STEP(@"api fail"); STEPLOG(); return NO; }
    unsigned char gidb[16]; base62ToGid(b62,gidb);
    NSData*meta=mercuryRC([NSString stringWithFormat:@"hm://metadata/4/track/%@",hexd(gidb,16)]);
    STEP(@"metadata");
    if(!meta.length){ STEPLOG(); if(err)*err=@"No metadata"; return NO; }
    // 3GS (600 MHz, Vorbis in Software): höchstens 160 kbit/s. Rang: 1=OGG_160 vor 0=OGG_96 vor 2=OGG_320 (nur als letzte Wahl).
    NSData*fileId=nil;int bestFmt=-1;unsigned char keyGid[16];memcpy(keyGid,gidb,16);
    for(NSData*af in psubs(meta,12)){int64_t fmt=pvarval(af,2);NSData*fid=psub(af,1);
        if(fid&&fmtRank(fmt)>bestFmt){bestFmt=fmtRank(fmt);fileId=fid;}}
    if(!fileId){for(NSData*alt in psubs(meta,13)){NSData*ag=psub(alt,1);
        for(NSData*af in psubs(alt,12)){int64_t fmt=pvarval(af,2);NSData*fid=psub(af,1);
            if(fid&&fmtRank(fmt)>bestFmt){bestFmt=fmtRank(fmt);fileId=fid;if(ag.length==16)memcpy(keyGid,ag.bytes,16);}}
        if(fileId)break;}}
    if(!fileId){ STEPLOG(); if(err)*err=@"No playable file"; return NO; }

    static uint32_t gAkSeq=0; uint32_t myseq=++gAkSeq;   // eindeutige Sequenz pro Key-Anfrage (seriell auf spotQ -> kein Race)
    NSMutableData*akr=[NSMutableData data];[akr appendData:fileId];[akr appendBytes:keyGid length:16];
    uint32_t akseq=htonl(myseq);[akr appendBytes:&akseq length:4];uint16_t z=0;[akr appendBytes:&z length:2];
    sendpkt(0x0c,akr);
    unsigned char audiokey[16];int haveKey=0,cmd;
    for(int i=0;i<80;i++){NSData*r=recvpkt(&cmd);if(!r)break;if(cmd==0x04){sendpkt(0x49,r);continue;}
        if(cmd==0x0d && r.length>=20){ uint32_t rs=ntohl(*(const uint32_t*)r.bytes);
            if(rs!=myseq){ slog(@"audiokey stale seq %u != %u -> skip",(unsigned)rs,(unsigned)myseq); continue; }
            memcpy(audiokey,(const unsigned char*)r.bytes+4,16);haveKey=1;break; }
        if(cmd==0x0e){ uint32_t rs=(r.length>=4)?ntohl(*(const uint32_t*)r.bytes):myseq;
            if(rs!=myseq){ continue; }
            const unsigned char*rb=r.bytes; NSInteger code=(r.length>=6)?((rb[4]<<8)|rb[5]):-1;
            gKeyLastCode=code; gKeyRefusedRow++; gKeyRefusedTotal++;
            slog(@"AesKeyError code %ld (account type %@, refused %ld in a row)",(long)code,gProductType?:@"?",(long)gKeyRefusedRow);
            if(accountKeysRefused()) postOnce(@"MMSpotifyKeysRefused");
            break; }}
    STEP(@"key");
    if(haveKey){ gKeyEverOK=YES; gKeyRefusedRow=0; }
    if(!haveKey){ slog(@"no AudioKey for %@",b62); STEPLOG(); if(err)*err=@"no AudioKey"; return NO; }

    loadUserToken();
    NSString*srp=[NSString stringWithFormat:@"/storage-resolve/files/audio/interactive/%@",hexd(fileId.bytes,(int)fileId.length)];
    NSData*sr=spclientGet(srp);
    if(!sr){ if(refreshUserToken()) sr=spclientGet(srp); }
    NSString*cdn=nil; NSMutableArray*all=[NSMutableArray array];
    if(sr){ for(NSData*u in psubs(sr,2)){ NSString*x=[[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding]; if(x.length)[all addObject:x]; } }
    cdn=all.firstObject; gLastCdns=all;
    { NSMutableArray*hosts=[NSMutableArray array]; for(NSString*x in all){ NSString*h=[NSURL URLWithString:x].host; if(h)[hosts addObject:h]; } slog(@"cdn hosts: %@",[hosts componentsJoinedByString:@" "]); }
    STEP(@"cdn-url");
    if(!cdn.length){ STEPLOG(); if(err)*err=@"No CDN URL"; return NO; }
    STEPLOG();
    #undef STEP
    #undef STEPLOG
    if(cdnOut)*cdnOut=cdn; if(keyOut)*keyOut=[NSData dataWithBytes:audiokey length:16];
    slog(@"resolve ok fmt=%s cdn=%@", bestFmt==3?"ogg160":bestFmt==2?"ogg96":"ogg320", cdn);
    return YES;
}

// AES-128-CTR (Zähler big-endian ab AUDIO_IV) mit mbedTLS: CommonCryptos CTR zählt unter iOS 5 den Zähler falsch hoch
// (ab Byte 16 Datenmüll -> stb_vorbis Fehler 30). Auf dem 3GS ist mbedTLS gleich schnell (8 MB: 0.73 s, CommonCrypto 0.78 s).
typedef struct { mbedtls_aes_context ac; unsigned char ctr[16], stream[16]; size_t off; } MMCtr;   // CTR-Zustand über Häppchen hinweg
static MMCtr* ctrNew(const void*key){ MMCtr*c=calloc(1,sizeof(MMCtr)); mbedtls_aes_init(&c->ac); mbedtls_aes_setkey_enc(&c->ac,key,128); memcpy(c->ctr,AUDIO_IV,16); return c; }
static void ctrRun(MMCtr*c,const void*in,void*out,size_t n){ mbedtls_aes_crypt_ctr(&c->ac,n,&c->off,c->ctr,c->stream,in,out); }
static void ctrFree(MMCtr*c){ if(c){ mbedtls_aes_free(&c->ac); free(c); } }
static void aesCTR_mbed(const void*key,const void*in,void*out,size_t n){
    mbedtls_aes_context ac; mbedtls_aes_init(&ac); mbedtls_aes_setkey_enc(&ac,key,128);
    unsigned char ctr[16],stream[16]; size_t off=0; memcpy(ctr,AUDIO_IV,16);
    mbedtls_aes_crypt_ctr(&ac,n,&off,ctr,stream,in,out); mbedtls_aes_free(&ac);
}

// Großer CDN-Download + AES-CTR-Entschlüsselung. Braucht KEINEN Socket -> darf abseits der spotQ laufen.
+ (NSData *)downloadDecrypt:(NSString *)cdn key:(NSData *)keyData err:(NSString **)err { return [self downloadDecrypt:cdn key:keyData err:err progress:nil]; }
+ (NSData *)downloadDecrypt:(NSString *)cdn key:(NSData *)keyData err:(NSString **)err progress:(void(^)(double frac))progress {
    NSError*ne=nil; CFAbsoluteTime t0=CFAbsoluteTimeGetCurrent();
    NSMutableData*enc=cdnFetch(cdn,&ne,progress);
    slog(@"cdn download %@: %.1f MB in %.1fs%@",[NSURL URLWithString:cdn].host,enc.length/1048576.0,CFAbsoluteTimeGetCurrent()-t0,ne?[@" error: " stringByAppendingString:ne.localizedDescription]:@"");
    if(!enc.length){ if(err)*err=[NSString stringWithFormat:@"CDN download failed (%@)",ne.localizedDescription?:@"empty"]; return nil; }
    CFAbsoluteTime t1=CFAbsoluteTimeGetCurrent();
    NSMutableData*out=enc;   // an Ort und Stelle (mbedTLS-CTR erlaubt gleichen Ein- und Ausgabepuffer): keine zweite Kopie in Songgröße
    aesCTR_mbed(keyData.bytes,enc.bytes,out.mutableBytes,enc.length);
    slog(@"decrypt %.1f MB in %.2fs",enc.length/1048576.0,CFAbsoluteTimeGetCurrent()-t1);
    return out;
}

+ (NSData *)loadAudioData:(NSString *)b62 err:(NSString **)err {
    NSString*cdn=nil; NSData*key=nil;
    if(![self resolveTrack:b62 cdn:&cdn key:&key err:err]) return nil;   // Socket-Teil (kurz)
    return [self downloadDecrypt:cdn key:key err:err];                   // großer Download
}

+ (BOOL)doPlay:(NSString *)b62 err:(NSString **)err {
    NSData*out=[self loadAudioData:b62 err:err];
    if(!out.length) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio playOgg:out]; });
    return YES;
}

// Track im Voraus laden+entschlüsseln und in den Cache (für nahtlosen Übergang)
+ (void)prefetchTrack:(NSString *)trackId {
    if(!trackId.length) return;
    if(cacheGet(trackId) || diskHas(trackId)) return;   // schon im RAM oder heruntergeladen
    // Lädt gerade ein angetippter Titel: nicht um die Bandbreite konkurrieren, danach vorladen
    @synchronized([MMSpotify class]){ if(gPlayDownloads>0){ gDeferredPrefetch=trackId; slog(@"prefetch %@ zurückgestellt (Titel lädt noch)",trackId); return; } }
    @synchronized(cacheLock()){ cacheInit(); if([gInflight containsObject:trackId]) return; [gInflight addObject:trackId]; }
    // Nur das kurze Auflösen (Socket) läuft auf der spotQ; der große Download daneben, damit ein angetippter Titel nicht
    // hinter dem ganzen Vorab-Download warten muss.
    void (^finish)(NSData*,BOOL,NSString*)=^(NSData*d,BOOL hit,NSString*e){
        if(d.length){ cachePut(trackId,d); slog(@"prefetch bereit: %@%@", trackId, hit?@" (Song-Cache)":@""); } else slog(@"prefetch fail: %@ (%@)",trackId,e);
        @synchronized(cacheLock()){ [gInflight removeObject:trackId]; }
    };
    dispatch_async(spotQ(), ^{
        if(cacheGet(trackId)){ @synchronized(cacheLock()){ [gInflight removeObject:trackId]; } return; }
        NSData*sd=streamLoad(trackId); if(sd.length){ finish(sd,YES,nil); return; }
        NSString*cdn=nil, *e=nil; NSData*key=nil;
        if(![self resolveTrack:trackId cdn:&cdn key:&key err:&e]){ finish(nil,NO,e); return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
            NSString*e2=nil; NSData*d=[self downloadDecrypt:cdn key:key err:&e2]; if(d.length) streamStore(trackId,d); finish(d,NO,e2); });
    });
}

// ---- Offline: Tracks herunterladen / Status ----
+ (BOOL)isDownloaded:(NSString *)trackId { return diskHas(trackId); }
+ (BOOL)playableOffline:(NSString *)trackId { return trackId.length && (diskHas(trackId) || streamHas(trackId) || cacheGet(trackId)); }
+ (BOOL)allDownloaded:(NSArray *)trackIds {
    if(!trackIds.count) return NO;
    BOOL any=NO;   // Titel, die Spotify nicht liefern kann, zählen nicht dagegen (aber mindestens einer muss da sein)
    for(NSString*t in trackIds){ if(diskHas(t)) any=YES; else if(!isUnavailable(t)) return NO; }
    return any;
}
// ===== Globaler Download-Manager mit Warteschlange =====
// Mehrere Playlists werden hintereinander abgearbeitet (keine zwei Ketten gleichzeitig).
// Pro Track: kurzer Socket-Teil (resolve) auf spotQ, großer Download auf dlDataQ -> Playback bleibt frei.
// Status geht per Notification raus: MMDownloadProgress {done,total}, MMDownloadDone {ok}, MMDownloadFull.
static NSMutableArray *gDlQueue=nil; static BOOL gDlRunning=NO; static NSInteger gDlDone=0, gDlTotal=0; static NSInteger gDlFails=0;
static double gDlLastT=0, gDlAvg=0;   // Zeit pro Titel (gleitender Mittelwert) für "noch etwa … Min."
static NSMutableSet *gDlSeen=nil;  // bereits in gDlTotal gezählte Track-IDs (gegen Doppelzählung über mehrere queue-Aufrufe)
// Background-Task: gibt dem Download beim Verlassen der App Gnadenfrist (auch ohne Musikwiedergabe)
static UIBackgroundTaskIdentifier gDlBg=(UIBackgroundTaskIdentifier)NSUIntegerMax;  // ==UIBackgroundTaskInvalid, aber als Compile-Time-Konstante
static void dlBgBegin(void){ dispatch_async(dispatch_get_main_queue(), ^{ if(gDlBg==UIBackgroundTaskInvalid) gDlBg=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ if(gDlBg!=UIBackgroundTaskInvalid){ [[UIApplication sharedApplication] endBackgroundTask:gDlBg]; gDlBg=UIBackgroundTaskInvalid; } }]; }); }
static void dlBgEnd(void){ dispatch_async(dispatch_get_main_queue(), ^{ if(gDlBg!=UIBackgroundTaskInvalid){ [[UIApplication sharedApplication] endBackgroundTask:gDlBg]; gDlBg=UIBackgroundTaskInvalid; } }); }
static dispatch_queue_t dlDataQ(void){ static dispatch_queue_t q; static dispatch_once_t o; dispatch_once(&o,^{ q=dispatch_queue_create("mesh.dl.data",DISPATCH_QUEUE_SERIAL); }); return q; }

static NSString *offlinePath(void); static NSArray* spTracks(NSArray*ids); static void dlinfoRemember(NSArray*ids);   // weiter unten definiert
// Titel, für die Spotify keine Audiodatei hat ("No playable file": entfernt, gesperrt, nie lizenziert). Sonst lud jeder Start
// sie erneut, die Leiste zeigte "135 von 136" und zählte den Fehlschlag dann als geladen. Nach 7 Tagen wird es neu versucht.
#define DL_UNAVAIL_RETRY (7*24*3600)
static NSInteger gDlUnavail=0;   // in diesem Durchgang übersprungen (für die Abschlussmeldung)
static NSString* unavailPath(void){ return [diskDir() stringByAppendingPathComponent:@"unavailable.plist"]; }
static NSMutableDictionary* unavailDict(void){   // Track-ID -> Zeitpunkt (NSDate) des Fehlschlags; nur unter @synchronized(unavailDict()) benutzen
    static NSMutableDictionary*d; static dispatch_once_t o;
    dispatch_once(&o,^{ NSDictionary*f=[NSDictionary dictionaryWithContentsOfFile:unavailPath()]; d=f?[f mutableCopy]:[NSMutableDictionary dictionary]; });
    return d;
}
static BOOL isUnavailable(NSString*tid){
    NSMutableDictionary*d=unavailDict(); @synchronized(d){ NSDate*t=d[tid]; return [t isKindOfClass:[NSDate class]] && -[t timeIntervalSinceNow]<DL_UNAVAIL_RETRY; }
}
static void setUnavailable(NSString*tid, BOOL on){
    NSMutableDictionary*d=unavailDict(); @synchronized(d){ if(!on && !d[tid]) return; if(on) d[tid]=[NSDate date]; else [d removeObjectForKey:tid]; [d writeToFile:unavailPath() atomically:YES]; }
}
+ (NSDictionary *)downloadStatus {
    @synchronized([MMSpotify class]){
        NSArray*q=gDlQueue?[gDlQueue copy]:@[]; NSInteger left=(NSInteger)q.count;
        return @{@"queue":q,@"done":@(gDlDone),@"total":@(gDlTotal),@"eta":@(gDlAvg>0?gDlAvg*left:-1)};
    }
}
+ (NSArray *)downloadedTracks {
    NSMutableArray*out=[NSMutableArray array]; NSString*dir=diskDir();
    for(NSString*f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]){
        if(![f hasSuffix:@".ogg"]) continue;
        struct stat st; if(stat([dir stringByAppendingPathComponent:f].fileSystemRepresentation,&st)!=0) continue;
        [out addObject:@{@"id":[f stringByDeletingPathExtension],@"bytes":@(st.st_size),@"date":@(st.st_mtime)}];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){ return [b[@"date"] compare:a[@"date"]]; }];   // neueste zuerst
    return out;
}
+ (void)deleteDownload:(NSString *)tid {
    if(!tid.length) return;
    [[NSFileManager defaultManager] removeItemAtPath:diskPath(tid) error:NULL];
    @synchronized([MMSpotify class]){   // auch aus den gemerkten Offline-Listen, sonst lädt der Auto-Resume ihn wieder
        NSMutableArray*arr=[NSMutableArray array];
        for(NSDictionary*e in [NSArray arrayWithContentsOfFile:offlinePath()]){
            if(![e isKindOfClass:[NSDictionary class]]) continue;
            NSMutableArray*ids=[e[@"ids"] mutableCopy]; [ids removeObject:tid];
            if(ids.count){ NSMutableDictionary*m=[e mutableCopy]; m[@"ids"]=ids; [arr addObject:m]; }
        }
        [arr writeToFile:offlinePath() atomically:YES];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadsChanged" object:nil]; });
}
+ (void)trackInfos:(NSArray *)ids completion:(void(^)(NSDictionary *byId))done {
    dispatch_async(spotQ(), ^{
        NSMutableDictionary*by=[NSMutableDictionary dictionary];
        for(NSUInteger i=0;i<ids.count;i+=50){
            for(NSDictionary*t in spTracks([ids subarrayWithRange:NSMakeRange(i,MIN(50,ids.count-i))])){
                NSArray*ar=t[@"artists"]; NSArray*im=t[@"album"][@"images"];
                by[t[@"id"]]=@{@"title":t[@"name"]?:@"",@"artist":ar.count?(ar[0][@"name"]?:@""):@"",@"cover":im.count?(im[0][@"url"]?:@""):@""};
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(by); });
    });
}
+ (BOOL)isDownloading { @synchronized([MMSpotify class]){ return gDlRunning; } }
+ (void)postDlProgress {
    NSInteger d,t; @synchronized([MMSpotify class]){ d=gDlDone; t=gDlTotal; }
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadProgress" object:nil userInfo:@{@"done":@(d),@"total":@(t)}]; });
}
+ (void)queueDownloadTracks:(NSArray *)trackIds {
    if(![trackIds isKindOfClass:[NSArray class]] || !trackIds.count) return;
    BOOL start=NO;
    @synchronized([MMSpotify class]){
        if(!gDlQueue) gDlQueue=[NSMutableArray array];
        if(!gDlSeen) gDlSeen=[NSMutableSet set];
        for(NSString*tid in trackIds){
            if(![tid isKindOfClass:[NSString class]]||!tid.length) continue;
            if([gDlSeen containsObject:tid]) continue;   // schon in dieser Session gezählt
            [gDlSeen addObject:tid];
            if(!diskHas(tid) && isUnavailable(tid)){ gDlUnavail++; continue; }   // Spotify hat keine Datei: nicht mitzählen, nicht laden
            gDlTotal++;                                   // zählt in den Nenner (ganze Playlist)
            if(diskHas(tid)){ gDlDone++; }                // schon offline -> auch in den Zähler (Balken bleibt, springt nicht auf 0)
            else [gDlQueue addObject:tid];                // fehlt -> zum Herunterladen einreihen
        }
        if(!gDlRunning){ gDlRunning=YES; start=YES; gDlLastT=CFAbsoluteTimeGetCurrent(); }
    }
    [self postDlProgress];
    if(start){ dlBgBegin(); [self dlStep]; }
}
+ (void)dlFinishTrack:(NSString *)tid {
    @synchronized([MMSpotify class]){
        double now=CFAbsoluteTimeGetCurrent(), dt=now-gDlLastT; gDlLastT=now;
        if(dt>1 && dt<600) gDlAvg=gDlAvg>0?0.7*gDlAvg+0.3*dt:dt;   // sofort fertige (schon da) zählen nicht
        if(gDlQueue.count && [gDlQueue[0] isEqualToString:tid]) [gDlQueue removeObjectAtIndex:0]; gDlDone++; }
    [self postDlProgress];
    // kleine Pause zwischen Tracks -> senkt Dauer-Stromzug/Wärme (schont schwachen Akku) und lässt Playback durch
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)), dispatch_get_global_queue(0,0), ^{ [MMSpotify dlStep]; });
}
+ (void)dlSkipUnavailable:(NSString *)tid {
    @synchronized([MMSpotify class]){
        if(gDlQueue.count && [gDlQueue[0] isEqualToString:tid]) [gDlQueue removeObjectAtIndex:0];
        if(gDlTotal>0) gDlTotal--; gDlUnavail++; }   // aus dem Nenner nehmen: "135 von 135" statt "136 von 136" mit einem Fehlschlag
    [self postDlProgress];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)), dispatch_get_global_queue(0,0), ^{ [MMSpotify dlStep]; });
}
+ (void)dlStep {
    NSString*tid=nil; BOOL finished=NO;
    @synchronized([MMSpotify class]){ if(gDlQueue.count==0){ gDlRunning=NO; finished=YES; } else tid=gDlQueue[0]; }
    if(finished){
        NSInteger okc, una; @synchronized([MMSpotify class]){ okc=gDlDone; una=gDlUnavail; gDlDone=0; gDlTotal=0; gDlUnavail=0; [gDlSeen removeAllObjects]; }
        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadDone" object:nil userInfo:@{@"ok":@(okc),@"unavailable":@(una)}]; });
        dlBgEnd();
        return;
    }
    dispatch_async(spotQ(), ^{   // NUR der kurze Socket-Teil blockiert spotQ
        @autoreleasepool {
            if(diskHas(tid)){ [MMSpotify dlFinishTrack:tid]; return; }
            __block BOOL moved=NO;   // schon im Song-Cache -> nur verschieben, nicht neu laden
            dispatch_sync(streamQ(), ^{ moved=streamHas(tid) && rename(streamPath(tid).fileSystemRepresentation, diskPath(tid).fileSystemRepresentation)==0; });
            if(moved){ slog(@"dl %@ aus dem Song-Cache übernommen",tid); dlinfoRemember(@[tid]); [MMSpotify dlFinishTrack:tid]; return; }
            if([MMSpotify freeDiskBytes] < 80*1024*1024) dispatch_sync(streamQ(), ^{ streamTrim(0,nil); });   // Song-Cache für Downloads freigeben
            if([MMSpotify freeDiskBytes] < 80*1024*1024){   // Platte voll -> abbrechen
                @synchronized([MMSpotify class]){ [gDlQueue removeAllObjects]; gDlRunning=NO; gDlDone=0; gDlTotal=0; gDlUnavail=0; [gDlSeen removeAllObjects]; }
                dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadFull" object:nil userInfo:nil]; });
                dlBgEnd();
                return;
            }
            NSString*cdn=nil; NSData*key=nil; NSString*e=nil;
            if(![MMSpotify resolveTrack:tid cdn:&cdn key:&key err:&e]){
                gDlFails++;
                slog(@"dl resolve fail #%ld %@ (%@)",(long)gDlFails,tid,e);
                BOOL keyIssue = (e && [e rangeOfString:@"AudioKey"].location!=NSNotFound) || (e && [e rangeOfString:@"logged in"].location!=NSNotFound);
                if(keyIssue){
                    // Spotify-Rate-Limit: NICHT überspringen, sondern denselben Track mit Backoff erneut.
                    // Verweigert Spotify dem Konto die Schlüssel ganz (neue Konten), hilft kein Wiederholen -> sofort stoppen
                    if(gDlFails>=12 || accountKeysRefused()){   // trotz Backoff/Reconnect dauerhaft -> sauber stoppen
                        if(gSock>=0){ close(gSock); gSock=-1; }
                        @synchronized([MMSpotify class]){ [gDlQueue removeAllObjects]; gDlRunning=NO; gDlDone=0; gDlTotal=0; gDlUnavail=0; [gDlSeen removeAllObjects]; }
                        gDlFails=0; slog(@"dl ABBRUCH: %@",accountKeysRefused()?@"Spotify verweigert diesem Konto die Schlüssel":@"12 Key-Fehler");
                        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadError" object:nil userInfo:nil]; });
                        dlBgEnd();
                        return;
                    }
                    if(gDlFails%3==0){ if(gSock>=0){ close(gSock); gSock=-1; } slog(@"dl reconnect (frisches Key-Kontingent)"); }  // alle 3 Fehler neu verbinden
                    double backoff=MIN((double)gDlFails,6.0)*2.5;   // 2.5s..15s hochzählen
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(backoff*NSEC_PER_SEC)), dispatch_get_global_queue(0,0), ^{ [MMSpotify dlStep]; });  // SELBER Track erneut (nicht aus Queue)
                    return;
                }
                gDlFails=0;
                if([e isEqualToString:@"No playable file"]){ setUnavailable(tid,YES); [MMSpotify dlSkipUnavailable:tid]; return; }   // merken, nicht als geladen zählen
                [MMSpotify dlFinishTrack:tid]; return;   // echtes Track-Problem -> überspringen
            }
            gDlFails=0;   // Erfolg -> Fehlerzähler zurücksetzen
            dispatch_async(dlDataQ(), ^{   // großer Download OHNE spotQ zu blockieren
                @autoreleasepool {
                    NSString*e2=nil; NSData*d=[MMSpotify downloadDecrypt:cdn key:key err:&e2];
                    if(d.length){ [d writeToFile:diskPath(tid) atomically:YES]; dlinfoRemember(@[tid]); setUnavailable(tid,NO); }
                    [MMSpotify dlFinishTrack:tid];
                }
            });
        }
    });
}
+ (void)removeDownloads:(NSArray *)trackIds {
    for(NSString*t in trackIds){ if(diskHas(t)) [[NSFileManager defaultManager] removeItemAtPath:diskPath(t) error:NULL]; }
}

// ---- Offline-Playlists dauerhaft merken (für Auto-Resume) ----
static NSString *offlinePath(void){ return [diskDir() stringByAppendingPathComponent:@"offline.plist"]; }
+ (void)markOffline:(NSString *)name trackIds:(NSArray *)trackIds {
    if(!trackIds.count) return;
    @synchronized([MMSpotify class]){
        NSMutableArray *arr=[[NSArray arrayWithContentsOfFile:offlinePath()] mutableCopy]?:[NSMutableArray array];
        for(NSInteger i=(NSInteger)arr.count-1;i>=0;i--){ if([arr[i][@"ids"] isEqualToArray:trackIds] || [arr[i][@"name"] isEqualToString:name?:@""]) [arr removeObjectAtIndex:i]; }
        [arr addObject:@{@"name":name?:@"", @"ids":trackIds}];
        [[NSFileManager defaultManager] createDirectoryAtPath:diskDir() withIntermediateDirectories:YES attributes:nil error:NULL];
        [arr writeToFile:offlinePath() atomically:YES];
    }
}
+ (void)unmarkOffline:(NSArray *)trackIds {
    @synchronized([MMSpotify class]){
        NSMutableArray *arr=[[NSArray arrayWithContentsOfFile:offlinePath()] mutableCopy]; if(!arr) return;
        for(NSInteger i=(NSInteger)arr.count-1;i>=0;i--){ if([arr[i][@"ids"] isEqualToArray:trackIds]) [arr removeObjectAtIndex:i]; }
        [arr writeToFile:offlinePath() atomically:YES];
    }
}
+ (void)resumeOfflineDownloads {
    NSArray *arr=[NSArray arrayWithContentsOfFile:offlinePath()]; if(!arr.count) return;
    // GESAMTE Offline-Liste reichen (nicht nur fehlende): queueDownloadTracks zählt bereits geladene
    // in Zähler+Nenner -> Balken setzt beim Fortsetzen an der echten Prozentzahl an, nicht auf 0.
    NSMutableArray *all=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set]; NSUInteger miss=0;
    for(NSDictionary *e in arr){ if(![e isKindOfClass:[NSDictionary class]])continue;
        for(NSString *tid in e[@"ids"]){ if([tid isKindOfClass:[NSString class]] && tid.length && ![seen containsObject:tid]){ [seen addObject:tid]; [all addObject:tid]; if(!diskHas(tid) && !isUnavailable(tid)) miss++; } } }
    if(miss){ slog(@"resume offline: %lu fehlende von %lu Tracks weiterladen", (unsigned long)miss, (unsigned long)all.count); [self queueDownloadTracks:all]; }
}
+ (long long)freeDiskBytes {
    NSDictionary*a=[[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    NSNumber*n=a[NSFileSystemFreeSize];
    return n?[n longLongValue]:0;
}
+ (long long)songCacheBytes { __block long long n=0; dispatch_sync(streamQ(), ^{ n=streamTrim(STREAM_MAX,nil); }); return n; }
+ (void)clearSongCache { dispatch_async(streamQ(), ^{ [[NSFileManager defaultManager] removeItemAtPath:streamDir() error:NULL]; }); }
+ (long long)cacheBytes {
    NSFileManager*fm=[NSFileManager defaultManager];
    NSArray*files=[fm contentsOfDirectoryAtPath:diskDir() error:NULL];
    long long sum=0;
    for(NSString*f in files){ if(![f hasSuffix:@".ogg"]) continue; NSDictionary*a=[fm attributesOfItemAtPath:[diskDir() stringByAppendingPathComponent:f] error:NULL]; sum+=[a[NSFileSize] longLongValue]; }
    return sum;
}

+ (void)fetchTrack:(NSString *)trackId completion:(void(^)(NSDictionary*,NSString*))done {
    dispatch_async(spotQ(), ^{
        NSString*err=nil; NSDictionary*info=[self metaOnly:trackId err:&err];
        dispatch_async(dispatch_get_main_queue(), ^{ done(info, err); });
    });
}

static NSUInteger gPlayGen=0;   // jede Wiedergabe-Anfrage zählt hoch; nur die neueste darf am Ende abspielen
+ (void)playTrack:(NSString *)trackId completion:(void(^)(BOOL,NSString*))done { [self playTrack:trackId stream:YES completion:done]; }
static NSInteger gPlayDownloads=0; static NSString*gStreamingId=nil, *gDeferredPrefetch=nil; static __weak MMAudioStream*gStreamingObj=nil;   // angetippter Titel lädt gerade (Vorladen wartet)
#define STREAM_START (512*1024)   // ab so vielen Bytes spielt der Titel schon (der Rest lädt weiter)
// stream=NO: erst ganz laden (z. B. Fortsetzen an einer gespeicherten Stelle: Spulen braucht die ganze Datei)
+ (void)playTrack:(NSString *)trackId stream:(BOOL)stream completion:(void(^)(BOOL,NSString*))done {
    // Läuft genau dieser Titel schon als Stream: nichts stoppen, nichts neu starten (vor dem Hochzählen, damit sein Start gilt)
    // (nur wenn genau dieser Stream gerade zu hören ist; sonst normal neu laden)
    BOOL same; @synchronized([MMSpotify class]){ same=[gStreamingId isEqualToString:trackId] && gStreamingObj && gStreamingObj==[MMAudio currentStream]; }
    if(same && stream && [MMAudio isBuffering]){ slog(@"playTrack %@ spielt schon (lädt noch)",trackId);
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(YES,nil); }); return; }
    NSUInteger gen; @synchronized([MMSpotify class]){ gen=++gPlayGen; }
    // Cache-Hit (RAM vorgeladen) -> sofort abspielen, kein Netz. Heruntergeladene Titel liest der Block unten von der Platte
    // (mehrere MB: auf dem Main-Thread hielt das die Oberfläche spürbar an)
    NSData*cd=cacheGet(trackId);
    if(cd){ gLoading=NO; slog(@"playTrack Cache-Hit %@", trackId);
        dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio playOgg:cd]; if(done)done(YES,nil); });
        return;
    }
    gLoading=YES;
    dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio stop]; });  // alten Track sofort stoppen
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{   // Song-Cache lesen, ohne hinter einem Vorladen auf der spotQ zu warten
        NSData*sd=nil; BOOL disk=NO;
        if(diskHas(trackId)){ sd=[NSData dataWithContentsOfFile:diskPath(trackId)]; disk=sd.length>0; }
        if(!sd.length) sd=streamLoad(trackId);
        if(sd.length){ cachePut(trackId,sd);
            BOOL current; @synchronized([MMSpotify class]){ current=(gen==gPlayGen); }
            if(!current){ slog(@"playTrack %@ überholt (neuerer Titel angetippt)",trackId); return; }
            gLoading=NO; slog(@"playTrack %@ %@",disk?@"Disk-Hit":@"Song-Cache-Hit",trackId);
            dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio playOgg:sd]; if(done)done(YES,nil); });
            return; }
        void (^play)(NSData*,NSString*)=^(NSData*d,NSString*err){
            BOOL current; @synchronized([MMSpotify class]){ current=(gen==gPlayGen); }
            if(!current){ slog(@"playTrack %@ überholt (neuerer Titel angetippt)",trackId); return; }   // Daten liegen trotzdem im Cache
            if(!d.length) slog(@"playTrack fail %@: %@", trackId, err?:@"?");
            gLoading=NO;
            dispatch_async(dispatch_get_main_queue(), ^{ if(d.length)[MMAudio playOgg:d]; if(done)done(d.length>0,err); });
        };
        // Wird genau dieser Titel gerade vorgeladen: darauf warten statt ein zweites Mal herunterzuladen
        BOOL inflight; @synchronized(cacheLock()){ cacheInit(); inflight=[gInflight containsObject:trackId]; }
        if(inflight){ CFAbsoluteTime tw=CFAbsoluteTimeGetCurrent();
            while(CFAbsoluteTimeGetCurrent()-tw<90){ BOOL still, current; @synchronized(cacheLock()){ still=[gInflight containsObject:trackId]; } @synchronized([MMSpotify class]){ current=(gen==gPlayGen); }
                if(!still || !current) break; usleep(200000); }
            NSData*pd=cacheGet(trackId); slog(@"playTrack %@: Vorladen abgewartet (%.1fs)%@",trackId,CFAbsoluteTimeGetCurrent()-tw,pd?@"":@", ohne Erfolg");
            if(pd.length){ play(pd,nil); return; } }
        // sonst: nur das kurze Auflösen auf der spotQ, Download daneben (nicht hinter einem anderen Vorab-Download).
        // Solange er lädt, steht der Titel in gInflight: ein zweiter Tipp (oder ein Vorladen) wartet darauf.
        @synchronized(cacheLock()){ [gInflight addObject:trackId]; }
        void (^play0)(NSData*,NSString*)=play;
        play=^(NSData*d,NSString*err){ @synchronized(cacheLock()){ [gInflight removeObject:trackId]; } play0(d,err); };
        dispatch_async(spotQ(), ^{
            NSData*cd2=cacheGet(trackId); if(cd2.length){ play(cd2,nil); return; }
            NSString*cdn=nil, *err=nil; NSData*key=nil;
            if(![self resolveTrack:trackId cdn:&cdn key:&key err:&err]){ play(nil,err); return; }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
                // Wiedergabe während des Downloads: Häppchen gleich entschlüsseln und ab STREAM_START schon abspielen
                @synchronized([MMSpotify class]){ gPlayDownloads++; gStreamingId=trackId; }
                __block MMAudioStream*st=nil; __block NSUInteger off=0; __block BOOL started=NO;
                MMCtr*cs=ctrNew(key.bytes); CFAbsoluteTime t0=CFAbsoluteTimeGetCurrent(); NSError*ne=nil;
                NSMutableData*full=cdnFetchEx(cdn,&ne,^(double f){   // grüner Ladebalken in Leiste/Player
                        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:MMTrackLoadProgress object:nil userInfo:@{@"id":trackId,@"frac":@(f)}]; }); },
                    ^BOOL(long long expected){ if(!stream || expected<=STREAM_START || st) return NO;   // klein, Länge unbekannt oder Fortsetzen: wie bisher ganz laden
                        st=[[MMAudioStream alloc] initWithLength:(NSUInteger)expected]; if(!st.data) return NO;
                        @synchronized([MMSpotify class]){ gStreamingObj=st; } return YES; },
                    ^BOOL(NSData*chunk){
                        if(!started){ BOOL cur; @synchronized([MMSpotify class]){ cur=(gen==gPlayGen); } if(!cur) return NO; }   // vor dem Start überholt: Download abbrechen
                        NSUInteger n=MIN(chunk.length,st.data.length-off);
                        ctrRun(cs,chunk.bytes,(unsigned char*)st.data.mutableBytes+off,n); off+=n;
                        OSMemoryBarrier(); st.avail=off;   // erst die Bytes, dann die Grenze (Mehrkern-iPads)
                        if(!started && off>=STREAM_START){ started=YES;
                            BOOL current; @synchronized([MMSpotify class]){ current=(gen==gPlayGen); }
                            if(current){ gLoading=NO; slog(@"stream %@: spielt nach %.1fs (%.1f von %.1f MB)",trackId,CFAbsoluteTimeGetCurrent()-t0,off/1048576.0,st.data.length/1048576.0);
                                MMAudioStream*s2=st; dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio playStream:s2]; if(done)done(YES,nil); }); } }
                        return YES; });
                NSData*d=nil; NSString*e2=ne?[NSString stringWithFormat:@"CDN download failed (%@)",ne.localizedDescription]:nil;
                if(st){ OSMemoryBarrier(); if(!ne && off==st.data.length){ st.complete=YES; d=st.data; } else st.failed=YES; }   // lief die Wiedergabe schon, hört sie am Ende des Geladenen auf
                else if(full.length){ ctrRun(cs,full.bytes,full.mutableBytes,full.length); d=full; }
                ctrFree(cs);
                slog(@"cdn download %@: %.1f MB in %.1fs%@%@",[NSURL URLWithString:cdn].host,(st?off:full.length)/1048576.0,CFAbsoluteTimeGetCurrent()-t0,st?@" (Stream)":@"",ne?[@" error: " stringByAppendingString:ne.localizedDescription]:@"");
                NSString*dp=nil;
                @synchronized([MMSpotify class]){ gPlayDownloads--; if([gStreamingId isEqualToString:trackId]) gStreamingId=nil; if(!gPlayDownloads){ dp=gDeferredPrefetch; gDeferredPrefetch=nil; } }
                if(d.length){ cachePut(trackId,d); streamStore(trackId,d); }   // gespielten Track auch cachen (zurück = sofort, später ohne Netz)
                if(started){ @synchronized(cacheLock()){ [gInflight removeObject:trackId]; } if(!d.length) slog(@"playTrack fail %@: %@", trackId, e2?:@"?"); }
                else play(d,e2);
                if(dp){ slog(@"prefetch %@ nachgeholt",dp); [self prefetchTrack:dp]; }   // nachgeholtes Vorladen des nächsten Titels
            });
        });
    });
}

// Verbindungstest für "Debug info": jeder Schritt mit Zeitlimit, Ergebnis Zeile für Zeile (auf dem Main-Thread)
+ (void)runConnectionTest:(void(^)(NSString *line))line done:(void(^)(void))done {
    void(^out)(NSString*)=^(NSString*l){ slog(@"test: %@",l); dispatch_async(dispatch_get_main_queue(), ^{ line(l); }); };
    dispatch_async(dispatch_get_global_queue(0,0), ^{ @autoreleasepool {
        out([self networkReachable]?@"Network: online":@"Network: OFFLINE");
        // 1. Spotify-Serverliste über HTTPS (eigenes TLS)
        CFAbsoluteTime t0=CFAbsoluteTimeGetCurrent(); int st=0;
        NSData*ad=httpsReq(@"GET",@"apresolve.spotify.com",@"/?type=accesspoint",@[],nil,&st);
        NSArray*aps=ad?[NSJSONSerialization JSONObjectWithData:ad options:0 error:NULL][@"accesspoint"]:nil;
        out([NSString stringWithFormat:@"Server list (HTTPS): %@ (%.1fs)",aps.count?[NSString stringWithFormat:@"%lu servers",(unsigned long)aps.count]:[NSString stringWithFormat:@"FAILED, HTTP %d",st],CFAbsoluteTimeGetCurrent()-t0]);
        // 2. jeden Spotify-Server direkt verbinden (das ist der Weg für Songs und Downloads)
        NSUInteger okc=0;
        for(NSString*ap in [aps subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)6,aps.count))]){
            NSArray*hp=[ap componentsSeparatedByString:@":"]; if(hp.count<2) continue;
            t0=CFAbsoluteTimeGetCurrent(); struct hostent*he=gethostbyname([hp[0] UTF8String]);
            if(!he){ out([NSString stringWithFormat:@"%@: DNS failed",ap]); continue; }
            struct sockaddr_in sa; memset(&sa,0,sizeof sa); sa.sin_family=AF_INET; sa.sin_port=htons([hp[1] intValue]); memcpy(&sa.sin_addr,he->h_addr,he->h_length);
            NSString*why=nil; int t=tcpConnect(&sa,&why); if(t>=0){ close(t); okc++; }
            out([NSString stringWithFormat:@"%@: %@ (%.1fs)",ap,t>=0?@"ok":[why uppercaseString],CFAbsoluteTimeGetCurrent()-t0]);
        }
        if(aps.count && !okc) out(@"=> Spotify's ports seem BLOCKED on this network");
        // 3. Song über die Spotify-Verbindung auflösen (Metadaten + Schlüssel + Download-Adresse), höchstens 45 s
        __block NSString*cdn=nil, *e=nil; __block BOOL ok=NO; dispatch_semaphore_t sem=dispatch_semaphore_create(0); t0=CFAbsoluteTimeGetCurrent();
        dispatch_async(spotQ(), ^{ NSString*c=nil, *er=nil; NSData*k=nil; ok=[self resolveTrack:@"0DiWol3AO6WpXZgp0goxAV" cdn:&c key:&k err:&er]; cdn=c; e=er; dispatch_semaphore_signal(sem); });
        if(dispatch_semaphore_wait(sem,dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC))){ out(@"Song lookup: NO ANSWER after 45s (Spotify connection stuck)"); }
        else out([NSString stringWithFormat:@"Song lookup + key: %@ (%.1fs)",ok?@"ok":[NSString stringWithFormat:@"FAILED: %@",e?:@"?"],CFAbsoluteTimeGetCurrent()-t0]);
        out([NSString stringWithFormat:@"Account: %@ · Country: %@",gProductType?:@"unknown",gCountry?:@"?"]);
        // 4. Song-Datei vom Download-Server laden (iOS-Netz, wie beim Abspielen)
        if(ok && cdn.length){
            NSURL*u=[NSURL URLWithString:cdn]; NSError*ne=nil; t0=CFAbsoluteTimeGetCurrent();
            NSData*d=[NSData dataWithContentsOfURL:u options:0 error:&ne];
            out([NSString stringWithFormat:@"Download %@: %@ (%.1fs)",u.host,d.length?[NSString stringWithFormat:@"%.1f MB ok",d.length/1048576.0]:[NSString stringWithFormat:@"FAILED %@",ne.localizedDescription?:@""],CFAbsoluteTimeGetCurrent()-t0]);
        }
        out(@"Test finished.");
        dispatch_async(dispatch_get_main_queue(), ^{ if(done) done(); });
    }});
}
+ (NSString *)productType { return gProductType; }
+ (NSString *)keyStatus {
    if(gKeyEverOK) return gKeyRefusedTotal?[NSString stringWithFormat:@"ok (%ld refused, last code %ld)",(long)gKeyRefusedTotal,(long)gKeyLastCode]:@"ok";
    if(gKeyRefusedTotal) return [NSString stringWithFormat:@"REFUSED %ld times, code %ld",(long)gKeyRefusedTotal,(long)gKeyLastCode];
    return @"not tried yet";
}
+ (NSString *)country { return gCountry; }
// Für "Fehlerinfos": nur die aussagekräftigen Zeilen, Download-Adressen ohne Schlüssel
+ (NSString *)diagnosticLog {
    NSString*all=[NSString stringWithContentsOfFile:MMPath(@".spotify-log") encoding:NSUTF8StringEncoding error:NULL]?:@"";   // Datei wird bei jeder Zeile neu geschrieben
    NSArray*keys=@[@"=== login",@"tls:",@"apresolve",@"ap ",@"handshake",@"no reply",@"Login",@"AuthFailure",@"reconnect",@"account type",@"country",@"resolve",@"AesKeyError",@"AudioKey",@"cdn",@"CDN",@"playTrack",@"fail",@"timeout",@"Unexpected",@"not reachable",@"dl ",@"test:"];
    NSMutableArray*out=[NSMutableArray array];
    NSRegularExpression*url=[NSRegularExpression regularExpressionWithPattern:@"(https?://[^/\\s]+)\\S*" options:0 error:NULL];
    for(NSString*l in [all componentsSeparatedByString:@"\n"]){
        if(!l.length || [l hasPrefix:@"resp head"]) continue;
        BOOL hit=NO; for(NSString*k in keys) if([l rangeOfString:k].location!=NSNotFound){ hit=YES; break; }
        if(hit) [out addObject:[url stringByReplacingMatchesInString:l options:0 range:NSMakeRange(0,l.length) withTemplate:@"$1/…"]];
    }
    if(out.count>70) [out removeObjectsInRange:NSMakeRange(0,out.count-70)];
    return [out componentsJoinedByString:@"\n"];
}
+ (NSData *)httpsGet:(NSURL *)url {
    if(![url.scheme isEqualToString:@"https"] || !url.host.length) return nil;
    NSString*path=url.path.length?url.path:@"/"; if(url.query.length) path=[path stringByAppendingFormat:@"?%@",url.query];
    int st=0; NSData*d=httpsReq(@"GET",url.host,path,@[],nil,&st);
    return (st==200 && d.length)?d:nil;
}
+ (NSString *)deviceModel { char b[64]={0}; size_t n=sizeof b; sysctlbyname("hw.machine",b,&n,NULL,0); return [NSString stringWithUTF8String:b]; }
+ (BOOL)isLoading { return gLoading; }

// ---- mbedTLS-HTTPS (iOS-6-TLS zu accounts/api.spotify.com ist zu alt -> selber TLS 1.2) ----
static int mmEntropy(void*d,unsigned char*o,size_t n){ (void)d; for(size_t i=0;i<n;i++)o[i]=arc4random()&0xff; return 0; }
// Vertrauenswürdige Wurzelzertifikate (Resources/roots.pem = Apples System-Roots), einmal geladen.
// NULL = nicht ladbar -> httpsReq baut KEINE Verbindung auf (nie ungeprüft weiter).
static mbedtls_x509_crt* caChain(void){
    static mbedtls_x509_crt ca; static BOOL ok=NO; static dispatch_once_t o;
    dispatch_once(&o,^{
        if(psa_crypto_init()!=PSA_SUCCESS){ slog(@"tls: psa_crypto_init fail"); return; }   // TLS 1.3 braucht PSA
        mbedtls_x509_crt_init(&ca);
        NSMutableData*pem=[[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"]] mutableCopy];
        if(!pem.length){ slog(@"tls: roots.pem fehlt"); return; }
        [pem appendBytes:"" length:1];   // PEM-Parser braucht abschließendes NUL
        NSTimeInterval t0=[NSDate timeIntervalSinceReferenceDate];
        int bad=mbedtls_x509_crt_parse(&ca,pem.bytes,pem.length);
        int n=0; for(mbedtls_x509_crt*c=&ca;c&&c->raw.len;c=c->next) n++;
        slog(@"tls: %d roots loaded (%d unreadable) in %.0f ms",n,bad>0?bad:0,([NSDate timeIntervalSinceReferenceDate]-t0)*1000);
        ok=(bad>=0 && n>0);
    });
    return ok?&ca:NULL;
}
static NSData* dechunk(NSData*d){
    NSMutableData*out=[NSMutableData data]; const unsigned char*b=d.bytes; NSUInteger n=d.length,p=0;
    while(p<n){ NSUInteger e=p; while(e<n && b[e]!='\r')e++; if(e>=n)break;
        char tmp[16]; NSUInteger len=e-p; if(len>15)len=15; memcpy(tmp,b+p,len); tmp[len]=0;
        long sz=strtol(tmp,NULL,16); p=e+2; if(sz<=0)break; if(p+(NSUInteger)sz>n)sz=(long)(n-p);
        [out appendBytes:b+p length:sz]; p+=sz+2; }
    return out;
}
// Ein Versuch. only12 = nur TLS 1.2 anbieten. *hsFail = 1, wenn die Verbindung stand, aber der TLS-Handshake scheiterte.
static NSData* httpsReqOnce(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut,BOOL only12,int*hsFail,MMHttpHead onHead,MMHttpData onData){
    if(statusOut)*statusOut=0; if(hsFail)*hsFail=0;
    mbedtls_net_context srv; mbedtls_ssl_context ssl; mbedtls_ssl_config conf; mbedtls_ctr_drbg_context ctr;
    mbedtls_net_init(&srv); mbedtls_ssl_init(&ssl); mbedtls_ssl_config_init(&conf); mbedtls_ctr_drbg_init(&ctr);
    NSData*result=nil; const char*h=[host UTF8String];
    mbedtls_x509_crt*ca=caChain();
    if(!ca){ slog(@"tls: no roots -> %@ refused",host); goto done; }
    if(mbedtls_ctr_drbg_seed(&ctr,mmEntropy,NULL,(const unsigned char*)"mmspot",6)!=0) goto done;
    if(mbedtls_net_connect(&srv,h,"443",MBEDTLS_NET_PROTO_TCP)!=0){ slog(@"tls: connect %@ fail",host); goto done; }
    if(mbedtls_ssl_config_defaults(&conf,MBEDTLS_SSL_IS_CLIENT,MBEDTLS_SSL_TRANSPORT_STREAM,MBEDTLS_SSL_PRESET_DEFAULT)!=0) goto done;
    mbedtls_ssl_conf_authmode(&conf,MBEDTLS_SSL_VERIFY_REQUIRED);   // Zertifikat + Hostname müssen stimmen
    mbedtls_ssl_conf_ca_chain(&conf,ca,NULL);
    mbedtls_ssl_conf_rng(&conf,mbedtls_ctr_drbg_random,&ctr);
    if(only12) mbedtls_ssl_conf_max_tls_version(&conf,MBEDTLS_SSL_VERSION_TLS1_2);
    mbedtls_ssl_conf_read_timeout(&conf,20000);   // 20 s ohne Daten = aufgeben (sonst hängt ein stockender Download für immer)
#ifdef DEBUG
    if(!only12 && [[NSFileManager defaultManager] fileExistsAtPath:MMPath(@".tls13fail")]){ slog(@"tls: handshake %@ fail (test: .tls13fail)",host); if(hsFail)*hsFail=1; goto done; }   // Test des Rückfalls auf TLS 1.2
#endif
    if(mbedtls_ssl_setup(&ssl,&conf)!=0) goto done;
    mbedtls_ssl_set_hostname(&ssl,h);
    mbedtls_ssl_set_bio(&ssl,&srv,mbedtls_net_send,mbedtls_net_recv,mbedtls_net_recv_timeout);
    { int hs; while((hs=mbedtls_ssl_handshake(&ssl))!=0){ if(hs!=MBEDTLS_ERR_SSL_WANT_READ&&hs!=MBEDTLS_ERR_SSL_WANT_WRITE){
            // lesbar: Fehlertext, angebotene Versionen und (falls geprüft) was am Zertifikat nicht stimmt
            char et[96]=""; mbedtls_strerror(hs,et,sizeof et); uint32_t vf=mbedtls_ssl_get_verify_result(&ssl); char vi[160]="";
            if(vf && vf!=0xffffffff){ mbedtls_x509_crt_verify_info(vi,sizeof vi,"",vf); for(char*c=vi;*c;c++) if(*c=='\n') *c=';'; }
            slog(@"tls: handshake %@ fail -0x%04x %s (offered %@)%@",host,-hs,et,only12?@"TLS 1.2":@"TLS 1.2+1.3",
                 vf==0xffffffff?@", certificate not checked yet":vf?[NSString stringWithFormat:@", certificate: %s",vi]:@"");
            if(hsFail)*hsFail=1; goto done; } } }
    { static NSMutableSet*seen; @synchronized([NSObject class]){ if(!seen) seen=[NSMutableSet set];   // einmal je Host: welche Version zustande kam
        if(![seen containsObject:host]){ [seen addObject:host]; slog(@"tls: %@ ok, %s",host,mbedtls_ssl_get_version(&ssl)); } } }
    { NSMutableString*req=[NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n",method,path,host];
      for(NSString*x in extra)[req appendFormat:@"%@\r\n",x];
      [req appendFormat:@"Content-Length: %lu\r\n\r\n",(unsigned long)body.length];
      NSMutableData*rd=[[req dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
      if(body.length)[rd appendData:body];
      const unsigned char*wp=rd.bytes; size_t wl=rd.length,wo=0;
      while(wo<wl){ int w=mbedtls_ssl_write(&ssl,wp+wo,wl-wo); if(w<=0){ if(w==MBEDTLS_ERR_SSL_WANT_READ||w==MBEDTLS_ERR_SSL_WANT_WRITE)continue; goto done; } wo+=w; } }
    { NSMutableData*resp=[NSMutableData data]; unsigned char buf[16384]; NSData*sep=[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
      BOOL streaming=NO, stopped=NO; long long want=-1, got=0;
      for(;;){ int rr=mbedtls_ssl_read(&ssl,buf,sizeof(buf)); if(rr==MBEDTLS_ERR_SSL_WANT_READ||rr==MBEDTLS_ERR_SSL_WANT_WRITE)continue; if(rr<=0)break;
        if(streaming){ got+=rr; if(!onData(buf,rr)){ stopped=YES; break; } if(want>=0 && got>=want) break; continue; }
        [resp appendBytes:buf length:rr];
        if(onData){ NSRange hr=[resp rangeOfData:sep options:0 range:NSMakeRange(0,resp.length)];   // Kopf da: ab jetzt durchreichen (nicht bei chunked)
          if(hr.location!=NSNotFound){
            NSString*hs=[[NSString alloc] initWithData:[resp subdataWithRange:NSMakeRange(0,hr.location)] encoding:NSUTF8StringEncoding]?:@"";
            if([hs rangeOfString:@"chunked" options:NSCaseInsensitiveSearch].location==NSNotFound){
              NSArray*pp=[hs componentsSeparatedByString:@" "]; NSInteger st=pp.count>1?[pp[1] integerValue]:0; if(statusOut)*statusOut=(int)st;
              NSRange cl=[hs rangeOfString:@"\r\nContent-Length:" options:NSCaseInsensitiveSearch];
              if(cl.location!=NSNotFound) want=[[hs substringFromIndex:NSMaxRange(cl)] longLongValue];
              streaming=YES; if(onHead) onHead(st,want);
              NSUInteger bo=hr.location+4; got=resp.length-bo;
              if(got>0 && !onData((const unsigned char*)resp.bytes+bo,(size_t)got)){ stopped=YES; break; }
              resp=nil; if(want>=0 && got>=want) break; } } } }
      if(streaming){ if(!stopped && (want<0 || got>=want)) result=[NSData data]; }   // Erfolg: alles durchgereicht
      NSRange sr=resp?[resp rangeOfData:sep options:0 range:NSMakeRange(0,resp.length)]:NSMakeRange(NSNotFound,0);
      if(sr.location!=NSNotFound){
        NSString*hstr=[[NSString alloc] initWithData:[resp subdataWithRange:NSMakeRange(0,sr.location)] encoding:NSUTF8StringEncoding];
        if(statusOut){ NSArray*pp=[hstr componentsSeparatedByString:@" "]; if(pp.count>1)*statusOut=[pp[1] intValue]; }
        NSData*bd=[resp subdataWithRange:NSMakeRange(sr.location+4,resp.length-sr.location-4)];
        if([hstr rangeOfString:@"chunked" options:NSCaseInsensitiveSearch].location!=NSNotFound) bd=dechunk(bd);
        result=bd;
        if(onData){ NSInteger st=statusOut?*statusOut:200; if(onHead) onHead(st,(long long)bd.length);   // chunked im Streaming-Modus: am Stück
            result=(!bd.length || onData(bd.bytes,bd.length))?[NSData data]:nil; }
      }
    }
done:
    mbedtls_ssl_close_notify(&ssl);
    mbedtls_net_free(&srv); mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&conf); mbedtls_ctr_drbg_free(&ctr);
    return result;
}
// method GET/POST, extra = Array von Header-Zeilen ("Key: Value"), body optional. statusOut optional.
// Scheitert der Handshake (manche Netze, Proxys oder Firewalls lassen TLS 1.3 nicht durch oder verändern es), einmal mit nur TLS 1.2
// nachfassen; klappt das, bleibt dieser Host bis zum Neustart bei TLS 1.2. Vor dem Senden gescheitert -> Wiederholen ist auch für POST sicher.
static NSData* httpsReq(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut){ return httpsReqEx(method,host,path,extra,body,statusOut,nil,nil); }
static NSData* httpsReqEx(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut,MMHttpHead onHead,MMHttpData onData){
    static NSMutableSet*only12; @synchronized([NSObject class]){ if(!only12) only12=[NSMutableSet set]; }
    BOOL o12; @synchronized(only12){ o12=[only12 containsObject:host]; }
    int hs=0; NSData*r=httpsReqOnce(method,host,path,extra,body,statusOut,o12,&hs,onHead,onData);
    if(r || !hs || o12) return r;
    slog(@"tls: %@ retry with TLS 1.2 only",host);
    r=httpsReqOnce(method,host,path,extra,body,statusOut,YES,&hs,onHead,onData);
    if(r){ @synchronized(only12){ [only12 addObject:host]; } slog(@"tls: %@ works with TLS 1.2 only, using that until restart",host); }
    else if(hs) slog(@"tls: %@ fails with TLS 1.3 and 1.2: HTTPS to Spotify is blocked or altered on this network or device (proxy, firewall, VPN or a tweak)",host);
    return r;
}

// Standard-Base64 (mit Padding) für Basic-Auth.
static NSString* b64std(NSData*data){
    static const char*t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char*b=data.bytes; NSUInteger n=data.length; NSMutableString*s=[NSMutableString string];
    for(NSUInteger i=0;i<n;i+=3){ int rem=(int)(n-i); unsigned v=(unsigned)b[i]<<16;
        if(rem>1)v|=(unsigned)b[i+1]<<8; if(rem>2)v|=(unsigned)b[i+2];
        [s appendFormat:@"%c",t[(v>>18)&63]]; [s appendFormat:@"%c",t[(v>>12)&63]];
        [s appendFormat:@"%c",(rem>1)?t[(v>>6)&63]:'=']; [s appendFormat:@"%c",(rem>2)?t[v&63]:'=']; }
    return s;
}
// Client-Credentials App-Token (ID+Secret) - für Katalog/Suche, ohne User-Login. Gecacht + erneuert.
#define KEY_ID_PATH  MMPath(@".spotify-clientid")
#define KEY_SEC_PATH MMPath(@".spotify-secret")
static NSString* gAppToken=nil; static NSTimeInterval gAppExp=0;
static NSString* readTrim(NSString*path){
    return [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
// Fragt bei Spotify einen App-Token an. st = HTTP-Status (0 = keine Verbindung).
static NSDictionary* requestAppToken(NSString*cid,NSString*sec,int*st){
    NSString*basic=b64std([[NSString stringWithFormat:@"%@:%@",cid,sec] dataUsingEncoding:NSUTF8StringEncoding]);
    NSArray*hdr=@[[@"Authorization: Basic " stringByAppendingString:basic],@"Content-Type: application/x-www-form-urlencoded"];
    NSData*d=httpsReq(@"POST",@"accounts.spotify.com",@"/api/token",hdr,[@"grant_type=client_credentials" dataUsingEncoding:NSUTF8StringEncoding],st);
    id j=d.length?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    slog(@"appToken: HTTP %d", *st);
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}
static NSString* appTokenSync(void){
    if(gAppToken && [[NSDate date] timeIntervalSince1970] < gAppExp-60) return gAppToken;
    NSString*cid=readTrim(KEY_ID_PATH), *sec=readTrim(KEY_SEC_PATH);
    if(!cid.length||!sec.length) return nil;
    int st=0; NSDictionary*j=requestAppToken(cid,sec,&st);
    NSString*at=j[@"access_token"]; NSNumber*ex=j[@"expires_in"];
    if(at.length){ gAppToken=at; gAppExp=[[NSDate date] timeIntervalSince1970]+(ex?ex.doubleValue:3600); }
    return gAppToken;
}
+ (BOOL)hasSearchKey { return readTrim(KEY_ID_PATH).length && readTrim(KEY_SEC_PATH).length; }
+ (void)saveSearchKeyId:(NSString *)cid secret:(NSString *)sec completion:(void(^)(BOOL ok, NSString *error))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        int st=0; NSDictionary*j=requestAppToken(cid,sec,&st);
        NSString*at=j[@"access_token"], *err=nil;
        if(at.length){
            NSDictionary*attr=@{NSFilePosixPermissions:@0600};   // nur die App darf den Schlüssel lesen
            NSFileManager*fm=[NSFileManager defaultManager];
            [fm createFileAtPath:KEY_ID_PATH contents:[cid dataUsingEncoding:NSUTF8StringEncoding] attributes:attr];
            [fm createFileAtPath:KEY_SEC_PATH contents:[sec dataUsingEncoding:NSUTF8StringEncoding] attributes:attr];
            NSNumber*ex=j[@"expires_in"]; gAppToken=at; gAppExp=[[NSDate date] timeIntervalSince1970]+(ex?ex.doubleValue:3600);
        }
        else if(st==0) err=NSLocalizedString(@"No connection to Spotify.",nil);
        else if(st==400||st==401) err=NSLocalizedString(@"Spotify doesn't recognize this key. Please check Client ID and Secret.",nil);
        else err=[NSString stringWithFormat:NSLocalizedString(@"Spotify error %d.",nil),st];
        dispatch_async(dispatch_get_main_queue(), ^{ done(at.length>0, err); });
    });
}
+ (void)removeSearchKey {
    [[NSFileManager defaultManager] removeItemAtPath:KEY_ID_PATH error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:KEY_SEC_PATH error:NULL];
    gAppToken=nil; gAppExp=0;
}

// ---- Suche: Web-API mit App-Token (Client-Credentials, nur Katalog, keine Nutzerdaten). Schlüssel liegt NICHT in der App,
//      sondern optional in Library/Riff/.spotify-clientid + .spotify-secret. Fehlt er -> Suche meldet "nicht verfügbar". ----
+ (void)webGet:(NSString *)path completion:(void(^)(NSDictionary *json, NSInteger status))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSString*at=appTokenSync();
        NSArray*hdr=at.length?@[[@"Authorization: Bearer " stringByAppendingString:at]]:@[];
        int st=0; NSData*d=httpsReq(@"GET",@"api.spotify.com",[@"/v1/" stringByAppendingString:path],hdr,nil,&st);
        if(!at.length) st=401;
        slog(@"webGet %@ -> HTTP %d, %lu B: %.120s", path, st, (unsigned long)d.length, d.length?[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String:"(nil)");
        NSDictionary*j=(d.length)?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        if(![j isKindOfClass:[NSDictionary class]]) j=nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(j, st); });
    });
}

// ======================================================================
// Interne Spotify-Server (spclient) - die Web-API (api.spotify.com) gibt dem Login-Token (Client 65b708) nur 429.
// Liefert dieselbe JSON-Form wie die Web-API, damit die Oberfläche unverändert bleibt.
// ======================================================================
#define SP_HOST @"spclient.wg.spotify.com"
static NSString* spUser(void){
    return [[NSString stringWithContentsOfFile:MMPath(@".spotify-user") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
// HTTPS gegen spclient mit dem Login-Token; bei 401 einmal erneuern und wiederholen.
static NSData* spReq(NSString*method,NSString*path,NSData*body,NSString*ctype,NSString*accept,int*st){
    if(!gToken.length) loadUserToken();
    NSData*(^go)(void)=^NSData*{
        NSMutableArray*h=[NSMutableArray array];
        if(gToken.length)[h addObject:[@"Authorization: Bearer " stringByAppendingString:gToken]];
        [h addObject:[@"Accept: " stringByAppendingString:accept]];
        if(ctype)[h addObject:[@"Content-Type: " stringByAppendingString:ctype]];
        return httpsReq(method,SP_HOST,path,h,body,st);
    };
    NSData*d=go();
    if((*st==401||!gToken.length) && refreshUserToken()) d=go();
    slog(@"sp %@ %.80@ -> HTTP %d (%lu B)", method, path, *st, (unsigned long)d.length);
    return d;
}
static NSDictionary* spJSON(NSString*path,int*st){
    NSData*d=spReq(@"GET",path,nil,nil,@"application/json",st);
    id j=(*st==200&&d.length)?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}
static NSString* b64ToHex(NSString*b64){   // Playlist-"picture" (Base64) -> Hex für i.scdn.co
    if(![b64 isKindOfClass:[NSString class]]||!b64.length) return nil;
    static const char*t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    NSMutableData*out=[NSMutableData data]; unsigned acc=0; int bits=0;
    for(NSUInteger i=0;i<b64.length;i++){ unichar c=[b64 characterAtIndex:i]; if(c=='=')break;
        const char*p=strchr(t,(char)c); if(!p||!c) continue;
        acc=(acc<<6)|(unsigned)(p-t); bits+=6; if(bits>=8){ bits-=8; unsigned char b=(acc>>bits)&0xff; [out appendBytes:&b length:1]; } }
    return hexd(out.bytes,(int)out.length);
}
// Von Spotify erzeugte Playlists (Lieblingssongs, "Your Top Songs 20xx", Blends, All-Time) haben kein "picture",
// sondern fertige Bild-Adressen in "pictureSize" -> die Größe "default" (~300 px) nehmen
static NSString* pictureSizeURL(NSDictionary*attrs){
    id ps=attrs[@"pictureSize"]; if(![ps isKindOfClass:[NSArray class]]) return nil;
    NSString*any=nil;
    for(NSDictionary*p in ps){ if(![p isKindOfClass:[NSDictionary class]]||![p[@"url"] isKindOfClass:[NSString class]]) continue;
        if([p[@"targetName"] isEqual:@"default"]) return p[@"url"]; if(!any) any=p[@"url"]; }
    return any;
}
static NSString* trackIdFromUri(NSString*u){ return ([u isKindOfClass:[NSString class]]&&[u hasPrefix:@"spotify:track:"])?[u substringFromIndex:14]:nil; }
static NSString* spStr(NSData*d){ return d?([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]?:@""):@""; }

// Titelinfos gesammelt (eine Anfrage pro 100 Titel) -> Web-API-Track-Dicts in Eingabereihenfolge.
// extended-metadata: Payloads (Track/Album/Artist-Protobuf) für viele URIs auf einmal, 100 pro Anfrage.
// kind: 8 = ARTIST_V4, 9 = ALBUM_V4, 10 = TRACK_V4. Ergebnis: uri -> Payload.
static NSDictionary* spExt(NSArray*uris,int kind,int*stOut){
    NSMutableDictionary*byUri=[NSMutableDictionary dictionary];
    for(NSUInteger off=0;off<uris.count;off+=100){
        NSArray*chunk=[uris subarrayWithRange:NSMakeRange(off,MIN((NSUInteger)100,uris.count-off))];
        NSMutableData*req=[NSMutableData data];
        for(NSString*u in chunk){ NSMutableData*q=[NSMutableData data]; pvarf(q,1,kind);
            NSMutableData*er=[NSMutableData data]; pstr(er,1,u); pmsg(er,2,q); pmsg(req,2,er); }
        int st=0; NSData*d=spReq(@"POST",@"/extended-metadata/v0/extended-metadata",req,@"application/protobuf",@"application/protobuf",&st);
        if(stOut) *stOut=st;
        if(st!=200||!d.length) continue;
        for(NSData*arr in psubs(d,2)) for(NSData*ed in psubs(arr,3)){
            NSString*u=spStr(psub(ed,2)); NSData*any=psub(ed,3); NSData*pl=any?psub(any,2):nil;
            if(u.length && pl.length) byUri[u]=pl;
        }
    }
    return byUri;
}
// ImageGroup (Feld 1 = Image{file_id 1, size 2}) -> i.scdn.co-URL, bevorzugt Größe 0 = DEFAULT (~300px)
static NSString* coverFromGroup(NSData*cg){
    NSString*cover=nil;
    for(NSData*im in (cg?psubs(cg,1):@[])){ NSData*fid=psub(im,1); if(!fid) continue;
        NSString*u=[@"https://i.scdn.co/image/" stringByAppendingString:hexd(fid.bytes,(int)fid.length)];
        if(!cover||pvarval(im,2)==0) cover=u; }
    return cover;
}
// Titelinfos gesammelt -> Web-API-Track-Dicts in Eingabereihenfolge (mit Album- und Artist-IDs).
static NSArray* spTracks(NSArray*ids){
    NSMutableArray*uris=[NSMutableArray array]; for(NSString*tid in ids)[uris addObject:[@"spotify:track:" stringByAppendingString:tid]];
    int st=0; NSDictionary*byUri=spExt(uris,10,&st);   // 10 = TRACK_V4
    NSMutableArray*out=[NSMutableArray array];
    for(NSString*tid in ids){
        NSData*tr=byUri[[@"spotify:track:" stringByAppendingString:tid]]; if(!tr.length) continue;
        NSString*name=spStr(psub(tr,2)); NSArray*arts=psubs(tr,4);
        NSString*artist=arts.count?spStr(psub(arts[0],2)):@"", *arid=arts.count?gidToBase62(psub(arts[0],1)):nil;
        NSData*alb=psub(tr,3); NSString*cover=alb?coverFromGroup(psub(alb,17)):nil, *alid=alb?gidToBase62(psub(alb,1)):nil;
        NSMutableDictionary*a=[@{@"name":artist} mutableCopy]; if(arid) a[@"id"]=arid;
        NSMutableDictionary*al=[@{@"images":cover?@[@{@"url":cover}]:@[],@"name":alb?spStr(psub(alb,2)):@""} mutableCopy]; if(alid) al[@"id"]=alid;
        int64_t zd=pvarval(tr,7); int64_t ms=zd>=0?((zd>>1)^-(zd&1)):0;   // Track.duration (ms) ist sint32 (ZigZag)
        [out addObject:@{@"id":tid,@"name":name,@"artists":@[a],@"album":al,@"duration_ms":@(ms>0?ms:0)}];
    }
    return out;
}
// Album-Protobuf (gid 1, name 2, artist 3, type 4, date 6{year 1}, disc 11{track 3}, cover_group 17) -> Web-API-ähnliches Dict ohne Titel
static NSDictionary* albumDict(NSString*alid,NSData*al){
    NSArray*arts=psubs(al,3); NSString*cover=coverFromGroup(psub(al,17));
    NSData*date=psub(al,6); int64_t zz=date?pvarval(date,1):-1; int64_t year=zz>=0?((zz>>1)^-(zz&1)):-1;   // Date.year ist sint32 (ZigZag)
    NSMutableDictionary*d=[@{@"id":alid,@"name":spStr(psub(al,2)),@"artists":@[@{@"name":arts.count?spStr(psub(arts[0],2)):@"",@"id":(arts.count?gidToBase62(psub(arts[0],1)):nil)?:@""}],
                             @"images":cover?@[@{@"url":cover}]:@[]} mutableCopy];
    if(year>0) d[@"release_date"]=[NSString stringWithFormat:@"%lld",year];
    return d;
}
static NSDictionary* qparams(NSString*path){
    NSMutableDictionary*q=[NSMutableDictionary dictionary]; NSRange r=[path rangeOfString:@"?"];
    if(r.location==NSNotFound) return q;
    for(NSString*kv in [[path substringFromIndex:r.location+1] componentsSeparatedByString:@"&"]){
        NSArray*p=[kv componentsSeparatedByString:@"="]; if(p.count==2) q[p[0]]=p[1]; }
    return q;
}
// Lieblingssongs: komplette Sammlung (wenige Anfragen à 300), neueste zuerst; 5 Min im RAM.
static NSArray* gLiked=nil; static NSTimeInterval gLikedAt=0;
static NSArray* spLikedIds(int*st){
    @synchronized([MMSpotify class]){
        if(gLiked && [[NSDate date] timeIntervalSince1970]-gLikedAt<300){ *st=200; return gLiked; }
        NSString*user=spUser(); if(!user.length){ *st=401; return nil; }
        NSMutableArray*items=[NSMutableArray array]; NSData*tok=nil;
        for(int page=0;page<40;page++){
            NSMutableData*req=[NSMutableData data]; pstr(req,1,user); pstr(req,2,@"collection");
            if(tok) pbytes(req,3,tok); pvarf(req,4,300);
            NSString*ct=@"application/vnd.collection-v2.spotify.proto";
            NSData*d=spReq(@"POST",@"/collection/v2/paging",req,ct,ct,st);
            if(*st!=200) return nil;
            for(NSData*it in psubs(d,1)){ NSString*tid=trackIdFromUri(spStr(psub(it,1))); if(tid && !psub(it,3)) [items addObject:@[tid,@(pvarval(it,2))]]; }
            tok=psub(d,2); if(!tok.length) break;
        }
        [items sortUsingComparator:^NSComparisonResult(NSArray*a,NSArray*b){ return [b[1] compare:a[1]]; }];
        NSMutableArray*ids=[NSMutableArray array]; for(NSArray*it in items)[ids addObject:it[0]]; gLiked=ids; gLikedAt=[[NSDate date] timeIntervalSince1970]; *st=200;
        return gLiked;
    }
}
static NSDictionary* trackPage(NSArray*ids,NSUInteger off,NSUInteger lim,NSUInteger total,NSString*nextBase){
    NSArray*slice=(off<ids.count)?[ids subarrayWithRange:NSMakeRange(off,MIN(lim,ids.count-off))]:@[];
    NSMutableArray*items=[NSMutableArray array]; for(NSDictionary*t in spTracks(slice)) [items addObject:@{@"track":t}];
    if(slice.count && !items.count) return nil;   // Titelinfos nicht ladbar (z.B. offline): Fehler statt leerer Seite, sonst überschreibt "leer" die gespeicherte Liste
    id next=(off+lim<total)?[NSString stringWithFormat:@"%@offset=%lu",nextBase,(unsigned long)(off+lim)]:[NSNull null];
    return @{@"items":items,@"next":next,@"total":@(total)};
}
// "Heruntergeladen": alle Songs auf der Platte als eine Liste, neueste zuerst.
// Titel/Artist/Cover/Dauer kommen aus dlinfo.plist; was dort fehlt, aus den gespeicherten Listen oder übers Netz.
// Was einmal bekannt ist, bleibt in dlinfo.plist -> die Liste geht auch offline vollständig.
// Platzhalter für Songs ohne bekannte Infos; landet auch in gespeicherten Listen und darf nie als echter Titel übernommen werden
#define DL_PLACEHOLDER @"…"
static BOOL realTitle(id t){ return [t isKindOfClass:[NSString class]] && [t length] && ![t isEqualToString:DL_PLACEHOLDER]; }
// dlinfo.plist: Titel/Artist/Cover/Dauer der heruntergeladenen Songs (für die Liste "Heruntergeladen", auch offline)
static NSString* dlinfoPath(void){ return [diskDir() stringByAppendingPathComponent:@"dlinfo.plist"]; }
static NSObject* dlinfoLock(void){ static NSObject*o; static dispatch_once_t t; dispatch_once(&t,^{ o=[NSObject new]; }); return o; }
static void dlinfoMerge(NSDictionary*add){
    if(!add.count) return;
    @synchronized(dlinfoLock()){
        NSMutableDictionary*info=[[NSDictionary dictionaryWithContentsOfFile:dlinfoPath()] mutableCopy]?:[NSMutableDictionary dictionary];
        for(NSString*k in add) if(realTitle(add[k][@"title"])) info[k]=add[k];
        [info writeToFile:dlinfoPath() atomically:YES];
    }
    for(NSDictionary*i in add.allValues) if([i[@"cover"] length] && ![MMCovers onDisk:i[@"cover"]]) [MMCovers prefetch:i[@"cover"]];   // Cover auch offline
}
static NSDictionary* infoFromTrack(NSDictionary*t){
    NSArray*ar=t[@"artists"], *im=t[@"album"][@"images"];
    return @{@"title":t[@"name"]?:@"",@"artist":ar.count?(ar[0][@"name"]?:@""):@"",@"cover":im.count?(im[0][@"url"]?:@""):@"",@"dur":t[@"duration_ms"]?:@0};
}
// nach einem fertigen Download: Infos im Hintergrund holen und merken (wir sind gerade online)
static void dlinfoRemember(NSArray*ids){
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{ @autoreleasepool {
        NSMutableDictionary*add=[NSMutableDictionary dictionary];
        for(NSDictionary*t in spTracks(ids)) if([t[@"id"] isKindOfClass:[NSString class]]) add[t[@"id"]]=infoFromTrack(t);
        dlinfoMerge(add);
    }});
}
static NSDictionary* spDownloads(int*st){
    NSArray*files=[MMSpotify downloadedTracks];
    NSMutableDictionary*info; @synchronized(dlinfoLock()){ info=[[NSDictionary dictionaryWithContentsOfFile:dlinfoPath()] mutableCopy]?:[NSMutableDictionary dictionary]; }
    NSMutableDictionary*add=[NSMutableDictionary dictionary];
    NSMutableSet*miss=[NSMutableSet set];
    for(NSDictionary*f in files) if(!realTitle(info[f[@"id"]][@"title"])){ [info removeObjectForKey:f[@"id"]]; [miss addObject:f[@"id"]]; }   // auch alte "…"-Einträge neu holen
    if(miss.count){   // 1. aus den Listen, die die App schon gespeichert hat
        for(NSString*fn in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:diskDir() error:NULL]){
            if(![fn hasPrefix:@"list_"] || ![fn hasSuffix:@".plist"]) continue;
            for(NSDictionary*t in [NSArray arrayWithContentsOfFile:[diskDir() stringByAppendingPathComponent:fn]]){
                if(![t isKindOfClass:[NSDictionary class]] || ![miss containsObject:t[@"id"]] || !realTitle(t[@"title"])) continue;   // z.B. die gespeicherte "Heruntergeladen"-Liste selbst
                add[t[@"id"]]=@{@"title":t[@"title"],@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@"",@"dur":t[@"dur"]?:@0};
                [miss removeObject:t[@"id"]];
            }
        }
    }
    if(miss.count && [MMSpotify networkReachable]){   // 2. der Rest übers Netz
        NSArray*ids=[miss allObjects];
        for(NSUInteger i=0;i<ids.count;i+=50) for(NSDictionary*t in spTracks([ids subarrayWithRange:NSMakeRange(i,MIN(50,ids.count-i))]))
            if([t[@"id"] isKindOfClass:[NSString class]]) add[t[@"id"]]=infoFromTrack(t);
    }
    [info addEntriesFromDictionary:add]; dlinfoMerge(add);
    if([MMSpotify networkReachable])   // Cover, die noch nicht auf der Platte liegen, nachholen (für offline)
        for(NSDictionary*f in files){ NSString*cu=info[f[@"id"]][@"cover"]; if(cu.length && ![MMCovers onDisk:cu]) [MMCovers prefetch:cu]; }
    NSMutableArray*items=[NSMutableArray array];
    for(NSDictionary*f in files){
        NSDictionary*i=info[f[@"id"]]; NSString*cov=i[@"cover"];
        [items addObject:@{@"track":@{@"id":f[@"id"],@"name":realTitle(i[@"title"])?i[@"title"]:DL_PLACEHOLDER,@"artists":@[@{@"name":i[@"artist"]?:@""}],
                                      @"album":@{@"images":[cov length]?@[@{@"url":cov}]:@[]},@"duration_ms":i[@"dur"]?:@0}}];
    }
    *st=200; return @{@"items":items,@"next":[NSNull null],@"total":@(items.count)};
}
// Übersetzt Web-API-GET-Pfade auf spclient. handled=NO -> Pfad unbekannt, normale Web-API nehmen.
static NSDictionary* spInternalGet(NSString*path,int*st,BOOL*handled){
    *handled=YES; NSDictionary*q=qparams(path);
    NSUInteger off=(NSUInteger)[q[@"offset"] integerValue], lim=q[@"limit"]?(NSUInteger)[q[@"limit"] integerValue]:50;
    if([path hasPrefix:@"me/downloads"]) return spDownloads(st);
    NSString*user=spUser();
    if([path hasPrefix:@"me/playlists"]){
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/playlist/v2/user/%@/rootlist?decorate=revision,attributes,length,owner&from=%lu&length=%lu",user,(unsigned long)off,(unsigned long)lim],st);
        if(!j) return nil;
        NSArray*its=j[@"contents"][@"items"], *meta=j[@"contents"][@"metaItems"];
        NSMutableArray*out=[NSMutableArray array];
        // Spotify lässt "length" bei leeren Playlists weg (0 = Standardwert). Nur wenn überhaupt Längen kommen, fehlende als leer werten.
        BOOL haveLen=NO; for(id mi in meta) if([mi isKindOfClass:[NSDictionary class]] && [mi[@"length"] isKindOfClass:[NSNumber class]]){ haveLen=YES; break; }
        for(NSUInteger i=0;i<[its count];i++){
            NSString*u=its[i][@"uri"]; if(![u isKindOfClass:[NSString class]]||![u hasPrefix:@"spotify:playlist:"]) continue;   // Ordner-Marker überspringen
            NSDictionary*mi=(i<[meta count]&&[meta[i] isKindOfClass:[NSDictionary class]])?meta[i]:nil, *a=mi[@"attributes"];
            id len=mi[@"length"];
            if(([len isKindOfClass:[NSNumber class]] && [len integerValue]==0) || (haveLen && !len)) continue;   // leere Playlists gar nicht zeigen
            NSString*hex=b64ToHex(a[@"picture"]), *pic=hex?[@"https://i.scdn.co/image/" stringByAppendingString:hex]:pictureSizeURL(a);
            NSMutableDictionary*pl=[@{@"id":[u substringFromIndex:17],@"name":[a[@"name"] isKindOfClass:[NSString class]]?a[@"name"]:@"Playlist",
                             @"images":pic?@[@{@"url":pic}]:@[]} mutableCopy];
            if([len isKindOfClass:[NSNumber class]]) pl[@"tracks"]=@{@"total":len};
            if([mi[@"ownerUsername"] isKindOfClass:[NSString class]]) pl[@"owner"]=@{@"id":mi[@"ownerUsername"]};
            pl[@"collaborative"]=@([a[@"collaborative"] boolValue]);
            [out addObject:pl];
        }
        // weitere Seiten (die Bibliothek lädt beim Scrollen nach): "length" = Einträge insgesamt
        NSUInteger total=[j[@"length"] respondsToSelector:@selector(unsignedIntegerValue)]?[j[@"length"] unsignedIntegerValue]:0;
        id next=(off+lim<total)?[NSString stringWithFormat:@"me/playlists?limit=%lu&offset=%lu",(unsigned long)lim,(unsigned long)(off+lim)]:[NSNull null];
        return @{@"items":out,@"next":next,@"total":@(total)};
    }
    if([path hasPrefix:@"playlists/"]){
        NSString*pid=[[path substringFromIndex:10] componentsSeparatedByString:@"?"][0];
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/playlist/v2/playlist/%@?decorate=attributes,length,owner&from=%lu&length=%lu",pid,(unsigned long)off,(unsigned long)lim],st);
        if(!j) return nil;
        NSMutableArray*ids=[NSMutableArray array];
        for(NSDictionary*it in j[@"contents"][@"items"]){ NSString*tid=[it isKindOfClass:[NSDictionary class]]?trackIdFromUri(it[@"uri"]):nil; if(tid)[ids addObject:tid]; }
        NSUInteger total=[j[@"length"] unsignedIntegerValue];
        NSDictionary*pg=trackPage(ids,0,ids.count,ids.count,@""); if(!pg){ *st=503; return nil; }
        id next=(off+lim<total)?[NSString stringWithFormat:@"playlists/%@?offset=%lu",pid,(unsigned long)(off+lim)]:[NSNull null];
        // Kopf für die Cover-Ansicht: Name, Bild, Beschreibung, Besitzer
        NSDictionary*a=[j[@"attributes"] isKindOfClass:[NSDictionary class]]?j[@"attributes"]:@{};
        NSString*hex=b64ToHex(a[@"picture"]), *pic=hex?[@"https://i.scdn.co/image/" stringByAppendingString:hex]:pictureSizeURL(a);
        NSMutableDictionary*out=[@{@"tracks":@{@"items":pg[@"items"],@"next":next,@"total":@(total)}} mutableCopy];
        if([a[@"name"] isKindOfClass:[NSString class]]) out[@"name"]=a[@"name"];
        if([a[@"description"] isKindOfClass:[NSString class]]) out[@"description"]=a[@"description"];
        if(pic) out[@"images"]=@[@{@"url":pic}];
        if([j[@"ownerUsername"] isKindOfClass:[NSString class]]) out[@"owner"]=@{@"id":j[@"ownerUsername"]};
        return out;
    }
    if([path hasPrefix:@"me/tracks"]){
        NSArray*ids=spLikedIds(st); if(!ids) return nil;
        NSDictionary*pg=trackPage(ids,off,lim,ids.count,@"me/tracks?"); if(!pg) *st=503; return pg;
    }
    if([path hasPrefix:@"me/player/recently-played"]){
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/recently-played/v3/user/%@/recently-played?format=json&limit=%lu&filter=default",user,(unsigned long)lim],st);
        if(!j) return nil;
        NSMutableArray*ids=[NSMutableArray array];
        NSMutableDictionary*at=[NSMutableDictionary dictionary];
        for(NSDictionary*c in j[@"playContexts"]){ NSString*tid=[c isKindOfClass:[NSDictionary class]]?trackIdFromUri(c[@"lastPlayedTrackUri"]):nil; if(tid&&![ids containsObject:tid]){ [ids addObject:tid]; if(c[@"lastPlayedTime"]) at[tid]=c[@"lastPlayedTime"]; } }
        NSMutableDictionary*pg=[trackPage(ids,0,ids.count,ids.count,@"") mutableCopy]; if(!pg){ *st=503; return nil; } NSMutableArray*its=[NSMutableArray array];
        for(NSDictionary*it in pg[@"items"]){ NSMutableDictionary*m=[it mutableCopy]; id a=at[it[@"track"][@"id"]]; if(a) m[@"at"]=a; [its addObject:m]; }   // Zeitpunkt (ms)
        pg[@"items"]=its; return pg;
    }
    if([path hasPrefix:@"albums/"]){   // Album: Kopf + alle Titel aller Discs
        NSString*alid=[[path substringFromIndex:7] componentsSeparatedByString:@"?"][0];
        NSData*al=spExt(@[[@"spotify:album:" stringByAppendingString:alid]],9,st)[[@"spotify:album:" stringByAppendingString:alid]];   // 9 = ALBUM_V4
        if(!al.length){ if(*st==200) *st=404; return nil; }
        NSMutableArray*ids=[NSMutableArray array];
        for(NSData*disc in psubs(al,11)) for(NSData*t in psubs(disc,3)){ NSString*tid=gidToBase62(psub(t,1)); if(tid)[ids addObject:tid]; }
        NSMutableDictionary*d=[albumDict(alid,al) mutableCopy];
        NSDictionary*pg=trackPage(ids,0,ids.count,ids.count,@""); if(!pg){ *st=503; return nil; }
        d[@"tracks"]=@{@"items":pg[@"items"],@"next":[NSNull null],@"total":@(ids.count)};
        *st=200; return d;
    }
    if([path hasPrefix:@"artists/"]){   // Artist: beliebteste Titel + Alben + Singles (neueste zuerst)
        NSString*arid=[[path substringFromIndex:8] componentsSeparatedByString:@"?"][0];
        NSString*uri=[@"spotify:artist:" stringByAppendingString:arid];
        NSData*ar=spExt(@[uri],8,st)[uri];   // 8 = ARTIST_V4
        if(!ar.length){ if(*st==200) *st=404; return nil; }
        NSMutableArray*top=[NSMutableArray array];
        for(NSData*tt in psubs(ar,4)){ for(NSData*t in psubs(tt,2)){ NSString*tid=gidToBase62(psub(t,1)); if(tid&&![top containsObject:tid])[top addObject:tid]; } if(top.count) break; }   // erste Länderliste
        if(top.count>10) [top removeObjectsInRange:NSMakeRange(10,top.count-10)];
        NSArray*(^group)(int)=^NSArray*(int f){ NSMutableArray*g=[NSMutableArray array];
            for(NSData*ag in psubs(ar,f)){ NSArray*als=psubs(ag,1); if(als.count){ NSString*a=gidToBase62(psub(als[0],1)); if(a&&![g containsObject:a])[g addObject:a]; } }   // pro Gruppe die erste Ausgabe
            return g; };
        NSArray*albumIds=group(5), *singleIds=group(6);
        NSMutableArray*uris=[NSMutableArray array];
        for(NSString*a in [albumIds arrayByAddingObjectsFromArray:singleIds]) [uris addObject:[@"spotify:album:" stringByAppendingString:a]];
        int ast=0; NSDictionary*alb=uris.count?spExt(uris,9,&ast):@{};
        NSArray*(^dicts)(NSArray*)=^NSArray*(NSArray*aids){ NSMutableArray*o=[NSMutableArray array];
            for(NSString*a in aids){ NSData*al=alb[[@"spotify:album:" stringByAppendingString:a]]; if(al.length)[o addObject:albumDict(a,al)]; }
            [o sortUsingComparator:^NSComparisonResult(NSDictionary*x,NSDictionary*y){ return [y[@"release_date"]?:@"" compare:x[@"release_date"]?:@""]; }];
            return o; };
        NSString*portrait=coverFromGroup(psub(ar,17));
        NSMutableArray*tops=[NSMutableArray array]; for(NSDictionary*t in spTracks(top)) [tops addObject:t];
        *st=200;
        return @{@"id":arid,@"name":spStr(psub(ar,2)),@"images":portrait?@[@{@"url":portrait}]:@[],
                 @"top_tracks":tops,@"albums":dicts(albumIds),@"singles":dicts(singleIds)};
    }
    if([path hasPrefix:@"me/recent-contexts"]){   // zuletzt gehörte Playlists/Alben/Artists (Startseite, wie in der Spotify-App)
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/recently-played/v3/user/%@/recently-played?format=json&limit=30&filter=default",user],st);
        if(!j) return nil;
        NSMutableArray*uris=[NSMutableArray array]; NSMutableDictionary*when=[NSMutableDictionary dictionary];
        for(NSDictionary*c in j[@"playContexts"]){ NSString*u=[c isKindOfClass:[NSDictionary class]]?c[@"uri"]:nil;
            if(![u isKindOfClass:[NSString class]]||[uris containsObject:u]) continue;
            if(c[@"lastPlayedTime"]) when[u]=c[@"lastPlayedTime"];
            if([u hasPrefix:@"spotify:playlist:"]||[u hasPrefix:@"spotify:album:"]||[u hasPrefix:@"spotify:artist:"]||[u hasSuffix:@":collection"]) [uris addObject:u];
            if(uris.count>=lim) break; }
        NSMutableArray*alb=[NSMutableArray array], *art=[NSMutableArray array];
        for(NSString*u in uris){ if([u hasPrefix:@"spotify:album:"])[alb addObject:u]; else if([u hasPrefix:@"spotify:artist:"])[art addObject:u]; }
        int xst=0; NSDictionary*albs=alb.count?spExt(alb,9,&xst):@{}, *arts=art.count?spExt(art,8,&xst):@{};
        NSMutableArray*out=[NSMutableArray array];
        for(NSString*u in uris){
            NSString*id_=[[u componentsSeparatedByString:@":"] lastObject];
            if([u hasSuffix:@":collection"]){ [out addObject:@{@"type":@"liked",@"uri":u}]; continue; }
            if([u hasPrefix:@"spotify:album:"]){ NSData*a=albs[u]; if(!a.length) continue;
                NSDictionary*d=albumDict(id_,a); [out addObject:@{@"type":@"album",@"id":id_,@"name":d[@"name"],@"images":d[@"images"]}]; continue; }
            if([u hasPrefix:@"spotify:artist:"]){ NSData*a=arts[u]; if(!a.length) continue;
                NSString*pic=coverFromGroup(psub(a,17)); [out addObject:@{@"type":@"artist",@"id":id_,@"name":spStr(psub(a,2)),@"images":pic?@[@{@"url":pic}]:@[]}]; continue; }
            int pst=0; NSDictionary*pl=spJSON([NSString stringWithFormat:@"/playlist/v2/playlist/%@?decorate=attributes&from=0&length=0",id_],&pst);
            NSDictionary*a=[pl[@"attributes"] isKindOfClass:[NSDictionary class]]?pl[@"attributes"]:nil; if(!a) continue;
            if([a[@"format"] isEqual:@"liked-songs"]){ [out addObject:@{@"type":@"liked",@"uri":u}]; continue; }   // Lieblingssongs als Playlist
            NSString*pic=pictureSizeURL(a);
            if(!pic){ NSString*hex=b64ToHex(a[@"picture"]); if(hex) pic=[@"https://i.scdn.co/image/" stringByAppendingString:hex]; }
            [out addObject:@{@"type":@"playlist",@"id":id_,@"name":[a[@"name"] isKindOfClass:[NSString class]]?a[@"name"]:@"Playlist",@"images":pic?@[@{@"url":pic}]:@[]}];
        }
        NSMutableArray*dedup=[NSMutableArray array]; BOOL liked=NO;   // Lieblingssongs nur einmal
        for(NSUInteger i=0;i<out.count;i++){ NSMutableDictionary*d=[out[i] mutableCopy];
            if([d[@"type"] isEqual:@"liked"]){ if(liked) continue; liked=YES; }
            id a=when[d[@"uri"]?:[NSString stringWithFormat:@"spotify:%@:%@",d[@"type"],d[@"id"]]]; if(a) d[@"at"]=a;
            [d removeObjectForKey:@"uri"];
            [dedup addObject:d]; }
        *st=200; return @{@"items":dedup};
    }
    if([path hasPrefix:@"me/top/"]){ *st=404; return nil; }   // kein interner Ersatz bekannt -> Bereich bleibt ausgeblendet
    *handled=NO; return nil;
}

// ---- Schreiben über die internen Server (die Web-API gibt diesem Client nur 429) ----
// Lieblingssongs: collection/v2/write, WriteRequest{username 1, set 2, items 3 {uri 1, added_at 2, is_removed 3}, client_update_id 4}
+ (void)setLiked:(BOOL)on track:(NSString *)trackId completion:(void(^)(BOOL ok))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSString*user=spUser(); BOOL ok=NO;
        if(user.length && trackId.length){
            NSMutableData*it=[NSMutableData data]; pstr(it,1,[@"spotify:track:" stringByAppendingString:trackId]);
            pvarf(it,2,(uint64_t)[[NSDate date] timeIntervalSince1970]); if(!on) pvarf(it,3,1);
            NSMutableData*req=[NSMutableData data]; pstr(req,1,user); pstr(req,2,@"collection"); pmsg(req,3,it);
            CFUUIDRef uu=CFUUIDCreate(NULL); pstr(req,4,[(NSString *)CFBridgingRelease(CFUUIDCreateString(NULL,uu)) lowercaseString]); CFRelease(uu);   // NSUUID erst ab iOS 6
            NSString*ct=@"application/vnd.collection-v2.spotify.proto"; int st=0;
            NSData*d=spReq(@"POST",@"/collection/v2/write",req,ct,ct,&st);
            ok=(st>=200&&st<300);
            if(!ok) slog(@"like %@ -> HTTP %d: %.200@",trackId,st,d?[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]:@"");
            if(ok) @synchronized([MMSpotify class]){   // Merkliste sofort anpassen (Liked Songs zeigt es beim nächsten Öffnen)
                if(gLiked){ NSMutableArray*m=[gLiked mutableCopy]; [m removeObject:trackId]; if(on)[m insertObject:trackId atIndex:0]; gLiked=m; } }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if(done) done(ok); });
    });
}
+ (NSString *)username { return spUser(); }
+ (NSNumber *)likedCached:(NSString *)trackId {   // sofort aus dem Speicher (5 Min gültig), sonst nil
    @synchronized([MMSpotify class]){ if(!gLiked || [[NSDate date] timeIntervalSince1970]-gLikedAt>=300) return nil; return @([gLiked containsObject:trackId]); }
}
+ (void)isLiked:(NSString *)trackId completion:(void(^)(BOOL liked, BOOL known))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        int st=0; NSArray*ids=spLikedIds(&st);
        dispatch_async(dispatch_get_main_queue(), ^{ done(ids && [ids containsObject:trackId], ids!=nil); });
    });
}
// Playlist: Titel ans Ende anhängen (playlist/v2 .../changes, ADD-Operation wie im Web-Player)
+ (void)addTrack:(NSString *)trackId toPlaylist:(NSString *)playlistId completion:(void(^)(BOOL ok))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSDictionary*body=@{@"deltas":@[@{@"ops":@[@{@"kind":@"ADD",@"add":@{@"items":@[@{@"uri":[@"spotify:track:" stringByAppendingString:trackId],
                                @"attributes":@{@"timestamp":[NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970]*1000)]}}],@"addLast":@YES}}],
                            @"info":@{@"source":@{@"client":@"WEBPLAYER"}}}],@"wantResultingRevisions":@NO,@"wantSyncResult":@NO,@"nonces":@[]};
        NSData*js=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL]; int st=0;
        NSData*d=spReq(@"POST",[NSString stringWithFormat:@"/playlist/v2/playlist/%@/changes",playlistId],js,@"application/json;charset=UTF-8",@"application/json",&st);
        BOOL ok=(st>=200&&st<300);
        if(!ok) slog(@"playlist add %@ -> HTTP %d: %.200@",playlistId,st,d?[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]:@"");
        dispatch_async(dispatch_get_main_queue(), ^{ if(done) done(ok); });
    });
}

// Web-API mit Methode (GET/PUT/DELETE/POST) über den User-Daten-Token.
+ (void)apiUser:(NSString *)method path:(NSString *)path body:(NSData *)body completion:(void(^)(NSDictionary *json, NSInteger status))done {
    // Suche (auch "Durchsuchen" und deren Folgeseiten) nur mit dem eigenen Entwicklerschlüssel:
    // den Login-Token weist die Web-API dafür fast immer mit 429 (Rate-Limit) ab
    if([method isEqualToString:@"GET"] && [path hasPrefix:@"search?"]){
        [self webGet:[path stringByReplacingOccurrencesOfString:@"&market=from_token" withString:@""] completion:done]; return; }
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        if([method isEqualToString:@"GET"]){   // erst interne Server; nur unbekannte Pfade gehen an die Web-API
            int ist=0; BOOL handled=NO; NSDictionary*ij=spInternalGet(path,&ist,&handled);
            if(handled){
                if(ist==401 && gRefreshDead) dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAuthExpired" object:nil]; });
                dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(ij, ij?200:(ist?ist:503)); });
                return;
            }
        }
        if(!gToken.length) loadUserToken();
        __block int st=0;
        NSData*(^go)(void)=^NSData*{
            NSMutableArray*h=[NSMutableArray array]; if(gToken.length)[h addObject:[@"Authorization: Bearer " stringByAppendingString:gToken]];
            if(body.length)[h addObject:@"Content-Type: application/json"];
            int s2=0; NSData*r=httpsReq(method,@"api.spotify.com",[@"/v1/" stringByAppendingString:path],h,body,&s2); st=s2; return r; };
        NSData*d=go();
        if(st==401 && refreshUserToken()) d=go();   // Token abgelaufen -> still erneuern
        // Refresh klappt nicht mehr -> App startet selbst den Code-Login
        if(st==401 && gRefreshDead) dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAuthExpired" object:nil]; });
        slog(@"apiUser %@ %@ -> HTTP %d (%lu B)", method, path, st, (unsigned long)d.length);
        NSDictionary*j=(d.length)?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        if(![j isKindOfClass:[NSDictionary class]]) j=nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(j, st); });
    });
}
// Stale-while-revalidate: erst Disk-Cache, dann Netz. Nur GET.
static NSString* apiCachePath(NSString*path){ return [NSString stringWithFormat:@"%@/api_%lu.json", diskDir(), (unsigned long)path.hash]; }
+ (void)apiUserCached:(NSString *)path completion:(void(^)(NSDictionary *json, NSInteger status, BOOL fresh))done {
    NSData*cd=[NSData dataWithContentsOfFile:apiCachePath(path)];
    id cj=cd.length?[NSJSONSerialization JSONObjectWithData:cd options:0 error:NULL]:nil;
    NSDictionary*cached=[cj isKindOfClass:[NSDictionary class]]?cj:nil;
    if(cached && done) done(cached, 200, NO);
    [self apiUser:@"GET" path:path body:nil completion:^(NSDictionary*j, NSInteger st){
        BOOL ok=(st>=200&&st<300)&&j;
        if(ok){
            if(cached && [j isEqual:cached]) return;   // unverändert -> UI bleibt wie sie ist
            NSData*out=[NSJSONSerialization dataWithJSONObject:j options:0 error:NULL];
            if(out.length) [out writeToFile:apiCachePath(path) atomically:YES];
            if(done) done(j, st, YES);
        } else if(!cached){ if(done) done(nil, st, YES); }   // nur ohne Cache Fehler melden
        else slog(@"apiUserCached %@ -> HTTP %d, zeige letzte Daten", path, (int)st);
    }];
}

+ (BOOL)hasUserToken {
    NSString*ut=[NSString stringWithContentsOfFile:MMPath(@".spotify-usertoken") encoding:NSUTF8StringEncoding error:NULL];
    return ut.length>0;
}

// Folgt der "next"-URL quer durch alle Seiten (me/tracks: j.items/j.next ; playlists/{id}: j.tracks.items/j.tracks.next).
+ (void)apiUserAllItems:(NSString *)path completion:(void(^)(NSArray *items, NSInteger status))done {
    NSMutableArray*acc=[NSMutableArray array];
    __block void (^step)(NSString*) = nil;
    step = [^(NSString *p){
        [self apiUser:@"GET" path:p body:nil completion:^(NSDictionary*j, NSInteger st){
            NSDictionary*page=[j isKindOfClass:[NSDictionary class]]?j:nil;
            if(page && ![page[@"items"] isKindOfClass:[NSArray class]] && [page[@"tracks"] isKindOfClass:[NSDictionary class]]) page=page[@"tracks"];  // Playlist: items liegen unter .tracks
            id items=page[@"items"];
            if([items isKindOfClass:[NSArray class]]) [acc addObjectsFromArray:items];
            id next=page[@"next"];
            if([next isKindOfClass:[NSString class]] && [next length]){
                NSString*rel=next; NSRange r=[next rangeOfString:@"/v1/"];
                if(r.location!=NSNotFound) rel=[next substringFromIndex:r.location+4];   // volle URL -> relativer Pfad
                step(rel);
            } else { if(done)done(acc.count?acc:((st>=200&&st<300)?acc:nil), st); step=nil; }   // fertig -> Zyklus auflösen
        }];
    } copy];
    step(path);
}

// ---- Login mit Code über ein anderes Gerät (OAuth Device Flow, wie bei Smart-TVs) ----
#define DEVICE_CLIENT @"65b708073fc0480ea92a077233ca87bd"
#define DEVICE_SCOPE  @"streaming%20user-read-private%20user-read-email%20user-library-read%20user-library-modify%20playlist-read-private%20playlist-read-collaborative%20playlist-modify-private%20playlist-modify-public%20user-read-recently-played%20user-top-read"

static NSDictionary* formPost(NSString*path,NSString*body,int*st){
    NSArray*hdr=@[@"Content-Type: application/x-www-form-urlencoded",@"Accept: application/json"];
    NSData*d=httpsReq(@"POST",@"accounts.spotify.com",path,hdr,[body dataUsingEncoding:NSUTF8StringEncoding],st);
    id j=d.length?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}

+ (void)deviceLoginStart:(void(^)(NSDictionary*info,NSString*err))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        int st=0; NSDictionary*j=formPost(@"/oauth2/device/authorize",
            [NSString stringWithFormat:@"client_id=%@&scope=%@",DEVICE_CLIENT,DEVICE_SCOPE],&st);
        slog(@"device/authorize HTTP %d -> %@", st, j[@"user_code"]?@"code ok":j[@"error"]);
        NSString*err=nil;
        if(![j[@"device_code"] length]||![j[@"user_code"] length]) err=st?[NSString stringWithFormat:@"Spotify: %@",j[@"error_description"]?:@(st)]:@"No connection to Spotify";
        dispatch_async(dispatch_get_main_queue(), ^{ done(err?nil:j, err); });
    });
}

+ (void)deviceLoginPoll:(NSDictionary*)info cancelled:(BOOL(^)(void))cancelled completion:(void(^)(NSString*token,NSString*err))done {
    NSString*code=info[@"device_code"];
    __block double interval=MAX([info[@"interval"] doubleValue],2.0);
    double deadline=[NSDate timeIntervalSinceReferenceDate]+MAX([info[@"expires_in"] doubleValue],60.0);
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSString*token=nil,*err=nil;
        while(!token && !err){
            [NSThread sleepForTimeInterval:interval];
            if(cancelled && cancelled()){ err=@"cancelled"; break; }
            if([NSDate timeIntervalSinceReferenceDate]>deadline){ err=@"Code expired – please start again"; break; }
            int st=0; NSDictionary*j=formPost(@"/api/token",
                [NSString stringWithFormat:@"grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Adevice_code&device_code=%@&client_id=%@",code,DEVICE_CLIENT],&st);
            NSString*at=j[@"access_token"], *e=j[@"error"];
            if(at.length){
                token=at; gToken=at;
                [at writeToFile:MMPath(@".spotify-usertoken") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                NSString*rt=j[@"refresh_token"];
                if(rt.length)[rt writeToFile:MMPath(@".spotify-userrefresh") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                slog(@"device login: token ok (refresh %@)", rt.length?@"ja":@"nein");
            }
            else if([e isEqualToString:@"authorization_pending"]) continue;
            else if([e isEqualToString:@"slow_down"]) interval+=5;
            else if([e isEqualToString:@"access_denied"]) err=@"Login was declined on the other device";
            else if([e isEqualToString:@"expired_token"]) err=@"Code expired – please start again";
            else if(st!=0 && e.length) err=[NSString stringWithFormat:@"Spotify: %@",j[@"error_description"]?:e];
            // st==0: Netzproblem -> einfach weiter versuchen
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(token, err); });
    });
}
// ---- Netz-Erkennung (SystemConfiguration, "gibt es eine Route ins Internet?") ----
static SCNetworkReachabilityRef gReach;
static BOOL reachFlags(SCNetworkReachabilityFlags f){
    if(!(f&kSCNetworkReachabilityFlagsReachable)) return NO;
    if((f&kSCNetworkReachabilityFlagsConnectionRequired) && !(f&kSCNetworkReachabilityFlagsConnectionOnTraffic)) return NO;
    return YES;
}
static SCNetworkReachabilityRef reachRef(void){
    if(!gReach){ struct sockaddr_in a; memset(&a,0,sizeof a); a.sin_len=sizeof a; a.sin_family=AF_INET;
        gReach=SCNetworkReachabilityCreateWithAddress(NULL,(const struct sockaddr*)&a); }
    return gReach;
}
+ (BOOL)networkReachable {
    SCNetworkReachabilityFlags f=0;
    return SCNetworkReachabilityGetFlags(reachRef(),&f) && reachFlags(f);
}
static BOOL gWasReachable=YES;
static void reachChanged(SCNetworkReachabilityRef r,SCNetworkReachabilityFlags f,void*info){
    BOOL ok=reachFlags(f); if(ok==gWasReachable) return;
    gWasReachable=ok; slog(@"Netz %@", ok?@"wieder da":@"weg");
    if(ok && [MMSpotify hasStoredCreds]) dispatch_async(spotQ(), ^{ if(gSock<0) reconnectStored(); });   // Session still neu aufbauen
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MMNetworkChanged" object:nil userInfo:@{@"reachable":@(ok)}];
}
+ (void)startNetworkWatch {
    static dispatch_once_t o; dispatch_once(&o, ^{
        gWasReachable=[self networkReachable];
        SCNetworkReachabilitySetCallback(reachRef(),reachChanged,NULL);
        SCNetworkReachabilityScheduleWithRunLoop(reachRef(),CFRunLoopGetMain(),kCFRunLoopCommonModes);
    });
}
// Abmelden (am Ende, damit alle Zustände oben deklariert sind)
+ (void)logoutCompletion:(void(^)(void))done {
    [MMAudio stop];
    @synchronized([MMSpotify class]){ [gDlQueue removeAllObjects]; gDlRunning=NO; gDlDone=0; gDlTotal=0; gDlUnavail=0; [gDlSeen removeAllObjects]; }
    // Verbindung sofort kappen: eine laufende Anfrage auf der spotQ bricht damit ab, statt bis zum Timeout zu warten.
    // Schließen und Zurücksetzen der Zustände folgt danach auf der spotQ (dort gehört der Socket hin).
    int s=gSock; if(s>=0) shutdown(s, SHUT_RDWR);
    dispatch_async(spotQ(), ^{
        if(gSock>=0){ close(gSock); gSock=-1; }
        gToken=nil; gClientToken=nil; gSpclient=nil; gLiked=nil; gLikedAt=0; gRefreshDead=NO; gRefreshedAt=0; gLoginRejected=NO; gLog=nil;
        @synchronized(cacheLock()){ [gCache removeAllObjects]; [gCacheOrder removeAllObjects]; [gInflight removeAllObjects]; }
    });
    // Löschen wartet nicht auf die spotQ
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSFileManager*fm=[NSFileManager defaultManager];
        for(NSString*f in @[@".spotify-creds",@".spotify-user",@".spotify-usertoken",@".spotify-userrefresh",@".spotify-token",
                            @".spotify-datatoken",@".spotify-datarefresh",@".spotify-log",@"history.plist"])
            [fm removeItemAtPath:MMPath(f) error:NULL];
        [fm removeItemAtPath:MMPath(@".spotcache") error:NULL];   // Downloads, Playlisten, Cover, API-Antworten
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString*bid=[[NSBundle mainBundle] bundleIdentifier];
            if(bid) [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bid];   // Warteschlange, letzter Song …
            [[NSUserDefaults standardUserDefaults] synchronize];
            if(done) done();
        });
    });
}

#ifdef DEBUG
// Diagnose: Song auflösen und jede CDN-Adresse einmal mit iOS-6-Netz (CFNetwork) und einmal mit eigenem TLS (mbedTLS) laden
// Diagnose: drei verweigerte Schlüssel vortäuschen (Popup + "Debug info" prüfen, ohne betroffenes Konto)
+ (void)debugFakeKeyRefusals { gKeyEverOK=NO; gKeyRefusedRow=3; gKeyRefusedTotal+=3; gKeyLastCode=1; slog(@"AesKeyError code 1 (simulated x3)"); if(accountKeysRefused()) postOnce(@"MMSpotifyKeysRefused"); }
// Diagnose: Verbindung zu ip:port mit dem Zeitlimit der Spotify-Verbindung (z.B. eine Adresse, die nie antwortet)
+ (void)debugApTest:(NSString *)ipport {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSArray*hp=[ipport componentsSeparatedByString:@":"]; if(hp.count<2) return;
        struct sockaddr_in sa; memset(&sa,0,sizeof sa); sa.sin_family=AF_INET; sa.sin_port=htons([hp[1] intValue]); inet_aton([hp[0] UTF8String],&sa.sin_addr);
        NSString*why=nil; CFAbsoluteTime t0=CFAbsoluteTimeGetCurrent(); int t=tcpConnect(&sa,&why);
        slog(@"aptest %@ -> %@ after %.1fs",ipport,t>=0?@"ok":why,CFAbsoluteTimeGetCurrent()-t0); if(t>=0) close(t);
    });
}
+ (void)debugCdnTest:(NSString *)tid {
    dispatch_async(spotQ(), ^{ @autoreleasepool {
        NSString*cdn=nil; NSData*key=nil; NSString*e=nil;
        if(![self resolveTrack:tid cdn:&cdn key:&key err:&e]){ slog(@"cdntest resolve fail: %@",e); return; }
        for(NSString*u in gLastCdns){
            NSURL*url=[NSURL URLWithString:u]; NSError*ne=nil; CFAbsoluteTime t0=CFAbsoluteTimeGetCurrent();
            NSData*d1=[NSData dataWithContentsOfURL:url options:0 error:&ne];
            slog(@"cdntest CFNetwork %@ -> %lu B in %.1fs %@",url.host,(unsigned long)d1.length,CFAbsoluteTimeGetCurrent()-t0,ne?ne.localizedDescription:@"");
            int st=0; t0=CFAbsoluteTimeGetCurrent(); NSString*pq=url.query.length?[NSString stringWithFormat:@"%@?%@",url.path,url.query]:url.path;
            NSData*d2=httpsReq(@"GET",url.host,pq,@[],nil,&st);
            slog(@"cdntest mbedTLS %@ -> HTTP %d %lu B in %.1fs",url.host,st,(unsigned long)d2.length,CFAbsoluteTimeGetCurrent()-t0);
        }
    }});
}

// MMDebug: roher extended-metadata-Payload (zum Prüfen der Protobuf-Feldnummern auf dem Gerät)
+ (NSData *)debugExt:(NSString *)uri kind:(int)kind { int st=0; return spExt(@[uri],kind,&st)[uri]; }
+ (NSData *)debugRaw:(NSString *)path { int st=0; return spReq(@"GET",path,nil,nil,@"application/json",&st); }
#endif
@end
