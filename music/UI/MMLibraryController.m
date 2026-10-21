#import "MMLibraryController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMTrackListController.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMSettingsController.h"
#import "MMSheet.h"
#import "MMKeepAlive.h"
#import "MMDownloadsController.h"

@interface MMLibraryController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMLibraryController {
    UITableView *_table;
    UILabel *_hint;
    NSArray *_playlists;   // @[ {name,id} ]
    NSString *_nextPath;   // nächste Seite der Playlists (nil = alle da); wird beim Scrollen ans Ende geladen
    BOOL _loadingMore;
    BOOL _loaded;
    UILabel *_hud;                 // untere Status-/Fortschrittsleiste
    NSArray *_pressedIds;          // Track-IDs der langgedrückten Zeile
    NSString *_pressedName;
    NSInteger _pressedRow;
    UIButton *_dlBtn;              // oben links: öffnet die Downloads-Seite
    BOOL _hasDl;                   // gibt es heruntergeladene Songs? Dann steht "Heruntergeladen" ganz oben
    NSMutableDictionary *_dlMemo;  // Pfad -> @(komplett offline); spart pro Zeile Plist-Lesen + Datei-Checks beim Scrollen
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(NO)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(0,8,W,34)];
    nav.text=L(@"Library"); nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];

    // Zahnrad oben rechts: Einstellungen
    UIButton*gear=[UIButton buttonWithType:UIButtonTypeCustom]; gear.frame=CGRectMake(W-48,6,44,38);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22,22),NO,0); [[SpotTheme headerInk] setFill];
    UIBezierPath*gp=[UIBezierPath bezierPath];
    for(int i=0;i<16;i++){ CGFloat a=i*M_PI/8-M_PI/16, r=(i%2)?8:10.5; CGPoint q=CGPointMake(11+r*cos(a),11+r*sin(a)); if(i==0)[gp moveToPoint:q]; else [gp addLineToPoint:q]; }
    [gp closePath]; [gp appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(11,11) radius:3.5 startAngle:0 endAngle:2*M_PI clockwise:NO]];
    gp.usesEvenOddFillRule=YES; [gp fill];
    [gear setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [gear addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:gear];

    // Download-Symbol oben links (gegenüber dem Zahnrad): öffnet die Downloads-Seite (laufende + heruntergeladene)
    _dlBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _dlBtn.frame=CGRectMake(4,6,44,38);
    [self drawDlBtn];
    [_dlBtn addTarget:self action:@selector(openDownloads) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_dlBtn];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,48,W,H-48) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorColor=[SpotTheme line];
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=[SpotTheme ios6]?45:60; _table.contentInset=UIEdgeInsetsMake(0,0,MMPageBottomInset(84),0);   // Platz für untere Leisten
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [SpotTheme skinTable:_table]; [self.view addSubview:_table];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,120,W-40,60)]; _hint.numberOfLines=0; _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; [self.view addSubview:_hint];

    // untere Status-/Fortschrittsleiste (für Offline-Downloads via Long-Press)
    _hud=[[UILabel alloc] initWithFrame:CGRectMake(0,H-96,W,36)]; _hud.backgroundColor=[SpotTheme card]; _hud.textColor=[SpotTheme ink];
    _hud.font=[UIFont boldSystemFontOfSize:13]; _hud.textAlignment=NSTextAlignmentCenter; _hud.hidden=YES;
    _hud.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth; [self.view addSubview:_hud];

    // gedrückt halten → Offline-Download / Verwaltung
    UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    lp.minimumPressDuration=0.45; [_table addGestureRecognizer:lp];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlRefresh) name:@"MMDownloadDone" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlRefresh) name:@"MMDownloadsChanged" object:nil];
    for(NSString*n in @[@"MMDownloadProgress",@"MMDownloadFull",@"MMDownloadError"]) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(drawDlBtn) name:n object:nil];
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}
- (void)dlRefresh { [_dlMemo removeAllObjects]; [_table reloadData]; [self updateHasDl]; [self drawDlBtn]; }
- (void)openDownloads { [[MMRootController shared] pushContent:[[MMDownloadsController alloc] init]]; }   // ✓-Badges nach Download-Ende aktualisieren
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// --- Offline via Long-Press ---
- (NSString *)pathForRow:(NSInteger)row {
    if(row==0) return @"me/tracks?market=from_token&limit=50";
    return [NSString stringWithFormat:@"playlists/%@?market=from_token",_playlists[row-1][@"id"]];
}
- (NSString *)listPathForRow:(NSInteger)row { return [NSString stringWithFormat:@"%@/.spotcache/list_%lu.plist",MMDataDir(),(unsigned long)[self pathForRow:row].hash]; }
- (NSArray *)cachedIdsForRow:(NSInteger)row {
    NSArray*c=[NSArray arrayWithContentsOfFile:[self listPathForRow:row]];   // von MMTrackListController beim Öffnen gecacht
    return [c isKindOfClass:[NSArray class]]?[c valueForKey:@"id"]:nil;
}
- (NSArray *)idsFromItems:(NSArray *)items {
    if(![items isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray*out=[NSMutableArray array];
    for(id it in items){ if(![it isKindOfClass:[NSDictionary class]])continue; id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it; id tid=t[@"id"]; if([tid isKindOfClass:[NSString class]])[out addObject:tid]; }
    return out;
}
// Download-Symbol: weiß, grün solange etwas herunterlädt
- (void)drawDlBtn {
    BOOL on=[MMSpotify isDownloading]; if(_dlBtn.tag==(on?2:1)) return; _dlBtn.tag=on?2:1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22,22),NO,0); [(on?([SpotTheme ios6]?[UIColor colorWithRed:0.6 green:1 blue:0.65 alpha:1]:[SpotTheme green]):[SpotTheme headerInk]) setStroke];
    UIBezierPath*dc=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1,1,20,20)]; dc.lineWidth=1.6; [dc stroke];
    UIBezierPath*da=[UIBezierPath bezierPath]; da.lineWidth=1.8; da.lineCapStyle=kCGLineCapRound; da.lineJoinStyle=kCGLineJoinRound;
    [da moveToPoint:CGPointMake(11,6)]; [da addLineToPoint:CGPointMake(11,15.5)]; [da moveToPoint:CGPointMake(7,11.5)]; [da addLineToPoint:CGPointMake(11,15.5)]; [da addLineToPoint:CGPointMake(15,11.5)]; [da stroke];
    [_dlBtn setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
}
- (NSInteger)lrow:(NSInteger)tableRow { return tableRow-(_hasDl?1:0); }
- (void)updateHasDl { BOOL h=[MMSpotify downloadedTracks].count>0; if(h!=_hasDl){ _hasDl=h; [_table reloadData]; } }
- (BOOL)rowDownloaded:(NSInteger)row {
    if(!_dlMemo) _dlMemo=[NSMutableDictionary dictionary];
    NSString*key=[self pathForRow:row]; NSNumber*v=_dlMemo[key];
    if(!v){ NSArray*cids=[self cachedIdsForRow:row]; v=@(cids.count && [MMSpotify allDownloaded:cids]); _dlMemo[key]=v; }
    return v.boolValue;
}
- (void)showHud:(NSString *)msg { _hud.text=msg; _hud.hidden=NO; }
- (void)toast:(NSString *)msg {
    _hud.text=msg; _hud.hidden=NO;
    [self performSelector:@selector(hideHud) withObject:nil afterDelay:1.8];
}
- (void)hideHud { _hud.hidden=YES; }

- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateBegan) return;
    NSIndexPath*ip=[_table indexPathForRowAtPoint:[g locationInView:_table]];
    NSInteger r=ip?[self lrow:ip.row]:-1;
    if(r<0 || r>=(NSInteger)(1+_playlists.count)) return;   // "Heruntergeladen" hat kein Download-Menü
    _pressedRow=r;
    _pressedName=(r==0)?L(@"Liked Songs"):_playlists[r-1][@"name"];
    NSArray*cids=[self cachedIdsForRow:r];
    if(cids.count){ _pressedIds=cids; [self showSheet]; return; }   // schnell & offline aus Cache
    [self showHud:L(@"Loading track list …")];
    [MMSpotify apiUserAllItems:[self pathForRow:r] completion:^(NSArray*items,NSInteger st){   // alle Seiten
        _hud.hidden=YES;
        NSArray*ids=[self idsFromItems:items];
        if(!ids.count){ [self toast:L(@"Couldn't load tracks.")]; return; }
        for(id it in items){ if(![it isKindOfClass:[NSDictionary class]])continue; id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it; id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]){ NSString*cu=[MMCovers bestURL:alb[@"images"]]; if(cu.length)[MMCovers prefetch:cu]; } }  // Cover offline mit runterladen
        _pressedIds=ids; [self showSheet];
    }];
}
// Menü wie beim Titel-Menü (MMSheet): Cover, Name, Anzahl + freier Platz, darunter Herunterladen/Entfernen
- (void)showSheet {
    BOOL have=[MMSpotify allDownloaded:_pressedIds];
    NSString*cover=(_pressedRow==0)?@"https://misc.scdn.co/liked-songs/liked-songs-300.png":_playlists[_pressedRow-1][@"cover"];
    NSString*sub=LF(@"Playlist · %lu songs · %@ free",(unsigned long)_pressedIds.count,[MMTrackListController fmtBytes:[MMSpotify freeDiskBytes]]);
    [MMSheet showIn:[MMRootController shared].view title:_pressedName subtitle:sub imageURL:[cover length]?cover:nil
            options:@[have?L(@"Remove download"):L(@"Download")] done:^(NSInteger i){ if(i==0) [self sheetToggle]; }];
}
- (void)sheetToggle {
    NSArray*ids=_pressedIds; BOOL have=[MMSpotify allDownloaded:ids];
    if(!ids.count) return;
    if(have){ [MMSpotify unmarkOffline:ids]; [MMSpotify removeDownloads:ids]; [self toast:L(@"Download removed")]; [self dlRefresh]; return; }
    // Track-Cover offline mit runterladen (aus der gecachten Liste, falls vorhanden)
    NSArray*cached=[NSArray arrayWithContentsOfFile:[self listPathForRow:_pressedRow]];
    for(id t in cached){ if([t isKindOfClass:[NSDictionary class]]){ NSString*cu=((NSDictionary*)t)[@"cover"]; if([cu isKindOfClass:[NSString class]]&&cu.length)[MMCovers prefetch:cu]; } }
    [MMSpotify markOffline:_pressedName trackIds:ids];   // dauerhaft merken -> Auto-Resume nach Neustart
    [MMSpotify queueDownloadTracks:ids];   // globale Warteschlange; Status läuft über die globale Leiste (Notifications)
    [self dlRefresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_dlMemo removeAllObjects];   // Listen könnten inzwischen neu gecacht oder geladen sein
    [self updateHasDl]; [self drawDlBtn];
    if(_loaded) return;
    if(![MMSpotify hasUserToken]){ _hint.text=L(@"Please log in again."); return; }
    _loaded=YES; _hint.text=L(@"Loading your playlists …");
    // erst die zuletzt geladenen Playlists zeigen, frische ersetzen sie still (nur bei Änderung)
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*items=j[@"items"];
        if(![items isKindOfClass:[NSArray class]]){ _hint.text=(st==401)?L(@"Session expired."):L(@"Couldn't load."); _loaded=NO; return; }
        _playlists=[MMLibraryController parsePlaylists:items]; _hint.hidden=YES;
        _nextPath=[j[@"next"] isKindOfClass:[NSString class]]?j[@"next"]:nil; [_table reloadData];
    }];
}
+ (NSArray *)parsePlaylists:(NSArray *)items {   // auch für die iPad-Seitenleiste
    NSMutableArray*out=[NSMutableArray array];
    for(NSDictionary*p in items){ if([p isKindOfClass:[NSDictionary class]]&&p[@"id"]) [out addObject:@{@"name":p[@"name"]?:L(@"Playlist"),@"id":p[@"id"],@"cover":[MMCovers bestURL:p[@"images"]]?:@""}]; }
    return out;
}
// Nächste 50 Playlists anhängen: nur neue Zeilen einfügen (kein komplettes Neuzeichnen), Kreisel unten solange
- (void)loadMore {
    if(_loadingMore || !_nextPath) return;
    _loadingMore=YES; NSString*p=_nextPath;
    UIActivityIndicatorView*sp=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    sp.frame=CGRectMake(0,0,_table.bounds.size.width,44); [sp startAnimating]; _table.tableFooterView=sp;
    [MMSpotify apiUser:@"GET" path:p body:nil completion:^(NSDictionary*j,NSInteger st){
        _loadingMore=NO; _table.tableFooterView=nil;
        NSArray*items=[j[@"items"] isKindOfClass:[NSArray class]]?j[@"items"]:nil;
        if(!items || ![p isEqualToString:_nextPath]) return;   // Fehler (beim nächsten Scrollen erneut) oder Liste inzwischen neu geladen
        NSArray*more=[MMLibraryController parsePlaylists:items]; NSUInteger start=1+_playlists.count+(_hasDl?1:0);   // +1 = Lieblingssongs oben
        _playlists=[_playlists arrayByAddingObjectsFromArray:more];
        _nextPath=[j[@"next"] isKindOfClass:[NSString class]]?j[@"next"]:nil;
        NSMutableArray*ips=[NSMutableArray array]; for(NSUInteger i=0;i<more.count;i++) [ips addObject:[NSIndexPath indexPathForRow:start+i inSection:0]];
        if(ips.count) [_table insertRowsAtIndexPaths:ips withRowAnimation:UITableViewRowAnimationNone];
    }];
}
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    if(_nextPath && ip.row>=(NSInteger)_playlists.count-6) [self loadMore];   // kurz vor dem Ende: nächste Seite
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (_hasDl?1:0) + 1 + _playlists.count; }  // +1 = gespeicherte Songs

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"r",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"r",tv)];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        BOOL six=[SpotTheme ios6];   // iOS 6 wie die Album-Liste der Musik-App: Cover bündig links, große fette Schrift
        UIImageView*th=[[UIImageView alloc] initWithFrame:six?CGRectMake(0,0,44,44):CGRectMake(12,6,48,48)]; th.tag=10; th.contentMode=UIViewContentModeScaleAspectFill; th.clipsToBounds=YES; th.layer.cornerRadius=six?0:2; [c.contentView addSubview:th];
        UILabel*nm=[[UILabel alloc] initWithFrame:six?CGRectMake(53,0,tv.bounds.size.width-53-36,44):CGRectMake(72,0,tv.bounds.size.width-72-40,60)]; nm.tag=11; nm.font=[UIFont boldSystemFontOfSize:six?17:16]; nm.textColor=[SpotTheme ink]; [c.contentView addSubview:nm];
        if(six){ nm.textColor=[SpotTheme ink]; [SpotTheme engrave:nm]; nm.shadowColor=[UIColor colorWithWhite:1 alpha:0.6]; }
        c.accessoryType=UITableViewCellAccessoryNone; }   // keine Pfeile: auf Schwarz kaum sichtbar
    UIImageView*th=(UIImageView*)[c.contentView viewWithTag:10];
    UILabel*nm=(UILabel*)[c.contentView viewWithTag:11];
    NSInteger r=[self lrow:ip.row];
    if(r<0){   // "Heruntergeladen"
        for(UIView*v in th.subviews)[v removeFromSuperview];
        th.accessibilityIdentifier=@"downloads"; th.image=[SpotTheme downloadsCover:48]; th.backgroundColor=[SpotTheme card];
        nm.text=L(@"Downloaded"); nm.textColor=[SpotTheme ink]; c.accessoryView=nil; return c;
    }
    if(r==0){
        nm.text=L(@"Liked Songs"); nm.textColor=[SpotTheme ink];
        [MMCovers likedCoverInto:th];
    } else {
        for(UIView*v in th.subviews)[v removeFromSuperview];
        nm.text=_playlists[r-1][@"name"]; nm.textColor=[SpotTheme ink];
        th.image=nil; th.backgroundColor=[SpotTheme card];
        NSString*cu=_playlists[r-1][@"cover"], *pid=_playlists[r-1][@"id"];
        th.accessibilityIdentifier=pid;                                   // Zelle wiederverwendet? -> Mosaik nur passend setzen
        if(cu.length) [MMCovers thumb:cu size:48 radius:0 into:th];
        else [MMCovers playlistCover:pid completion:^(NSString*mu){       // kein eigenes Bild -> Mosaik wie in der Spotify-App
            if(mu && [th.accessibilityIdentifier isEqualToString:pid]) [MMCovers thumb:mu size:48 radius:0 into:th]; }];
    }
    if([self rowDownloaded:r]){
        c.accessoryView=[[UIImageView alloc] initWithImage:[SpotTheme downloadedIcon:18]];
    } else c.accessoryView=nil;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if([SpotTheme ios6]){ dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [tv deselectRowAtIndexPath:ip animated:NO]; }); }   // iOS 6: gedrückte Zeile bleibt sichtbar, bis die Seite hereingeschoben ist
    else [tv deselectRowAtIndexPath:ip animated:YES];
    MMTrackListController*tl;
    NSInteger r=[self lrow:ip.row];
    if(r<0) tl=[[MMTrackListController alloc] initWithTitle:L(@"Downloaded") path:@"me/downloads"];
    else if(r==0) tl=[[MMTrackListController alloc] initWithTitle:L(@"Liked Songs") path:@"me/tracks?market=from_token&limit=50"];
    else { NSDictionary*p=_playlists[r-1]; tl=[[MMTrackListController alloc] initWithTitle:p[@"name"] path:[NSString stringWithFormat:@"playlists/%@?market=from_token",p[@"id"]]]; }
    [[MMRootController shared] pushContent:tl];   // im Inhaltsbereich -> untere Leisten bleiben sichtbar
}
// ---- Einstellungen: eigene Seite ----
- (void)openSettings { [[MMRootController shared] pushContent:[[MMSettingsController alloc] init]]; }
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }   // iPad gedreht: Zellen in neuer Breite
@end
