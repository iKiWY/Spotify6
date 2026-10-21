#import "MMPlayerController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMAudio.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMTrackListController.h"
#import "MMArtistController.h"
#import "MMQueueController.h"
#import "MMSongMenu.h"
#import <MediaPlayer/MediaPlayer.h>

@interface MMPlayerController () <UIGestureRecognizerDelegate>
@end

@implementation MMPlayerController {
    BOOL _playing;
    UIView *_playBtn;
    UIView *_coverView;
    UILabel *_titleLbl;
    UILabel *_artistLbl;
    UILabel *_albumLbl;        // Kopfzeile "SONG FROM ALBUM" -> Albumname
    UIView *_progView, *_thumbView;
    UILabel *_t1, *_t2;
    CGFloat _trackX, _trackW, _progY, _barH, _thumbS;   // Fortschrittsleiste: Höhe der Leiste, Größe des Knopfs
    NSTimer *_timer;
    UIActivityIndicatorView *_spinner;
    UIButton *_shufBtn, *_repBtn;
    UIView *_col; CGSize _builtSize;   // Inhalt in einer Spalte (iPhone: ganze Breite, iPad: mittig, max. 528 pt); nach dem Drehen neu gebaut
    MMQueueController *_qDock; BOOL _builtDock;
    UIView *_loadView; double _loadFrac;           // grüner Ladebalken auf der Fortschrittslinie (_loadFrac < 0 = aus)   // iPad quer: Warteschlange als Spalte rechts, der Player rückt nach links
    NSArray *_stripViews;      // iOS 6: Zeitleiste über dem Cover (Antippen des Covers blendet sie aus/ein)
    BOOL _appBehind;           // beim Runterziehen liegt die App selbst hinter dem Player (iOS 6 nimmt sie währenddessen aus dem Fenster)
}
- (UIColor *)c:(int)r g:(int)g b:(int)b { return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }

- (void)loadView {
    _loadFrac=-1;
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];   // ohne Statusleiste
    self.view.backgroundColor=[self c:40 g:34 b:52];   // dunkler Verlauf-Ton
    if([SpotTheme ios6]) self.view.backgroundColor=[UIColor blackColor];   // iOS 6: schwarz wie die Musik-App
    _playing=[MMAudio isPlaying];
    // Runterziehen von überall oberhalb der Fortschrittsleiste: Player folgt dem Finger (darunter: Spulen und Tasten)
    UIPanGestureRecognizer*drag=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragDown:)];
    drag.delegate=self; [self.view addGestureRecognizer:drag];
    [self buildUI];
}
// Drehen wie die App (iPad alle Richtungen); nach dem Drehen baut sich die Spalte in der neuen Größe neu auf
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return MMShouldAutorotate(o); }
- (BOOL)shouldAutorotate { return MMIsPad(); }
MM_IOS6_BEGIN
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return (UIInterfaceOrientationMask)MMSupportedOrientations(); }
MM_IOS6_END
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if(_qDock && self.view.bounds.size.width<self.view.bounds.size.height) [self closeQueueDock];   // hochkant: keine zwei Spalten
    if(MMIsPad() && (!CGSizeEqualToSize(self.view.bounds.size,_builtSize) || _builtDock!=(_qDock!=nil))){ [self buildUI]; [self tick]; }
    if(_qDock){ CGSize b=self.view.bounds.size; _qDock.view.frame=CGRectMake(b.width-320,0,320,b.height); }
}
- (void)buildUI {
    [_col removeFromSuperview];
    CGFloat FW=self.view.bounds.size.width-(_qDock?320:0), H=self.view.bounds.size.height, W=(MMIsPad()&&![SpotTheme ios6])?MIN(FW,528):FW;   // iOS 6: ganze Breite wie die Musik-App (Cover so groß wie möglich)
    _builtDock=(_qDock!=nil);
    // Spalte ganz unten einfügen: ein offenes Menü (Sheet) bleibt nach dem Neuaufbau sichtbar
    _col=[[UIView alloc] initWithFrame:CGRectMake(floor((FW-W)/2),0,W,H)]; [self.view insertSubview:_col atIndex:0]; _builtSize=self.view.bounds.size;
    if([SpotTheme ios6]){ [self buildIOS6:W height:H]; return; }

    // Kopf: Chevron runter + Albumzeile
    UIButton*down=[UIButton buttonWithType:UIButtonTypeCustom]; down.frame=CGRectMake(6,8,40,34);
    UIBezierPath*ch=[UIBezierPath bezierPath]; ch.lineWidth=2; ch.lineCapStyle=kCGLineCapRound;
    [ch moveToPoint:CGPointMake(12,14)];[ch addLineToPoint:CGPointMake(20,22)];[ch addLineToPoint:CGPointMake(28,14)];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(40,34),NO,0);[[SpotTheme ink] setStroke];[ch stroke];UIImage*chImg=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    [down setImage:chImg forState:UIControlStateNormal];
    [down addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [_col addSubview:down];
    // Warteschlange: Symbol oben rechts (drei Linien, wie in der Spotify-App), gegenüber vom Schließen-Pfeil
    UIButton*qb=[UIButton buttonWithType:UIButtonTypeCustom]; qb.frame=CGRectMake(W-46,8,40,34);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22,18),NO,0); [[SpotTheme ink] setFill];
    for(int i=0;i<3;i++){ UIRectFill(CGRectMake(6,2+i*6,16,2)); UIRectFill(CGRectMake(0,2+i*6,2,2)); }
    [qb setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [qb addTarget:self action:@selector(openQueue) forControlEvents:UIControlEventTouchUpInside]; [_col addSubview:qb];
    UILabel*a1=[[UILabel alloc] initWithFrame:CGRectMake(50,10,W-100,14)]; a1.text=L(@"SONG FROM ALBUM"); a1.font=[UIFont systemFontOfSize:10]; a1.textColor=[SpotTheme muted]; a1.textAlignment=NSTextAlignmentCenter; [_col addSubview:a1];
    UILabel*a2=[[UILabel alloc] initWithFrame:CGRectMake(50,24,W-100,18)]; a2.font=[UIFont boldSystemFontOfSize:12]; a2.textColor=[SpotTheme ink]; a2.textAlignment=NSTextAlignmentCenter; [_col addSubview:a2];
    _albumLbl=a2; [self refreshAlbum];

    // ---- Layout von UNTEN verankert, damit alles in 480pt passt ----
    CGFloat devY   = H-28;      // "Verfügbare Geräte"
    CGFloat ctrlCy = H-64;      // Steuerungs-Mitte (Play-Button-Top = ctrlCy-19, unten bleiben ~19 pt)
    CGFloat progY  = H-124;     // Fortschrittsleiste
    CGFloat arY    = progY-40;  // Künstler
    CGFloat tiY    = arY-28;    // Titel
    CGFloat coverTop = 66;
    CGFloat side = (tiY-16) - coverTop; if(side>W-48) side=W-48; if(side<80) side=80;
    if(MMIsPad()) coverTop += floor(((tiY-16)-coverTop-side)/2);   // iPad: Cover mittig im freien Platz über dem Titel
    CGFloat coverX = (W-side)/2;

    // großes Cover (echtes Bild kommt später rein; dunkler Platzhalter)
    UIView*cover=[[UIView alloc] initWithFrame:CGRectMake(coverX,coverTop,side,side)]; cover.backgroundColor=[SpotTheme card]; cover.layer.cornerRadius=4; cover.clipsToBounds=YES; cover.tag=99;
    UIActivityIndicatorView*cs=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    cs.center=CGPointMake(side/2,side/2); cs.tag=98; [cs startAnimating]; [cover addSubview:cs];
    [_col addSubview:cover];
    _coverView=cover;
    [cover addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAlbum)]];   // Cover -> Album

    // Titel + Künstler
    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(24,tiY,W-48-44,26)]; t.text=_trackTitle?:@""; t.font=[UIFont boldSystemFontOfSize:19]; t.textColor=[SpotTheme ink]; [_col addSubview:t]; _titleLbl=t;
    UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(24,arY,W-48-44,20)]; ar.text=_trackArtist?:@""; ar.font=[SpotTheme body]; ar.textColor=[SpotTheme muted]; [_col addSubview:ar]; _artistLbl=ar;
    ar.userInteractionEnabled=YES; [ar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openArtist)]];   // Artist -> Artist-Seite
    // (+) rechts neben Titel/Artist: laufenden Titel zu den Lieblingssongs oder in eine Playlist
    UIButton*plus=[UIButton buttonWithType:UIButtonTypeCustom]; plus.frame=CGRectMake(W-24-40,tiY+6,44,44);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(28,28),NO,0); [[SpotTheme ink] setStroke];
    UIBezierPath*pc=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1.5,1.5,25,25)]; pc.lineWidth=1.6; [pc stroke];
    UIBezierPath*pp=[UIBezierPath bezierPath]; pp.lineWidth=1.8; pp.lineCapStyle=kCGLineCapRound;
    [pp moveToPoint:CGPointMake(14,8.5)]; [pp addLineToPoint:CGPointMake(14,19.5)]; [pp moveToPoint:CGPointMake(8.5,14)]; [pp addLineToPoint:CGPointMake(19.5,14)]; [pp stroke];
    [plus setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [plus addTarget:self action:@selector(saveCurrent) forControlEvents:UIControlEventTouchUpInside]; [_col addSubview:plus];
    [self loadCover];

    // Fortschrittsleiste
    _trackX=24; _trackW=W-48; _progY=progY; _barH=3; _thumbS=10;
    UIView*track=[[UIView alloc] initWithFrame:CGRectMake(24,progY,W-48,3)]; track.backgroundColor=[SpotTheme ios6]?[self c:170 g:170 b:175]:[self c:80 g:80 b:80]; track.layer.cornerRadius=1.5; [_col addSubview:track];
    _loadView=[[UIView alloc] initWithFrame:CGRectMake(24,progY,0,3)]; _loadView.backgroundColor=[SpotTheme green]; _loadView.layer.cornerRadius=1.5; [_col addSubview:_loadView]; [self setLoadProgress:_loadFrac];
    _progView=[[UIView alloc] initWithFrame:CGRectMake(24,progY,0,3)]; _progView.backgroundColor=[SpotTheme ink]; _progView.layer.cornerRadius=1.5; [_col addSubview:_progView];
    _thumbView=[[UIView alloc] initWithFrame:CGRectMake(24-5,progY-3.5,10,10)]; _thumbView.backgroundColor=[SpotTheme ink]; _thumbView.layer.cornerRadius=5; [_col addSubview:_thumbView];
    _t1=[[UILabel alloc] initWithFrame:CGRectMake(24,progY+10,60,14)]; _t1.text=@"0:00"; _t1.font=[UIFont systemFontOfSize:11]; _t1.textColor=[SpotTheme muted]; [_col addSubview:_t1];
    _t2=[[UILabel alloc] initWithFrame:CGRectMake(W-84,progY+10,60,14)]; _t2.text=@"-0:00"; _t2.font=[UIFont systemFontOfSize:11]; _t2.textColor=[SpotTheme muted]; _t2.textAlignment=NSTextAlignmentRight; [_col addSubview:_t2];
    // Spul-Bereich (tippen oder ziehen)
    UIView*seek=[[UIView alloc] initWithFrame:CGRectMake(_trackX-12,progY-20,_trackW+24,44)];
    [seek addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeek:)]];
    [seek addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeek:)]];
    [_col addSubview:seek];

    // Steuerung
    _shufBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _shufBtn.frame=CGRectMake(24-11,ctrlCy-11,44,44);
    [_shufBtn addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside];
    [_col addSubview:_shufBtn]; [self drawShuffle];
    [self addCtrl:@"prev" x:W*0.28 cy:ctrlCy sz:26 action:nil];
    _playBtn=[[UIView alloc] initWithFrame:CGRectMake(W/2-32,ctrlCy-19,64,64)]; _playBtn.backgroundColor=[SpotTheme ink]; _playBtn.layer.cornerRadius=32; [_col addSubview:_playBtn];
    UIButton*pb=[UIButton buttonWithType:UIButtonTypeCustom]; pb.frame=_playBtn.bounds; [pb addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside]; [_playBtn addSubview:pb];
    [self drawPlayPause];
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.frame=_playBtn.bounds; _spinner.hidesWhenStopped=YES; _spinner.userInteractionEnabled=NO; [_playBtn addSubview:_spinner];
    [self addCtrl:@"next" x:W*0.72-26 cy:ctrlCy sz:26 action:nil];
    _repBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _repBtn.frame=CGRectMake(W-46-11,ctrlCy-11,44,44);
    [_repBtn addTarget:self action:@selector(cycleRepeat) forControlEvents:UIControlEventTouchUpInside];
    [_col addSubview:_repBtn]; [self drawRepeat];
    // Tap-Flächen für Zurück/Weiter
    UIButton*prevB=[UIButton buttonWithType:UIButtonTypeCustom]; prevB.frame=CGRectMake(W*0.28-9,ctrlCy-9,44,44); [prevB addTarget:self action:@selector(prevTrack) forControlEvents:UIControlEventTouchUpInside]; [_col addSubview:prevB];
    UIButton*nextB=[UIButton buttonWithType:UIButtonTypeCustom]; nextB.frame=CGRectMake(W*0.72-26-9,ctrlCy-9,44,44); [nextB addTarget:self action:@selector(nextTrack) forControlEvents:UIControlEventTouchUpInside]; [_col addSubview:nextB];

    (void)devY;  // "Verfügbare Geräte" entfernt (keine Connect-Funktion)
}

// ---- iOS 6 (Musik-App) ----
static void grad(CGRect r, const CGFloat *c, const CGFloat *l, size_t n){
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB(); CGGradientRef g=CGGradientCreateWithColorComponents(cs,c,l,n);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(),g,CGPointMake(0,r.origin.y),CGPointMake(0,CGRectGetMaxY(r)),0); CGGradientRelease(g); CGColorSpaceRelease(cs);
}
// Steuerzeichen weiß mit dunkler Kante darüber (auf der schwarzen Glanzleiste)
static UIImage* transportGlyph(NSString*kind, CGFloat sz){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz,sz+1),NO,0);
    for(int pass=0;pass<2;pass++){
        CGFloat dy=pass?1:0; [(pass?[UIColor whiteColor]:[UIColor colorWithWhite:0 alpha:0.85]) setFill];
        if([kind isEqualToString:@"play"]){ UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(sz*0.22,sz*0.12+dy)]; [t addLineToPoint:CGPointMake(sz*0.22,sz*0.88+dy)]; [t addLineToPoint:CGPointMake(sz*0.86,sz*0.5+dy)]; [t closePath]; [t fill]; }
        else if([kind isEqualToString:@"pause"]){ UIRectFill(CGRectMake(sz*0.2,sz*0.14+dy,sz*0.22,sz*0.72)); UIRectFill(CGRectMake(sz*0.58,sz*0.14+dy,sz*0.22,sz*0.72)); }
        else { BOOL n=[kind isEqualToString:@"next"];   // zwei Dreiecke + Strich
            for(int k=0;k<2;k++){ CGFloat x0=n?sz*(0.06+k*0.36):sz*(0.94-k*0.36), x1=n?x0+sz*0.36:x0-sz*0.36;
                UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(x0,sz*0.22+dy)]; [t addLineToPoint:CGPointMake(x0,sz*0.78+dy)]; [t addLineToPoint:CGPointMake(x1,sz*0.5+dy)]; [t closePath]; [t fill]; }
            UIRectFill(CGRectMake(n?sz*0.80:sz*0.08,sz*0.22+dy,sz*0.1,sz*0.56)); }
    }
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
// Schwarzer, umrandeter Leistenknopf (Kopfleiste der Musik-App) mit weißem Zeichen
static UIImage* blackBarButton(UIImage*glyph, CGFloat w){
    CGFloat H=30; UIGraphicsBeginImageContextWithOptions(CGSizeMake(w,H),NO,0);
    UIBezierPath*p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,w-1,H-2) cornerRadius:5];
    [[UIColor colorWithWhite:1 alpha:0.18] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,1.5,w-1,H-2) cornerRadius:5] fill];
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [p addClip];
    CGFloat c[]={0.32,0.32,0.32,1, 0.12,0.12,0.12,1, 0.05,0.05,0.05,1}, l[]={0,0.5,1}; grad(CGRectMake(0,0,w,H),c,l,3);
    CGContextRestoreGState(cx); [[UIColor blackColor] setStroke]; p.lineWidth=1; [p stroke];
    [glyph drawAtPoint:CGPointMake((w-glyph.size.width)/2,(H-1-glyph.size.height)/2)];
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
- (void)buildIOS6:(CGFloat)W height:(CGFloat)H {
    _col.backgroundColor=[UIColor blackColor];
    BOOL hud=MMIsPad();   // iPad: Tasten in einer schwebenden Fläche über dem Cover (wie die Video-App), das Cover nimmt den ganzen Platz
    CGFloat ctrlMin=hud?0:96, side=MIN(W,H-44-ctrlMin), coverX=(W-side)/2, coverY=44, barY=coverY+side, barH=H-barY;
    if(hud){ coverY=44+floor((H-44-side)/2); barY=coverY+side; barH=H-barY;   // iPad: Cover senkrecht mittig
        UIView*bgTap=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,H)]; bgTap.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;   // schwarze Fläche antippen = Steuerung aus/ein
        [bgTap addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleStrip)]]; [_col addSubview:bgTap]; }
    CGFloat BW=W, barX=0; if(hud){ barH=100; BW=MIN(W-48,520); barX=floor((W-BW)/2);
        CGFloat free=H-(coverY+side); barY=free>=barH+24?coverY+side+floor((free-barH)/2):H-barH-28; }   // Platz unter dem Cover: mittig darin, sonst schwebend über dem Cover
    // Cover über die ganze Breite (Platzhalter dunkel, Bild kommt nach)
    UIView*cover=[[UIView alloc] initWithFrame:CGRectMake(coverX,coverY,side,side)]; cover.backgroundColor=[UIColor colorWithWhite:0.12 alpha:1]; cover.clipsToBounds=YES; cover.tag=99;
    UIActivityIndicatorView*cs=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    cs.center=CGPointMake(side/2,side/2); cs.tag=98; [cs startAnimating]; [cover addSubview:cs];
    [_col addSubview:cover]; _coverView=cover;
    [cover addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleStrip)]];   // wie die Musik-App: Cover antippen = Zeitleiste weg/her
    [self loadCover];
    // Kopfleiste: schwarzer Glanz, links Schließen, rechts Warteschlange, Mitte Artist / Titel / Album
    UIImageView*top=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,W,44)]; top.image=[SpotTheme toolbarImage:44]; top.userInteractionEnabled=YES; [_col addSubview:top];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(16,10),NO,0); [[UIColor whiteColor] setStroke];
    UIBezierPath*ch=[UIBezierPath bezierPath]; ch.lineWidth=2.4; ch.lineCapStyle=kCGLineCapRound; ch.lineJoinStyle=kCGLineJoinRound;
    [ch moveToPoint:CGPointMake(2,2)]; [ch addLineToPoint:CGPointMake(8,8)]; [ch addLineToPoint:CGPointMake(14,2)]; [ch stroke];
    UIImage*chImg=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    UIButton*down=[UIButton buttonWithType:UIButtonTypeCustom]; down.frame=CGRectMake(6,7,40,30); [down setImage:blackBarButton(chImg,40) forState:UIControlStateNormal];
    [down addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [top addSubview:down];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(18,14),NO,0); [[UIColor whiteColor] setFill];
    for(int i=0;i<3;i++){ UIRectFill(CGRectMake(5,1+i*5,13,2)); UIRectFill(CGRectMake(0,1+i*5,2,2)); }
    UIImage*lst=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    UIButton*qb=[UIButton buttonWithType:UIButtonTypeCustom]; qb.frame=CGRectMake(W-46,7,40,30); [qb setImage:blackBarButton(lst,40) forState:UIControlStateNormal];
    [qb addTarget:self action:@selector(openQueue) forControlEvents:UIControlEventTouchUpInside]; [top addSubview:qb];
    UILabel*(^line)(CGFloat,UIColor*)=^UILabel*(CGFloat y,UIColor*c){ UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(52,y,W-104,13)]; l.font=[UIFont boldSystemFontOfSize:12];
        l.textColor=c; l.textAlignment=NSTextAlignmentCenter; l.backgroundColor=[UIColor clearColor]; l.shadowColor=[UIColor blackColor]; l.shadowOffset=CGSizeMake(0,-1); [top addSubview:l]; return l; };
    UIColor*grey=[UIColor colorWithWhite:0.65 alpha:1];
    _artistLbl=line(3,grey); _artistLbl.text=_trackArtist?:@"";
    _titleLbl=line(16,[UIColor whiteColor]); _titleLbl.text=_trackTitle?:@"";
    _albumLbl=line(29,grey); [self refreshAlbum];
    UIView*hit=[[UIView alloc] initWithFrame:CGRectMake(52,0,W-104,44)]; [top addSubview:hit];   // Artist / Titel / Album antippen -> Album des Titels
    [hit addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAlbum)]];
    // Zeitleiste halbdurchsichtig über dem oberen Coverrand: Zeit, Leiste mit Glanzknopf, Restzeit, (+)
    UIView*strip=[[UIView alloc] initWithFrame:CGRectMake(0,44,W,40)]; strip.backgroundColor=[UIColor colorWithWhite:0 alpha:0.6]; [_col addSubview:strip];
    _t1=[[UILabel alloc] initWithFrame:CGRectMake(4,13,44,14)]; _t1.font=[UIFont boldSystemFontOfSize:12]; _t1.textColor=[UIColor whiteColor]; _t1.textAlignment=NSTextAlignmentRight; _t1.backgroundColor=[UIColor clearColor]; _t1.text=@"0:00"; [strip addSubview:_t1];
    _t2=[[UILabel alloc] initWithFrame:CGRectMake(W-88,13,44,14)]; _t2.font=[UIFont boldSystemFontOfSize:12]; _t2.textColor=[UIColor whiteColor]; _t2.backgroundColor=[UIColor clearColor]; _t2.text=@"-0:00"; [strip addSubview:_t2];
    _barH=9; _thumbS=23; _progY=44+(40-_barH)/2;
    _trackX=52+_thumbS/2; _trackW=(W-92)-_thumbS/2-_trackX;   // Knopf ragt halb über die Enden: so weit Abstand zu den Zeiten
    UIView*track=[[UIView alloc] initWithFrame:CGRectMake(_trackX,_progY,_trackW,_barH)]; track.backgroundColor=[UIColor colorWithWhite:0.2 alpha:1]; track.layer.cornerRadius=_barH/2;
    track.layer.borderColor=[UIColor colorWithWhite:0 alpha:0.9].CGColor; track.layer.borderWidth=1; [_col addSubview:track];
    _loadView=[[UIView alloc] initWithFrame:CGRectMake(_trackX,_progY,0,_barH)]; _loadView.backgroundColor=[UIColor colorWithWhite:0.45 alpha:1]; _loadView.layer.cornerRadius=_barH/2; [_col addSubview:_loadView]; [self setLoadProgress:_loadFrac];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,_barH),YES,0); CGFloat gc[]={0.45,0.85,0.50,1, 0.12,0.58,0.22,1}, gl[]={0,1}; grad(CGRectMake(0,0,1,_barH),gc,gl,2);
    UIColor*fill=[UIColor colorWithPatternImage:UIGraphicsGetImageFromCurrentImageContext()]; UIGraphicsEndImageContext();
    _progView=[[UIView alloc] initWithFrame:CGRectMake(_trackX,_progY,0,_barH)]; _progView.backgroundColor=fill; _progView.layer.cornerRadius=_barH/2; [_col addSubview:_progView];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(_thumbS,_thumbS),NO,0);   // weißer Glanzknopf
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSetShadowWithColor(cx,CGSizeMake(0,1),1.5,[UIColor colorWithWhite:0 alpha:0.7].CGColor);
    UIBezierPath*kn=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2,1.5,_thumbS-4,_thumbS-4)]; [[UIColor whiteColor] setFill]; [kn fill];
    CGContextSetShadowWithColor(cx,CGSizeZero,0,NULL); CGContextSaveGState(cx); [kn addClip];
    CGFloat kc[]={1,1,1,1, 0.82,0.82,0.84,1}, kl[]={0,1}; grad(CGRectMake(0,1.5,_thumbS,_thumbS-4),kc,kl,2); CGContextRestoreGState(cx);
    UIImageView*th=[[UIImageView alloc] initWithImage:UIGraphicsGetImageFromCurrentImageContext()]; UIGraphicsEndImageContext();
    _thumbView=th; [_col addSubview:th]; [self placeProgress:0];
    UIView*seek=[[UIView alloc] initWithFrame:CGRectMake(_trackX-12,44,_trackW+24,40)];
    [seek addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeek:)]];
    [seek addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeek:)]];
    [_col addSubview:seek];
    UIButton*plus=[UIButton buttonWithType:UIButtonTypeCustom]; plus.frame=CGRectMake(W-46,44,40,40);   // mittig unter dem Warteschlangen-Knopf
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20,20),NO,0); [[UIColor whiteColor] setStroke];
    UIBezierPath*pp=[UIBezierPath bezierPath]; pp.lineWidth=2.2; pp.lineCapStyle=kCGLineCapRound;
    [pp moveToPoint:CGPointMake(10,3)]; [pp addLineToPoint:CGPointMake(10,17)]; [pp moveToPoint:CGPointMake(3,10)]; [pp addLineToPoint:CGPointMake(17,10)]; [pp stroke];
    [plus setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [plus addTarget:self action:@selector(saveCurrent) forControlEvents:UIControlEventTouchUpInside]; [_col addSubview:plus];
    _stripViews=@[strip,track,_loadView,_progView,_thumbView,seek,plus];
    // Schwarze Glanzleiste unten: Wiederholen, Zurück, Play/Pause, Weiter, Zufall; darunter die Lautstärke
    UIImage*barImg;
    if(hud){   // abgerundet, halbdurchsichtig schwarz mit Glanz oben und feiner heller Kante, in voller Größe gezeichnet
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(BW,barH),NO,0); CGContextRef hc=UIGraphicsGetCurrentContext();
        UIBezierPath*hp=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,BW-1,barH-1) cornerRadius:12];
        [[UIColor colorWithWhite:0 alpha:0.68] setFill]; [hp fill];
        CGContextSaveGState(hc); [hp addClip]; CGFloat hg[]={1,1,1,0.16, 1,1,1,0.05, 1,1,1,0, 1,1,1,0}, hl[]={0,0.5,0.5,1}; grad(CGRectMake(0,0,BW,barH),hg,hl,4); CGContextRestoreGState(hc);
        [[UIColor colorWithWhite:1 alpha:0.25] setStroke]; hp.lineWidth=1; [hp stroke];
        barImg=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    } else {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,barH),YES,0);
        CGFloat ac[]={0.24,0.24,0.25,1, 0.11,0.11,0.12,1, 0.03,0.03,0.03,1, 0,0,0,1}, al[]={0,0.45,0.45,1}; grad(CGRectMake(0,0,1,barH),ac,al,4);   // Glanzkante wie die Kopfleiste
        [[UIColor blackColor] setFill]; UIRectFill(CGRectMake(0,0,1,1)); [[UIColor colorWithWhite:0.42 alpha:1] setFill]; UIRectFill(CGRectMake(0,1,1,1));
        barImg=[UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:0 topCapHeight:0]; UIGraphicsEndImageContext();
    }
    UIImageView*alu=[[UIImageView alloc] initWithFrame:CGRectMake(barX,barY,BW,barH)]; alu.image=barImg;
    alu.userInteractionEnabled=YES; [_col addSubview:alu];
    if(hud){ _stripViews=[_stripViews arrayByAddingObjectsFromArray:@[alu,top]];   // iPad: Antippen lässt nur das Cover stehen alu.layer.shadowColor=[UIColor blackColor].CGColor; alu.layer.shadowOpacity=0.5; alu.layer.shadowRadius=6;
        alu.layer.shadowOffset=CGSizeMake(0,2); alu.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:alu.bounds cornerRadius:12].CGPath; }   // Cover antippen blendet sie mit aus
    BOOL vol=barH>=90; CGFloat cy=vol?barH*0.38:barH/2, volY=barH*0.70;
    if(hud){ cy=36; volY=66; }
    _repBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _repBtn.frame=CGRectMake(8,cy-22,44,44); [_repBtn addTarget:self action:@selector(cycleRepeat) forControlEvents:UIControlEventTouchUpInside]; [alu addSubview:_repBtn]; [self drawRepeat];
    _shufBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _shufBtn.frame=CGRectMake(BW-52,cy-22,44,44); [_shufBtn addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside]; [alu addSubview:_shufBtn]; [self drawShuffle];
    UIButton*prevB=[UIButton buttonWithType:UIButtonTypeCustom]; prevB.frame=CGRectMake(BW/2-110,cy-24,60,48); [prevB setImage:transportGlyph(@"prev",30) forState:UIControlStateNormal];
    [prevB addTarget:self action:@selector(prevTrack) forControlEvents:UIControlEventTouchUpInside]; [alu addSubview:prevB];
    UIButton*nextB=[UIButton buttonWithType:UIButtonTypeCustom]; nextB.frame=CGRectMake(BW/2+50,cy-24,60,48); [nextB setImage:transportGlyph(@"next",30) forState:UIControlStateNormal];
    [nextB addTarget:self action:@selector(nextTrack) forControlEvents:UIControlEventTouchUpInside]; [alu addSubview:nextB];
    _playBtn=[[UIView alloc] initWithFrame:CGRectMake(BW/2-30,cy-26,60,52)]; [alu addSubview:_playBtn];
    UIButton*pb=[UIButton buttonWithType:UIButtonTypeCustom]; pb.frame=_playBtn.bounds; [pb addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside]; [_playBtn addSubview:pb];
    [self drawPlayPause];
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.frame=_playBtn.bounds; _spinner.hidesWhenStopped=YES; _spinner.userInteractionEnabled=NO; [_playBtn addSubview:_spinner];
    if(vol){ MPVolumeView*vv=[[MPVolumeView alloc] initWithFrame:CGRectMake(24,volY,BW-48,23)]; vv.showsRouteButton=NO; [alu addSubview:vv];
        if([vv respondsToSelector:@selector(setMinimumVolumeSliderImage:forState:)]){   // iOS 6: gefüllter Teil grün statt blau
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(11,9),NO,0); UIBezierPath*rr=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,10,8) cornerRadius:4];
            CGContextRef vc=UIGraphicsGetCurrentContext(); CGContextSaveGState(vc); [rr addClip]; CGFloat vgc[]={0.45,0.85,0.50,1, 0.12,0.58,0.22,1}, vgl[]={0,1}; grad(CGRectMake(0,0,11,9),vgc,vgl,2);
            CGContextRestoreGState(vc); [[UIColor colorWithWhite:0 alpha:0.5] setStroke]; [rr stroke];
            UIImage*mi=[UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(0,5,0,5)]; UIGraphicsEndImageContext();
            MM_IOS6_BEGIN [vv setMinimumVolumeSliderImage:mi forState:UIControlStateNormal]; MM_IOS6_END }
        else for(UIView*sv in vv.subviews) if([sv isKindOfClass:[UISlider class]] && [sv respondsToSelector:@selector(setMinimumTrackTintColor:)])   // iOS 5: Regler darin grün tönen
            ((UISlider*)sv).minimumTrackTintColor=[UIColor colorWithRed:0.25 green:0.70 blue:0.33 alpha:1]; }
}
- (void)toggleStrip {
    BOOL show=((UIView*)_stripViews.firstObject).alpha<0.5;
    [UIView animateWithDuration:0.25 animations:^{ for(UIView*v in _stripViews) v.alpha=show?1:0; }];
    for(UIView*v in _stripViews) if(v.gestureRecognizers.count||[v isKindOfClass:[UIButton class]]) v.userInteractionEnabled=show;   // ausgeblendet nicht antippbar
}
- (void)drawPlayPause {
    for(UIView*v in _playBtn.subviews){ if(v.tag==7)[v removeFromSuperview]; }
    if([SpotTheme ios6]){ UIImageView*iv=[[UIImageView alloc] initWithImage:transportGlyph(_playing?@"pause":@"play",36)]; iv.tag=7; iv.userInteractionEnabled=NO;
        iv.center=CGPointMake(_playBtn.bounds.size.width/2,_playBtn.bounds.size.height/2); [_playBtn addSubview:iv]; return; }
    UIView*icon=[[UIView alloc] initWithFrame:_playBtn.bounds]; icon.tag=7; icon.userInteractionEnabled=NO;
    if(_playing){ // Pause = zwei Balken
        for(int i=0;i<2;i++){ UIView*b=[[UIView alloc] initWithFrame:CGRectMake(23+i*12,20,6,24)]; b.backgroundColor=[SpotTheme bg]; [icon addSubview:b]; }   // 23..41 -> mittig im 64er-Kreis
    } else { // Play = Dreieck
        UIBezierPath*tri=[UIBezierPath bezierPath]; [tri moveToPoint:CGPointMake(25,20)];[tri addLineToPoint:CGPointMake(25,44)];[tri addLineToPoint:CGPointMake(45,32)];[tri closePath];
        CAShapeLayer*sl=[CAShapeLayer layer]; sl.path=tri.CGPath; sl.fillColor=[[SpotTheme bg] CGColor]; [icon.layer addSublayer:sl];
    }
    [_playBtn addSubview:icon];
}
- (void)toggleShuffle { MMRootController*r=[MMRootController shared]; [r setShuffle:!r.shuffle]; [self drawShuffle]; }
// Spotify-Symbol: zwei gekreuzte Pfeile; an = grün + Punkt darunter
- (void)drawShuffle { [_shufBtn setImage:[SpotTheme shuffleIcon:[MMRootController shared].shuffle] forState:UIControlStateNormal]; }
- (void)cycleRepeat { MMRootController*r=[MMRootController shared]; r.repeatMode=(r.repeatMode+1)%3; [self drawRepeat]; }
// Spotify-Symbol: Schleife mit Pfeil; an = grün + Punkt, "Titel wiederholen" zusätzlich mit kleiner 1
- (void)drawRepeat { [_repBtn setImage:[SpotTheme repeatIcon:[MMRootController shared].repeatMode] forState:UIControlStateNormal]; }
- (void)togglePlay { [[MMRootController shared] togglePlayPause]; _playing=[MMAudio isPlaying]; [self drawPlayPause]; }   // über die Wiedergabe-Logik (Neustart nach Titelende)

- (void)loadCover {
    if(!_coverURL.length) return;
    NSString*u=_coverURL;
    UIImageView*cur=[_coverView.subviews lastObject];
    if([cur isKindOfClass:[UIImageView class]] && [MMCovers cached:u]){ cur.image=[MMCovers cached:u]; return; }   // schon im Speicher -> sofort
    [MMCovers load:u completion:^(UIImage*img){
        if(!img || ![u isEqualToString:_coverURL]) return;   // veraltet (inzwischen weitergeskippt)
        for(UIView*v in _coverView.subviews)[v removeFromSuperview];
        UIImageView*iv=[[UIImageView alloc] initWithFrame:_coverView.bounds];
        iv.image=img; iv.contentMode=UIViewContentModeScaleAspectFill; iv.clipsToBounds=YES;
        [_coverView addSubview:iv];
    }];
}

// Von außen aufrufbar, wenn echte Metadaten/Cover nach dem Öffnen eintreffen.
- (void)updateTitle:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover {
    self.trackTitle=title; self.trackArtist=artist; self.coverURL=cover;
    _titleLbl.text=title?:@""; _artistLbl.text=artist?:@""; [self loadCover]; [self refreshAlbum];
    [_qDock reload];   // eingeblendete Warteschlange zeigt den neuen Titel
}
- (void)setLoadProgress:(double)frac {
    _loadFrac=frac; _loadView.hidden=(frac<0);
    if(frac>=0) _loadView.frame=CGRectMake(_trackX,_progY,_trackW*MIN(1,frac),_barH);
}
- (void)placeProgress:(CGFloat)w {
    _progView.frame=CGRectMake(_trackX,_progY,w,_barH);
    _thumbView.frame=CGRectMake(_trackX+w-_thumbS/2,_progY+_barH/2-_thumbS/2,_thumbS,_thumbS);
}
- (void)refreshAlbum { NSString*al=[MMRootController shared].nowPlaying[@"album"]; _albumLbl.text=al.length?al:(_trackArtist?:@""); }

// ---- Album / Artist des laufenden Titels öffnen: Player schließen, Seite im Inhaltsbereich zeigen ----
// IDs kommen aus den Titel-Metadaten; sind sie noch nicht da (gerade gewechselt), erst nachladen.
- (void)openPage:(BOOL)album {
    NSDictionary*np=[MMRootController shared].nowPlaying; if(!np) return;
    NSString*key=album?@"albumId":@"artistId";
    void (^go)(NSString*,NSString*)=^(NSString*pid,NSString*name){
        UIViewController*vc=album?[[MMTrackListController alloc] initWithTitle:name.length?name:L(@"Album") path:[@"albums/" stringByAppendingString:pid]]
                                 :[[MMArtistController alloc] initWithArtistId:pid name:name];
        [self dismissViewControllerAnimated:YES completion:^{ [[MMRootController shared] pushContent:vc]; }];
    };
    if([np[key] length]){ go(np[key], album?np[@"album"]:np[@"artist"]); return; }
    [MMSpotify fetchTrack:np[@"id"] completion:^(NSDictionary*info,NSString*e){
        if([info[key] length]) go(info[key], album?info[@"album"]:info[@"artist"]);
    }];
}
- (void)openAlbum { [self openPage:YES]; }
- (void)saveCurrent { NSDictionary*np=[MMRootController shared].nowPlaying; if(np) [MMSongMenu showSaveForTrack:np]; }
- (void)openQueue {
    if(MMIsPad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation)){ [self toggleQueueDock]; return; }   // quer: von rechts herein
    [self presentViewController:[[MMQueueController alloc] init] animated:YES completion:nil];
}
// ---- iPad quer: Warteschlange schiebt sich von rechts herein, die Player-Spalte rückt in die linke Fläche ----
- (void)toggleQueueDock {
    if(_qDock){ [self closeQueueDock]; return; }
    MMQueueController*q=[[MMQueueController alloc] init]; __weak MMPlayerController*ws=self; q.onClose=^{ [ws closeQueueDock]; };
    [self addChildViewController:q];
    CGSize b=self.view.bounds.size; q.view.frame=CGRectMake(b.width,0,320,b.height);
    UIView*edge=[[UIView alloc] initWithFrame:CGRectMake(0,0,1,b.height)]; edge.backgroundColor=[SpotTheme line]; edge.autoresizingMask=UIViewAutoresizingFlexibleHeight; [q.view addSubview:edge];
    [q viewWillAppear:YES]; [self.view addSubview:q.view]; [q didMoveToParentViewController:self];
    _qDock=q; [self slideColumn];
    [UIView animateWithDuration:0.3 animations:^{ q.view.frame=CGRectMake(b.width-320,0,320,b.height); }];
}
- (void)closeQueueDock {
    MMQueueController*q=_qDock; if(!q) return; _qDock=nil;
    [q willMoveToParentViewController:nil]; [self slideColumn];
    [UIView animateWithDuration:0.3 animations:^{ q.view.frame=CGRectOffset(q.view.frame,320,0); } completion:^(BOOL f){ [q.view removeFromSuperview]; [q removeFromParentViewController]; }];
}
// Spalte neu bauen und vom alten Platz an den neuen gleiten lassen
- (void)slideColumn {
    CGFloat oldX=_col.frame.origin.x; [self buildUI]; [self tick];
    _col.transform=CGAffineTransformMakeTranslation(oldX-_col.frame.origin.x,0);
    [UIView animateWithDuration:0.3 animations:^{ _col.transform=CGAffineTransformIdentity; }];
}
- (void)openArtist { [self openPage:NO]; }

- (void)addCtrl:(NSString *)kind x:(CGFloat)x cy:(CGFloat)cy sz:(CGFloat)sz action:(SEL)sel {
    UIImageView*iv=[[UIImageView alloc] initWithFrame:CGRectMake(x,cy,sz,sz)];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz,sz),NO,0);
    UIColor*col=([kind isEqualToString:@"shuffle"]||[kind isEqualToString:@"repeat"])?[SpotTheme muted]:[SpotTheme ink];
    [col setStroke]; [col setFill];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    if([kind isEqualToString:@"prev"]||[kind isEqualToString:@"next"]){
        BOOL n=[kind isEqualToString:@"next"]; CGFloat a=n?0:sz, d=n?1:-1;
        UIBezierPath*t1=[UIBezierPath bezierPath]; [t1 moveToPoint:CGPointMake(a+d*sz*0.15,sz*0.2)];[t1 addLineToPoint:CGPointMake(a+d*sz*0.15,sz*0.8)];[t1 addLineToPoint:CGPointMake(a+d*sz*0.55,sz*0.5)];[t1 closePath];[t1 fill];
        UIBezierPath*bar=[UIBezierPath bezierPathWithRect:CGRectMake(n?sz*0.78:sz*0.1,sz*0.2,sz*0.12,sz*0.6)];[bar fill];
    } else if([kind isEqualToString:@"shuffle"]){
        [p moveToPoint:CGPointMake(sz*0.1,sz*0.3)];[p addLineToPoint:CGPointMake(sz*0.35,sz*0.3)];[p addLineToPoint:CGPointMake(sz*0.7,sz*0.7)];[p addLineToPoint:CGPointMake(sz*0.9,sz*0.7)];
        [p moveToPoint:CGPointMake(sz*0.1,sz*0.7)];[p addLineToPoint:CGPointMake(sz*0.35,sz*0.7)];[p addLineToPoint:CGPointMake(sz*0.7,sz*0.3)];[p addLineToPoint:CGPointMake(sz*0.9,sz*0.3)];[p stroke];
    } else { // repeat
        [p moveToPoint:CGPointMake(sz*0.25,sz*0.3)];[p addLineToPoint:CGPointMake(sz*0.75,sz*0.3)];[p addLineToPoint:CGPointMake(sz*0.75,sz*0.6)];
        [p moveToPoint:CGPointMake(sz*0.75,sz*0.7)];[p addLineToPoint:CGPointMake(sz*0.25,sz*0.7)];[p addLineToPoint:CGPointMake(sz*0.25,sz*0.4)];[p stroke];
    }
    iv.image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [_col addSubview:iv];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate]; _timer=nil;
}

static NSString* fmtTime(double s){ if(s<0)s=0; int m=(int)s/60, sec=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,sec]; }

- (void)tick {
    double cur=[MMAudio currentTime], dur=[MMAudio duration];
    double frac=(dur>0)?(cur/dur):0; if(frac<0)frac=0; if(frac>1)frac=1;
    CGFloat w=_trackW*frac;
    [self placeProgress:w];
    _t1.text=fmtTime(cur);
    _t2.text=[NSString stringWithFormat:@"-%@",fmtTime(dur>cur?dur-cur:0)];
    // Laden -> Spinner statt Play/Pause; sonst Icon mit echtem Zustand synchronisieren
    UIView*icon=[_playBtn viewWithTag:7];
    if([MMSpotify isLoading]){
        if(!_spinner.isAnimating)[_spinner startAnimating];
        icon.hidden=YES;
        // Anzeige des alten Tracks zurücksetzen
        [self placeProgress:0];
        _t1.text=@"0:00"; _t2.text=@"-0:00";
    } else {
        [_spinner stopAnimating]; icon.hidden=NO;
        BOOL p=[MMAudio isPlaying];
        if(p!=_playing){ _playing=p; [self drawPlayPause]; }
    }
}

- (void)prevTrack { [[MMRootController shared] playPrev]; }
- (void)nextTrack { [[MMRootController shared] playNext]; }

- (void)handleSeek:(UIGestureRecognizer *)g {
    double dur=[MMAudio duration]; if(dur<=0) return;
    CGPoint p=[g locationInView:_col];
    double frac=(p.x-_trackX)/_trackW; if(frac<0)frac=0; if(frac>1)frac=1;
    CGFloat w=_trackW*frac;
    [self placeProgress:w];
    _t1.text=fmtTime(frac*dur); _t2.text=[NSString stringWithFormat:@"-%@",fmtTime(dur-frac*dur)];
    BOOL tap=[g isKindOfClass:[UITapGestureRecognizer class]];
    if(tap || g.state==UIGestureRecognizerStateEnded) [MMAudio seekTo:frac*dur];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

// ---- Runterziehen am Schließen-Pfeil: Player folgt dem Finger; weit genug oder schnell = schließen, sonst zurückfedern ----
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if(![g isKindOfClass:[UIPanGestureRecognizer class]] || g.view!=self.view) return YES;
    if(MMIsPad() && self.interfaceOrientation!=UIInterfaceOrientationPortrait) return NO;   // iPad gedreht: Schließen über den Pfeil oben
    CGPoint p=[g locationInView:self.view], v=[(UIPanGestureRecognizer*)g velocityInView:self.view];
    return p.y<_progY-16 && v.y>0 && v.y>fabs(v.x);   // nur oberhalb der Leiste und nach unten
}
- (void)dragDown:(UIPanGestureRecognizer *)g {
    UIWindow*win=self.view.window; if(!win) return;
    CGFloat H=win.bounds.size.height, dy=MAX(0,[g translationInView:win].y);
    UIView*app=[MMRootController shared].view;
    if(g.state==UIGestureRecognizerStateBegan){
        // Die App selbst darunterlegen (kostet nichts); ein Bild davon zu zeichnen dauerte auf dem 3GS ~0,2 s und ließ den Finger hängen
        if(!app.window){ [win insertSubview:app belowSubview:self.view]; _appBehind=YES; }
    } else if(g.state==UIGestureRecognizerStateChanged){
        self.view.transform=CGAffineTransformMakeTranslation(0,dy);
    } else {
        BOOL dismiss=(g.state==UIGestureRecognizerStateEnded) && (dy>H*0.25 || [g velocityInView:win].y>700);
        BOOL put=_appBehind; _appBehind=NO;
        [UIView animateWithDuration:0.22 animations:^{ self.view.transform=dismiss?CGAffineTransformMakeTranslation(0,H):CGAffineTransformIdentity; }
                         completion:^(BOOL f){
            if(dismiss) [self dismissViewControllerAnimated:NO completion:nil];   // die App liegt schon richtig im Fenster
            else if(put) [app removeFromSuperview];                              // zurückgefedert: wieder wie vor dem Ziehen
        }];
    }
}
@end
