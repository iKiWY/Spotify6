#import "MMStartController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMRootController.h"
#import "MMSongMenu.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "MMTrackListController.h"
#import "MeshL10n.h"
#import "MMHistory.h"
#import "MMArtistController.h"
#import "MMRecent.h"

// Kacheln reagieren sofort (delaysContentTouches=NO); damit man trotzdem auf ihnen scrollen kann, muss Scrollen die Knöpfe abbrechen dürfen
// (UIScrollView lässt Knöpfe sonst nicht los: Ziehen scrollte nicht, Loslassen öffnete die Kachel)
@interface MMTouchScroll : UIScrollView @end
@implementation MMTouchScroll
- (BOOL)touchesShouldCancelInContentView:(UIView *)v { return YES; }
@end

@implementation MMStartController {
    UIScrollView *_sc;
    UIView *_content;             // alle Inhalte (beim Neuzeichnen geleert; Scrollbalken bleiben)
    CGFloat _y, _W;
    NSArray *_recent, *_top;      // @[ {id,title,artist,cover} ]
    NSArray *_quick;              // @[ {name,path,cover} | {name,artistId,cover} | {liked} ] - die 6 Kacheln
    NSArray *_recentTiles, *_libTiles;   // zuletzt gehört (zuerst) + eigene Playlists (füllen auf, wenn weniger als 6)
    NSArray *_serverCtx, *_serverRecent; // Spotifys Verlauf (mit Zeitpunkt "at"); wird mit dem Verlauf auf dem iPhone gemischt
    UILabel *_greet;
    UIView *_skel;                // Platzhalter beim allerersten Laden (noch kein Cache)
    NSArray *_recentPlaylists;    // zuletzt gehörte Playlists [{id,name,cover}]
    BOOL _needsRender;            // verdeckt geändert: beim nächsten Sichtbarwerden neu zeichnen
    NSMutableDictionary *_rows, *_oldRows;   // gezeichnete Reihen: Schlüssel -> {data, views, h, w} (unverändert = wiederverwenden)
}

- (NSString *)greeting {
    NSInteger h=[[[NSCalendar currentCalendar] components:NSHourCalendarUnit fromDate:[NSDate date]] hour];
    if(h<11) return L(@"Good morning");
    if(h<18) return L(@"Good afternoon");
    return L(@"Good evening");
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(NO)];
    self.view.backgroundColor=[SpotTheme ios6]?[SpotTheme shelfColor]:[SpotTheme pageBackground];   // iOS 6: ganze Seite auf dem hellen Regal
    _W=self.view.bounds.size.width;

    _greet=[[UILabel alloc] initWithFrame:CGRectMake(16,10,_W-32,30)];
    _greet.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    _greet.text=[self greeting]; _greet.font=[UIFont boldSystemFontOfSize:22]; _greet.textColor=[SpotTheme ink]; [self.view addSubview:_greet];

    _sc=[[MMTouchScroll alloc] initWithFrame:CGRectMake(0,46,_W,self.view.bounds.size.height-46)];
    _sc.contentInset=UIEdgeInsetsMake(0,0,MMPageBottomInset(84),0); _sc.alwaysBounceVertical=YES; if([SpotTheme ios6]) _sc.delaysContentTouches=NO;   // Kacheln zeigen den Druck sofort   // Platz für Now-Playing + Download-Leiste
    _sc.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_sc];
    _content=[[UIView alloc] initWithFrame:CGRectMake(0,0,_W,0)]; [_sc addSubview:_content];
    _y=8;

    [self showSkeleton];
    [self loadAll];
    // offline gestartet und Netz kommt zurück -> frische Daten holen
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(netBack:) name:@"MMNetworkChanged" object:nil];
    // neuer Titel gespielt -> Kacheln und "Zuletzt gehört" sofort nachziehen (Spotify kennt Wiedergaben dieser App nicht)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(historyChanged) name:MMHistoryChanged object:nil];
}
- (void)netBack:(NSNotification *)n { if([n.userInfo[@"reachable"] boolValue]) [self loadAll]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// iPad gedreht: Breite übernehmen, Raster und Karussells neu aufbauen (die Daten bleiben)
- (void)relayoutForSize:(CGSize)size {
    _W=size.width;
    if(_skel){ [_skel removeFromSuperview]; _skel=nil; [self showSkeleton]; }   // lädt noch: Umrisse in neuer Breite
    else if(_recentTiles || _libTiles) [self mergeTiles];   // 6 oder 8 Kacheln, zeichnet neu
    else [self render];
}
- (void)finish { _content.frame=CGRectMake(0,0,_W,_y+20); _sc.contentSize=CGSizeMake(_W,_y+20); }

// Alle drei Bereiche laden parallel; jeder zeigt sofort die letzten Daten und wird bei Änderung neu gezeichnet.
- (void)loadAll {
    // Kacheln wie in der Spotify-App: zuletzt gehörte Playlists, Alben und Artists; Lücken füllen eigene Playlists
    [MMSpotify apiUserCached:@"me/recent-contexts?limit=8" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        _serverCtx=[j[@"items"] isKindOfClass:[NSArray class]]?j[@"items"]:@[]; [self rebuildRecentTiles];
    }];
    [MMSpotify apiUserCached:@"me/playlists?limit=8" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSMutableArray*q=[NSMutableArray arrayWithObject:[self likedTile]];
        for(NSDictionary*p in ([j[@"items"] isKindOfClass:[NSArray class]]?j[@"items"]:@[])){
            if(![p isKindOfClass:[NSDictionary class]]||![p[@"id"] isKindOfClass:[NSString class]]) continue;
            [q addObject:[self playlistTile:p[@"id"] name:p[@"name"]?:L(@"Playlist") cover:[MMCovers bestURL:p[@"images"]]?:@""]];
        }
        _libTiles=q; [self mergeTiles];
    }];
    [MMSpotify apiUserCached:@"me/player/recently-played?limit=30" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        _serverRecent=[self parseTracks:j[@"items"] dedupe:YES]; [self rebuildRecentTracks]; [self render];
    }];
    [MMRecent playlists:20 done:^(NSArray*list){ if([list isEqual:_recentPlaylists]) return; _recentPlaylists=list; [self render]; }];   // unverändert: nicht neu zeichnen
    [MMSpotify apiUserCached:@"me/top/tracks?limit=20&time_range=short_term" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        _top=[self parseTracks:j[@"items"] dedupe:NO]; [self render];
    }];
}

// ---- Verlauf: iPhone + Spotify nach Zeitpunkt mischen (neueste zuerst), Doppelte raus ----
static long long atOf(NSDictionary*d){ id a=d[@"at"]; return [a respondsToSelector:@selector(longLongValue)]?[a longLongValue]:0; }
static NSArray* byTime(NSArray*a,NSArray*b,NSString*(^key)(NSDictionary*),NSUInteger max){
    NSMutableArray*all=[NSMutableArray array];
    for(id x in [a arrayByAddingObjectsFromArray:b]) if([x isKindOfClass:[NSDictionary class]]) [all addObject:x];
    [all sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary*x,NSDictionary*y){ long long p=atOf(x),q=atOf(y); return p>q?NSOrderedAscending:p<q?NSOrderedDescending:NSOrderedSame; }];
    NSMutableArray*out=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(NSDictionary*x in all){ NSString*k=key(x); if(!k||[seen containsObject:k]) continue; [seen addObject:k]; [out addObject:x]; if(out.count>=max) break; }
    return out;
}
- (void)historyChanged {   // pro Titel kommen zwei Meldungen (Titel + Herkunft): gebündelt einmal neu zeichnen
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(historyChangedNow) object:nil];
    [self performSelector:@selector(historyChangedNow) withObject:nil afterDelay:0.4];
}
- (void)historyChangedNow {
    [self rebuildRecentTiles]; [self rebuildRecentTracks]; [self render];
    [MMRecent playlists:20 done:^(NSArray*list){ if([list isEqual:_recentPlaylists]) return; _recentPlaylists=list; [self render]; }];   // unverändert: nicht neu zeichnen
}
- (void)rebuildRecentTracks {
    if(!_serverRecent && ![MMHistory tracks].count) return;
    _recent=byTime([MMHistory tracks],_serverRecent?:@[],^NSString*(NSDictionary*x){ return x[@"id"]; },30);
}
- (void)rebuildRecentTiles {
    if(!_serverCtx && ![MMHistory contexts].count) return;
    NSString*(^keyOf)(NSDictionary*)=^NSString*(NSDictionary*x){ return [x[@"type"] isEqual:@"liked"]?@"liked":[NSString stringWithFormat:@"%@:%@",x[@"type"],x[@"id"]]; };
    // Bild je Eintrag: fehlt es beim neuesten (älterer Verlauf auf dem iPhone ohne Cover), das von Spotifys Eintrag nehmen
    NSMutableDictionary*img=[NSMutableDictionary dictionary];
    for(NSDictionary*x in [(_serverCtx?:@[]) arrayByAddingObjectsFromArray:[MMHistory contexts]]){
        if(![x isKindOfClass:[NSDictionary class]]) continue; NSString*k=keyOf(x);
        if(!img[k] && [MMCovers bestURL:x[@"images"]].length) img[k]=x[@"images"]; }
    NSMutableArray*ctx=[NSMutableArray array];
    for(NSDictionary*x in byTime([MMHistory contexts],_serverCtx?:@[],keyOf,8)){
        NSDictionary*im=img[keyOf(x)];
        if(im && ![MMCovers bestURL:x[@"images"]].length){ NSMutableDictionary*m=[x mutableCopy]; m[@"images"]=im; [ctx addObject:m]; } else [ctx addObject:x]; }
    NSMutableArray*q=[NSMutableArray array];
    for(NSDictionary*c in ctx){
        NSString*type=c[@"type"], *cid=[c[@"id"] isKindOfClass:[NSString class]]?c[@"id"]:@"", *nm=[c[@"name"] isKindOfClass:[NSString class]]?c[@"name"]:@"";
        NSString*cov=[MMCovers bestURL:c[@"images"]]?:@"";
        if([type isEqual:@"liked"]) [q addObject:[self likedTile]];
        else if(!cid.length) continue;
        else if([type isEqual:@"artist"]) [q addObject:@{@"name":nm,@"artistId":cid,@"cover":cov}];
        else if([type isEqual:@"album"]) [q addObject:@{@"name":nm,@"path":[@"albums/" stringByAppendingString:cid],@"cover":cov}];
        else if([type isEqual:@"playlist"]) [q addObject:[self playlistTile:cid name:nm cover:cov]];
    }
    _recentTiles=q; [self mergeTiles];
}
// Kacheln oben: 6, auf dem iPad quer 8 (4 x 2)
- (NSUInteger)tileMax { return (MMIsPad() && MMGridColumns(_W)>=4)?8:6; }
- (NSDictionary *)likedTile { return @{@"name":L(@"Liked Songs"),@"path":@"me/tracks?market=from_token&limit=50",@"liked":@1}; }
- (NSMutableDictionary *)playlistTile:(NSString *)pid name:(NSString *)name cover:(NSString *)cov {
    NSMutableDictionary*tile=[@{@"name":name,@"path":[NSString stringWithFormat:@"playlists/%@?market=from_token",pid],@"cover":cov} mutableCopy];
    if(!cov.length) [MMCovers playlistCover:pid completion:^(NSString*mu){   // kein eigenes Bild -> Mosaik wie in der Bibliothek
        if(!mu.length) return;
        tile[@"cover"]=mu;                                 // kann sofort (aus dem Speicher) kommen -> erst setzen,
        if([_quick containsObject:tile]) [self render]; }];   // dann nur neu zeichnen, wenn die Kacheln schon stehen
    return tile;
}
// Zuletzt gehört zuerst, dann eigene Playlists ohne Doppelte, höchstens 6. Erst zeichnen, wenn die Verlaufs-Antwort da ist
// (sonst springen die Kacheln); ohne Netz und ohne gespeicherten Verlauf bleiben die eigenen Playlists.
- (void)mergeTiles {
    if(!_recentTiles && !_libTiles) return;
    NSMutableArray*q=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(NSDictionary*t in [(_recentTiles?:@[]) arrayByAddingObjectsFromArray:_libTiles?:@[]]){
        NSString*key=t[@"path"]?:t[@"artistId"]; if(!key||[seen containsObject:key]) continue;
        [seen addObject:key]; [q addObject:t]; if(q.count>=[self tileMax]) break; }
    if(!_recentTiles && q.count<[self tileMax]) return;   // Verlauf steht noch aus und füllt evtl. noch
    _quick=q; [self render];
}

// Zeichnet den ganzen Inhalt neu; vertikale und horizontale Scroll-Position bleiben erhalten.
// Graue, pulsierende Umrisse genau dort, wo gleich Kacheln und Cover erscheinen.
- (void)showSkeleton {
    _skel=[[UIView alloc] initWithFrame:CGRectMake(0,0,_W,700)]; _skel.userInteractionEnabled=NO;
    UIColor*c=[SpotTheme card];
    UIView*(^box)(CGRect,CGFloat)=^UIView*(CGRect r,CGFloat rad){ UIView*v=[[UIView alloc] initWithFrame:r]; v.backgroundColor=c; v.layer.cornerRadius=rad; [_skel addSubview:v]; return v; };
    NSInteger cols=MMGridColumns(_W), rows=(6+cols-1)/cols;
    CGFloat gap=10, tileW=(_W-16*2-gap*(cols-1))/cols, tileH=56, y=8;
    for(int i=0;i<6;i++) box(CGRectMake(16+(i%cols)*(tileW+gap), y+(i/cols)*(tileH+gap), tileW, tileH), 4);
    y+=rows*(tileH+gap)+10;
    box(CGRectMake(16,y+4,150,18),4); y+=32;                       // Überschrift
    for(int i=0;i<3;i++){ CGFloat x=16+i*(128+14);                 // Karussell: Cover + zwei Textzeilen
        box(CGRectMake(x,y,128,128),4); box(CGRectMake(x,y+136,100,11),3); box(CGRectMake(x,y+153,64,9),3); }
    [_sc addSubview:_skel];
    _skel.alpha=1;
    [UIView animateWithDuration:0.8 delay:0 options:UIViewAnimationOptionAutoreverse|UIViewAnimationOptionRepeat|UIViewAnimationOptionCurveEaseInOut
                     animations:^{ _skel.alpha=0.35; } completion:nil];
}

// Sichtbar = im Fenster und keine Seite darüber geöffnet. Verdeckt kostet ein Neuzeichnen (alle Reihen neu) auf dem 3GS spürbar Zeit
- (BOOL)onScreen { return self.view.window && ![MMRootController shared].hasPushedContent; }
- (void)pageDidShow { if(_needsRender){ _needsRender=NO; [self render]; } }
- (void)render {
    if(!_quick && !_recent && !_top) return;
    if(!_skel && ![self onScreen]){ _needsRender=YES; return; }   // erstes Laden (Platzhalter) immer zeichnen
    _needsRender=NO;
    if(_skel){
        if(!_quick || !_recent) return;   // erstes Laden: erst umschalten, wenn Kacheln UND „Zuletzt gehört“ da sind -> kein Springen
        UIView*sk=_skel; _skel=nil; [sk.layer removeAllAnimations];
        _content.alpha=0;
        [UIView animateWithDuration:0.3 animations:^{ sk.alpha=0; _content.alpha=1; } completion:^(BOOL f){ [sk removeFromSuperview]; }];
    }
    NSMutableDictionary*rowX=[NSMutableDictionary dictionary];
    for(UIView*v in _content.subviews){ if(v.tag>=1 && v.tag<=6 && [v isKindOfClass:[UIScrollView class]]) rowX[@(v.tag)]=@(((UIScrollView*)v).contentOffset.x); }
    for(UIView*v in [_content.subviews copy]) [v removeFromSuperview];
    _oldRows=_rows; _rows=[NSMutableDictionary dictionary];   // alte Reihen bleiben bis zum Ende greifbar
    _y=8;
    if(_quick.count) [self row:@"grid" data:_quick build:^{ [self buildGrid]; }];
    // zuletzt gehörte Titel (Kacheln), Playlists, Alben und Artists (iPhone und iPad gleich)
    if(_recent.count) [self row:@"songs" data:_recent build:^{ [self addSongTiles:L(@"Recently played") offset:[rowX[@5] floatValue]]; }];
    if(_recentPlaylists.count) [self row:@"playlists" data:_recentPlaylists build:^{ [self addCoverRow:L(@"Recent playlists") items:_recentPlaylists round:NO section:3 offset:[rowX[@3] floatValue]]; }];
    NSArray*albs=[self recentAlbums]; if(albs.count) [self row:@"albums" data:albs build:^{ [self addCoverRow:L(@"Recent albums") items:albs round:NO section:6 offset:[rowX[@6] floatValue]]; }];
    NSArray*arts=[self recentArtists]; if(arts.count) [self row:@"artists" data:arts build:^{ [self addCoverRow:L(@"Recent artists") items:arts round:YES section:4 offset:[rowX[@4] floatValue]]; }];
    if(_top.count) [self row:@"top" data:_top build:^{ [self addCarousel:L(@"Your top tracks") tracks:_top section:2 offset:[rowX[@2] floatValue]]; }];
    _oldRows=nil;
    [self finish];
}
// Eine Reihe zeichnen oder, wenn Daten und Breite gleich geblieben sind, die vorhandenen Ansichten nur an die neue Stelle schieben.
// Nach einem neuen Titel ändert sich meist nur "Zuletzt gehört": alles neu aufzubauen hielt den 3GS jedes Mal spürbar an.
- (void)row:(NSString *)key data:(id)data build:(void(^)(void))build {
    NSDictionary*o=_oldRows[key]; CGFloat y0=_y; NSArray*views;
    if(o && [o[@"data"] isEqual:data] && [o[@"w"] floatValue]==_W){
        CGFloat dy=_y-[o[@"y"] floatValue];
        views=o[@"views"]; for(UIView*v in views){ v.frame=CGRectOffset(v.frame,0,dy); [_content addSubview:v]; }
        _y+=[o[@"h"] floatValue];
    } else {
        NSUInteger n0=_content.subviews.count; build();
        views=[_content.subviews subarrayWithRange:NSMakeRange(n0,_content.subviews.count-n0)];
    }
    _rows[key]=@{@"data":data,@"views":views,@"y":@(y0),@"h":@(_y-y0),@"w":@(_W)};
}

// Abschnittskopf: iOS 6 eine eingeprägte Trennlinie über die ganze Breite und darunter der Titel (dunkelgrau, weißer Schatten), sonst große Überschrift
- (void)sectionTitle:(NSString *)title {
    if([SpotTheme ios6]){
        for(int k=0;k<2;k++){ UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(0,_y-4+k,_W,1)]; ln.backgroundColor=k?[UIColor whiteColor]:[UIColor colorWithWhite:0.76 alpha:1]; ln.autoresizingMask=UIViewAutoresizingFlexibleWidth; [_content addSubview:ln]; }
        UILabel*h=[[UILabel alloc] initWithFrame:CGRectMake(16,_y+8,_W-32,24)]; h.text=title; h.font=[UIFont boldSystemFontOfSize:20]; h.textColor=[SpotTheme ink];
        [SpotTheme engrave:h]; [_content addSubview:h]; _y+=8+24+10; return; }
    UILabel*h=[[UILabel alloc] initWithFrame:CGRectMake(16,_y,_W-32,26)]; h.text=title; h.font=[UIFont boldSystemFontOfSize:18]; h.textColor=[SpotTheme ink]; [_content addSubview:h]; _y+=32;
}
// Cover passend verkleinert und mit runden Ecken im Hintergrund vorgezeichnet: kein Beschneiden mit Ecken (zeichnete auf dem 3GS
// jedes Bild außerhalb des Bildschirms neu) und kein Dekodieren großer Bilder auf dem Hauptthread. Startseite war dadurch Sekunden langsam.
static void coverInto(NSString *url, UIImageView *iv, CGFloat radius) {
    iv.clipsToBounds=NO; if(url.length) [MMCovers thumb:url size:iv.bounds.size.width radius:radius into:iv];
}
// Kachel mit Cover links (Schnellzugriff, Zuletzt gehört). iOS 6: gewölbte Taste mit eingelassenem Cover, beim Antippen dunkler
- (UIView *)plateTile:(CGRect)f cover:(UIImageView **)covOut {
    UIView*tile=[[UIView alloc] initWithFrame:f]; CGFloat h=f.size.height; UIImageView*cov;
    if([SpotTheme ios6]){
        UIImageView*bg=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,f.size.width,h+1)]; bg.tag=77;
        bg.image=[SpotTheme plateImage:f.size pressed:NO]; bg.highlightedImage=[SpotTheme plateImage:f.size pressed:YES]; [tile addSubview:bg];
        cov=[[UIImageView alloc] initWithFrame:CGRectMake(5,5,h-10,h-10)]; cov.layer.cornerRadius=3;
        cov.layer.borderWidth=1; cov.layer.borderColor=[UIColor colorWithWhite:0 alpha:0.22].CGColor;
    } else {
        tile.backgroundColor=[SpotTheme card]; tile.layer.cornerRadius=4; tile.clipsToBounds=YES;
        cov=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,h,h)];
    }
    cov.contentMode=UIViewContentModeScaleAspectFill; cov.backgroundColor=[SpotTheme line]; [tile addSubview:cov];   // nicht beschneiden: das Bild kommt passend und rund vorgezeichnet (coverInto)
    *covOut=cov; return tile;
}
// iOS 6: Taste gedrückt zeigen, solange der Finger darauf ist
- (void)pressable:(UIButton *)b {
    if(![SpotTheme ios6]) return;
    [b addTarget:self action:@selector(plateDown:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
    [b addTarget:self action:@selector(plateUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
}
- (void)plateDown:(UIButton *)b { ((UIImageView*)[b.superview viewWithTag:77]).highlighted=YES; }
- (void)plateUp:(UIButton *)b { ((UIImageView*)[b.superview viewWithTag:77]).highlighted=NO; }

// ---------- 1) Schnellzugriff-Grid (deine Playlists + Lieblingssongs) ----------
- (void)buildGrid {
    NSInteger cols=MMGridColumns(_W);   // iPhone 2, iPad 3-4
    CGFloat gap=10, tileW=(_W-16*2-gap*(cols-1))/cols, tileH=56;
    for(int i=0;i<(int)_quick.count;i++){
        NSDictionary*it=_quick[i];
        CGFloat col=i%cols, rowY=_y+(i/cols)*(tileH+gap);
        UIImageView*cov; UIView*tile=[self plateTile:CGRectMake(16+col*(tileW+gap),rowY,tileW,tileH) cover:&cov];
        if(it[@"liked"]) [MMCovers likedCoverInto:cov];
        else coverInto(it[@"cover"],cov,[SpotTheme ios6]?3:0);
        CGFloat lx=[SpotTheme ios6]?tileH+1:tileH+6; UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(lx,0,tileW-lx-2,tileH)]; nm.text=it[@"name"]; nm.numberOfLines=2; nm.font=[UIFont boldSystemFontOfSize:12.5]; nm.textColor=[SpotTheme ink]; [SpotTheme engrave:nm]; [tile addSubview:nm];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=i; [tap addTarget:self action:@selector(openQuick:) forControlEvents:UIControlEventTouchUpInside]; [self pressable:tap]; [tile addSubview:tap];
        [_content addSubview:tile];
    }
    int rows=((int)_quick.count+(int)cols-1)/(int)cols; _y+=rows*(tileH+gap)+10;
}
- (void)openQuick:(UIButton *)b {
    if(b.tag>=(int)_quick.count) return;
    NSDictionary*it=_quick[b.tag];
    if(it[@"artistId"]){ [[MMRootController shared] pushContent:[[MMArtistController alloc] initWithArtistId:it[@"artistId"] name:it[@"name"]]]; return; }
    MMTrackListController*tl=[[MMTrackListController alloc] initWithTitle:it[@"name"] path:it[@"path"]];
    [[MMRootController shared] pushContent:tl];   // im Inhaltsbereich -> untere Leisten bleiben sichtbar
}

- (NSArray *)parseTracks:(id)items dedupe:(BOOL)dd {
    if(![items isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray*out=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(id it in items){
        if(![it isKindOfClass:[NSDictionary class]]) continue;
        id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it;
        NSString*tid=[t[@"id"] isKindOfClass:[NSString class]]?t[@"id"]:nil; if(!tid) continue;
        if(dd){ if([seen containsObject:tid]) continue; [seen addObject:tid]; }
        NSString*nm=[t[@"name"] isKindOfClass:[NSString class]]?t[@"name"]:@"";
        id arts=t[@"artists"]; NSString*an=@"", *aid=@""; if([arts isKindOfClass:[NSArray class]]&&[arts count]){ id a0=arts[0]; if([a0 isKindOfClass:[NSDictionary class]]&&[a0[@"name"] isKindOfClass:[NSString class]]) an=a0[@"name"];
            if([a0 isKindOfClass:[NSDictionary class]]&&[a0[@"id"] isKindOfClass:[NSString class]]) aid=a0[@"id"]; }   // für "Zuletzt gehörte Artists" (iPad)
        id alb=t[@"album"]; NSString*cov=[alb isKindOfClass:[NSDictionary class]]?[MMCovers bestURL:alb[@"images"]]:@"";
        NSMutableDictionary*e=[@{@"id":tid,@"title":nm,@"artist":an,@"artistId":aid,@"cover":cov?:@""} mutableCopy];
        if(((NSDictionary*)it)[@"at"]) e[@"at"]=((NSDictionary*)it)[@"at"];
        if([alb isKindOfClass:[NSDictionary class]] && [alb[@"id"] isKindOfClass:[NSString class]]){ e[@"albumId"]=alb[@"id"]; e[@"album"]=[alb[@"name"] isKindOfClass:[NSString class]]?alb[@"name"]:@""; }
        [out addObject:e];
    }
    return out;
}

- (void)addCarousel:(NSString *)title tracks:(NSArray *)tracks section:(int)sec offset:(CGFloat)ox {
    [self sectionTitle:title];
    CGFloat cw=128, pad=14, R=[SpotTheme ios6]?22:0, tx=R?cw+18:cw+4, tileH=tx+36;   // iOS 6: Spiegelbild unter dem Cover, Text darunter
    UIScrollView*row=[[MMTouchScroll alloc] initWithFrame:CGRectMake(0,_y,_W,tileH)]; row.showsHorizontalScrollIndicator=NO; row.delaysContentTouches=_sc.delaysContentTouches; row.tag=sec; [_content addSubview:row];
    CGFloat x=16;
    for(int i=0;i<(int)tracks.count;i++){
        NSDictionary*t=tracks[i];
        UIView*tile=[[UIView alloc] initWithFrame:CGRectMake(x,0,cw,tileH)];
        UIImageView*cov=[SpotTheme shelfCover:CGRectMake(0,0,cw,cw) in:tile reflection:R]; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; [SpotTheme shadowBehind:cov];
        coverInto(t[@"cover"],cov,4);
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(0,tx,cw,16)]; ti.text=t[@"title"]; ti.font=[UIFont boldSystemFontOfSize:12.5]; ti.textColor=[SpotTheme ink]; [SpotTheme engrave:ti]; [tile addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(0,tx+16,cw,15)]; ar.text=t[@"artist"]; ar.font=[UIFont systemFontOfSize:11]; ar.textColor=[SpotTheme muted]; [SpotTheme engrave:ar]; [tile addSubview:ar];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=sec*1000+i; [tap addTarget:self action:@selector(playTile:) forControlEvents:UIControlEventTouchUpInside]; [tile addSubview:tap];
        UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tileMenu:)]; lp.minimumPressDuration=0.45; [tap addGestureRecognizer:lp];   // lange drücken = Titel-Menü statt Album
        [row addSubview:tile]; x+=cw+pad;
    }
    row.contentSize=CGSizeMake(x,tileH);
    row.contentOffset=CGPointMake(MAX(0,MIN(ox,x-_W)),0);
    _y+=tileH+18;
}
// ---------- iPad: Reihen unter den Kacheln ----------
// Zuletzt gehörte Titel als Kacheln in Kachelgröße (Cover links, Titel + Artist); Antippen spielt den Titel
- (void)addSongTiles:(NSString *)title offset:(CGFloat)ox {
    [self sectionTitle:title];
    NSInteger cols=MMGridColumns(_W); CGFloat gap=10, tileW=(_W-16*2-gap*(cols-1))/cols, tileH=56, x=16;
    UIScrollView*row=[[MMTouchScroll alloc] initWithFrame:CGRectMake(0,_y,_W,tileH+2)]; row.showsHorizontalScrollIndicator=NO; row.delaysContentTouches=_sc.delaysContentTouches; row.tag=5; [_content addSubview:row];   // +2: Lichtkante unter den Tasten
    for(int i=0;i<(int)_recent.count;i++){
        NSDictionary*t=_recent[i];
        UIImageView*cov; UIView*tile=[self plateTile:CGRectMake(x,0,tileW,tileH) cover:&cov];
        coverInto(t[@"cover"],cov,[SpotTheme ios6]?3:0);
        CGFloat lx=[SpotTheme ios6]?tileH+2:tileH+8; UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(lx,9,tileW-lx-6,20)]; ti.text=t[@"title"]; ti.font=[UIFont boldSystemFontOfSize:12.5]; ti.textColor=[SpotTheme ink]; ti.backgroundColor=[UIColor clearColor]; [SpotTheme engrave:ti]; [tile addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(lx,28,tileW-lx-6,18)]; ar.text=t[@"artist"]; ar.font=[UIFont systemFontOfSize:11]; ar.textColor=[SpotTheme muted]; ar.backgroundColor=[UIColor clearColor]; [SpotTheme engrave:ar]; [tile addSubview:ar];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=5000+i; [tap addTarget:self action:@selector(openRowItem:) forControlEvents:UIControlEventTouchUpInside]; [self pressable:tap]; [tile addSubview:tap];
        UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tileMenu:)]; lp.minimumPressDuration=0.45; [tap addGestureRecognizer:lp];
        [row addSubview:tile]; x+=tileW+gap;
    }
    row.contentSize=CGSizeMake(x+6,tileH); row.contentOffset=CGPointMake(MAX(0,MIN(ox,x+6-_W)),0);
    _y+=tileH+18;
}
// Je Artist ein Eintrag, an der Stelle seines neuesten Titels (Bild wird nachgeladen)
- (NSArray *)recentArtists {
    NSMutableArray*o=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(NSDictionary*t in _recent){ NSString*aid=[t[@"artistId"] isKindOfClass:[NSString class]]?t[@"artistId"]:@"";
        if(!aid.length || [seen containsObject:aid]) continue; [seen addObject:aid];
        [o addObject:@{@"id":aid,@"name":t[@"artist"]?:@""}]; if(o.count>=20) break; }
    return o;
}
// Je Album ein Eintrag, an der Stelle seines neuesten Titels (Cover = Cover des Titels)
- (NSArray *)recentAlbums {
    NSMutableArray*o=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(NSDictionary*t in _recent){ NSString*al=[t[@"albumId"] isKindOfClass:[NSString class]]?t[@"albumId"]:@"";
        if(!al.length || [seen containsObject:al]) continue; [seen addObject:al];
        [o addObject:@{@"id":al,@"name":[t[@"album"] isKindOfClass:[NSString class]]?t[@"album"]:@"",@"cover":t[@"cover"]?:@"",@"artist":t[@"artist"]?:@""}]; if(o.count>=20) break; }
    return o;
}
// Reihe mit großen Covern (wie "Zuletzt gehört" auf dem iPhone): Playlists (eckig) oder Artists (rund, Bild per MMRecent)
- (void)addCoverRow:(NSString *)title items:(NSArray *)items round:(BOOL)round section:(int)sec offset:(CGFloat)ox {
    [self sectionTitle:title];
    CGFloat cw=128, pad=14, R=([SpotTheme ios6]&&!round)?22:0, tx=R?cw+18:cw+6, tileH=tx+(round?24:20), x=16;
    BOOL two=[SpotTheme ios6]&&sec==3, sub=[SpotTheme ios6]&&sec==6; if(two||sub) tileH+=16;   // iOS 6: Playlist-Namen auf zwei Zeilen, Alben mit Artist   // iOS 6: eckige Cover mit Spiegelbild
    UIScrollView*row=[[MMTouchScroll alloc] initWithFrame:CGRectMake(0,_y,_W,tileH)]; row.showsHorizontalScrollIndicator=NO; row.delaysContentTouches=_sc.delaysContentTouches; row.tag=sec; [_content addSubview:row];
    for(int i=0;i<(int)items.count;i++){
        NSDictionary*it=items[i];
        UIView*tile=[[UIView alloc] initWithFrame:CGRectMake(x,0,cw,tileH)];
        UIImageView*cov=[SpotTheme shelfCover:CGRectMake(0,0,cw,cw) in:tile reflection:R]; cov.backgroundColor=[SpotTheme card];
        cov.layer.cornerRadius=round?cw/2:4;
        if(round && [SpotTheme ios6]){ cov.layer.borderWidth=3; cov.layer.borderColor=[UIColor whiteColor].CGColor; }   // Artists: weißer Rahmen wie ein Foto
        [SpotTheme shadowBehind:cov];
        CGFloat rad=round?cw/2:4; cov.clipsToBounds=NO;
        if(round){ __weak UIImageView*wc=cov; [MMRecent artistImage:it[@"id"] done:^(NSString*u){ if(u.length && wc) coverInto(u,wc,rad); }]; }
        else if([it[@"cover"] length]) coverInto(it[@"cover"],cov,rad);
        else [MMCovers playlistCover:it[@"id"] completion:^(NSString*mu){ if(mu.length) coverInto(mu,cov,rad); }];   // ohne eigenes Bild: Mosaik
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(0,tx,cw,16)]; ti.text=it[@"name"]; ti.font=[UIFont boldSystemFontOfSize:12.5]; ti.textColor=[SpotTheme ink]; [SpotTheme engrave:ti];
        if(round) ti.textAlignment=NSTextAlignmentCenter; [tile addSubview:ti];
        if(two){ ti.numberOfLines=2; CGSize ts=[ti.text sizeWithFont:ti.font constrainedToSize:CGSizeMake(cw,32) lineBreakMode:NSLineBreakByTruncatingTail]; ti.frame=CGRectMake(0,tx,cw,MAX(16,ts.height)); }   // oben bündig
        if(sub){ UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(0,tx+16,cw,15)]; ar.text=it[@"artist"]; ar.font=[UIFont systemFontOfSize:11]; ar.textColor=[SpotTheme muted]; [SpotTheme engrave:ar]; [tile addSubview:ar]; }
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=sec*1000+i; [tap addTarget:self action:@selector(openRowItem:) forControlEvents:UIControlEventTouchUpInside]; [tile addSubview:tap];
        [row addSubview:tile]; x+=cw+pad;
    }
    row.contentSize=CGSizeMake(x,tileH); row.contentOffset=CGPointMake(MAX(0,MIN(ox,x-_W)),0);
    _y+=tileH+18;
}
- (void)openRowItem:(UIButton *)b {
    int sec=(int)b.tag/1000, idx=(int)b.tag%1000; MMRootController*root=[MMRootController shared];
    if(sec==5){ if(idx<(int)_recent.count){ [root playList:_recent index:idx]; } return; }   // Titel spielen (iPad: die Leiste unten zeigt ihn)
    if(sec==3 && idx<(int)_recentPlaylists.count){ NSDictionary*p=_recentPlaylists[idx];
        [root pushContent:[[MMTrackListController alloc] initWithTitle:p[@"name"] path:[NSString stringWithFormat:@"playlists/%@?market=from_token",p[@"id"]]]]; return; }
    NSArray*albs=[self recentAlbums];
    if(sec==6 && idx<(int)albs.count){ NSDictionary*a=albs[idx];
        [root pushContent:[[MMTrackListController alloc] initWithTitle:[a[@"name"] length]?a[@"name"]:L(@"Album") path:[@"albums/" stringByAppendingString:a[@"id"]]]]; return; }
    NSArray*arts=[self recentArtists];
    if(sec==4 && idx<(int)arts.count) [root pushContent:[[MMArtistController alloc] initWithArtistId:arts[idx][@"id"] name:arts[idx][@"name"]]];
}

- (void)tileMenu:(UILongPressGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateBegan) return;
    int sec=g.view.tag/1000, idx=g.view.tag%1000;
    NSArray*list=(sec==1||sec==5)?_recent:_top;   // 5 = iPad-Titelkacheln
    if(idx<(int)list.count) [MMSongMenu showForTrack:list[idx]];
}
- (void)playTile:(UIButton *)b {
    int sec=b.tag/1000, idx=b.tag%1000;
    NSArray*list=(sec==1)?_recent:_top;
    if(idx>=(int)list.count) return;
    NSDictionary*t=list[idx];
    if(sec==1 && [t[@"albumId"] length]){   // "Zuletzt gehört": öffnet das Album des Titels (wie in der Spotify-App)
        [[MMRootController shared] pushContent:[[MMTrackListController alloc] initWithTitle:[t[@"album"] length]?t[@"album"]:L(@"Album") path:[@"albums/" stringByAppendingString:t[@"albumId"]]]];
        return;
    }
    [[MMRootController shared] playList:list index:idx];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _greet.text=[self greeting]; }
@end
