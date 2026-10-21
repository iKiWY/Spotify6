#import "MMPadPlayerBar.h"
#import "MMRootController.h"
#import "MMAudio.h"
#import "MMCovers.h"
#import "SpotTheme.h"
#import <QuartzCore/QuartzCore.h>

// Zeichen der Leiste: iOS 6 weiß (schwarze Glanzleiste), sonst die Schriftfarbe
static UIColor* fg(void){ return [SpotTheme ios6]?[UIColor whiteColor]:[SpotTheme ink]; }
static NSString* fmt(double s){ if(s<0||s!=s)s=0; int m=(int)s/60, sec=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,sec]; }

// Wiedergabe-Symbole (Linien/Flächen wie im großen Player)
static UIImage* glyph(NSString*kind, CGFloat sz, UIColor*col){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz,sz),NO,0); [col setFill];
    if([kind isEqualToString:@"prev"]||[kind isEqualToString:@"next"]){
        BOOL n=[kind isEqualToString:@"next"]; CGFloat a=n?0:sz, d=n?1:-1;
        UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(a+d*sz*0.15,sz*0.2)]; [t addLineToPoint:CGPointMake(a+d*sz*0.15,sz*0.8)]; [t addLineToPoint:CGPointMake(a+d*sz*0.6,sz*0.5)]; [t closePath]; [t fill];
        [[UIBezierPath bezierPathWithRect:CGRectMake(n?sz*0.7:sz*0.18,sz*0.2,sz*0.12,sz*0.6)] fill];
    } else if([kind isEqualToString:@"pause"]){
        [[UIBezierPath bezierPathWithRect:CGRectMake(sz*0.3,sz*0.25,sz*0.13,sz*0.5)] fill]; [[UIBezierPath bezierPathWithRect:CGRectMake(sz*0.57,sz*0.25,sz*0.13,sz*0.5)] fill];
    } else {   // play
        UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(sz*0.36,sz*0.24)]; [t addLineToPoint:CGPointMake(sz*0.36,sz*0.76)]; [t addLineToPoint:CGPointMake(sz*0.76,sz*0.5)]; [t closePath]; [t fill];
    }
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
// Pfeil nach oben (Linie wie das Chevron im Player); circle = auf dunklem Kreis (über dem Cover)
static UIImage* upArrow(CGFloat sz, BOOL circle){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz,sz),NO,0);
    if(circle){ [[UIColor colorWithWhite:0 alpha:0.6] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,sz,sz)] fill]; }
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=circle?1.8:2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    [p moveToPoint:CGPointMake(sz*0.3,sz*0.58)]; [p addLineToPoint:CGPointMake(sz*0.5,sz*0.38)]; [p addLineToPoint:CGPointMake(sz*0.7,sz*0.58)];
    [fg() setStroke]; [p stroke];
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
static UIImage* queueGlyph(void){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20,16),NO,0); [fg() setFill];
    for(int i=0;i<3;i++){ UIRectFill(CGRectMake(5,1+i*6,15,2)); UIRectFill(CGRectMake(0,1+i*6,2,2)); }
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}

@implementation MMPadPlayerBar {
    UIImageView *_cover; UILabel *_title, *_artist, *_cur, *_rem;
    UIButton *_shuf, *_prev, *_play, *_next, *_rep, *_queue, *_info, *_toSide, *_full; BOOL _coverHidden; UIView *_load; double _loadFrac;
    UIActivityIndicatorView *_spin; UISlider *_slider; NSTimer *_timer; BOOL _scrubbing; NSString *_coverURL;
}

- (id)initWithFrame:(CGRect)f {
    if(!(self=[super initWithFrame:f])) return nil;
    BOOL six=[SpotTheme ios6];
    self.backgroundColor=six?[UIColor colorWithPatternImage:[SpotTheme toolbarImage:f.size.height]]:[SpotTheme bar];   // iOS 6: schwarze Glanzleiste wie der Mini-Player auf dem iPhone
    UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(0,0,f.size.width,0.5)]; ln.backgroundColor=six?[UIColor blackColor]:[SpotTheme line]; ln.autoresizingMask=UIViewAutoresizingFlexibleWidth; [self addSubview:ln];
    _cover=[[UIImageView alloc] init]; _cover.backgroundColor=six?[UIColor colorWithWhite:0.18 alpha:1]:[SpotTheme card]; _cover.clipsToBounds=YES; _cover.contentMode=UIViewContentModeScaleAspectFill; [self addSubview:_cover];
    _title=[[UILabel alloc] init]; _title.font=[UIFont boldSystemFontOfSize:14]; _title.textColor=fg(); _title.backgroundColor=[UIColor clearColor]; [self addSubview:_title];
    _artist=[[UILabel alloc] init]; _artist.font=[SpotTheme sub]; _artist.textColor=six?[UIColor colorWithWhite:0.72 alpha:1]:[SpotTheme muted]; _artist.backgroundColor=[UIColor clearColor]; [self addSubview:_artist];
    // Cover + Titel antippen -> großer Player
    _info=[UIButton buttonWithType:UIButtonTypeCustom]; [_info addTarget:self action:@selector(openPlayer) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:_info];
    _shuf=[self btn:@selector(toggleShuffle)]; _prev=[self btn:@selector(prev)]; _play=[self btn:@selector(togglePlay)]; _next=[self btn:@selector(next)];
    _rep=[self btn:@selector(cycleRepeat)]; _queue=[self btn:@selector(openQueue)];
    [_prev setImage:glyph(@"prev",22,fg()) forState:UIControlStateNormal]; [_next setImage:glyph(@"next",22,fg()) forState:UIControlStateNormal];
    [_queue setImage:queueGlyph() forState:UIControlStateNormal];
    _full=[self btn:@selector(openPlayer)]; [_full setImage:upArrow(28,NO) forState:UIControlStateNormal];      // ganz rechts: großer Player
    _toSide=[self btn:@selector(coverToSidebar)]; [_toSide setImage:upArrow(18,YES) forState:UIControlStateNormal];   // klein oben rechts am Cover
    if(!six){ _play.backgroundColor=[SpotTheme ink]; _play.layer.cornerRadius=17; }   // iOS 6: nur das weiße Zeichen (wie die Musik-App)
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:six?UIActivityIndicatorViewStyleWhite:UIActivityIndicatorViewStyleGray]; _spin.hidesWhenStopped=YES; [self addSubview:_spin];
    _cur=[self timeLabel:NSTextAlignmentRight]; _rem=[self timeLabel:0];
    // schlanke Linie: eigene Spurbilder 2 pt hoch (die Standardspur ist deutlich dicker)
    _slider=[[UISlider alloc] init];
    UIImage*(^track)(UIColor*)=^UIImage*(UIColor*c){ UIGraphicsBeginImageContextWithOptions(CGSizeMake(3,2),NO,0); [c setFill]; UIRectFill(CGRectMake(0,0,3,2));
        UIImage*i=[UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:1 topCapHeight:0]; UIGraphicsEndImageContext(); return i; };
    [_slider setMinimumTrackImage:track(six?[UIColor colorWithRed:0.40 green:0.86 blue:0.47 alpha:1]:[SpotTheme ink]) forState:UIControlStateNormal];
    [_slider setMaximumTrackImage:track([UIColor colorWithWhite:1 alpha:0.25]) forState:UIControlStateNormal];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(10,10),NO,0); [fg() setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,10,10)] fill];
    [_slider setThumbImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [_slider addTarget:self action:@selector(scrubStart) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnd) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [self addSubview:_slider];
    _load=[[UIView alloc] init]; _load.backgroundColor=[SpotTheme green]; _load.layer.cornerRadius=1; _load.userInteractionEnabled=NO; _load.hidden=YES; _loadFrac=-1;
    [self addSubview:_load];   // über dem Regler: zeigt beim Laden, wie weit der Titel schon da ist
    [self drawModes]; [self setPlaying:NO loading:NO];
    return self;
}
- (UIButton *)btn:(SEL)a { UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; return b; }
// al = NSTextAlignment-Wert (der Typname ist erst ab iOS 6 markiert)
- (UILabel *)timeLabel:(NSInteger)al { UILabel*l=[[UILabel alloc] init]; l.font=[UIFont systemFontOfSize:11]; l.textColor=[SpotTheme ios6]?[UIColor colorWithWhite:0.72 alpha:1]:[SpotTheme muted];
    l.backgroundColor=[UIColor clearColor]; l.textAlignment=al; [self addSubview:l]; return l; }

// Anordnung aus der aktuellen Breite (hoch 768 / quer 1024): links Titel, Mitte Tasten + Fortschritt, rechts Warteschlange
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W=self.bounds.size.width, H=self.bounds.size.height, cs=H-16;
    _cover.frame=CGRectMake(8,8,cs,cs); _cover.hidden=_coverHidden;
    _toSide.frame=CGRectMake(8+cs-26,6,28,28); _toSide.hidden=_coverHidden || !_coverURL.length;   // ohne Titel nichts zu verschieben   // Tippfläche größer als das Bild
    CGFloat midW=MIN(420,W*0.46), midX=(W-midW)/2, tx=_coverHidden?16:8+cs+12, tw=midX-tx-12;
    _title.frame=CGRectMake(tx,H/2-19,tw,18); _artist.frame=CGRectMake(tx,H/2+1,tw,16);
    _info.frame=CGRectMake(0,0,midX-8,H);   // Cover + Titel antippen -> großer Player (der Pfeil am Cover liegt darüber)
    CGFloat cy=6, b=36, mid=W/2;
    _play.frame=CGRectMake(mid-17,cy+1,34,34); _spin.center=_play.center;
    _prev.frame=CGRectMake(mid-17-12-b,cy,b,b); _next.frame=CGRectMake(mid+17+12,cy,b,b);
    _shuf.frame=CGRectMake(_prev.frame.origin.x-8-44,cy-4,44,44); _rep.frame=CGRectMake(CGRectGetMaxX(_next.frame)+8,cy-4,44,44);
    CGFloat sy=cy+b+4;
    _cur.frame=CGRectMake(midX,sy,36,20); _rem.frame=CGRectMake(midX+midW-36,sy,36,20);
    _slider.frame=CGRectMake(midX+42,sy,midW-84,20);
    _load.frame=CGRectMake(midX+42,sy+9,(midW-84)*MAX(0,MIN(1,_loadFrac)),2);   // genau auf der 2-pt-Spur
    _full.frame=CGRectMake(W-56,(H-44)/2,44,44);       // ganz rechts: großer Player
    _queue.frame=CGRectMake(W-56-44,(H-44)/2,44,44);   // links daneben: Warteschlange
}

- (void)showTitle:(NSString *)title artist:(NSString *)artist coverURL:(NSString *)cover {
    _title.text=title?:@""; _artist.text=artist?:@"";
    if(![cover isEqualToString:_coverURL]){ _coverURL=cover; _cover.image=nil; if(cover.length) [MMCovers load:cover into:_cover]; [self setNeedsLayout]; }
    [self tick];
}
- (void)setPlaying:(BOOL)playing loading:(BOOL)loading {
    [_play setImage:glyph(playing?@"pause":@"play",34,[SpotTheme ios6]?[UIColor whiteColor]:[UIColor blackColor]) forState:UIControlStateNormal];
    _play.hidden=loading; if(loading) [_spin startAnimating]; else [_spin stopAnimating];
    [self drawModes]; [self tick];
}
- (void)drawModes {
    MMRootController*r=[MMRootController shared];
    [_shuf setImage:[SpotTheme shuffleIcon:r.shuffle] forState:UIControlStateNormal];
    [_rep setImage:[SpotTheme repeatIcon:r.repeatMode] forState:UIControlStateNormal];
}

// Fortschritt nur, solange die Leiste im Fenster ist
- (void)didMoveToWindow {
    [_timer invalidate]; _timer=nil;
    if(self.window){ _timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES]; [self tick]; }
}
- (void)tick {
    double d=[MMAudio duration], t=[MMAudio currentTime];
    if(_scrubbing) t=_slider.value*d;
    else _slider.value=d>0?(float)(t/d):0;
    _cur.text=fmt(t); _rem.text=d>0?[@"-" stringByAppendingString:fmt(d-t)]:@"";
}
- (void)scrubStart { _scrubbing=YES; }
- (void)scrubEnd { _scrubbing=NO; double d=[MMAudio duration]; if(d>0) [MMAudio seekTo:_slider.value*d]; [self tick]; }

- (void)openPlayer { [[MMRootController shared] openPlayer]; }
- (void)coverToSidebar { if(self.onCoverToSidebar) self.onCoverToSidebar(); }
- (void)setLoadProgress:(double)frac { _loadFrac=frac; _load.hidden=(frac<0); [self setNeedsLayout]; }
- (void)setCoverHidden:(BOOL)hidden { if(hidden==_coverHidden) return; _coverHidden=hidden; [UIView animateWithDuration:0.25 animations:^{ [self layoutSubviews]; }]; }
- (void)togglePlay { [[MMRootController shared] togglePlayPause]; }
- (void)prev { [[MMRootController shared] playPrev]; }
- (void)next { [[MMRootController shared] playNext]; }
- (void)openQueue { [[MMRootController shared] openQueue]; }
- (void)toggleShuffle { MMRootController*r=[MMRootController shared]; [r setShuffle:!r.shuffle]; [self drawModes]; }
- (void)cycleRepeat { MMRootController*r=[MMRootController shared]; r.repeatMode=(r.repeatMode+1)%3; [self drawModes]; }
@end
