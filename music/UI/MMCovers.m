#import "MMCovers.h"
#import <objc/runtime.h>
#import "MMSpotify.h"
#import <CommonCrypto/CommonDigest.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/time.h>

@implementation MMCovers

static NSCache *gRam(void){ static NSCache*c; static dispatch_once_t o; dispatch_once(&o,^{ c=[[NSCache alloc] init]; c.countLimit=40; c.totalCostLimit=20*1024*1024; }); return c; }
static NSUInteger imgCost(UIImage*i){ return (NSUInteger)(i.size.width*i.size.height*4*i.scale*i.scale); }
static dispatch_queue_t gQ(void){ static dispatch_queue_t q; static dispatch_once_t o; dispatch_once(&o,^{ q=dispatch_queue_create("mesh.covers",DISPATCH_QUEUE_CONCURRENT); }); return q; }

static NSString *imgDir(void){
    NSString*d=MMPath(@".spotcache/img");
    static dispatch_once_t o; dispatch_once(&o,^{ [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL]; });
    return d;
}
static NSString *diskPath(NSString*url){ return [imgDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.jpg",(unsigned long)url.hash]]; }
// Gleiches Bild unter verschiedenen Adressen nur EINMAL auf der Platte: Inhalt liegt in c_<md5>.jpg,
// jede Adress-Datei ist ein Hardlink darauf (kein zusätzlicher Platz, Lesen bleibt unverändert).
static NSString *md5Hex(NSData*d){ unsigned char h[CC_MD5_DIGEST_LENGTH]; CC_MD5(d.bytes,(CC_LONG)d.length,h);
    NSMutableString*s=[NSMutableString string]; for(int i=0;i<CC_MD5_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",h[i]]; return s; }
static void storeDeduped(NSData*d,NSString*path){
    NSString*content=[imgDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"c_%@.jpg",md5Hex(d)]];
    NSFileManager*fm=[NSFileManager defaultManager];
    if(![fm fileExistsAtPath:content]) [d writeToFile:content atomically:YES];
    unlink(path.fileSystemRepresentation);
    if(link(content.fileSystemRepresentation,path.fileSystemRepresentation)!=0) [d writeToFile:path atomically:YES];   // Notfalls normale Kopie
}
// Wartung (Dopplungen zusammenführen, Abgelaufenes löschen) nacheinander auf einer Warteschlange
static dispatch_queue_t gMaint(void){ static dispatch_queue_t q; static dispatch_once_t o; dispatch_once(&o,^{ q=dispatch_queue_create("mesh.covers.maint",DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(q,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0)); }); return q; }
// ---- Lebensdauer: 14 Tage seit dem letzten Anzeigen; jedes Anzeigen setzt die Frist neu ----
#define COVER_TTL (14*86400)
static void touchCover(NSString*url){
    static NSMutableSet*done; static dispatch_once_t o; dispatch_once(&o,^{ done=[NSMutableSet set]; });
    @synchronized(done){ if([done containsObject:url]) return; [done addObject:url]; }   // einmal pro App-Start reicht
    dispatch_async(gQ(), ^{ utimes(diskPath(url).fileSystemRepresentation,NULL); });     // Änderungszeit = "zuletzt gesehen"
}
// Beim Start im Hintergrund: abgelaufene Cover löschen, danach Bildinhalte ohne Verweis
static void expireCovers(void){
    static dispatch_once_t o; dispatch_once(&o, ^{
        dispatch_async(gMaint(), ^{ @autoreleasepool {
            NSFileManager*fm=[NSFileManager defaultManager]; time_t now=time(NULL); int gone=0;
            NSArray*files=[fm contentsOfDirectoryAtPath:imgDir() error:NULL];
            for(NSString*f in files){
                if([f hasPrefix:@"c_"] || ![f hasSuffix:@".jpg"]) continue;
                struct stat st; NSString*p=[imgDir() stringByAppendingPathComponent:f];
                if(stat(p.fileSystemRepresentation,&st)==0 && now-st.st_mtime>COVER_TTL){ unlink(p.fileSystemRepresentation); gone++; }
            }
            for(NSString*f in files){                  // Inhalt, auf den keine Adresse mehr zeigt (nur noch 1 Verweis = er selbst)
                if(![f hasPrefix:@"c_"]) continue;
                struct stat st; NSString*p=[imgDir() stringByAppendingPathComponent:f];
                if(stat(p.fileSystemRepresentation,&st)==0 && st.st_nlink<=1){ unlink(p.fileSystemRepresentation); gone++; }
            }
            NSLog(@"[covers] %d abgelaufene Dateien entfernt",gone);
        }});
    });
}

// Einmalig: vorhandene Dopplungen zusammenführen
static void dedupeExisting(void){
    static dispatch_once_t o; dispatch_once(&o, ^{
        dispatch_async(gMaint(), ^{ @autoreleasepool {
            NSString*flag=[imgDir() stringByAppendingPathComponent:@".deduped"];
            NSFileManager*fm=[NSFileManager defaultManager]; if([fm fileExistsAtPath:flag]) return;
            for(NSString*f in [fm contentsOfDirectoryAtPath:imgDir() error:NULL]){
                if([f hasPrefix:@"c_"] || ![f hasSuffix:@".jpg"]) continue;
                NSString*p=[imgDir() stringByAppendingPathComponent:f];
                NSData*d=[NSData dataWithContentsOfFile:p]; if(d.length) storeDeduped(d,p);
            }
            [@"1" writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }});
    });
}

+ (NSString *)bestURL:(id)images {
    if(![images isKindOfClass:[NSArray class]] || ![images count]) return @"";
    NSArray*a=images; NSUInteger idx=(a.count>=3)?1:0;   // mittleres Bild (~300px) scharf genug & sparsam; sonst größtes
    id im=a[idx]; if(![im isKindOfClass:[NSDictionary class]]) im=a[0];
    id u=[im isKindOfClass:[NSDictionary class]]?im[@"url"]:nil;
    return [u isKindOfClass:[NSString class]]?u:@"";
}

+ (UIImage *)cached:(NSString *)url { return url.length?[gRam() objectForKey:url]:nil; }
+ (BOOL)onDisk:(NSString *)url { return url.length && [[NSFileManager defaultManager] fileExistsAtPath:diskPath(url)]; }

// Cover aus dem Netz: erst über iOS (schnell, mit Sitzungen); lehnt iOS den Host ab (iOS 7 kennt die Zertifikate von Spotifys
// Bild-CDN nicht: SSL-Fehler -9813), über das eigene TLS. Ein Host, bei dem iOS scheitert, geht danach gleich über das eigene TLS.
static NSData* fetchCover(NSString *url) {
    static NSMutableSet*own; static dispatch_once_t o; dispatch_once(&o,^{ own=[NSMutableSet set]; });
    NSURL*u=[NSURL URLWithString:url]; if(!u) return nil;
    BOOL viaOwn; @synchronized(own){ viaOwn=u.host && [own containsObject:u.host]; }
    if(!viaOwn){ NSData*d=[NSData dataWithContentsOfURL:u];
        if(d.length || ![u.scheme isEqualToString:@"https"] || ![MMSpotify networkReachable]) return d; }   // ohne Netz nicht nochmal versuchen
    static dispatch_semaphore_t slots; static dispatch_once_t so; dispatch_once(&so,^{ slots=dispatch_semaphore_create(3); });   // höchstens 3 gleichzeitig (jede blockiert einen Thread)
    dispatch_semaphore_wait(slots,DISPATCH_TIME_FOREVER); NSData*d=[MMSpotify httpsGet:u]; dispatch_semaphore_signal(slots);
    if(d.length && !viaOwn){ @synchronized(own){ [own addObject:u.host]; } MMLog(@"covers: %@ via own TLS (iOS HTTPS refused)",u.host); }
    return d;
}

static dispatch_queue_t gPre(void){ static dispatch_queue_t q; static dispatch_once_t o; dispatch_once(&o,^{ q=dispatch_queue_create("mesh.covers.prefetch",DISPATCH_QUEUE_SERIAL); }); return q; }
+ (void)prefetch:(NSString *)url {
    if(!url.length || [gRam() objectForKey:url]) return;
    dispatch_async(gPre(), ^{                          // seriell -> hämmert das Netz nicht, blockiert den Audio-Socket nicht
        @autoreleasepool {
            NSString*dp=diskPath(url);
            if([[NSFileManager defaultManager] fileExistsAtPath:dp]) return;
            NSData*d=fetchCover(url);
            if(d.length && [UIImage imageWithData:d]) storeDeduped(d,dp);
        }
    });
}

+ (void)load:(NSString *)url completion:(void(^)(UIImage *))done {
    if(!url.length){ if(done)done(nil); return; }
    UIImage*ram=[gRam() objectForKey:url];
    touchCover(url);
    if(ram){ if(done)done(ram); return; }
    dispatch_async(gQ(), ^{
        UIImage*img=nil;
        NSString*dp=diskPath(url);
        NSData*d=[NSData dataWithContentsOfFile:dp];        // erst Platte
        if(d.length) img=[UIImage imageWithData:d];
        if(!img){                                           // dann Netz
            d=fetchCover(url);
            if(d.length){ img=[UIImage imageWithData:d]; if(img) storeDeduped(d,dp); }
        }
        if(img)[gRam() setObject:img forKey:url cost:imgCost(img)];
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(img); });
    });
}

+ (void)load:(NSString *)url into:(UIImageView *)iv {
    if(!iv) return;
    UIImage*ram=[gRam() objectForKey:url];
    if(ram){ iv.image=ram; touchCover(url); return; }
    // Reuse-Schutz: merke die URL am ImageView, setze Bild nur wenn noch dieselbe
    objc_setAssociatedObject(iv, @selector(image), url, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self load:url completion:^(UIImage*img){
        if(img && [objc_getAssociatedObject(iv, @selector(image)) isEqualToString:url]) iv.image=img;
    }];
}
// ---- Kleine Vorschaubilder für lange Listen ----
// Volles Cover (~300px) wird im Hintergrund gelesen, auf Zeilengröße verkleinert, mit runden Ecken
// vorgezeichnet und fertig dekodiert gemerkt. Der Main-Thread muss beim Scrollen nichts mehr dekodieren,
// und es passen hunderte davon in den Speicher (48px ~ 9 KB statt ~360 KB).
static NSCache *gThumbs(void){ static NSCache*c; static dispatch_once_t o; dispatch_once(&o,^{ c=[[NSCache alloc] init]; c.countLimit=400; }); return c; }
+ (void)thumb:(NSString *)url size:(CGFloat)pt radius:(CGFloat)r into:(UIImageView *)iv {
    if(!iv || !url.length) return;
    NSString*key=[url stringByAppendingFormat:@"#%g#%g",pt,r];
    objc_setAssociatedObject(iv, @selector(image), key, OBJC_ASSOCIATION_COPY_NONATOMIC);   // Reuse-Schutz
    touchCover(url);
    UIImage*t=[gThumbs() objectForKey:key];
    if(t){ iv.image=t; return; }
    dispatch_async(gQ(), ^{ @autoreleasepool {
        UIImage*full=[gRam() objectForKey:url];
        if(!full){
            NSString*dp=diskPath(url); NSData*d=[NSData dataWithContentsOfFile:dp];
            if(d.length) full=[UIImage imageWithData:d];
            if(!full){ d=fetchCover(url); if(d.length){ full=[UIImage imageWithData:d]; if(full) storeDeduped(d,dp); } }
        }
        UIImage*th=nil;
        if(full.size.width>0 && full.size.height>0){
            CGFloat k=MAX(pt/full.size.width,pt/full.size.height), w=full.size.width*k, h=full.size.height*k;   // wie AspectFill
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(pt,pt),NO,0);
            if(r>0) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,pt,pt) cornerRadius:r] addClip];
            [full drawInRect:CGRectMake((pt-w)/2,(pt-h)/2,w,h)];
            th=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
            if(th) [gThumbs() setObject:th forKey:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if(th && [objc_getAssociatedObject(iv, @selector(image)) isEqualToString:key]) iv.image=th;
        });
    }});
}
// ---- Mosaik für Playlists ohne eigenes Bild ----
static NSString *mosaicMemo(void){ return MMPath(@".spotcache/plcovers.plist"); }
+ (void)playlistCover:(NSString *)pid completion:(void(^)(NSString *))done {
    if(!pid.length){ if(done)done(nil); return; }
    static NSMutableDictionary*memo; static NSMutableDictionary*waiting;
    if(!memo){ memo=[[NSDictionary dictionaryWithContentsOfFile:mosaicMemo()] mutableCopy]?:[NSMutableDictionary dictionary]; waiting=[NSMutableDictionary dictionary]; }
    NSDictionary*m=memo[pid];
    NSString*mu=m[@"url"];
    // Mosaik-Dateien liegen im App-Ordner, dessen Name sich bei jedem Update ändert -> gemerkten Pfad auf den aktuellen Ordner umbiegen
    if([mu hasPrefix:@"file:"]) mu=[[NSURL fileURLWithPath:[imgDir() stringByAppendingPathComponent:[[(NSURL*)[NSURL URLWithString:mu] path] lastPathComponent]]] absoluteString];
    BOOL fileGone=[mu hasPrefix:@"file:"] && ![[NSFileManager defaultManager] fileExistsAtPath:[(NSURL*)[NSURL URLWithString:mu] path]];   // inzwischen abgelaufen
    if(mu.length && !fileGone && ![MMSpotify networkReachable]){ if(done)done(mu); return; }   // offline: gemerktes Mosaik immer nehmen, nicht neu bauen
    double age=[[NSDate date] timeIntervalSince1970]-[m[@"t"] doubleValue];
    if(m && !fileGone && age<(mu.length?7*86400:3600)){ if(done)done(mu.length?mu:nil); return; }   // Treffer eine Woche merken, Fehlschlag (z.B. offline) nur 1 h
    if(waiting[pid]){ if(done)[waiting[pid] addObject:[done copy]]; return; }   // schon unterwegs -> mitwarten
    waiting[pid]=[NSMutableArray array]; if(done)[waiting[pid] addObject:[done copy]];
    void (^finish)(NSString*)=^(NSString*url){
        memo[pid]=@{@"url":url?:@"",@"t":@([[NSDate date] timeIntervalSince1970])};
        [memo writeToFile:mosaicMemo() atomically:YES];
        NSArray*cbs=waiting[pid]; [waiting removeObjectForKey:pid];
        for(void(^cb)(NSString*) in cbs) cb(url);
    };
    [MMSpotify apiUser:@"GET" path:[NSString stringWithFormat:@"playlists/%@?offset=0&limit=16",pid] body:nil completion:^(NSDictionary*j,NSInteger st){
        id items=j[@"tracks"][@"items"]; NSMutableArray*urls=[NSMutableArray array];
        if([items isKindOfClass:[NSArray class]]) for(id it in items){
            if(![it isKindOfClass:[NSDictionary class]]) continue;
            id t=it[@"track"]; if(![t isKindOfClass:[NSDictionary class]]) t=it;
            id alb=t[@"album"]; NSString*u=[alb isKindOfClass:[NSDictionary class]]?[self bestURL:alb[@"images"]]:nil;
            if(u.length && ![urls containsObject:u]) [urls addObject:u];   // verschiedene Alben
            if(urls.count==4) break;
        }
        if(!urls.count){ if(st>=200&&st<300) finish(nil); else { NSArray*cbs=waiting[pid]; [waiting removeObjectForKey:pid]; for(void(^cb)(NSString*) in cbs) cb(nil); } return; }
        if(urls.count<4){ finish(urls[0]); return; }
        // vier Cover laden und zu einem Bild zusammensetzen
        __block NSInteger left=4; NSMutableArray*imgs=[NSMutableArray arrayWithObjects:[NSNull null],[NSNull null],[NSNull null],[NSNull null],nil];
        for(NSUInteger k=0;k<4;k++) [self load:urls[k] completion:^(UIImage*img){
            if(img) imgs[k]=img;
            if(--left) return;
            for(id x in imgs) if(x==[NSNull null]){ finish(urls[0]); return; }
            CGFloat S=300, h=S/2;
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(S,S),YES,1);
            for(NSUInteger q=0;q<4;q++) [imgs[q] drawInRect:CGRectMake((q%2)*h,(q/2)*h,h,h)];
            UIImage*mos=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
            NSString*file=[imgDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"mosaic_%@.jpg",pid]];
            NSData*jpg=UIImageJPEGRepresentation(mos,0.85); [jpg writeToFile:file atomically:YES];
            NSString*url=[[NSURL fileURLWithPath:file] absoluteString];
            [gRam() setObject:mos forKey:url cost:imgCost(mos)];
            storeDeduped(jpg,diskPath(url));
            finish(url);
        }];
    }];
}
// ---- Cover aller eigenen Playlists + Lieblingssongs im Hintergrund auf die Platte holen ----
+ (void)precacheLibrary {
    dedupeExisting();
    expireCovers();
    static BOOL running=NO; if(running) return; running=YES;
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        if(!fresh) return;                                     // erst die frische Antwort abwarten
        NSMutableArray*paths=[NSMutableArray arrayWithObject:@"me/tracks?market=from_token&limit=50"];
        id pl=j[@"items"];
        if([pl isKindOfClass:[NSArray class]]) for(id p in pl){
            if(![p isKindOfClass:[NSDictionary class]] || ![p[@"id"] isKindOfClass:[NSString class]]) continue;
            NSString*u=[self bestURL:p[@"images"]]; if(u.length){ if([self onDisk:u]) touchCover(u); else [self prefetch:u]; }   // Playlist-Bild selbst
            [paths addObject:[NSString stringWithFormat:@"playlists/%@?market=from_token",p[@"id"]]];
        }
        __block void (^next)(NSUInteger)=nil;
        next=[^(NSUInteger k){
            if(k>=paths.count){ running=NO; next=nil; return; }
            NSString*path=paths[k];
            NSArray*list=[NSArray arrayWithContentsOfFile:[NSString stringWithFormat:@"%@/.spotcache/list_%lu.plist",MMDataDir(),(unsigned long)path.hash]];
            void (^queue)(NSArray*)=^(NSArray*urls){
                NSMutableSet*seen=[NSMutableSet set];          // gleiches Album -> nur einmal
                for(NSString*u in urls) if(u.length && ![seen containsObject:u]){ [seen addObject:u]; if([self onDisk:u]) touchCover(u); else [self prefetch:u]; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ if(next) next(k+1); });
            };
            if([list isKindOfClass:[NSArray class]] && list.count){ queue([list valueForKey:@"cover"]); return; }
            // noch nie geöffnet: erste Seite holen (reicht für Cover Flow und Mosaik)
            [MMSpotify apiUser:@"GET" path:path body:nil completion:^(NSDictionary*r,NSInteger s2){
                id items=r[@"items"]; if(![items isKindOfClass:[NSArray class]]) items=r[@"tracks"][@"items"];
                NSMutableArray*urls=[NSMutableArray array];
                if([items isKindOfClass:[NSArray class]]) for(id it in items){
                    if(![it isKindOfClass:[NSDictionary class]]) continue;
                    id t=it[@"track"]; if(![t isKindOfClass:[NSDictionary class]]) t=it;
                    id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]) [urls addObject:[self bestURL:alb[@"images"]]?:@""];
                }
                queue(urls);
            }];
        } copy];
        next(0);
    }];
}
+ (void)likedCoverInto:(UIImageView *)iv {
    static NSString*const url=@"https://misc.scdn.co/liked-songs/liked-songs-300.png";
    for(UIView*v in iv.subviews) [v removeFromSuperview];
    iv.accessibilityIdentifier=@"liked";   // Zelle inzwischen anders belegt? -> Bild nicht mehr setzen
    UIImage*ram=[self cached:url]; if(ram){ iv.image=ram; return; }
    iv.image=nil; iv.backgroundColor=[UIColor colorWithRed:0.29 green:0.16 blue:0.78 alpha:1];
    UILabel*hl=[[UILabel alloc] initWithFrame:iv.bounds]; hl.text=@"\u2665"; hl.textAlignment=NSTextAlignmentCenter; hl.backgroundColor=[UIColor clearColor];
    hl.font=[UIFont systemFontOfSize:iv.bounds.size.height*0.42]; hl.textColor=[UIColor whiteColor]; [iv addSubview:hl];
    [self load:url completion:^(UIImage*img){
        if(!img || ![iv.accessibilityIdentifier isEqualToString:@"liked"]) return;
        [hl removeFromSuperview]; iv.image=img;
    }];
}
@end
