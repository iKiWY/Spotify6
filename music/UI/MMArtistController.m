#import "MMArtistController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMTrackListController.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMSongMenu.h"

@interface MMArtistController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMArtistController {
    NSString *_artistId, *_name, *_portraitURL;
    UILabel *_nav, *_hint, *_bigName;
    UIImageView *_portrait;
    UITableView *_table, *_table2;   // iPad: _table links "Beliebt", _table2 rechts Alben / Singles & EPs
    UIActivityIndicatorView *_spin;
    NSArray *_tracks;              // @[ {id,title,artist,cover} ] - Abspiel-Queue
    NSArray *_sections;            // @[ @{title, kind:@"tracks"|@"albums", rows} ]
}

- (id)initWithArtistId:(NSString *)artistId name:(NSString *)name {
    if((self=[super init])){ _artistId=artistId; _name=name; }
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
    _nav=[[UILabel alloc] initWithFrame:CGRectMake(70,8,W-140,34)];
    _nav.text=_name?:@""; _nav.font=[UIFont boldSystemFontOfSize:16]; _nav.textColor=[SpotTheme ink]; _nav.textAlignment=NSTextAlignmentCenter; _nav.adjustsFontSizeToFitWidth=YES; [self.view addSubview:_nav];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=MMTrackRowH; _table.contentInset=UIEdgeInsetsMake(0,0,MMPageBottomInset(90),0);
    _table.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth; [SpotTheme skinTable:_table]; [self.view addSubview:_table];

    // Kopf: rundes Bild + großer Name
    UIView*head=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,172)];
    _portrait=[[UIImageView alloc] initWithFrame:CGRectMake(W/2-56,8,112,112)]; _portrait.backgroundColor=[SpotTheme card];
    _portrait.layer.cornerRadius=56; _portrait.clipsToBounds=YES; _portrait.contentMode=UIViewContentModeScaleAspectFill; [head addSubview:_portrait];
    _bigName=[[UILabel alloc] initWithFrame:CGRectMake(16,128,W-32,32)]; _bigName.text=_name?:@""; _bigName.font=[UIFont boldSystemFontOfSize:24];
    _bigName.textColor=[SpotTheme ink]; _bigName.textAlignment=NSTextAlignmentCenter; _bigName.adjustsFontSizeToFitWidth=YES; [head addSubview:_bigName];
    if([SpotTheme ios6]){ [SpotTheme albumHeadBackground:head]; [SpotTheme shadowBehind:_portrait]; [SpotTheme engrave:_bigName];   // Grund wie der Albumkopf, Bild mit Schatten
        _bigName.textColor=[SpotTheme ink]; _bigName.shadowColor=[UIColor colorWithWhite:1 alpha:0.45]; }
    MMAutoMask(head);   // iPad: Bild und Name bleiben beim Drehen mittig
    if(MMIsPad()){
        // iPad: Kopf fest oben, darunter zwei Spalten, die jede für sich scrollen (wie Spotify 2012 auf dem iPad)
        head.frame=CGRectMake(0,46,W,172); head.autoresizingMask=UIViewAutoresizingFlexibleWidth; [self.view addSubview:head];
        CGFloat ty=46+172, lw=floor(W/2);
        _table.frame=CGRectMake(0,ty,lw,H-ty); _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleHeight;
        _table2=[[UITableView alloc] initWithFrame:CGRectMake(lw,ty,W-lw,H-ty) style:UITableViewStylePlain];
        _table2.backgroundColor=[SpotTheme bg]; _table2.separatorStyle=UITableViewCellSeparatorStyleNone; _table2.dataSource=self; _table2.delegate=self; [SpotTheme skinTable:_table2];
        _table2.rowHeight=MMTrackRowH; _table2.contentInset=_table.contentInset;
        _table2.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_table2];
    } else _table.tableHeaderView=head;
    __weak MMArtistController*ws=self;   // lange drücken auf einen beliebten Titel -> Titel-Menü
    [MMSongMenu attachToTable:_table swipeToQueue:YES trackAt:^NSDictionary*(NSIndexPath*ip){ MMArtistController*s=ws; if(!s||ip.section>=(NSInteger)s->_sections.count) return nil;
        NSArray*ss=[s secs:s->_table]; if(ip.section>=(NSInteger)ss.count) return nil;
        NSDictionary*sec=ss[ip.section]; return [sec[@"kind"] isEqualToString:@"tracks"]?sec[@"rows"][ip.row]:nil; }];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,240,W-40,40)]; _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; _hint.numberOfLines=2; _hint.hidden=YES; [self.view addSubview:_hint];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.center=CGPointMake(W/2,250); _spin.hidesWhenStopped=YES; [_spin startAnimating]; [self.view addSubview:_spin];

    [self load];
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}

- (void)load {
    [MMSpotify apiUserCached:[@"artists/" stringByAppendingString:_artistId] completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        [_spin stopAnimating];
        if(![j isKindOfClass:[NSDictionary class]]){ _hint.text=(st==401)?L(@"Session expired."):L(@"Couldn't load (offline?)."); _hint.hidden=NO; return; }
        [self show:j];
    }];
}

static NSString* yearOf(NSDictionary*a){ id y=a[@"release_date"]; return [y isKindOfClass:[NSString class]]?y:@""; }

- (void)show:(NSDictionary *)j {
    NSString*nm=[j[@"name"] isKindOfClass:[NSString class]]?j[@"name"]:@"";
    if(nm.length){ _name=nm; _nav.text=nm; _bigName.text=nm; }
    NSString*pu=[MMCovers bestURL:j[@"images"]]; if(pu.length){ _portraitURL=pu; [MMCovers load:pu into:_portrait]; }
    NSMutableArray*tr=[NSMutableArray array];
    for(NSDictionary*t in ([j[@"top_tracks"] isKindOfClass:[NSArray class]]?j[@"top_tracks"]:@[])){
        if(![t isKindOfClass:[NSDictionary class]]||![t[@"id"] isKindOfClass:[NSString class]]) continue;
        NSArray*arts=t[@"artists"]; NSString*an=([arts isKindOfClass:[NSArray class]]&&arts.count)?arts[0][@"name"]:@"";
        NSString*aln=[t[@"album"][@"name"] isKindOfClass:[NSString class]]?t[@"album"][@"name"]:@"";
        [tr addObject:@{@"id":t[@"id"],@"title":t[@"name"]?:@"",@"artist":an?:@"",@"album":aln,@"cover":[MMCovers bestURL:t[@"album"][@"images"]]?:@""}];
    }
    _tracks=tr;
    NSMutableArray*secs=[NSMutableArray array];
    if(tr.count) [secs addObject:@{@"title":L(@"Popular"),@"kind":@"tracks",@"rows":tr}];
    for(NSArray*g in @[@[@"albums",L(@"Albums")],@[@"singles",L(@"Singles & EPs")]]){
        NSArray*rows=[j[g[0]] isKindOfClass:[NSArray class]]?j[g[0]]:@[];
        if(rows.count) [secs addObject:@{@"title":g[1],@"kind":@"albums",@"rows":rows}];
    }
    _sections=secs;
    _hint.hidden=(secs.count>0); if(!secs.count) _hint.text=L(@"Empty.");
    [_table reloadData]; [_table2 reloadData];
}

// Abschnitte einer Tabelle: iPhone alle; iPad links nur "Beliebt" (Titel), rechts Alben und Singles
- (NSArray *)secs:(UITableView *)tv {
    if(!_table2) return _sections?:@[];
    BOOL left=(tv==_table); NSMutableArray*o=[NSMutableArray array];
    for(NSDictionary*sec in _sections) if([sec[@"kind"] isEqualToString:@"tracks"]==left) [o addObject:sec];
    return o;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [self secs:tv].count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [[self secs:tv][s][@"rows"] count]; }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return [SpotTheme ios6]?22:40; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    if([SpotTheme ios6]) return [SpotTheme plainSectionHeader:[self secs:tv][s][@"title"] width:tv.bounds.size.width];
    UIView*v=[[UIView alloc] initWithFrame:CGRectMake(0,0,tv.bounds.size.width,40)]; v.backgroundColor=[SpotTheme bg];
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,8,tv.bounds.size.width-32,28)]; l.text=[self secs:tv][s][@"title"];
    l.font=[UIFont boldSystemFontOfSize:18]; l.textColor=[SpotTheme ink]; l.backgroundColor=[UIColor clearColor]; [v addSubview:l];
    return v;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width;
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"r",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"r",tv)];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(16,6,44,44)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; cov.clipsToBounds=YES; cov.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(70,9,W-70-16,20)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.textColor=[SpotTheme ink]; [c.contentView addSubview:ti];
        UILabel*sb=[[UILabel alloc] initWithFrame:CGRectMake(70,29,W-70-16,18)]; sb.tag=3; sb.font=[SpotTheme sub]; sb.textColor=[SpotTheme muted]; [c.contentView addSubview:sb]; }
    NSDictionary*sec=[self secs:tv][ip.section], *r=sec[@"rows"][ip.row];
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1]; cov.image=nil;
    if([sec[@"kind"] isEqualToString:@"tracks"]){
        ((UILabel*)[c.contentView viewWithTag:2]).text=r[@"title"];
        ((UILabel*)[c.contentView viewWithTag:3]).text=r[@"album"];
        [MMCovers load:r[@"cover"] into:cov];
    } else {
        ((UILabel*)[c.contentView viewWithTag:2]).text=[r[@"name"] isKindOfClass:[NSString class]]?r[@"name"]:@"";
        ((UILabel*)[c.contentView viewWithTag:3]).text=yearOf(r);
        [MMCovers load:[MMCovers bestURL:r[@"images"]] into:cov];
    }
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];   // Auswahl nicht stehen lassen (sonst bleibt die Schrift weiß)
    NSDictionary*sec=[self secs:tv][ip.section];
    if([sec[@"kind"] isEqualToString:@"tracks"]){
        [[MMRootController shared] playList:_tracks index:ip.row context:@{@"type":@"artist",@"id":_artistId,@"name":_name?:@"",@"images":_portraitURL?@[@{@"url":_portraitURL}]:@[]}];
        return;
    }
    NSDictionary*a=sec[@"rows"][ip.row]; if(![a[@"id"] isKindOfClass:[NSString class]]) return;
    MMTrackListController*tl=[[MMTrackListController alloc] initWithTitle:a[@"name"]?:L(@"Album") path:[@"albums/" stringByAppendingString:a[@"id"]]];
    [[MMRootController shared] pushContent:tl];
}
- (void)close { [[MMRootController shared] popContent]; }
- (void)relayoutForSize:(CGSize)size { [_table reloadData]; [_table2 reloadData]; }   // iPad gedreht: Zellen in neuer Breite
@end
