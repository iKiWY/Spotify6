#import "MMTrackListController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMArtistController.h"
#import <objc/runtime.h>
static char kRowKey;   // Zeilennummer am Artist-Label (Album-Seite)
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMSongMenu.h"

@interface MMTrackListController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>
@end

@implementation MMTrackListController {
    NSString *_title, *_path;
    UITableView *_table;
    UILabel *_hint;
    NSMutableArray *_tracks;   // @[ {id,title,artist,cover} ] - wächst beim Scrollen
    NSCache *_imgCache;
    UIButton *_offBtn; UIActivityIndicatorView *_offSpin; UIColor *_grn;   // Offline-Knopf oben rechts
    NSString *_nextPath;       // relativer Pfad der nächsten Seite (nil = fertig)
    BOOL _loadingPage, _firstDone;
    BOOL _showingCache;        // gerade wird die gespeicherte Liste gezeigt, erste frische Seite steht noch aus
    NSArray *_allIds;          // vollständige ID-Liste (für Download der GANZEN Playlist)
    NSArray *_allCovers;       // Cover-URLs der ganzen Liste (werden beim Speichern mit offline geholt)
    UIActivityIndicatorView *_spin;
    // Cover-Ansicht (Einstellung): großes Cover + Name + Artist/Beschreibung + Infozeile, Titel nummeriert
    BOOL _coverStyle;
    BOOL _fromPart;         // gezeigte Liste ist eine gespeicherte Teilliste (nicht alle Seiten)
    BOOL _offline;          // ohne Netz: nicht spielbare Songs grau, Antippen nur bei spielbaren
    NSDictionary *_meta;       // Kopf-Daten der ersten Seite: name, images, artists, release_date, description, owner
    NSUInteger _total;         // Titel insgesamt laut Spotify
    UIImageView *_hCover; UILabel *_hTitle, *_hSub, *_hInfo;
    BOOL _dlRunning;           // nach "Speichern" läuft der Download dieser Liste -> Kreisel statt Knopf
}
+ (BOOL)coverStyle { id v=[[NSUserDefaults standardUserDefaults] objectForKey:@"listCoverStyle"]; return v?[v boolValue]:YES; }   // Standard: an (wer es ausgeschaltet hat, behält aus)
+ (void)setCoverStyle:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"listCoverStyle"]; [[NSUserDefaults standardUserDefaults] synchronize]; }

- (id)initWithTitle:(NSString *)title path:(NSString *)path {
    if((self=[super init])){ _title=title; _path=path; _imgCache=[[NSCache alloc] init]; _coverStyle=[MMTrackListController coverStyle]; }
    return self;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34);
    [SpotTheme styleBackButton:back]; [back setTitleColor:[SpotTheme ink] forState:UIControlStateNormal];
    back.titleLabel.font=[UIFont systemFontOfSize:14]; back.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];

    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(70,8,W-140,34)];
    nav.text=_title; nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; nav.adjustsFontSizeToFitWidth=YES; [self.view addSubview:nav];

    // --- Offline-Knopf oben rechts (gegenüber von Zurück); fragt vor dem Speichern und vor dem Entfernen nach ---
    _grn=[UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1];
    _offBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _offBtn.frame=CGRectMake(W-52,8,44,34);
    _offBtn.hidden=YES; [self.view addSubview:_offBtn];
    if([self isDownloads]){ [_offBtn setImage:shuffleIcon() forState:UIControlStateNormal]; [_offBtn addTarget:self action:@selector(shufflePlay) forControlEvents:UIControlEventTouchUpInside]; }   // "Heruntergeladen": Zufallswiedergabe statt Download
    else [_offBtn addTarget:self action:@selector(toggleDownload) forControlEvents:UIControlEventTouchUpInside];
    _offSpin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _offSpin.center=_offBtn.center; _offSpin.hidesWhenStopped=YES; [self.view addSubview:_offSpin];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=([SpotTheme ios6]&&_coverStyle)?52:MMTrackRowH; _table.contentInset=UIEdgeInsetsMake(0,0,MMPageBottomInset(90),0);   // iOS 6: Zeilen so hoch wie in der Warteschlange
    _table.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth; [SpotTheme skinTable:_table]; if([SpotTheme ios6]){ _table.backgroundColor=[SpotTheme shelfColor]; if(_coverStyle) _table.separatorStyle=UITableViewCellSeparatorStyleNone; }   // iOS 6: Grund wie die Startseite; Musik-App-Zeilen zeichnen ihre Linien selbst
    [self.view addSubview:_table];

    if(_coverStyle) [self buildHeader];
    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,_coverStyle?190:110,W-40,40)]; _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; [self.view addSubview:_hint];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.center=CGPointMake(W/2,_coverStyle?210:90); _spin.hidesWhenStopped=YES; [_spin startAnimating]; [self.view addSubview:_spin];

    __weak MMTrackListController*ws=self;   // lange drücken: Als Nächstes / Warteschlange / Lieblingssongs / Playlist
    [MMSongMenu attachToTable:_table swipeToQueue:YES trackAt:^NSDictionary*(NSIndexPath*ip){ MMTrackListController*s=ws; return (s && ip.row<(NSInteger)s->_tracks.count)?s->_tracks[ip.row]:nil; }];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlRefresh) name:@"MMDownloadDone" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlRefresh) name:@"MMDownloadsChanged" object:nil];
    for(NSString*n in @[@"MMDownloadFull",@"MMDownloadError"]) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlStopped) name:n object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(netChanged) name:@"MMNetworkChanged" object:nil];
    [self load];
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}

// ---- Kopf der Cover-Ansicht ----
- (void)buildHeader {
    // kleines Cover links, Angaben rechts daneben -> die ersten Titel bleiben ohne Scrollen sichtbar
    CGFloat W=self.view.bounds.size.width, side=112, x=16+side+12, tw=W-x-12;
    UIView*h=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,side+18)];
    BOOL six=[SpotTheme ios6]; if(six) h.frame=CGRectMake(0,0,W,side+22);   // iOS 6: Platz für das Spiegelbild
    _hCover=[SpotTheme shelfCover:CGRectMake(16,6,side,side) in:h reflection:six?13:0 fade:[UIColor colorWithWhite:0.90 alpha:1]]; _hCover.backgroundColor=[SpotTheme card];
    _hTitle=[[UILabel alloc] initWithFrame:CGRectMake(x,8,tw,44)]; _hTitle.font=[UIFont boldSystemFontOfSize:18]; _hTitle.textColor=[SpotTheme ink];
    _hTitle.numberOfLines=2; _hTitle.backgroundColor=[UIColor clearColor]; [h addSubview:_hTitle];
    _hSub=[[UILabel alloc] initWithFrame:CGRectMake(x,54,tw,32)]; _hSub.font=[UIFont boldSystemFontOfSize:12]; _hSub.textColor=[SpotTheme ink];
    _hSub.numberOfLines=2; _hSub.backgroundColor=[UIColor clearColor]; [h addSubview:_hSub];
    if([_path hasPrefix:@"albums/"]){ _hSub.userInteractionEnabled=YES; [_hSub addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerArtistTap)]]; }
    _hInfo=[[UILabel alloc] initWithFrame:CGRectMake(x,86,tw,32)]; _hInfo.font=[UIFont systemFontOfSize:11]; _hInfo.textColor=[SpotTheme muted];
    _hInfo.numberOfLines=2; _hInfo.backgroundColor=[UIColor clearColor]; [h addSubview:_hInfo];
    if(six){   // wie ein Album in der Musik-App: grauer Verlauf, Cover mit Spiegelbild, dunkelgraue Schrift mit weißem Schatten, Linie zur ersten Zeile
        [SpotTheme albumHeadBackground:h];
        _hTitle.textColor=[SpotTheme ink]; _hSub.textColor=[SpotTheme ink]; _hInfo.textColor=[SpotTheme muted];
        _hTitle.font=[UIFont boldSystemFontOfSize:16]; _hSub.font=[UIFont boldSystemFontOfSize:11]; _hInfo.font=[UIFont boldSystemFontOfSize:10];   // kleiner, wie die Musik-App
        for(UILabel*l in @[_hTitle,_hSub,_hInfo]){ [SpotTheme engrave:l]; l.shadowColor=[UIColor colorWithWhite:1 alpha:0.45]; }   // schwacher Schatten: auf dem dunklen Verlaufsanfang wirkte der volle wie ein Schein
    }
    MMAutoMask(h);
    _table.tableHeaderView=h;
    [self updateHeader];
}
static NSString* stripTags(NSString*s){   // Playlist-Beschreibungen enthalten oft <a href=…>-Links und &amp;
    if(![s isKindOfClass:[NSString class]]) return @"";
    NSMutableString*o=[NSMutableString string]; BOOL tag=NO;
    for(NSUInteger i=0;i<s.length;i++){ unichar c=[s characterAtIndex:i]; if(c=='<') tag=YES; else if(c=='>') tag=NO; else if(!tag) [o appendFormat:@"%C",c]; }
    for(NSArray*e in @[@[@"&amp;",@"&"],@[@"&#x27;",@"'"],@[@"&#39;",@"'"],@[@"&quot;",@"\""],@[@"&lt;",@"<"],@[@"&gt;",@">"]]) [o replaceOccurrencesOfString:e[0] withString:e[1] options:0 range:NSMakeRange(0,o.length)];
    return o;
}
static NSString* fmtDuration(long long ms){
    long long m=(ms+30000)/60000; if(m<60) return [NSString stringWithFormat:L(@"%lld min"),m];
    return [NSString stringWithFormat:L(@"%lld h %lld min"),m/60,m%60];
}
- (void)updateHeader {
    if(!_hCover) return;
    BOOL liked=[_path hasPrefix:@"me/tracks"], album=[_path hasPrefix:@"albums/"];
    _hTitle.text=[_meta[@"name"] length]?_meta[@"name"]:_title;
    // Untertitel: Album -> Artist; Playlist -> Beschreibung (sonst "Spotify" bei Spotify-Listen)
    NSString*sub=@"";
    if(album){ NSArray*a=_meta[@"artists"]; if([a isKindOfClass:[NSArray class]]&&a.count&&[a[0][@"name"] isKindOfClass:[NSString class]]) sub=a[0][@"name"]; }
    else if(!liked){ sub=stripTags(_meta[@"description"]); if(!sub.length && [_meta[@"owner"][@"id"] isEqual:@"spotify"]) sub=@"Spotify"; }
    _hSub.text=sub;
    // Infozeile: Art · Jahr · Anzahl, Dauer (Dauer erst, wenn alle Titel geladen sind)
    NSMutableArray*parts=[NSMutableArray arrayWithObject:album?L(@"Album"):L(@"Playlist")];
    NSString*yr=[_meta[@"release_date"] isKindOfClass:[NSString class]]?_meta[@"release_date"]:nil; if(album && yr.length>=4) [parts addObject:[yr substringToIndex:4]];
    NSString*kind=[parts componentsJoinedByString:@" · "], *cnt=nil;
    NSUInteger n=_total?:_tracks.count;
    if(n){ cnt=(n==1)?L(@"1 song"):[NSString stringWithFormat:L(@"%lu songs"),(unsigned long)n];
        // gespeicherte Teilliste: keine falsche Gesamtdauer
        long long ms=0; BOOL all=(!_nextPath && _tracks.count && !_fromPart); for(NSDictionary*t in _tracks) ms+=[t[@"dur"] longLongValue];
        if(all && ms>0) cnt=[cnt stringByAppendingFormat:@", %@",fmtDuration(ms)]; }
    // Eine Zeile, wenn alles passt; sonst Anzahl + Dauer komplett in die zweite Zeile (nie mitten drin umbrechen)
    NSString*one=cnt?[NSString stringWithFormat:@"%@ · %@",kind,cnt]:kind;
    // Alben: Anzahl + Dauer immer in eine eigene Zeile; Playlists: nur wenn es nicht in eine Zeile passt
    _hInfo.text=(!cnt || (!album && [one sizeWithFont:_hInfo.font].width<=_hInfo.bounds.size.width))?one:[NSString stringWithFormat:@"%@\n%@",kind,cnt];
    [self layoutHeader];
    if(liked){ [MMCovers likedCoverInto:_hCover]; return; }
    if([self isDownloads]){ for(UIView*v in _hCover.subviews)[v removeFromSuperview]; _hCover.image=[SpotTheme downloadsCover:_hCover.bounds.size.width]; return; }
    NSString*cu=[MMCovers bestURL:_meta[@"images"]]; if(!cu.length && _tracks.count && album) cu=_tracks[0][@"cover"];
    if(cu.length){ for(UIView*v in _hCover.subviews)[v removeFromSuperview]; [MMCovers load:cu into:_hCover]; }
    // Playlist ohne eigenes Bild: Mosaik wie in der Bibliothek. Erst wenn die Kopf-Daten da sind (sonst gewann beim ersten
    // Öffnen das langsamere Mosaik gegen das echte Cover) und nur, wenn bis dahin kein echtes Bild aufgetaucht ist.
    else if(!album && _meta && !_hCover.image){ __weak MMTrackListController*ws=self;
        [MMCovers playlistCover:[[[_path componentsSeparatedByString:@"?"][0] componentsSeparatedByString:@"/"] lastObject] completion:^(NSString*mu){
            MMTrackListController*s=ws; if(mu.length && s && ![MMCovers bestURL:s->_meta[@"images"]].length) [MMCovers load:mu into:s->_hCover]; }]; }
}
// Titel / Untertitel / Info rechts neben dem Cover: jede Zeile so hoch wie ihr Text, gleiche Abstände, als Block mittig zum Cover
- (void)layoutHeader {
    // Abstände: Titel→Artist knapper (2), Artist→Info großzügiger (6) - die Zeilenhöhen der Schriften bringen eigenen Weißraum mit
    CGFloat x=_hTitle.frame.origin.x, tw=_hTitle.bounds.size.width, g1=2, g2=6, side=_hCover.bounds.size.height, y0=_hCover.frame.origin.y;
    CGFloat (^fit)(UILabel*,NSInteger)=^CGFloat(UILabel*l,NSInteger lines){
        if(!l.text.length){ l.hidden=YES; return 0; } l.hidden=NO;
        CGFloat lh=l.font.lineHeight, h=[l.text sizeWithFont:l.font constrainedToSize:CGSizeMake(tw,lh*lines+1) lineBreakMode:NSLineBreakByTruncatingTail].height;
        return MIN(ceil(h),ceil(lh*lines)); };
    CGFloat ht=fit(_hTitle,2), hs=fit(_hSub,2), hi=fit(_hInfo,2);
    CGFloat total=ht+(hs?g1+hs:0)+(hi?(hs?g2:g1)+hi:0), y=y0+floor(MAX(0,(side-total)/2));   // ganze Punkte: halbe ließen die Schrift verschwommen aussehen (Playlists)
    _hTitle.frame=CGRectMake(x,y,tw,ht); y+=ht+g1;
    if(hs){ _hSub.frame=CGRectMake(x,y,tw,hs); y+=hs+g2; }
    if(hi) _hInfo.frame=CGRectMake(x,y,tw,hi);
}
- (void)netChanged { BOOL o=![MMSpotify networkReachable]; if(o!=_offline){ _offline=o; [_table reloadData]; } }
// Teilliste (noch nicht alle Seiten geladen): eigene Datei, damit die Bibliothek sie nicht für vollständig hält
- (NSString *)partPath { return [[self listPath] stringByAppendingString:@".part"]; }
- (NSArray *)cachedList {
    NSArray*full=[NSArray arrayWithContentsOfFile:[self listPath]]; _fromPart=!full;
    return full?:[NSArray arrayWithContentsOfFile:[self partPath]];
}
- (NSString *)metaPath { return [[self listPath] stringByAppendingString:@".meta"]; }

- (NSString *)listPath { return [NSString stringWithFormat:@"%@/.spotcache/list_%lu.plist",MMDataDir(), (unsigned long)_path.hash]; }

- (void)load {
    _tracks=[NSMutableArray array];
    _offline=![MMSpotify networkReachable];
    NSArray*cached=[self cachedList];   // zuletzt geladene Liste (komplett oder bis wohin gescrollt) sofort zeigen
    NSDictionary*cm=[NSDictionary dictionaryWithContentsOfFile:[self metaPath]]; if(cm){ _meta=cm[@"meta"]; _total=[cm[@"total"] unsignedIntegerValue]; }
    if(cached.count){ _tracks=[cached mutableCopy]; _allIds=[cached valueForKey:@"id"]; _showingCache=YES;
        [_spin stopAnimating]; _hint.hidden=YES; [self updateDlState]; [_table reloadData]; }
    [self updateHeader];
    [self loadNextPage];
}

- (NSArray *)parseItems:(NSArray *)items {
    NSMutableArray*out=[NSMutableArray array];
    for(NSDictionary*it in items){
        if(![it isKindOfClass:[NSDictionary class]]) continue;
        id tw=it[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:([it isKindOfClass:[NSDictionary class]]?it:nil);
        NSString*tid=[t[@"id"] isKindOfClass:[NSString class]]?t[@"id"]:nil;
        if(!tid) continue;   // NSNull/removed/local tracks überspringen
        NSString*nm=[t[@"name"] isKindOfClass:[NSString class]]?t[@"name"]:@"";
        id arts=t[@"artists"]; NSString*an=@"";
        NSString*aid=@"";
        if([arts isKindOfClass:[NSArray class]] && [arts count]){ id a0=[arts objectAtIndex:0]; if([a0 isKindOfClass:[NSDictionary class]] && [a0[@"name"] isKindOfClass:[NSString class]]) an=a0[@"name"];
            if([a0 isKindOfClass:[NSDictionary class]] && [a0[@"id"] isKindOfClass:[NSString class]]) aid=a0[@"id"]; }
        id alb=t[@"album"]; NSString*cov=@"", *aln=@"";
        if([alb isKindOfClass:[NSDictionary class]]){ cov=[MMCovers bestURL:alb[@"images"]];   // scharfes (mittleres) Cover
            if([alb[@"name"] isKindOfClass:[NSString class]]) aln=alb[@"name"]; }   // Album-Spalte (iPad)
        id dur=t[@"duration_ms"];
        [out addObject:@{@"id":tid,@"title":nm,@"artist":an,@"artistId":aid,@"album":aln,@"cover":cov?:@"",@"dur":[dur isKindOfClass:[NSNumber class]]?dur:@0}];
    }
    return out;
}

// Lädt EINE Seite (50–100 Titel). Beim Scrollen ans Ende wird die nächste nachgeladen.
- (void)loadNextPage {
    if(_loadingPage) return;
    if(_firstDone && !_nextPath) return;   // alles da
    _loadingPage=YES;
    NSString*p = _nextPath ?: _path;       // erste Seite = _path
    [MMSpotify apiUser:@"GET" path:p body:nil completion:^(NSDictionary*j,NSInteger st){
        _loadingPage=YES;   // bleibt gesperrt bis fertig verarbeitet
        NSDictionary*page=[j isKindOfClass:[NSDictionary class]]?j:nil;
        if(page && [p isEqualToString:_path]){   // erste Seite: Kopf-Daten (Name, Bild, Artist, Jahr, Beschreibung) merken
            NSMutableDictionary*m=[NSMutableDictionary dictionary];
            for(NSString*k in @[@"name",@"images",@"artists",@"release_date",@"description",@"owner"]) if(page[k] && ![page[k] isKindOfClass:[NSNull class]]) m[k]=page[k];
            NSDictionary*tp=[page[@"tracks"] isKindOfClass:[NSDictionary class]]?page[@"tracks"]:page; id tot=tp[@"total"];
            _meta=m; if([tot respondsToSelector:@selector(unsignedIntegerValue)]) _total=[tot unsignedIntegerValue];
            [@{@"meta":m,@"total":@(_total)} writeToFile:[self metaPath] atomically:YES];
            [self updateHeader];
        }
        if(page && ![page[@"items"] isKindOfClass:[NSArray class]] && [page[@"tracks"] isKindOfClass:[NSDictionary class]]) page=page[@"tracks"];  // Playlist: items unter .tracks
        NSArray*items=page[@"items"];
        if(![items isKindOfClass:[NSArray class]]){
            _loadingPage=NO; _firstDone=YES; [_spin stopAnimating];
            if(_showingCache){ _showingCache=NO; _nextPath=nil; return; }   // offline -> gespeicherte Liste bleibt stehen
            if(!_tracks.count){
                NSArray*cached=[self cachedList];   // Offline-Fallback
                if(cached.count){ _tracks=[cached mutableCopy]; _nextPath=nil; _hint.hidden=YES; [self updateDlState]; [_table reloadData]; return; }
                _hint.text=(st==401)?L(@"Session expired."):L(@"Couldn't load (offline?).");
            }
            return;
        }
        NSArray*fresh=[self parseItems:items];
        if(_showingCache){
            // Erste frische Seite gegen die gezeigte Liste prüfen: gleiche Länge + gleicher Anfang -> unverändert lassen
            _showingCache=NO;
            id tot=page[@"total"]; NSUInteger total=[tot respondsToSelector:@selector(unsignedIntegerValue)]?[tot unsignedIntegerValue]:0;
            if(total>=items.count-fresh.count) total-=items.count-fresh.count;   // übersprungene (lokale/gelöschte) Titel der ersten Seite nicht mitzählen
            NSArray*head=(_tracks.count>=fresh.count)?[_tracks subarrayWithRange:NSMakeRange(0,fresh.count)]:nil;
            if(total==_tracks.count && [head isEqualToArray:fresh]){ _firstDone=YES; _nextPath=nil; _loadingPage=NO; return; }
            _tracks=[NSMutableArray array]; _allIds=nil;   // geändert -> frisch aufbauen
        }
        [_tracks addObjectsFromArray:fresh]; _fromPart=NO;
        // next-URL -> relativer Pfad merken
        id next=page[@"next"]; _nextPath=nil;
        if([next isKindOfClass:[NSString class]] && [next length]){ NSRange r=[next rangeOfString:@"/v1/"]; _nextPath=(r.location!=NSNotFound)?[next substringFromIndex:r.location+4]:next; }
        _firstDone=YES; _loadingPage=NO; [_spin stopAnimating];
        _hint.hidden=(_tracks.count>0); if(!_tracks.count)_hint.text=L(@"Empty.");
        // Liste merken (für offline): komplett, sobald alle Seiten da sind, sonst als Teilliste
        if(_tracks.count){ [[NSFileManager defaultManager] createDirectoryAtPath:MMPath(@".spotcache") withIntermediateDirectories:YES attributes:nil error:NULL];
            if(!_nextPath){ [_tracks writeToFile:[self listPath] atomically:YES]; [[NSFileManager defaultManager] removeItemAtPath:[self partPath] error:NULL]; _allIds=[_tracks valueForKey:@"id"]; }
            else [_tracks writeToFile:[self partPath] atomically:YES]; }
        [self updateDlState]; [_table reloadData]; [self updateHeader];
    }];
}

+ (NSString *)fmtBytes:(long long)b {
    if(b>=1024LL*1024*1024) return [NSString stringWithFormat:@"%.1f GB",b/1073741824.0];
    return [NSString stringWithFormat:@"%.0f MB",b/1048576.0];
}
// Zufallswiedergabe: zwei gekreuzte Pfeile (wie im Player), grün
static UIImage* shuffleIcon(void){
    CGFloat B=26, sz=20, o=3; UIGraphicsBeginImageContextWithOptions(CGSizeMake(B,B),NO,0); [([SpotTheme ios6]?[SpotTheme headerInk]:[SpotTheme green]) setStroke];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    #define P(x,y) CGPointMake(o+sz*(x),o+sz*(y))
    [p moveToPoint:P(0.05,0.25)]; [p addCurveToPoint:P(0.9,0.75) controlPoint1:P(0.5,0.25) controlPoint2:P(0.45,0.75)];
    [p moveToPoint:P(0.05,0.75)]; [p addCurveToPoint:P(0.9,0.25) controlPoint1:P(0.5,0.75) controlPoint2:P(0.45,0.25)];
    [p moveToPoint:P(0.74,0.1)];  [p addLineToPoint:P(0.92,0.25)]; [p addLineToPoint:P(0.74,0.4)];
    [p moveToPoint:P(0.74,0.6)];  [p addLineToPoint:P(0.92,0.75)]; [p addLineToPoint:P(0.74,0.9)];
    #undef P
    [p stroke]; UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
// Knopf-Symbol: Kreis mit Pfeil nach unten (noch nicht offline) bzw. grüner Kreis mit Haken (offline)
static UIImage* offIcon(BOOL have, UIColor*grn){
    if([SpotTheme ios6]){   // iOS 6: kleiner (20), geladen = nur ein weißer Haken in derselben Größe
        CGFloat S=20; UIGraphicsBeginImageContextWithOptions(CGSizeMake(S,S),NO,0); CGContextRef cx=UIGraphicsGetCurrentContext();
        CGContextSetShadowWithColor(cx,CGSizeMake(0,-1),0,[UIColor colorWithWhite:0 alpha:0.4].CGColor); [[UIColor whiteColor] setStroke];
        UIBezierPath*p=[UIBezierPath bezierPath]; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
        if(have){ p.lineWidth=2.6; [p moveToPoint:CGPointMake(3.5,10.5)]; [p addLineToPoint:CGPointMake(8,15)]; [p addLineToPoint:CGPointMake(16.5,5)]; [p stroke]; }
        else { UIBezierPath*c=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1.5,1.5,17,17)]; c.lineWidth=1.5; [c stroke];
            p.lineWidth=1.8; [p moveToPoint:CGPointMake(10,5.5)]; [p addLineToPoint:CGPointMake(10,14)]; [p moveToPoint:CGPointMake(6.5,10.5)]; [p addLineToPoint:CGPointMake(10,14)]; [p addLineToPoint:CGPointMake(13.5,10.5)]; [p stroke]; }
        UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img; }
    if(have) return [SpotTheme downloadedIcon:26];   // gleiches Zeichen wie in den Zeilen
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26,26),NO,0);
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    { [[SpotTheme headerInk] setStroke]; UIBezierPath*c=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2,2,22,22)]; c.lineWidth=1.5; [c stroke];
        [p moveToPoint:CGPointMake(13,7.5)]; [p addLineToPoint:CGPointMake(13,18)]; [p moveToPoint:CGPointMake(8.5,13.5)]; [p addLineToPoint:CGPointMake(13,18)]; [p addLineToPoint:CGPointMake(17.5,13.5)]; [p stroke]; }
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
- (BOOL)isDownloads { return [_path hasPrefix:@"me/downloads"]; }
// Zufallswiedergabe der heruntergeladenen Songs: zufälliger Start, Rest gemischt
- (void)shufflePlay {
    NSArray*list=[self playableTracks]; if(!list.count) return;
    MMRootController*r=[MMRootController shared]; [r setShuffle:YES];
    [r playList:list index:(NSInteger)arc4random_uniform((u_int32_t)list.count) context:[self context]];
}
- (void)updateDlState {
    if([self isDownloads]){ _offBtn.hidden=!_tracks.count; [_offSpin stopAnimating]; return; }
    if(_dlRunning && [MMSpotify isDownloading]){ _offBtn.hidden=YES; [_offSpin startAnimating]; return; }   // lädt gerade: Kreisel
    _dlRunning=NO;
    [_offSpin stopAnimating];
    if(!_tracks.count){ _offBtn.hidden=YES; return; }
    _offBtn.hidden=NO; _offBtn.enabled=YES;
    NSArray*ids=_allIds?:[_tracks valueForKey:@"id"];   // _allIds = vollständig (nach letzter Seite)
    [_offBtn setImage:offIcon(_allIds && [MMSpotify allDownloaded:ids],_grn) forState:UIControlStateNormal];
}
enum { kAlertRemove=1, kAlertSave=2 };
- (void)toggleDownload {
    if(!_tracks.count) return;
    NSArray*ids=_allIds?:[_tracks valueForKey:@"id"];
    if(_allIds && [MMSpotify allDownloaded:ids]){
        UIAlertView*a=[[UIAlertView alloc] initWithTitle:L(@"Remove offline?") message:L(@"Delete the downloaded tracks of this playlist.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Remove"),nil];
        a.tag=kAlertRemove; [a show];
        return;
    }
    // Noch nicht alle Seiten da? -> erst vollständige ID-Liste holen (klein), dann fragen und die GANZE Liste laden.
    if(!_allIds){
        _offBtn.hidden=YES; [_offSpin startAnimating];
        [MMSpotify apiUserAllItems:_path completion:^(NSArray*items,NSInteger st){
            NSMutableArray*out=[NSMutableArray array], *covs=[NSMutableArray array];
            for(id it in items){
                if(![it isKindOfClass:[NSDictionary class]])continue;
                id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it;
                id tid=t[@"id"]; if([tid isKindOfClass:[NSString class]])[out addObject:tid];
                id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]){ NSString*cu=[MMCovers bestURL:alb[@"images"]]; if(cu.length)[covs addObject:cu]; }
            }
            [self updateDlState];
            if(!out.count) return;
            _allIds=out; _allCovers=covs; [self askSave];
        }];
        return;
    }
    [self askSave];
}
- (void)askSave {
    NSString*msg=LF(@"%lu tracks · %@ free",(unsigned long)_allIds.count,[MMTrackListController fmtBytes:[MMSpotify freeDiskBytes]]);
    UIAlertView*a=[[UIAlertView alloc] initWithTitle:L(@"Save offline?") message:msg delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"),nil];
    a.tag=kAlertSave; [a show];
}
- (void)startDownload:(NSArray *)ids {
    for(NSDictionary*t in _tracks){ NSString*cu=t[@"cover"]; if([cu isKindOfClass:[NSString class]]&&cu.length)[MMCovers prefetch:cu]; }  // geladene Cover offline sichern
    for(NSString*cu in _allCovers) [MMCovers prefetch:cu];   // und die der noch nicht angezeigten Titel
    [MMSpotify markOffline:_title trackIds:ids];   // dauerhaft als Offline-Liste merken -> Auto-Resume nach Neustart
    [MMSpotify queueDownloadTracks:ids];   // globale Warteschlange; Status läuft über die globale Leiste (Notifications)
    _dlRunning=YES; [self updateDlState];
}
- (void)alertView:(UIAlertView *)av clickedButtonAtIndex:(NSInteger)idx {
    if(idx!=1) return;
    if(av.tag==kAlertSave){ [self startDownload:_allIds]; return; }
    NSArray*ids=_allIds?:[_tracks valueForKey:@"id"]; [MMSpotify unmarkOffline:ids]; [MMSpotify removeDownloads:ids]; [self updateDlState]; [_table reloadData];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _tracks.count; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    if(_nextPath && !_loadingPage && ip.row >= (NSInteger)_tracks.count-8) [self loadNextPage];   // nahe Ende -> nächste Seite
}
// Zeilen: 56 pt hoch. iPad: rechts Spalten für Album (nicht auf Album-Seiten, da überall gleich) und Dauer.
// Album-Seiten: Antippen des Artist-Namens öffnet den Artist (der Rest der Zeile spielt wie bisher).
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width, RH=tv.rowHeight;
    BOOL albumPage=[_path hasPrefix:@"albums/"], cols=MMIsPad(), albumCol=cols && !albumPage;
    CGFloat timeX=W-32-8-48, albumX=floor(W*0.55), textR=cols?(albumCol?albumX-12:timeX-12):W-40;
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"r",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"r",tv)];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        // Cover-Ansicht: Nummer vorn; Alben ohne Cover (alle gleich), Playlists mit kleinem Cover zwischen Nummer und Titel
        BOOL num=_coverStyle, cover=!_coverStyle || !albumPage, six=num && [SpotTheme ios6];
        CGFloat tx=num?(cover?84:40):70; if(six) tx=cover?96:52;
        if(six){   // iOS 6 wie die Musik-App: Zeilen abwechselnd hell/dunkler, Nummernspalte mit eingeprägter senkrechter Linie
            UIView*bgv=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,RH)]; bgv.tag=60;
            CGFloat lines[][3]={{0,0,1.0},{RH-1,0,0.776}};   // oben weiß, unten grau
            for(int k=0;k<2;k++){ UIView*l=[[UIView alloc] initWithFrame:CGRectMake(0,lines[k][0],W,1)]; l.backgroundColor=[UIColor colorWithWhite:lines[k][2] alpha:1]; l.autoresizingMask=UIViewAutoresizingFlexibleWidth; [bgv addSubview:l]; }
            for(int k=0;k<2;k++){ UIView*l=[[UIView alloc] initWithFrame:CGRectMake(42+k,0,1,RH)]; l.backgroundColor=[UIColor colorWithWhite:k?0.96:0.74 alpha:1]; [bgv addSubview:l]; }
            c.backgroundView=bgv; }
        if(num){ UILabel*no=[[UILabel alloc] initWithFrame:six?CGRectMake(0,0,42,RH):CGRectMake(4,0,30,RH)]; no.tag=5; no.font=six?[UIFont boldSystemFontOfSize:14]:[UIFont systemFontOfSize:15]; no.textColor=six?[SpotTheme ink]:[SpotTheme muted];
            no.textAlignment=NSTextAlignmentCenter; no.adjustsFontSizeToFitWidth=YES; [c.contentView addSubview:no]; }
        if(cover){ UIImageView*cov=[[UIImageView alloc] initWithFrame:six?CGRectMake(50,(RH-40)/2,40,40):num?CGRectMake(36,8,40,40):CGRectMake(16,6,44,44)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; cov.clipsToBounds=YES; cov.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:cov]; }
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(tx,9,textR-tx,20)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.textColor=[SpotTheme ink]; [c.contentView addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(tx,29,textR-tx,18)]; ar.tag=3; ar.font=[SpotTheme sub]; ar.textColor=[SpotTheme muted]; [c.contentView addSubview:ar];
        if(six){ ti.textColor=[SpotTheme ink]; ar.textColor=[SpotTheme muted];
            ti.font=[UIFont boldSystemFontOfSize:14]; ar.font=[UIFont systemFontOfSize:12]; ti.frame=CGRectMake(tx,8,textR-tx,19); ar.frame=CGRectMake(tx,26,textR-tx,17);
            for(UILabel*l in @[ti,ar,(UILabel*)[c.contentView viewWithTag:5]]){ [SpotTheme engrave:l]; l.shadowColor=[UIColor colorWithWhite:1 alpha:0.6]; } }
        if(albumPage){ ar.userInteractionEnabled=YES; [ar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowArtistTap:)]]; }
        if(albumCol){ UILabel*al=[[UILabel alloc] initWithFrame:CGRectMake(albumX,0,timeX-12-albumX,RH)]; al.tag=6; al.font=[SpotTheme sub]; al.textColor=[SpotTheme muted]; [c.contentView addSubview:al]; }
        if(cols){ UILabel*tm=[[UILabel alloc] initWithFrame:CGRectMake(timeX,0,48,RH)]; tm.tag=7; tm.font=[SpotTheme sub]; tm.textColor=[SpotTheme muted]; tm.textAlignment=NSTextAlignmentRight; [c.contentView addSubview:tm]; }
        UIImageView*dl=[[UIImageView alloc] initWithFrame:CGRectMake(W-32,(RH-18)/2,18,18)]; dl.tag=4; dl.contentMode=UIViewContentModeCenter; dl.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin; [c.contentView addSubview:dl]; }
    NSDictionary*t=_tracks[ip.row];
    if(c.backgroundView.tag==60) c.backgroundView.backgroundColor=[UIColor colorWithWhite:(ip.row%2)?0.918:0.871 alpha:1];   // abwechselnd wie die Musik-App
    ((UILabel*)[c.contentView viewWithTag:2]).text=t[@"title"];
    UILabel*ar=(UILabel*)[c.contentView viewWithTag:3]; ar.text=t[@"artist"]; objc_setAssociatedObject(ar,&kRowKey,@(ip.row),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(albumPage){ CGRect f=ar.frame; f.size.width=MIN([t[@"artist"] sizeWithFont:ar.font].width+8,textR-f.origin.x); ar.frame=f; }   // nur der Name ist antippbar, der Rest der Zeile spielt
    ((UILabel*)[c.contentView viewWithTag:6]).text=t[@"album"];
    long long ms=[t[@"dur"] longLongValue]; ((UILabel*)[c.contentView viewWithTag:7]).text=ms>0?[NSString stringWithFormat:@"%lld:%02lld",ms/60000,(ms/1000)%60]:@"";
    ((UIImageView*)[c.contentView viewWithTag:4]).image=[MMSpotify isDownloaded:t[@"id"]]?[SpotTheme downloadedIcon:18]:nil;
    if(_coverStyle) ((UILabel*)[c.contentView viewWithTag:5]).text=[NSString stringWithFormat:@"%ld",(long)ip.row+1];
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1];
    if(cov){ cov.image=nil; [MMCovers load:t[@"cover"] into:cov]; }   // gemeinsamer RAM+Platte-Cache (reuse-sicher)
    c.contentView.alpha=(_offline && ![MMSpotify playableOffline:t[@"id"]])?0.35:1;   // offline nicht spielbar -> grau
    return c;
}
// Album-Seite: Artist-Name in einer Zeile oder im Kopf -> Artist-Seite
- (void)rowArtistTap:(UITapGestureRecognizer *)g {
    NSInteger r=[objc_getAssociatedObject(g.view,&kRowKey) integerValue];
    if(r<0 || r>=(NSInteger)_tracks.count) return;
    NSDictionary*t=_tracks[r]; [self openArtist:t[@"artistId"] name:t[@"artist"]];
}
- (void)headerArtistTap {
    NSArray*a=_meta[@"artists"]; NSDictionary*a0=([a isKindOfClass:[NSArray class]] && a.count)?a[0]:nil;
    if([a0 isKindOfClass:[NSDictionary class]]) [self openArtist:a0[@"id"] name:a0[@"name"]];
}
- (void)openArtist:(NSString *)aid name:(NSString *)name {
    if(![aid isKindOfClass:[NSString class]] || !aid.length) return;
    [[MMRootController shared] pushContent:[[MMArtistController alloc] initWithArtistId:aid name:name]];
}
// was ohne Netz spielt (heruntergeladen / im Song-Cache); online alles
- (NSArray *)playableTracks {
    if(!_offline) return _tracks;
    NSMutableArray*p=[NSMutableArray array]; for(NSDictionary*t in _tracks) if([MMSpotify playableOffline:t[@"id"]]) [p addObject:t];
    return p;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];   // Auswahl nicht stehen lassen (sonst bleibt die Schrift weiß)
    NSDictionary*t=_tracks[ip.row]; NSArray*list=[self playableTracks]; NSUInteger i=[list indexOfObject:t];
    if(i==NSNotFound) return;   // offline und nicht gespeichert: grau, spielt nicht
    [[MMRootController shared] playList:list index:(NSInteger)i context:[self context]];
}
// Herkunft für den Verlauf: Lieblingssongs, Playlist oder Album (Cover = Albumcover des ersten Titels)
- (NSDictionary *)context {
    NSString*id_=[[[_path componentsSeparatedByString:@"?"][0] componentsSeparatedByString:@"/"] lastObject];
    if([_path hasPrefix:@"me/tracks"]) return @{@"type":@"liked"};
    if([self isDownloads]) return @{@"type":@"downloads",@"name":L(@"Downloaded")};
    if([_path hasPrefix:@"playlists/"]){ NSString*cu=[MMCovers bestURL:_meta[@"images"]];   // echtes Playlist-Cover (sonst zeigte die Startseite keins)
        return @{@"type":@"playlist",@"id":id_,@"name":[_meta[@"name"] length]?_meta[@"name"]:(_title?:@""),@"images":cu.length?@[@{@"url":cu}]:@[]}; }
    if([_path hasPrefix:@"albums/"]){ NSString*cu=_tracks.count?_tracks[0][@"cover"]:nil;
        return @{@"type":@"album",@"id":id_,@"name":_title?:@"",@"images":cu.length?@[@{@"url":cu}]:@[]}; }
    return nil;
}
- (void)close { [[MMRootController shared] popContent]; }
- (void)dlRefresh { if(![MMSpotify isDownloading]) _dlRunning=NO; [self updateDlState]; [_table reloadData]; }
- (void)dlStopped { _dlRunning=NO; [self updateDlState]; [_table reloadData]; }   // nach Download-Ende ✓-Marken aktualisieren
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }   // iPad gedreht: Zellen in neuer Breite
@end
