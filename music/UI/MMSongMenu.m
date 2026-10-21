#import "MMSongMenu.h"
#import <objc/runtime.h>
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMSheet.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMTrackListController.h"
#import "MMArtistController.h"

// ---- Playlist-Auswahl (nur eigene oder gemeinsame Playlists), im Inhaltsbereich ----
@interface MMPlaylistPicker : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSDictionary *track;
@end
@implementation MMPlaylistPicker {
    UITableView *_table; UILabel *_hint; UIActivityIndicatorView *_spin;
    NSArray *_lists;   // @[ {id,name,cover} ]
}
- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,70,34);
    [back setTitle:L(@"Cancel") forState:UIControlStateNormal]; [back setTitleColor:[SpotTheme ink] forState:UIControlStateNormal];
    back.titleLabel.font=[UIFont systemFontOfSize:14]; back.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(80,8,W-160,34)]; nav.text=L(@"Add to playlist"); nav.font=[UIFont boldSystemFontOfSize:16];
    nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; nav.adjustsFontSizeToFitWidth=YES; [self.view addSubview:nav];
    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorColor=[SpotTheme line]; _table.rowHeight=60; _table.contentInset=UIEdgeInsetsMake(0,0,90,0);
    _table.dataSource=self; _table.delegate=self; _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [SpotTheme skinTable:_table]; [self.view addSubview:_table];
    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,110,W-40,40)]; _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; _hint.numberOfLines=2; _hint.hidden=YES; [self.view addSubview:_hint];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]; _spin.center=CGPointMake(W/2,90); _spin.hidesWhenStopped=YES; [_spin startAnimating]; [self.view addSubview:_spin];
    [SpotTheme skinPage:self.view];
    NSString*me=[MMSpotify username];
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        [_spin stopAnimating];
        NSArray*items=[j[@"items"] isKindOfClass:[NSArray class]]?j[@"items"]:nil;
        if(!items){ _hint.text=L(@"Couldn't load (offline?)."); _hint.hidden=NO; return; }
        NSMutableArray*out=[NSMutableArray array];
        for(NSDictionary*p in items){ if(![p isKindOfClass:[NSDictionary class]]||![p[@"id"] isKindOfClass:[NSString class]]) continue;
            BOOL mine=[p[@"owner"] isKindOfClass:[NSDictionary class]] && [p[@"owner"][@"id"] isEqual:me];
            if(!mine && ![p[@"collaborative"] boolValue]) continue;   // fremde Playlists lassen sich nicht ändern
            [out addObject:@{@"id":p[@"id"],@"name":[p[@"name"] isKindOfClass:[NSString class]]?p[@"name"]:L(@"Playlist"),@"cover":[MMCovers bestURL:p[@"images"]]?:@""}]; }
        _lists=out; _hint.hidden=(out.count>0); if(!out.count) _hint.text=L(@"You have no playlists of your own yet.");
        [_table reloadData];
    }];
    MMAutoMask(self.view);
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _lists.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"r",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"r",tv)]; c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*th=[[UIImageView alloc] initWithFrame:CGRectMake(12,6,48,48)]; th.tag=10; th.backgroundColor=[SpotTheme card]; th.contentMode=UIViewContentModeScaleAspectFill; th.clipsToBounds=YES; [c.contentView addSubview:th];
        UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(72,0,tv.bounds.size.width-88,60)]; nm.tag=11; nm.font=[UIFont systemFontOfSize:16]; nm.textColor=[SpotTheme ink]; [c.contentView addSubview:nm]; }
    NSDictionary*p=_lists[ip.row];
    ((UILabel*)[c.contentView viewWithTag:11]).text=p[@"name"];
    UIImageView*th=(UIImageView*)[c.contentView viewWithTag:10]; th.image=nil; [MMCovers load:p[@"cover"] into:th];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];   // Auswahl nicht stehen lassen (sonst bleibt die Schrift weiß)
    NSDictionary*p=_lists[ip.row]; MMRootController*root=[MMRootController shared];
    tv.userInteractionEnabled=NO;
    [MMSpotify addTrack:self.track[@"id"] toPlaylist:p[@"id"] completion:^(BOOL ok){
        [root showDownloadMessage:ok?LF(@"Added to %@",p[@"name"]):L(@"Couldn't save – please try again")];
        [root popContent];
    }];
}
- (void)close { [[MMRootController shared] popContent]; }
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }
@end

@interface MMSwipeGate : NSObject <UIGestureRecognizerDelegate>   // nur waagrecht nach rechts starten, sonst scrollt die Liste
@end
@implementation MMSwipeGate
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)g { CGPoint v=[g velocityInView:g.view]; return v.x>0 && fabs(v.x)>fabs(v.y)*1.5; }
@end

// ---- Menü ----
@implementation MMSongMenu
// Das Menü kommt über die oberste sichtbare Ansicht (auch über Player/Warteschlange)
static UIView* topHost(void){ UIViewController*vc=[MMRootController shared]; while(vc.presentedViewController) vc=vc.presentedViewController; return vc.view; }

+ (void)showForTrack:(NSDictionary *)t {
    if(![t[@"id"] length]) return;
    NSNumber*liked=[MMSpotify likedCached:t[@"id"]];
    if(!liked){   // Lieblingssongs noch nicht im Speicher -> einmal laden, dann Menü
        [MMSpotify isLiked:t[@"id"] completion:^(BOOL l, BOOL known){ [self show:t liked:known?@(l):nil]; }];
        return;
    }
    [self show:t liked:liked];
}
// Album/Artist des Titels öffnen; IDs aus dem Titel (Player) oder aus den Metadaten
+ (void)openPage:(BOOL)album forTrack:(NSDictionary *)t {
    NSString*key=album?@"albumId":@"artistId";
    void (^go)(NSString*,NSString*)=^(NSString*pid,NSString*name){
        UIViewController*vc=album?[[MMTrackListController alloc] initWithTitle:name.length?name:L(@"Album") path:[@"albums/" stringByAppendingString:pid]]
                                 :[[MMArtistController alloc] initWithArtistId:pid name:name];
        [[MMRootController shared] showContent:vc];
    };
    if([t[key] length]){ go(t[key], album?t[@"album"]:t[@"artist"]); return; }
    [MMSpotify fetchTrack:t[@"id"] completion:^(NSDictionary*info,NSString*e){
        if([info[key] length]) go(info[key], album?info[@"album"]:info[@"artist"]);
        else [[MMRootController shared] showDownloadMessage:L(@"Couldn't load (offline?).")];
    }];
}
+ (void)show:(NSDictionary *)t liked:(NSNumber *)liked {
    MMRootController*root=[MMRootController shared];
    NSMutableArray*opts=[NSMutableArray arrayWithObjects:L(@"View artist"),L(@"View album"),L(@"Play next"),L(@"Add to queue"),nil];
    if(liked) [opts addObject:liked.boolValue?L(@"Remove from Liked Songs"):L(@"Add to Liked Songs")];   // unbekannt (offline) -> weglassen
    [opts addObject:L(@"Add to playlist …")];
    [opts addObject:[MMSpotify isDownloaded:t[@"id"]]?L(@"Remove download"):L(@"Download")];   // einzelner Titel offline
    NSString*cover=[t[@"cover"] length]?t[@"cover"]:@"";
    [MMSheet showIn:topHost() title:t[@"title"] subtitle:t[@"artist"] imageURL:cover options:opts done:^(NSInteger i){
        if(i<0) return;
        NSString*o=opts[i];
        if([o isEqualToString:L(@"View artist")]) [self openPage:NO forTrack:t];
        else if([o isEqualToString:L(@"View album")]) [self openPage:YES forTrack:t];
        else if([o isEqualToString:L(@"Play next")]){ [root queueTrack:t next:YES]; [root showDownloadMessage:L(@"Plays next")]; }
        else if([o isEqualToString:L(@"Add to queue")]){ [root queueTrack:t next:NO]; [root showDownloadMessage:L(@"Added to queue")]; }
        else if([o isEqualToString:L(@"Add to playlist …")]){ MMPlaylistPicker*pk=[[MMPlaylistPicker alloc] init]; pk.track=t; [root showContent:pk]; }
        else if([o isEqualToString:L(@"Download")]){
            if([t[@"cover"] length]) [MMCovers prefetch:t[@"cover"]];   // Cover für offline mit holen
            [MMSpotify queueDownloadTracks:@[t[@"id"]]];               // Fortschritt/Ende über die Download-Leiste unten
        }
        else if([o isEqualToString:L(@"Remove download")]){
            [MMSpotify removeDownloads:@[t[@"id"]]]; [root showDownloadMessage:L(@"Download removed")];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadsChanged" object:nil];   // Häkchen in Listen auffrischen
        }
        else if(!liked.boolValue) [self setLiked:YES track:t];
        else [MMSheet showIn:topHost() title:L(@"Remove from Liked Songs?") subtitle:t[@"title"] options:@[L(@"Remove")] done:^(NSInteger k){   // nachfragen
            if(k==0) [self setLiked:NO track:t]; }];
    }];
}
// Kurzmenü für den (+)-Knopf im Player: Lieblingssongs an/aus, Zur Playlist hinzufügen
+ (void)showSaveForTrack:(NSDictionary *)t {
    if(![t[@"id"] length]) return;
    NSNumber*liked=[MMSpotify likedCached:t[@"id"]];
    if(!liked){ [MMSpotify isLiked:t[@"id"] completion:^(BOOL l, BOOL known){ [self showSave:t liked:known?@(l):nil]; }]; return; }
    [self showSave:t liked:liked];
}
+ (void)showSave:(NSDictionary *)t liked:(NSNumber *)liked {
    NSMutableArray*opts=[NSMutableArray array];
    if(liked) [opts addObject:liked.boolValue?L(@"Remove from Liked Songs"):L(@"Add to Liked Songs")];
    [opts addObject:L(@"Add to playlist …")];
    [MMSheet showIn:topHost() title:t[@"title"] subtitle:t[@"artist"] imageURL:[t[@"cover"] length]?t[@"cover"]:@"" options:opts done:^(NSInteger i){
        if(i<0) return;
        if([opts[i] isEqualToString:L(@"Add to playlist …")]){ MMPlaylistPicker*pk=[[MMPlaylistPicker alloc] init]; pk.track=t; [[MMRootController shared] showContent:pk]; }
        else if(!liked.boolValue) [self setLiked:YES track:t];
        else [MMSheet showIn:topHost() title:L(@"Remove from Liked Songs?") subtitle:t[@"title"] options:@[L(@"Remove")] done:^(NSInteger k){ if(k==0) [self setLiked:NO track:t]; }];
    }];
}
+ (void)setLiked:(BOOL)on track:(NSDictionary *)t {
    [MMSpotify setLiked:on track:t[@"id"] completion:^(BOOL ok){
        [[MMRootController shared] showDownloadMessage:!ok?L(@"Couldn't save – please try again"):on?L(@"Added to Liked Songs"):L(@"Removed from Liked Songs")]; }];
}

// Lange drücken auf eine Zeile -> Menü; nach rechts ziehen -> ans Ende der Warteschlange (wie in der Spotify-App:
// die Zeile folgt dem Finger, links erscheint das Warteschlangen-Symbol, ab der Schwelle grün; loslassen = einreihen).
// Der Block hängt an den Erkennern (kein eigenes Objekt nötig).
static char kTrackAtKey;
#define kSwipeAt 90.0   // ab hier wird eingereiht
static MMSwipeGate *gGate;
static UITableViewCell *gSwCell; static UIView *gSwBack; static UIImageView *gSwIcon, *gSwSnap; static BOOL gSwArmed;

static char kRemoveKey;   // Block (NSIndexPath*, commit) -> BOOL: Wischen entfernt statt einzureihen (Warteschlange)
static UIColor *gSwOn; static BOOL gSwRemove;   // Farbe ab der Schwelle; Modus des laufenden Wischens
static UIImage* queueIcon(UIColor*c, BOOL minus){   // drei Linien + Plus (einreihen) bzw. Minus (entfernen)
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26,22),NO,0); [c setFill];
    UIRectFill(CGRectMake(0,3,15,2)); UIRectFill(CGRectMake(0,10,15,2)); UIRectFill(CGRectMake(0,17,9,2));
    UIRectFill(CGRectMake(13,16,12,2)); if(!minus) UIRectFill(CGRectMake(18,11,2,12));
    UIImage*i=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return i;
}
+ (void)attachToTable:(UITableView *)table swipeToQueue:(BOOL)swipe trackAt:(NSDictionary *(^)(NSIndexPath *))trackAt {
    [self attachToTable:table swipe:swipe remove:nil trackAt:trackAt];
}
+ (void)attachToTable:(UITableView *)table swipeToRemove:(BOOL(^)(NSIndexPath *, BOOL))remove trackAt:(NSDictionary *(^)(NSIndexPath *))trackAt {
    [self attachToTable:table swipe:YES remove:remove trackAt:trackAt];
}
+ (void)attachToTable:(UITableView *)table swipe:(BOOL)swipe remove:(BOOL(^)(NSIndexPath *, BOOL))remove trackAt:(NSDictionary *(^)(NSIndexPath *))trackAt {
    UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    lp.minimumPressDuration=0.45;
    objc_setAssociatedObject(lp,&kTrackAtKey,trackAt,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [table addGestureRecognizer:lp];
    if(!swipe) return;
    if(!gGate) gGate=[[MMSwipeGate alloc] init];
    UIPanGestureRecognizer*pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(swipePan:)];
    pan.delegate=gGate;
    objc_setAssociatedObject(pan,&kTrackAtKey,trackAt,OBJC_ASSOCIATION_COPY_NONATOMIC);
    if(remove) objc_setAssociatedObject(pan,&kRemoveKey,remove,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [table addGestureRecognizer:pan];
    [table.panGestureRecognizer requireGestureRecognizerToFail:pan];   // senkrecht: unser Erkenner scheitert sofort, die Liste scrollt
}
static NSDictionary* trackFor(UIGestureRecognizer*g, NSIndexPath**ipOut){
    UITableView*tv=(UITableView*)g.view; NSIndexPath*ip=[tv indexPathForRowAtPoint:[g locationInView:tv]]; if(!ip) return nil;
    if(ipOut) *ipOut=ip;
    NSDictionary*(^trackAt)(NSIndexPath*)=objc_getAssociatedObject(g,&kTrackAtKey);
    return trackAt?trackAt(ip):nil;
}
+ (void)longPress:(UILongPressGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateBegan) return;
    NSDictionary*t=trackFor(g,NULL); if(t) [self showForTrack:t];
}
#ifdef DEBUG
+ (void)debugSwipe:(UIPanGestureRecognizer *)fake real:(UIGestureRecognizer *)real {   // Track-Block des echten Erkenners übernehmen
    objc_setAssociatedObject(fake,&kTrackAtKey,objc_getAssociatedObject(real,&kTrackAtKey),OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(fake,&kRemoveKey,objc_getAssociatedObject(real,&kRemoveKey),OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self swipePan:fake];
}
#endif
+ (void)swipePan:(UIPanGestureRecognizer *)g {
    UITableView*tv=(UITableView*)g.view;
    if(g.state==UIGestureRecognizerStateBegan){
        NSIndexPath*ip=nil; NSDictionary*t=trackFor(g,&ip);
        BOOL(^remove)(NSIndexPath*,BOOL)=objc_getAssociatedObject(g,&kRemoveKey);
        if(remove && !remove(ip,NO)) t=nil;   // diese Zeile lässt sich nicht entfernen (läuft gerade)
        gSwCell=t?[tv cellForRowAtIndexPath:ip]:nil; if(!gSwCell) return;
        objc_setAssociatedObject(g,"track",t,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g,"ip",ip,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gSwRemove=remove!=nil; gSwOn=gSwRemove?[UIColor colorWithRed:0.89 green:0.22 blue:0.24 alpha:1]:[SpotTheme green];
        // Die Zelle legt ihre contentView bei jedem Layout-Durchgang neu an (Verschieben hält nicht) ->
        // stattdessen ein Bild der Zeile darüberlegen und das verschieben; die echte Zeile ist so lange unsichtbar.
        UIView*cv=gSwCell.contentView;
        UIGraphicsBeginImageContextWithOptions(cv.bounds.size,YES,0);
        [[SpotTheme bg] setFill]; UIRectFill(cv.bounds); [cv.layer renderInContext:UIGraphicsGetCurrentContext()];
        gSwSnap=[[UIImageView alloc] initWithImage:UIGraphicsGetImageFromCurrentImageContext()]; UIGraphicsEndImageContext();
        gSwSnap.frame=cv.frame;
        gSwBack=[[UIView alloc] initWithFrame:gSwCell.bounds]; gSwBack.backgroundColor=[SpotTheme card];
        gSwIcon=[[UIImageView alloc] initWithFrame:CGRectMake(24,(gSwCell.bounds.size.height-22)/2,26,22)]; gSwIcon.image=queueIcon([SpotTheme muted],gSwRemove); [gSwBack addSubview:gSwIcon];
        [gSwCell addSubview:gSwBack]; [gSwCell addSubview:gSwSnap]; cv.hidden=YES; gSwArmed=NO;
        return;
    }
    if(!gSwCell) return;
    CGFloat dx=MAX(0,[g translationInView:tv].x); if(dx>kSwipeAt) dx=kSwipeAt+(dx-kSwipeAt)*0.35;   // über der Schwelle zäher
    if(g.state==UIGestureRecognizerStateChanged){
        gSwSnap.transform=CGAffineTransformMakeTranslation(dx,0);
        BOOL armed=dx>=kSwipeAt;
        if(armed!=gSwArmed){ gSwArmed=armed;   // Schwelle erreicht: grün + weißes Symbol
            gSwBack.backgroundColor=armed?gSwOn:[SpotTheme card]; gSwIcon.image=queueIcon(armed?[UIColor whiteColor]:[SpotTheme muted],gSwRemove); }
        return;
    }
    UITableViewCell*cell=gSwCell; UIView*back=gSwBack, *snap=gSwSnap; BOOL add=gSwArmed && g.state==UIGestureRecognizerStateEnded;
    NSDictionary*t=objc_getAssociatedObject(g,"track"); NSIndexPath*ip=objc_getAssociatedObject(g,"ip");
    BOOL(^remove)(NSIndexPath*,BOOL)=objc_getAssociatedObject(g,&kRemoveKey);
    gSwCell=nil; gSwBack=nil; gSwSnap=nil; gSwIcon=nil; gSwArmed=NO;
    if(add && t && !remove){ [[MMRootController shared] queueTrack:t next:NO]; [[MMRootController shared] showDownloadMessage:L(@"Added to queue")]; }
    [UIView animateWithDuration:0.25 animations:^{ snap.transform=CGAffineTransformIdentity; }
                     completion:^(BOOL f){ cell.contentView.hidden=NO; [snap removeFromSuperview]; [back removeFromSuperview];
                         if(add && remove) remove(ip,YES); }];   // erst zurückgleiten, dann die Zeile entfernen
}
@end
