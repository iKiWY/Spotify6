#import "MMRecent.h"
#import "MMSpotify.h"
#import "MMHistory.h"
#import "MMCovers.h"

static long long atOf(NSDictionary*d){ id a=d[@"at"]; return [a respondsToSelector:@selector(longLongValue)]?[a longLongValue]:0; }

@implementation MMRecent

+ (NSArray *)mergePlaylists:(NSArray *)server max:(NSUInteger)max {
    NSMutableArray*all=[NSMutableArray array];
    for(id x in [[MMHistory contexts] arrayByAddingObjectsFromArray:server?:@[]])
        if([x isKindOfClass:[NSDictionary class]] && [x[@"type"] isEqual:@"playlist"] && [x[@"id"] isKindOfClass:[NSString class]]) [all addObject:x];
    [all sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary*x,NSDictionary*y){ long long p=atOf(x),q=atOf(y); return p>q?NSOrderedAscending:p<q?NSOrderedDescending:NSOrderedSame; }];
    // Bild: fehlt es beim neuesten Eintrag (älterer Verlauf in der App), das aus einem anderen Eintrag derselben Playlist nehmen
    NSMutableDictionary*img=[NSMutableDictionary dictionary];
    for(NSDictionary*x in all){ NSString*u=[MMCovers smallURL:x[@"images"]]; if(u.length && !img[x[@"id"]]) img[x[@"id"]]=u; }
    NSMutableArray*out=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(NSDictionary*x in all){
        if([seen containsObject:x[@"id"]]) continue; [seen addObject:x[@"id"]];
        NSString*nm=[x[@"name"] isKindOfClass:[NSString class]]?x[@"name"]:@"";
        [out addObject:@{@"id":x[@"id"],@"name":nm,@"cover":img[x[@"id"]]?:@""}];
        if(out.count>=max) break;
    }
    return out;
}

// Seitenleiste und Startseite fragen meist gleichzeitig: eine laufende Anfrage bedient alle Wartenden
// Spotifys Liste kostet ~20 Anfragen (eine je Playlist) -> höchstens alle 10 Minuten neu holen. Eigene Wiedergaben
// stehen sofort drin, weil mergePlaylists den Verlauf dieser App (MMHistory) dazumischt.
#define RECENT_REFRESH 600
+ (void)playlists:(NSUInteger)max done:(void(^)(NSArray *list))done {
    static NSMutableArray*waiting; static NSArray*lastItems, *knownItems; static CFAbsoluteTime askedAt;
    void (^cb)(NSArray*)=[^(NSArray*items){ done([self mergePlaylists:items max:max]); } copy];
    // gemessen ab dem letzten Senden: apiUserCached meldet eine unveränderte Antwort gar nicht erst
    if(!waiting && knownItems && CFAbsoluteTimeGetCurrent()-askedAt<RECENT_REFRESH){ cb(knownItems); return; }
    if(waiting){ [waiting addObject:cb]; if(lastItems) cb(lastItems); return; }   // läuft schon: Zwischenstand sofort, frisch später
    waiting=[NSMutableArray arrayWithObject:cb]; lastItems=nil; askedAt=CFAbsoluteTimeGetCurrent();
    // unveränderte Daten melden sich nicht ein zweites Mal -> Anfrage nach 20 s spätestens als beendet ansehen
    NSMutableArray*mine=waiting;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(20*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ if(waiting==mine) waiting=nil; });
    __block BOOL answered=NO;
    [MMSpotify apiUserCached:@"me/recent-contexts?limit=20" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*items=[j[@"items"] isKindOfClass:[NSArray class]]?j[@"items"]:nil;
        if(items) lastItems=knownItems=items;
        NSArray*cbs=[waiting copy]; if(fresh) waiting=nil;   // die frische (oder fehlgeschlagene) Antwort beendet die Anfrage
        if(!items && answered) return;
        answered=YES; for(void(^c)(NSArray*) in cbs) c(items);
    }];
    // ohne Netz und ohne gespeicherte Antwort: wenigstens der Verlauf dieser App
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(!answered){ answered=YES; for(void(^c)(NSArray*) in [waiting copy]) c(nil); } });
}

+ (void)artistImage:(NSString *)artistId done:(void(^)(NSString *url))done {
    static NSMutableDictionary*mem, *waiting;   // gefundene Bilder; laufende Anfragen -> wartende Rückrufe
    if(!mem){ mem=[NSMutableDictionary dictionary]; waiting=[NSMutableDictionary dictionary]; }
    if(!artistId.length){ done(nil); return; }
    if(mem[artistId]){ done(mem[artistId]); return; }
    if(waiting[artistId]){ [waiting[artistId] addObject:[done copy]]; return; }   // schon unterwegs: nur mitwarten
    waiting[artistId]=[NSMutableArray arrayWithObject:[done copy]];
    [MMSpotify apiUserCached:[@"artists/" stringByAppendingString:artistId] completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSString*u=[j isKindOfClass:[NSDictionary class]]?[MMCovers smallURL:j[@"images"]]:nil;
        if(u.length) mem[artistId]=u;   // nur echte Bilder merken: offline gestartet -> beim nächsten Zeichnen erneut
        NSArray*cbs=waiting[artistId]; if(fresh || u.length) [waiting removeObjectForKey:artistId];
        for(void(^cb)(NSString*) in cbs) cb(u.length?u:nil);
    }];
}
@end
