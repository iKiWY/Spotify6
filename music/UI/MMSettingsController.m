#import "MMSettingsController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMTrackListController.h"
#import "MMKeySetupController.h"
#import "MMKeepAlive.h"
#import "MeshL10n.h"
#import "MMDownloadsController.h"
#import "MMDiagnosticsController.h"
#import "MMSheet.h"

@interface MMSettingsController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMSettingsController {
    UITableView *_table;
    NSArray *_items;      // flach: Titel-, Einstellungs- und Hinweis-Zeilen (keine schwebenden Abschnittsköpfe)
    NSArray *_sections;   // @[ @{title, footer, rows:@[ @{kind: switch|link|info|danger, title, key} ]} ]
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme pageBackground];   // iOS 6: Nadelstreifen
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34);
    [SpotTheme styleBackButton:back]; back.titleLabel.font=[UIFont systemFontOfSize:14];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(90,8,W-180,34)]; nav.text=L(@"Settings"); nav.font=[UIFont boldSystemFontOfSize:16];
    nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; nav.backgroundColor=[UIColor clearColor]; [self.view addSubview:nav];

    // flach wie in der Spotify-App: iOS-6-Gruppen zeichnen helle Kanten und Schatten um jede Karte
    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:[SpotTheme ios6]?UITableViewStyleGrouped:UITableViewStylePlain];   // iOS 6: echte gruppierte Liste
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone;
    if([SpotTheme ios6]){ _table.backgroundView=nil; _table.backgroundColor=[UIColor clearColor]; _table.separatorStyle=UITableViewCellSeparatorStyleSingleLine; }
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=54;
    _table.contentInset=_table.scrollIndicatorInsets=UIEdgeInsetsMake(0,0,MMPageBottomInset(90),0); _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_table];
    [self build];
    for(NSString*n in @[@"MMDownloadsChanged",@"MMDownloadDone"]) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:n object:nil];
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}
- (void)refresh { [self build]; [_table reloadData]; }   // z. B. nach dem Löschen auf der Downloads-Seite
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self build]; [_table reloadData]; }   // z. B. nach dem Suchschlüssel
- (void)build {
    NSArray*dl=[MMSpotify downloadedTracks]; long long dlBytes=0; for(NSDictionary*d in dl) dlBytes+=[d[@"bytes"] longLongValue];
    _sections=@[
      @{@"title":L(@"Display"),@"footer":@"",
        @"rows":MMIsPad()?@[@{@"kind":@"switch",@"title":L(@"Cover Flow in sidebar"),@"key":@"cflow"},   // iPad: Drehen dreht das Layout, Cover Flow kommt aus der Seitenleiste
                            @{@"kind":@"switch",@"title":L(@"Album/playlist page covers"),@"key":@"cover"}]
                         :@[@{@"kind":@"switch",@"title":L(@"Cover Flow when rotated"),@"key":@"cflow"},
                            @{@"kind":@"switch",@"title":L(@"Album/playlist page covers"),@"key":@"cover"}]},
      @{@"title":L(@"Skin"),@"footer":@"",
        @"rows":@[@{@"kind":@"link",@"title":L(@"Skin"),@"key":@"skin",@"detail":[SpotTheme ios6]?@"Classic iOS":@"Spotify"}]},
      @{@"title":L(@"Notification Center"),@"footer":L(@"Shows the current song with play, back and next in Notification Center."),
        @"rows":@[@{@"kind":@"switch",@"title":L(@"Now playing widget"),@"key":@"ncw"}]},
      @{@"title":L(@"Search"),@"footer":L(@"Search uses your own free Spotify developer key."),
        @"rows":@[@{@"kind":@"link",@"title":[MMSpotify hasSearchKey]?L(@"Change search key"):L(@"Unlock search"),@"key":@"key"}]},
      @{@"title":L(@"Downloads"),@"footer":L(@"Background download keeps saving offline songs while Spotify6 is in the background."),
        @"rows":@[@{@"kind":@"link",@"title":L(@"Downloaded songs"),@"key":@"downloads",
                    @"detail":LF(@"%lu · %@",(unsigned long)dl.count,[MMTrackListController fmtBytes:dlBytes])},
                  @{@"kind":@"switch",@"title":L(@"Background download"),@"key":@"bg"}]},
      @{@"title":L(@"Song cache"),@"footer":L(@"Recently played songs are kept (up to 500 MB) so they play again without downloading."),
        @"rows":@[@{@"kind":@"info",@"title":L(@"In use"),@"detail":[MMTrackListController fmtBytes:[MMSpotify songCacheBytes]]},
                  @{@"kind":@"button",@"title":L(@"Clear song cache"),@"key":@"clearcache"}]},
      @{@"title":L(@"Account"),@"footer":@"",
        @"rows":@[@{@"kind":@"info",@"title":L(@"Logged in to Spotify")},   // der Benutzername ist nur eine Kennung (31xh…), nichts zum Anzeigen
                  @{@"kind":@"button",@"title":L(@"Log out"),@"key":@"logout",@"primary":@YES}]},
      @{@"title":L(@"Help"),@"footer":L(@"If songs don't play, open this and send a screenshot to the developer."),
        @"rows":@[@{@"kind":@"link",@"title":L(@"Debug info"),@"key":@"diag"}]}];
    NSMutableArray*it=[NSMutableArray array];
    for(NSDictionary*sec in _sections){
        [it addObject:@{@"kind":@"header",@"title":sec[@"title"],@"first":@(it.count==0)}];
        NSArray*rows=sec[@"rows"];
        for(NSUInteger i=0;i<rows.count;i++){ NSMutableDictionary*r=[rows[i] mutableCopy]; r[@"last"]=@(i+1==rows.count); [it addObject:r]; }
        if([sec[@"footer"] length]) [it addObject:@{@"kind":@"footer",@"title":sec[@"footer"]}];
    }
    // ganz unten die installierte Version (aus der Info.plist, passt also immer zum Build)
    [it addObject:@{@"kind":@"version",@"title":[NSString stringWithFormat:@"Spotify6 %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]}];
    _items=it;
}
- (BOOL)valueFor:(NSString *)key {
    if([key isEqual:@"bg"]) return [MMKeepAlive enabled];
    if([key isEqual:@"cflow"]) return [MMRootController coverFlowOnRotate];
    if([key isEqual:@"ncw"]){ id v=[[NSUserDefaults standardUserDefaults] objectForKey:@"ncWidget"]; return v?[v boolValue]:YES; }   // liest das Widget in SpringBoard
    return [MMTrackListController coverStyle];
}
- (void)switched:(UISwitch *)sw {
    NSString*key=@[@"bg",@"cflow",@"cover",@"ncw"][sw.tag];
    if([key isEqual:@"bg"]) [MMKeepAlive setEnabled:sw.on];
    else if([key isEqual:@"ncw"]){ [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"ncWidget"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
    else if([key isEqual:@"cflow"]) [MMRootController setCoverFlowOnRotate:sw.on];
    else [MMTrackListController setCoverStyle:sw.on];   // gilt ab dem nächsten Öffnen einer Liste
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [SpotTheme ios6]?[_sections[s][@"rows"] count]:_items.count; }
// ---- iOS 6: gruppierte Liste mit System-Überschriften und -Fußtexten ----
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [SpotTheme ios6]?_sections.count:1; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return [SpotTheme ios6]?_sections[s][@"title"]:nil; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if(![SpotTheme ios6]) return nil;
    NSString*f=_sections[s][@"footer"];
    if(s+1==(NSInteger)_sections.count) f=[NSString stringWithFormat:@"%@%@Spotify6 %@",f?:@"",[f length]?@"\n\n":@"",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    return [f length]?f:nil;
}
- (UITableViewCell *)ios6Cell:(NSIndexPath *)ip {
    NSDictionary*r=_sections[ip.section][@"rows"][ip.row]; NSString*kind=r[@"kind"];
    UITableViewCell*c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.textLabel.text=r[@"title"]; c.detailTextLabel.text=r[@"detail"]; c.selectionStyle=UITableViewCellSelectionStyleNone;
    c.textLabel.adjustsFontSizeToFitWidth=YES; c.textLabel.minimumFontSize=12;   // lange Namen neben dem Schalter verkleinern statt abschneiden
    if([kind isEqual:@"switch"]){
        UISwitch*sw=[[UISwitch alloc] init]; sw.onTintColor=[SpotTheme green]; sw.on=[self valueFor:r[@"key"]];
        sw.tag=[@[@"bg",@"cflow",@"cover",@"ncw"] indexOfObject:r[@"key"]];
        [sw addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw;
    } else if([kind isEqual:@"link"]){ c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle=UITableViewCellSelectionStyleGray; }
    else if([kind isEqual:@"button"]){   // Knopf-Zeile: Text mittig; Abmelden rot
        c.textLabel.textAlignment=NSTextAlignmentCenter; c.selectionStyle=UITableViewCellSelectionStyleGray;
        c.textLabel.textColor=[r[@"primary"] boolValue]?[UIColor colorWithRed:0.78 green:0.1 blue:0.1 alpha:1]:[UIColor colorWithRed:0.20 green:0.31 blue:0.52 alpha:1];
    } else if([kind isEqual:@"info"] && !r[@"detail"]) c.textLabel.textColor=[SpotTheme muted];
    c.textLabel.highlightedTextColor=c.detailTextLabel.highlightedTextColor=[UIColor colorWithWhite:0.25 alpha:1];   // Systemauswahl (grau, rund) mit dunkler Schrift
    c.textLabel.backgroundColor=c.detailTextLabel.backgroundColor=[UIColor clearColor];
    return c;
}
static UIFont* footFont(void){ return [UIFont systemFontOfSize:13]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if([SpotTheme ios6]) return 44;
    NSDictionary*r=_items[ip.row]; NSString*kind=r[@"kind"];
    if([kind isEqual:@"header"]) return [r[@"first"] boolValue]?44:58;
    if([kind isEqual:@"version"]) return 48;
    if([kind isEqual:@"footer"]) return ceilf([r[@"title"] sizeWithFont:footFont() constrainedToSize:CGSizeMake(tv.bounds.size.width-32,200) lineBreakMode:NSLineBreakByWordWrapping].height)+12;
    return [kind isEqual:@"button"]?64:54;
}
// schmaler Pfeil nach rechts (statt des iOS-Pfeils)
static UIImage* chevron(void){
    static UIImage*img; if(img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8,14),NO,0); [[SpotTheme faint] setStroke];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=1.8; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    [p moveToPoint:CGPointMake(1.5,1.5)]; [p addLineToPoint:CGPointMake(6.5,7)]; [p addLineToPoint:CGPointMake(1.5,12.5)]; [p stroke];
    img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if([SpotTheme ios6]) return [self ios6Cell:ip];
    NSDictionary*r=_items[ip.row]; NSString*kind=r[@"kind"]; CGFloat W=tv.bounds.size.width, H=[self tableView:tv heightForRowAtIndexPath:ip];
    UITableViewCell*c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];   // wenige Zeilen: kein Wiederverwenden nötig
    c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
    if([kind isEqual:@"header"]){   // Abschnittstitel groß und fett wie in der Spotify-App
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,H-34,W-32,26)]; l.text=r[@"title"];
        l.font=[UIFont boldSystemFontOfSize:19]; l.textColor=[SpotTheme ink]; l.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:l]; return c;
    }
    if([kind isEqual:@"footer"]){   // Erklärung grau unter dem Abschnitt
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,0,W-32,H-10)]; l.text=r[@"title"]; l.numberOfLines=0;
        l.font=footFont(); l.textColor=[SpotTheme faint]; l.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:l]; return c;
    }
    if([kind isEqual:@"version"]){
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,8,W-32,H-8)]; l.text=r[@"title"]; l.textAlignment=NSTextAlignmentCenter;
        l.font=footFont(); l.textColor=[SpotTheme faint]; l.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:l]; return c;
    }
    UIView*sel=[[UIView alloc] init]; sel.backgroundColor=[SpotTheme card]; c.selectedBackgroundView=sel;
    if([kind isEqual:@"button"]){   // Pille in der Mitte: "Log out" weiß gefüllt, sonst nur umrandet
        BOOL primary=[r[@"primary"] boolValue];
        UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake((W-220)/2,12,220,40); b.layer.cornerRadius=20;
        b.backgroundColor=primary?[SpotTheme ink]:[UIColor clearColor];
        if(!primary){ b.layer.borderWidth=1; b.layer.borderColor=[SpotTheme faint].CGColor; }
        [b setTitle:r[@"title"] forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:15];
        [b setTitleColor:primary?[UIColor blackColor]:[SpotTheme ink] forState:UIControlStateNormal];
        [b setTitleColor:[SpotTheme muted] forState:UIControlStateHighlighted];
        b.accessibilityIdentifier=r[@"key"]; [b addTarget:self action:@selector(tapButton:) forControlEvents:UIControlEventTouchUpInside];
        [c.contentView addSubview:b]; return c;
    }
    if(![r[@"last"] boolValue]){ UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(16,53.5,W-16,0.5)]; ln.backgroundColor=[SpotTheme line]; ln.autoresizingMask=UIViewAutoresizingFlexibleWidth; [c addSubview:ln]; }
    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(16,0,W-140,54)]; t.text=r[@"title"]; t.backgroundColor=[UIColor clearColor];
    t.font=[UIFont systemFontOfSize:16]; t.textColor=[kind isEqual:@"info"]&&!r[@"detail"]?[SpotTheme muted]:[SpotTheme ink]; t.adjustsFontSizeToFitWidth=YES; t.minimumFontSize=12; [c.contentView addSubview:t];
    CGFloat right=W-16;
    if([kind isEqual:@"switch"]){
        UISwitch*sw=[[UISwitch alloc] init]; sw.onTintColor=[SpotTheme green]; sw.on=[self valueFor:r[@"key"]];
        sw.tag=[@[@"bg",@"cflow",@"cover",@"ncw"] indexOfObject:r[@"key"]];
        sw.frame=CGRectMake(right-sw.frame.size.width,(54-sw.frame.size.height)/2,sw.frame.size.width,sw.frame.size.height);
        [sw addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged]; [c.contentView addSubview:sw];
    } else if([kind isEqual:@"link"]){
        UIImageView*ch=[[UIImageView alloc] initWithImage:chevron()]; ch.center=CGPointMake(right-4,27); [c.contentView addSubview:ch]; right-=18;
        c.selectionStyle=UITableViewCellSelectionStyleGray;
    }
    if(r[@"detail"]){
        UILabel*d=[[UILabel alloc] initWithFrame:CGRectMake(right-130,0,130,54)]; d.text=r[@"detail"]; d.textAlignment=NSTextAlignmentRight;
        d.font=[UIFont systemFontOfSize:15]; d.textColor=[SpotTheme muted]; d.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:d];
    }
    return c;
}
- (void)tapButton:(UIButton *)b { [self run:b.accessibilityIdentifier]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary*r=[SpotTheme ios6]?_sections[ip.section][@"rows"][ip.row]:_items[ip.row];
    if([SpotTheme ios6] && [r[@"kind"] isEqual:@"button"]){ [self run:r[@"key"]]; return; }
    if([r[@"kind"] isEqual:@"link"]) [self run:r[@"key"]];
}
- (void)run:(NSString *)key {
    if([key isEqual:@"key"]){
        MMKeySetupController*k=[[MMKeySetupController alloc] init]; k.skippable=NO;
        k.onDone=^(BOOL saved){ [[MMRootController shared] popContent]; };
        [[MMRootController shared] pushContent:k];
    } else if([key isEqual:@"logout"]) [MMRootController confirmLogout];
    else if([key isEqual:@"diag"]) [[MMRootController shared] pushContent:[[MMDiagnosticsController alloc] init]];
    else if([key isEqual:@"skin"]){   // Farben und Leisten werden beim Aufbau gelesen: die Oberfläche wird neu gebaut
        [MMSheet showIn:[MMRootController shared].view title:L(@"Skin") subtitle:nil
                options:@[@"Spotify",@"Classic iOS"] done:^(NSInteger i){
            if(i<0||i>1) return; NSString*sk=i?@"ios6":@"spotify"; if([sk isEqualToString:[SpotTheme skin]]) return;
            [MMRootController switchSkin:sk];   // Oberfläche neu aufbauen, Wiedergabe läuft weiter
        }];
    }
    else if([key isEqual:@"downloads"]) [[MMRootController shared] pushContent:[[MMDownloadsController alloc] init]];
    else if([key isEqual:@"clearcache"]){ [MMSpotify clearSongCache]; [self build]; [_table reloadData]; }
}
- (void)close { [[MMRootController shared] popContent]; }
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; }   // iPad gedreht: Zellen in neuer Breite
@end
