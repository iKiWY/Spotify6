#import "MMPadSidebar.h"
#import "MMLayout.h"
#import "SpotTheme.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "MMRecent.h"
#import "MMHistory.h"
#import "MeshL10n.h"
#import <QuartzCore/QuartzCore.h>

#define ROW_H 44
#define PL_ROW_H 48

// eigene Symbole für die beiden unteren Einträge (gleicher Strich wie die Tab-Symbole)
static UIImage* sideIcon(NSString*name, UIColor*c, CGFloat s){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s,s),NO,0); [c setStroke]; [c setFill];
    if([name isEqualToString:@"coverflow"]){   // drei Cover, die äußeren schräg
        UIBezierPath*m=[UIBezierPath bezierPathWithRect:CGRectMake(s*0.36,s*0.22,s*0.28,s*0.56)]; m.lineWidth=s*0.075; [m stroke];
        for(int side=0;side<2;side++){ CGFloat x0=side?s*0.70:s*0.30, x1=side?s*0.90:s*0.10;
            UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=s*0.075; p.lineJoinStyle=kCGLineJoinRound;
            [p moveToPoint:CGPointMake(x0,s*0.28)]; [p addLineToPoint:CGPointMake(x1,s*0.34)]; [p addLineToPoint:CGPointMake(x1,s*0.66)]; [p addLineToPoint:CGPointMake(x0,s*0.72)]; [p stroke]; }
    } else {   // settings: Zahnrad (wie oben rechts in der Library)
        UIBezierPath*gp=[UIBezierPath bezierPath]; CGFloat c0=s/2, ro=s*0.42, ri=s*0.32;
        for(int i=0;i<16;i++){ CGFloat a=i*M_PI/8-M_PI/16, r=(i%2)?ri:ro; CGPoint q=CGPointMake(c0+r*cos(a),c0+r*sin(a)); if(i==0)[gp moveToPoint:q]; else [gp addLineToPoint:q]; }
        [gp closePath]; [gp appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(c0,c0) radius:s*0.14 startAngle:0 endAngle:2*M_PI clockwise:NO]];
        gp.usesEvenOddFillRule=YES; [gp fill];
    }
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}

@interface MMPadSidebar () <UITableViewDataSource,UITableViewDelegate>
@end
@implementation MMPadSidebar {
    NSArray *_mainKeys; NSMutableArray *_mainBtns, *_footBtns;
    UITableView *_table; NSArray *_playlists; NSString *_sel;
    UIView *_coverBox; UIImageView *_bigCover; NSString *_coverURL;   // großes Cover unten (eingeblendet über die Player-Leiste)
    UIView *_footLine; BOOL _showCF; CGFloat _tableY;                 // Fuß: Cover Flow (abschaltbar) + Einstellungen
}

- (id)initWithFrame:(CGRect)f {
    if(!(self=[super initWithFrame:f])) return nil;
    BOOL six=[SpotTheme ios6];
    self.backgroundColor=six?[SpotTheme sourceListColor]:[UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1];
    CGFloat W=f.size.width, H=f.size.height;
    _mainKeys=@[@"home",@"browse",@"search",@"library"];
    NSArray*titles=@[L(@"Home"),L(@"Browse"),L(@"Search"),L(@"Library")];
    _mainBtns=[NSMutableArray array]; CGFloat y=10;
    if(six){   // iOS 6: oben dieselbe grüne Leiste wie über dem Inhalt (wie eine geteilte Ansicht)
        UINavigationBar*nb=[[UINavigationBar alloc] initWithFrame:CGRectMake(0,0,W,44)]; nb.tintColor=[SpotTheme barTint]; nb.autoresizingMask=UIViewAutoresizingFlexibleWidth;
        [nb setItems:@[[[UINavigationItem alloc] initWithTitle:@"Spotify"]] animated:NO]; nb.userInteractionEnabled=NO; [self addSubview:nb]; y+=44; }
    for(NSUInteger i=0;i<_mainKeys.count;i++,y+=ROW_H) [_mainBtns addObject:[self rowButton:_mainKeys[i] title:titles[i] y:y]];
    y+=10;
    [self lineAt:y];
    y+=12;
    UILabel*hd=[[UILabel alloc] initWithFrame:CGRectMake(20,y,W-40,16)]; hd.font=[UIFont boldSystemFontOfSize:11]; hd.textColor=[SpotTheme faint];
    hd.backgroundColor=[UIColor clearColor]; hd.text=[L(@"Recent Playlists") uppercaseString]; [self addSubview:hd];
    if(six){ hd.textColor=[UIColor colorWithRed:0.43 green:0.46 blue:0.51 alpha:1]; hd.shadowColor=[UIColor colorWithWhite:1 alpha:0.7]; hd.shadowOffset=CGSizeMake(0,1); }
    y+=22;
    CGFloat foot=2*ROW_H+12; _tableY=y; _showCF=YES;
    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,y,W,H-y-foot) style:UITableViewStylePlain];
    _table.backgroundColor=[UIColor clearColor]; _table.separatorStyle=UITableViewCellSeparatorStyleNone; _table.rowHeight=PL_ROW_H;
    _table.dataSource=self; _table.delegate=self; _table.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    [self addSubview:_table];
    _footLine=[self lineAt:H-foot];
    _footBtns=[NSMutableArray array];
    UIButton*cf=[self rowButton:@"coverflow" title:L(@"Cover Flow") y:H-foot+6]; UIButton*st=[self rowButton:@"settings" title:L(@"Settings") y:H-foot+6+ROW_H];
    for(UIButton*b in @[cf,st]) [_footBtns addObject:b];
    // rechte Kante: feine Linie zum Inhalt
    UIView*edge=[[UIView alloc] initWithFrame:CGRectMake(W-1,0,1,H)]; edge.backgroundColor=six?[UIColor colorWithWhite:0.58 alpha:1]:[SpotTheme line];
    edge.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleHeight; [self addSubview:edge];
    [self setSelectedKey:@"home"];
    [self reloadPlaylists];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(historyChanged) name:MMHistoryChanged object:nil];
    return self;
}

// ---- großes Cover unten: kommt von unten herein (aus Richtung Player-Leiste) ----
- (void)showCover:(NSString *)url animated:(BOOL)animated {
    CGFloat W=self.bounds.size.width, H=self.bounds.size.height;
    if(!_coverBox){
        _coverBox=[[UIView alloc] initWithFrame:CGRectMake(0,H,W,W)]; _coverBox.backgroundColor=[SpotTheme card];
        _coverBox.autoresizingMask=UIViewAutoresizingFlexibleTopMargin; _coverBox.clipsToBounds=YES;
        _bigCover=[[UIImageView alloc] initWithFrame:_coverBox.bounds]; _bigCover.contentMode=UIViewContentModeScaleAspectFill; [_coverBox addSubview:_bigCover];
        UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(W-40,4,36,36);
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(26,26),NO,0);   // Pfeil nach unten auf dunklem Kreis
        [[UIColor colorWithWhite:0 alpha:0.6] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,26,26)] fill];
        UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
        [p moveToPoint:CGPointMake(8,11)]; [p addLineToPoint:CGPointMake(13,16)]; [p addLineToPoint:CGPointMake(18,11)]; [[SpotTheme chromeInk] setStroke]; [p stroke];
        [back setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
        [back addTarget:self action:@selector(coverBack) forControlEvents:UIControlEventTouchUpInside]; [_coverBox addSubview:back];
        [self addSubview:_coverBox];
    }
    if(![url isEqualToString:_coverURL]){ _coverURL=url; _bigCover.image=nil; if(url.length) [MMCovers load:url into:_bigCover]; }
    CGRect on=CGRectMake(0,H-W,W,W);
    [self layoutFooter];   // Cover Flow/Einstellungen wandern ans Ende der Liste
    if(CGRectEqualToRect(_coverBox.frame,on)) return;
    [self bringSubviewToFront:_coverBox];
    [UIView animateWithDuration:animated?0.3:0 animations:^{ _coverBox.frame=on; }];
}
- (void)hideCoverAnimated:(BOOL)animated {
    if(!_coverBox) return;
    UIView*box=_coverBox; _coverBox=nil; _coverURL=nil;
    [self layoutFooter];
    [UIView animateWithDuration:animated?0.25:0 animations:^{ box.frame=CGRectOffset(box.frame,0,box.frame.size.height); } completion:^(BOOL f){ [box removeFromSuperview]; }];
}
- (void)historyChanged {   // zwei Meldungen pro Titel -> einmal neu laden
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadPlaylists) object:nil];
    [self performSelector:@selector(reloadPlaylists) withObject:nil afterDelay:0.4];
}
- (void)coverBack { if(self.onCoverBack) self.onCoverBack(); }

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// ---- Fuß: normal fest unten; liegt das große Cover dort, werden Cover Flow/Einstellungen zu den letzten Listenzeilen ----
- (NSArray *)footKeys { return _showCF?@[@"coverflow",@"settings"]:@[@"settings"]; }
- (void)setShowsCoverFlow:(BOOL)on { if(on==_showCF) return; _showCF=on; [self layoutFooter]; [_table reloadData]; }
- (void)layoutSubviews { [super layoutSubviews]; [self layoutFooter]; }
- (void)layoutFooter {
    CGFloat W=self.bounds.size.width, H=self.bounds.size.height; NSArray*keys=[self footKeys];
    BOOL inList=(_coverBox!=nil); CGFloat foot=inList?0:keys.count*ROW_H+12;
    _footLine.hidden=inList; _footLine.frame=[SpotTheme ios6]?CGRectMake(0,H-foot,W,2):CGRectMake(16,H-foot,W-32,1);
    for(UIButton*b in _footBtns){ NSUInteger i=[keys indexOfObject:b.accessibilityLabel];
        b.hidden=inList || i==NSNotFound; if(i!=NSNotFound) b.frame=CGRectMake(0,H-foot+6+i*ROW_H,W,ROW_H); }
    _table.frame=CGRectMake(0,_tableY,W,H-_tableY-foot);
    UIEdgeInsets in=UIEdgeInsetsZero; if(inList) in.bottom=W;   // Liste endet über dem großen Cover
    if(!UIEdgeInsetsEqualToEdgeInsets(_table.contentInset,in)){ _table.contentInset=_table.scrollIndicatorInsets=in; [_table reloadData]; }
}

// Trennlinie: iOS 6 eingeprägt (dunkel + weiß) über die ganze Breite, sonst fein und eingerückt
- (UIView *)lineAt:(CGFloat)y {
    CGFloat W=self.bounds.size.width; BOOL six=[SpotTheme ios6];
    UIView*ln=[[UIView alloc] initWithFrame:six?CGRectMake(0,y,W,2):CGRectMake(16,y,W-32,1)]; ln.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    ln.backgroundColor=six?[UIColor whiteColor]:[SpotTheme line];
    if(six){ UIView*d=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,1)]; d.backgroundColor=[UIColor colorWithWhite:0.76 alpha:1]; d.autoresizingMask=UIViewAutoresizingFlexibleWidth; [ln addSubview:d]; }
    [self addSubview:ln]; return ln;
}
// Farbe und Grund einer Zeile je nach Auswahl. iOS 6: gewählt = grüner Verlauf, weiße Schrift mit Schatten
- (void)styleLabel:(UILabel *)l on:(BOOL)on {
    if(![SpotTheme ios6]){ l.textColor=on?[SpotTheme ink]:[SpotTheme muted]; return; }
    l.textColor=on?[UIColor whiteColor]:[SpotTheme ink];
    l.shadowColor=on?[UIColor colorWithWhite:0 alpha:0.35]:[UIColor colorWithWhite:1 alpha:0.6]; l.shadowOffset=CGSizeMake(0,on?-1:1);
}
- (UIImage *)iconFor:(NSString *)k on:(BOOL)on {
    if(![SpotTheme ios6]){ UIColor*c=on?[SpotTheme ink]:[SpotTheme muted]; return [_mainKeys containsObject:k]?MMTabIcon(k,c,24):sideIcon(k,c,24); }
    UIColor*c=on?[UIColor whiteColor]:[UIColor colorWithWhite:0.36 alpha:1];
    return [_mainKeys containsObject:k]?[SpotTheme glyph:[SpotTheme tabGlyph:k] color:c]:sideIcon(k,c,24);
}
- (UIButton *)rowButton:(NSString *)key title:(NSString *)title y:(CGFloat)y {
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake(0,y,self.bounds.size.width,ROW_H);
    b.accessibilityLabel=key; [b addTarget:self action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside];
    UIImageView*iv=[[UIImageView alloc] initWithFrame:[SpotTheme ios6]?CGRectMake(17,(ROW_H-30)/2,30,30):CGRectMake(20,(ROW_H-24)/2,24,24)]; iv.tag=99; iv.contentMode=UIViewContentModeCenter; [b addSubview:iv];
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(58,0,self.bounds.size.width-70,ROW_H)]; l.text=title; l.font=[UIFont boldSystemFontOfSize:15];
    l.backgroundColor=[UIColor clearColor]; l.tag=98; [b addSubview:l];
    [self addSubview:b]; return b;
}
- (void)tapRow:(UIButton *)b { if(self.onSelect) self.onSelect(b.accessibilityLabel); }

- (void)setSelectedKey:(NSString *)key {
    _sel=key;
    for(UIButton*b in [_mainBtns arrayByAddingObjectsFromArray:_footBtns]){
        NSString*k=b.accessibilityLabel; BOOL on=[k isEqualToString:key];
        ((UIImageView*)[b viewWithTag:99]).image=[self iconFor:k on:on];
        [self styleLabel:(UILabel*)[b viewWithTag:98] on:on];
        if([SpotTheme ios6]){ b.backgroundColor=[UIColor clearColor]; [b setBackgroundImage:on?[SpotTheme sourceSelectionImage:b.bounds.size]:nil forState:UIControlStateNormal]; }
        else b.backgroundColor=on?[UIColor colorWithWhite:1 alpha:0.06]:[UIColor clearColor];
    }
    [_table reloadData];
}

// "Recent Playlists": zuletzt gehörte Playlists (Spotifys Verlauf + Wiedergaben in dieser App); nach jeder neuen Wiedergabe neu
- (void)reloadPlaylists {
    __weak MMPadSidebar*ws=self;
    [MMRecent playlists:30 done:^(NSArray*list){ MMPadSidebar*s=ws; if(!s) return; s->_playlists=list; [s->_table reloadData]; }];
}

- (NSString *)nameForKey:(NSString *)key {
    if([key isEqualToString:@"liked"]) return L(@"Liked Songs");
    for(NSDictionary*p in _playlists) if([key isEqualToString:[@"playlist:" stringByAppendingString:p[@"id"]]]) return p[@"name"];
    return nil;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1+_playlists.count+(_coverBox?[self footKeys].count:0); }   // +1 = Lieblingssongs
- (NSString *)keyForRow:(NSInteger)r {
    if(r==0) return @"liked";
    if(r-1<(NSInteger)_playlists.count) return [@"playlist:" stringByAppendingString:_playlists[r-1][@"id"]];
    return [self footKeys][r-1-_playlists.count];   // Cover Flow / Einstellungen (nur während das Cover liegt)
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:@"pl"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"pl"];
        c.selectionStyle=UITableViewCellSelectionStyleNone; c.backgroundColor=[UIColor clearColor];
        UIImageView*iv=[[UIImageView alloc] initWithFrame:CGRectMake(20,(PL_ROW_H-36)/2,36,36)]; iv.tag=1; iv.clipsToBounds=YES;
        iv.contentMode=UIViewContentModeScaleAspectFill; iv.backgroundColor=[SpotTheme card]; iv.layer.cornerRadius=2; [c.contentView addSubview:iv];
        UILabel*l=[[UILabel alloc] init]; l.tag=2; l.font=[UIFont systemFontOfSize:14];
        l.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:l]; }
    UIImageView*iv=(UIImageView*)[c.contentView viewWithTag:1]; UILabel*l=(UILabel*)[c.contentView viewWithTag:2];
    l.frame=CGRectMake(66,0,tv.bounds.size.width-76,PL_ROW_H);   // Breite aus der Tabelle (die Zelle hat beim Anlegen noch keine)
    NSString*key=[self keyForRow:ip.row]; BOOL on=[key isEqualToString:_sel];
    iv.image=nil; iv.accessibilityLabel=nil;
    BOOL foot=[key isEqualToString:@"coverflow"]||[key isEqualToString:@"settings"];
    iv.backgroundColor=foot?[UIColor clearColor]:[SpotTheme card]; iv.contentMode=foot?UIViewContentModeCenter:UIViewContentModeScaleAspectFill;
    if(foot){ l.text=[key isEqualToString:@"settings"]?L(@"Settings"):L(@"Cover Flow"); iv.image=[self iconFor:key on:on]; }
    else if(ip.row==0){ l.text=L(@"Liked Songs"); [MMCovers likedCoverInto:iv]; }
    else { NSDictionary*p=_playlists[ip.row-1]; l.text=p[@"name"]; iv.accessibilityLabel=p[@"id"];
        if([p[@"cover"] length]) [MMCovers thumb:p[@"cover"] size:36 radius:2 into:iv];
        else { NSString*pid=p[@"id"]; __weak UIImageView*wiv=iv;   // kein eigenes Bild: Mosaik aus den ersten Songs (wie in der Bibliothek)
            [MMCovers playlistCover:pid completion:^(NSString*mu){ if(mu.length && [wiv.accessibilityLabel isEqualToString:pid]) [MMCovers thumb:mu size:36 radius:2 into:wiv]; }]; } }
    [self styleLabel:l on:on];
    if([SpotTheme ios6]){ c.contentView.backgroundColor=[UIColor clearColor];
        UIImageView*bg=(UIImageView*)c.backgroundView; if(![bg isKindOfClass:[UIImageView class]]){ bg=[[UIImageView alloc] init]; c.backgroundView=bg; }
        bg.image=on?[SpotTheme sourceSelectionImage:CGSizeMake(tv.bounds.size.width,PL_ROW_H)]:nil; }
    else c.contentView.backgroundColor=on?[UIColor colorWithWhite:1 alpha:0.06]:[UIColor clearColor];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    if(self.onSelect) self.onSelect([self keyForRow:ip.row]);
}
@end
