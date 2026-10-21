#import "MMSearchController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMKeySetupController.h"
#import "MeshL10n.h"
#import "MMCovers.h"
#import "MMTrackListController.h"
#import "MMArtistController.h"
#import "MMSongMenu.h"

@interface MMSearchController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate, UISearchBarDelegate>
@end

@implementation MMSearchController {
    UITextField *_field;
    UISearchBar *_sbar;   // iOS 6: echte Suchleiste; _field bleibt die Logik dahinter
    UITableView *_table;
    UILabel *_hint;
    UIButton *_unlock;   // "Suche freischalten" ohne eigenen Schlüssel
    NSArray *_results;   // Titel @[ {id,title,artist,cover} ] - zugleich die Abspiel-Queue
    NSArray *_artists;   // @[ {id,name,cover} ]
    NSArray *_albums;    // @[ {id,name,sub,cover} ]
    NSArray *_secs;      // sichtbare Abschnitte in Reihenfolge: @"recent" / @"artists" / @"tracks" / @"albums"
    NSArray *_recents;   // zuletzt aus der Suche geöffnet: @[ {kind: artist|album|track, id, name, sub, cover} ], neueste zuerst
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(NO)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(0,8,W,34)];
    nav.text=L(@"Search"); nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];

    // Suchfeld
    UIView*box=[[UIView alloc] initWithFrame:CGRectMake(16,46,W-32,42)]; box.backgroundColor=[UIColor whiteColor]; box.layer.cornerRadius=8; [self.view addSubview:box];
    _field=[[UITextField alloc] initWithFrame:CGRectMake(12,0,W-32-24,42)];
    _field.placeholder=L(@"Artists, songs …"); _field.font=[UIFont systemFontOfSize:15]; _field.textColor=[UIColor blackColor];
    _field.returnKeyType=UIReturnKeySearch; _field.delegate=self; _field.autocorrectionType=UITextAutocorrectionTypeNo;
    _field.autoresizingMask=UIViewAutoresizingFlexibleWidth; _field.clearButtonMode=UITextFieldViewModeWhileEditing; _field.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter; [box addSubview:_field];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,98,W,H-98) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=MMTrackRowH; _table.contentInset=_table.scrollIndicatorInsets=UIEdgeInsetsMake(0,0,MMPageBottomInset(84),0);
    [SpotTheme skinTable:_table];
    if([SpotTheme ios6]){   // echte iOS-Suchleiste unter der Navigationsleiste; das eigene Feld bleibt unsichtbar die Logik
        box.hidden=YES; _sbar=[[UISearchBar alloc] initWithFrame:CGRectMake(0,44,W,44)]; _sbar.tintColor=[SpotTheme barTint];
        _sbar.placeholder=_field.placeholder; _sbar.delegate=self; _sbar.autocorrectionType=UITextAutocorrectionTypeNo; _sbar.autoresizingMask=UIViewAutoresizingFlexibleWidth;
        [self.view addSubview:_sbar]; _table.frame=CGRectMake(0,88,W,H-88); }
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_table];   // mit dem Inhaltsbereich (über der Tab-Leiste) mitschrumpfen   // Platz für Now-Playing + Download-Leiste

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,140,W-40,40)]; _hint.text=L(@"Find millions of songs."); _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; _hint.numberOfLines=0; [self.view addSubview:_hint];

    _unlock=[UIButton buttonWithType:UIButtonTypeCustom]; _unlock.frame=CGRectMake(50,196,W-100,44);
    _unlock.backgroundColor=[SpotTheme green]; _unlock.layer.cornerRadius=22; _unlock.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    [_unlock setTitle:L(@"UNLOCK SEARCH") forState:UIControlStateNormal]; [_unlock setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    if([SpotTheme ios6]){ _unlock.backgroundColor=[UIColor clearColor]; [_unlock setBackgroundImage:[SpotTheme glossyImage:[SpotTheme green] radius:10] forState:UIControlStateNormal];
        [_unlock setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [_unlock setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal]; _unlock.titleLabel.shadowOffset=CGSizeMake(0,-1); }
    [_unlock addTarget:self action:@selector(openKeySetup) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_unlock];
    // Schlüssel ändern/entfernen: lange auf "Suche" drücken
    nav.userInteractionEnabled=YES;
    [nav addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(navLongPress:)]];
    __weak MMSearchController*ws=self;   // lange drücken auf einen Titel (Treffer oder zuletzt gesucht) -> Titel-Menü
    [MMSongMenu attachToTable:_table swipeToQueue:YES trackAt:^NSDictionary*(NSIndexPath*ip){ MMSearchController*s=ws; if(!s||ip.section>=(NSInteger)s->_secs.count) return nil;
        NSString*k=s->_secs[ip.section];
        if([k isEqualToString:@"recent"]){ NSDictionary*r=s->_recents[ip.row]; return [r[@"kind"] isEqual:@"track"]?[MMSearchController trackOf:r]:nil; }
        return [k isEqualToString:@"tracks"]?s->_results[ip.row]:nil; }];
    [_field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    // Tastatur weg: irgendwo daneben tippen (Zeilen bleiben antippbar) oder die Liste ziehen
    UITapGestureRecognizer*kt=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
    kt.cancelsTouchesInView=NO; kt.delegate=self; [self.view addGestureRecognizer:kt];
#ifdef DEBUG
    [[NSNotificationCenter defaultCenter] addObserverForName:@"MMDebugSearch" object:nil queue:nil usingBlock:^(NSNotification*n){ _field.text=n.object; [self doSearch:n.object]; }];
#endif
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}

- (void)viewDidLoad { [super viewDidLoad]; [self refreshKeyState]; [self showRecents]; }
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self fitBottomInset]; }
// Unten genau so viel Platz wie die sichtbaren Leisten brauchen (die Download-Leiste ist meist aus)
- (void)fitBottomInset { _table.contentInset=_table.scrollIndicatorInsets=UIEdgeInsetsMake(0,0,[[MMRootController shared] bottomBarsHeight]+8,0); }

// ---- Zuletzt gesucht: was nach einer Suche angetippt wurde (Artist, Album, Titel), höchstens 10 ----
#define kRecentsKey @"searchRecents"
+ (NSDictionary *)trackOf:(NSDictionary *)r { return @{@"id":r[@"id"],@"title":r[@"name"]?:@"",@"artist":r[@"sub"]?:@"",@"cover":r[@"cover"]?:@""}; }
- (NSArray *)loadRecents { id a=[[NSUserDefaults standardUserDefaults] objectForKey:kRecentsKey]; return [a isKindOfClass:[NSArray class]]?a:@[]; }
- (void)remember:(NSDictionary *)e {
    NSMutableArray*a=[[self loadRecents] mutableCopy];
    for(NSInteger i=(NSInteger)a.count-1;i>=0;i--) if([a[i][@"kind"] isEqual:e[@"kind"]] && [a[i][@"id"] isEqual:e[@"id"]]) [a removeObjectAtIndex:i];
    [a insertObject:e atIndex:0]; while(a.count>10) [a removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kRecentsKey]; [[NSUserDefaults standardUserDefaults] synchronize];
}
// Ohne Suchbegriff: Liste "Zuletzt gesucht" statt Treffern
- (void)showRecents {
    if(![MMSpotify hasSearchKey]) return;
    _recents=[self loadRecents]; _results=nil; _artists=nil; _albums=nil;
    _secs=_recents.count?@[@"recent"]:@[]; [self fitBottomInset]; [_table reloadData];
    _hint.hidden=(_recents.count>0); _hint.text=L(@"Find millions of songs.");
}
- (void)fieldChanged { if(!_field.text.length) [self showRecents]; }
- (BOOL)textFieldShouldClear:(UITextField *)tf { dispatch_async(dispatch_get_main_queue(), ^{ [self showRecents]; }); return YES; }
- (void)clearRecents {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kRecentsKey]; [[NSUserDefaults standardUserDefaults] synchronize];
    [self showRecents];
}
- (void)refreshKeyState {
    BOOL has=[MMSpotify hasSearchKey];
    _unlock.hidden=has; _field.enabled=has; _field.superview.alpha=has?1:0.4;
    _sbar.userInteractionEnabled=has; _sbar.alpha=has?1:0.5;
    if(!has){ _results=nil; _artists=nil; _albums=nil; _secs=nil; [_table reloadData]; _hint.hidden=NO;
        _hint.frame=CGRectMake(20,120,self.view.bounds.size.width-40,64);
        _hint.text=L(@"Search needs your own free Spotify key. Set it up once in about 3 minutes."); }
    else if(!_results.count){ _hint.frame=CGRectMake(20,140,self.view.bounds.size.width-40,40); _hint.text=L(@"Find millions of songs."); }
}
- (void)navLongPress:(UILongPressGestureRecognizer *)g { if(g.state==UIGestureRecognizerStateBegan) [self openKeySetup]; }
- (void)openKeySetup {
    [self.view endEditing:YES];
    MMKeySetupController*k=[[MMKeySetupController alloc] init]; k.skippable=NO;
    __weak MMSearchController*ws=self;
    k.onDone=^(BOOL saved){ [[MMRootController shared] popContent]; [ws refreshKeyState]; };
    [[MMRootController shared] pushContent:k];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if(_sbar) return [_sbar isFirstResponder] && ![t.view isDescendantOfView:_sbar];
    return _field.isFirstResponder && ![t.view isDescendantOfView:_field.superview]; }
- (void)hideKeyboard { [self.view endEditing:YES]; [_sbar resignFirstResponder]; }
// iOS 6: die Suchleiste reicht Eingaben an das (unsichtbare) Feld weiter, damit die Suchlogik gleich bleibt
- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t { _field.text=t; [self fieldChanged]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; _field.text=sb.text; [self doSearch:sb.text]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)sv { [self hideKeyboard]; }
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self doSearch:tf.text]; return YES; }

static NSString* str(id v){ return [v isKindOfClass:[NSString class]]?v:@""; }
static NSString* firstArtist(NSDictionary*x){ id a=x[@"artists"]; return ([a isKindOfClass:[NSArray class]]&&[a count]&&[a[0] isKindOfClass:[NSDictionary class]])?str(a[0][@"name"]):@""; }
static NSArray* items(NSDictionary*j,NSString*k){ id v=[j[k] isKindOfClass:[NSDictionary class]]?j[k][@"items"]:nil; return [v isKindOfClass:[NSArray class]]?v:@[]; }

- (void)doSearch:(NSString *)q {
    if(!q.length) return;
    _hint.text=L(@"Searching…"); _hint.hidden=NO;
    NSString*enc=[q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    [MMSpotify webGet:[NSString stringWithFormat:@"search?q=%@&type=track,artist,album&limit=10",enc] completion:^(NSDictionary*j,NSInteger st){
        if(st==429){ _hint.text=L(@"Too many requests – wait a moment and retry."); _hint.hidden=NO; return; }
        NSMutableArray*tr=[NSMutableArray array], *ar=[NSMutableArray array], *al=[NSMutableArray array];
        for(NSDictionary*t in items(j,@"tracks")){ if(![t isKindOfClass:[NSDictionary class]]||!str(t[@"id"]).length) continue;
            NSDictionary*alb=[t[@"album"] isKindOfClass:[NSDictionary class]]?t[@"album"]:nil;
            [tr addObject:@{@"id":t[@"id"],@"title":str(t[@"name"]),@"artist":firstArtist(t),@"cover":[MMCovers bestURL:alb[@"images"]]?:@""}]; }
        for(NSDictionary*a in items(j,@"artists")){ if(![a isKindOfClass:[NSDictionary class]]||!str(a[@"id"]).length) continue;
            [ar addObject:@{@"id":a[@"id"],@"name":str(a[@"name"]),@"cover":[MMCovers bestURL:a[@"images"]]?:@""}]; if(ar.count>=3) break; }
        for(NSDictionary*a in items(j,@"albums")){ if(![a isKindOfClass:[NSDictionary class]]||!str(a[@"id"]).length) continue;
            NSString*yr=str(a[@"release_date"]); if(yr.length>4) yr=[yr substringToIndex:4];
            NSString*sub=yr.length?[NSString stringWithFormat:@"%@ · %@",firstArtist(a),yr]:firstArtist(a);
            [al addObject:@{@"id":a[@"id"],@"name":str(a[@"name"]),@"sub":sub,@"cover":[MMCovers bestURL:a[@"images"]]?:@""}]; if(al.count>=6) break; }
        _results=tr; _artists=ar; _albums=al;
        NSMutableArray*secs=[NSMutableArray array];
        if(ar.count)[secs addObject:@"artists"];
        if(tr.count)[secs addObject:@"tracks"];
        if(al.count)[secs addObject:@"albums"];
        _secs=secs; [self fitBottomInset]; [_table reloadData]; [_table setContentOffset:CGPointZero animated:NO];
        if(!secs.count){ _hint.text=![MMSpotify networkReachable]?L(@"You're offline. Search needs an internet connection."):(st>=500)?L(@"Spotify isn't responding – please try again."):(st==401)?L(@"Your search key no longer works. Long-press \"Search\" at the top to change it."):L(@"Nothing found."); _hint.hidden=NO; return; }
        _hint.hidden=YES;
    }];
}

- (NSArray *)rowsOf:(NSInteger)s { NSString*k=_secs[s]; return [k isEqualToString:@"recent"]?_recents:[k isEqualToString:@"artists"]?_artists:[k isEqualToString:@"albums"]?_albums:_results; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _secs.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self rowsOf:s].count; }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return [SpotTheme ios6]?22:36; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    NSString*k=_secs[s];
    NSString*title=[k isEqualToString:@"recent"]?L(@"Recent searches"):[k isEqualToString:@"artists"]?L(@"Artists"):[k isEqualToString:@"albums"]?L(@"Albums"):L(@"Songs");
    if([SpotTheme ios6]){   // iOS-6-Abschnittskopf; "Löschen" rechts in Weiß
        UIView*v=[SpotTheme plainSectionHeader:title width:tv.bounds.size.width];
        if([k isEqualToString:@"recent"]){ v.userInteractionEnabled=YES;
            UIButton*clr=[UIButton buttonWithType:UIButtonTypeCustom]; clr.frame=CGRectMake(tv.bounds.size.width-90,0,80,22);
            [clr setTitle:L(@"Clear") forState:UIControlStateNormal]; [clr setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [clr setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.44] forState:UIControlStateNormal]; clr.titleLabel.shadowOffset=CGSizeMake(0,1);
            clr.titleLabel.font=[UIFont boldSystemFontOfSize:14]; clr.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
            [clr addTarget:self action:@selector(clearRecents) forControlEvents:UIControlEventTouchUpInside]; [v addSubview:clr]; }
        return v; }
    UIView*v=[[UIView alloc] initWithFrame:CGRectMake(0,0,tv.bounds.size.width,36)]; v.backgroundColor=[SpotTheme bg];
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,8,tv.bounds.size.width-32,24)];
    l.text=title;
    l.font=[UIFont boldSystemFontOfSize:17]; l.textColor=[SpotTheme ink]; l.backgroundColor=[UIColor clearColor]; [v addSubview:l];
    if([k isEqualToString:@"recent"]){   // "Löschen" rechts in der Überschrift
        UIButton*clr=[UIButton buttonWithType:UIButtonTypeCustom]; clr.frame=CGRectMake(tv.bounds.size.width-90,4,80,30);
        [clr setTitle:L(@"Clear") forState:UIControlStateNormal]; [clr setTitleColor:[SpotTheme muted] forState:UIControlStateNormal];
        clr.titleLabel.font=[UIFont systemFontOfSize:14]; clr.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
        [clr addTarget:self action:@selector(clearRecents) forControlEvents:UIControlEventTouchUpInside]; [v addSubview:clr]; }
    return v;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width;
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"r",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"r",tv)];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(16,6,44,44)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.clipsToBounds=YES; cov.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(70,9,W-70-16,20)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.textColor=[SpotTheme ink]; [c.contentView addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(70,29,W-70-16,18)]; ar.tag=3; ar.font=[SpotTheme sub]; ar.textColor=[SpotTheme muted]; [c.contentView addSubview:ar]; }
    NSString*k=_secs[ip.section]; NSDictionary*r=[self rowsOf:ip.section][ip.row];
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1];
    if([k isEqualToString:@"recent"]){   // gespeicherter Eintrag: Art aus "kind", Untertitel wie in den Treffern
        NSString*kind=r[@"kind"];
        cov.layer.cornerRadius=[kind isEqual:@"artist"]?24:4;
        ((UILabel*)[c.contentView viewWithTag:2]).text=r[@"name"];
        ((UILabel*)[c.contentView viewWithTag:3]).text=[kind isEqual:@"artist"]?L(@"Artist"):[kind isEqual:@"album"]?LF(@"Album · %@",r[@"sub"]?:@""):LF(@"Song · %@",r[@"sub"]?:@"");
        cov.image=nil; [MMCovers load:r[@"cover"] into:cov];
        return c;
    }
    cov.layer.cornerRadius=[k isEqualToString:@"artists"]?24:4;   // Artists rund wie in der Spotify-App
    ((UILabel*)[c.contentView viewWithTag:2]).text=[k isEqualToString:@"tracks"]?r[@"title"]:r[@"name"];
    ((UILabel*)[c.contentView viewWithTag:3]).text=[k isEqualToString:@"tracks"]?r[@"artist"]:[k isEqualToString:@"albums"]?r[@"sub"]:L(@"Artist");
    cov.image=nil; [MMCovers load:r[@"cover"] into:cov];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];   // Auswahl nicht stehen lassen (sonst bleibt die Schrift weiß)
    [self.view endEditing:YES];
    NSString*k=_secs[ip.section]; NSDictionary*r=[self rowsOf:ip.section][ip.row];
    NSString*kind=[k isEqualToString:@"recent"]?r[@"kind"]:[k isEqualToString:@"artists"]?@"artist":[k isEqualToString:@"albums"]?@"album":@"track";
    // merken (zuletzt angetippt nach oben); Titel speichern Name + Artist, Alben "Artist · Jahr"
    NSDictionary*e=[k isEqualToString:@"recent"]?r:@{@"kind":kind,@"id":r[@"id"],@"name":([kind isEqual:@"track"]?r[@"title"]:r[@"name"])?:@"",
                                                     @"sub":([kind isEqual:@"track"]?r[@"artist"]:[kind isEqual:@"album"]?r[@"sub"]:@"")?:@"",@"cover":r[@"cover"]?:@""};
    [self remember:e];
    if([kind isEqual:@"artist"]){ [[MMRootController shared] pushContent:[[MMArtistController alloc] initWithArtistId:e[@"id"] name:e[@"name"]]]; return; }
    if([kind isEqual:@"album"]){ [[MMRootController shared] pushContent:[[MMTrackListController alloc] initWithTitle:e[@"name"] path:[@"albums/" stringByAppendingString:e[@"id"]]]]; return; }
    if([k isEqualToString:@"recent"]) [[MMRootController shared] playList:@[[MMSearchController trackOf:e]] index:0];
    else [[MMRootController shared] playList:_results index:ip.row];   // alle gefundenen Titel = Queue
}
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }   // iPad gedreht: Zellen in neuer Breite
@end
