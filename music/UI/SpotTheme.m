#import "SpotTheme.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
static UIColor* rgb(int r,int g,int b){ return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
static BOOL gIOS6;
static void drawGradient(CGRect r, const CGFloat *comps, const CGFloat *locs, size_t n){
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB(); CGGradientRef g=CGGradientCreateWithColorComponents(cs,comps,locs,n);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(),g,CGPointMake(0,r.origin.y),CGPointMake(0,CGRectGetMaxY(r)),0);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
}
// ---- Navigationsleiste (iOS 6): echte UINavigationBar über dem selbst gebauten Seitenkopf ----
@interface MMNavHelper : NSObject <UINavigationBarDelegate>
@property (nonatomic,weak) UIButton *back; @property (nonatomic,weak) UILabel *title; @property (nonatomic,strong) UINavigationItem *item;
@end
@implementation MMNavHelper
- (BOOL)navigationBar:(UINavigationBar *)nb shouldPopItem:(UINavigationItem *)it { [self.back sendActionsForControlEvents:UIControlEventTouchUpInside]; return NO; }   // die Seite schließt sich selbst
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)o change:(NSDictionary *)ch context:(void *)ctx { self.item.title=self.title.text; }   // Titel kommt manchmal erst später (Artist)
- (void)dealloc { [_title removeObserver:self forKeyPath:@"text"]; }
@end

// iOS 6: Zellen in markierten Listen (skinTable) bekommen beim ersten Layout grüne Auswahl und weiße Schrift beim Antippen
@interface UITableViewCell (MMSkin) @end
@implementation UITableViewCell (MMSkin)
- (void)mm_layoutSubviews {
    [self mm_layoutSubviews];   // Original (vertauscht)
    UIView*t=self.superview; while(t && ![t isKindOfClass:[UITableView class]]) t=t.superview;
    if(t && objc_getAssociatedObject(t,"mmSkin") && [SpotTheme ios6]) [SpotTheme skinCell:self];
}
@end
// Cover mit Spiegelbild: jedes Bild, das MMCovers (auch später) setzt, geht ans Spiegelbild weiter
@interface MMMirrorImageView : UIImageView
@property (nonatomic,weak) UIImageView *mirror;
@end
@implementation MMMirrorImageView
- (void)setImage:(UIImage *)im { [super setImage:im]; self.mirror.image=im; }
@end
@interface SpotTheme (Private)
+ (UIImage *)ios6BackButtonImage;
@end
@implementation SpotTheme
+ (void)initialize { if(self==[SpotTheme class]) [self applySkin]; }
// Gespeicherten Skin übernehmen (Start und Wechsel ohne Neustart); der Zellen-Hook wird einmal installiert und prüft selbst
+ (void)applySkin {
    gIOS6=[[self skin] isEqualToString:@"ios6"];
    static BOOL hooked; if(gIOS6 && !hooked){ hooked=YES;
        method_exchangeImplementations(class_getInstanceMethod([UITableViewCell class],@selector(layoutSubviews)),class_getInstanceMethod([UITableViewCell class],@selector(mm_layoutSubviews))); }
}
+ (NSString *)skin { NSString*s=[[NSUserDefaults standardUserDefaults] stringForKey:@"skin"]; return s.length?s:@"spotify"; }
+ (void)setSkin:(NSString *)skin { [[NSUserDefaults standardUserDefaults] setObject:skin forKey:@"skin"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
+ (BOOL)ios6 { return gIOS6; }
// iOS 6: weißer Inhalt, schwarze Schrift, Akzent im Spotify-Grün (Leisten grün getönt)
+ (UIColor *)bg    { return gIOS6?[UIColor whiteColor]:rgb(18,18,18); }
+ (UIColor *)bar   { return gIOS6?rgb(20,20,20):rgb(24,24,24); }
+ (UIColor *)card  { return gIOS6?[UIColor whiteColor]:rgb(40,40,40); }
+ (UIColor *)green { return gIOS6?rgb(30,150,64):rgb(29,185,84); }
+ (UIColor *)ink   { return gIOS6?[UIColor colorWithWhite:0.20 alpha:1]:[UIColor whiteColor]; }   // iOS 6: ein Dunkelgrau für alle Texte (wie die Bibliothekszeilen)
+ (UIColor *)muted { return gIOS6?[UIColor colorWithWhite:0.40 alpha:1]:rgb(179,179,179); }   // iOS 6: ein Grau für alle Zweitzeilen
+ (UIColor *)faint { return gIOS6?rgb(150,150,150):rgb(114,114,114); }
+ (UIColor *)line  { return gIOS6?rgb(224,224,224):rgb(42,42,42); }
+ (UIColor *)chromeInk { return [UIColor whiteColor]; }
+ (UIColor *)headerInk { return gIOS6?[UIColor whiteColor]:[self ink]; }
+ (UIColor *)barTint { return rgb(56,100,68); }   // gedecktes Waldgrün: iOS hellt die Leisten mit Glanz noch auf
// iOS 6: Nadelstreifen. groupTableViewBackgroundColor ist unter iOS 6 außerhalb von Tabellen durchsichtig -> selbst zeichnen
// (7 px: 5 x RGB 197,204,212 und 2 x 203,210,216, wie das Original)
+ (UIColor *)pageBackground {
    if(!gIOS6) return [self bg];
    static UIColor*c; if(c) return c;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(7,1),YES,1);
    [rgb(197,204,212) setFill]; UIRectFill(CGRectMake(0,0,5,1)); [rgb(203,210,216) setFill]; UIRectFill(CGRectMake(5,0,2,1));
    c=[UIColor colorWithPatternImage:UIGraphicsGetImageFromCurrentImageContext()]; UIGraphicsEndImageContext(); return c;
}
+ (UIColor *)groupedHeaderInk { return rgb(76,86,108); }
+ (UIImage *)toolbarImage:(CGFloat)h {
    static NSMutableDictionary*memo; if(!memo) memo=[NSMutableDictionary dictionary]; UIImage*m=memo[@(h)]; if(m) return m;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,h),YES,0);
    CGFloat c[]={0.27,0.27,0.27,1, 0.13,0.13,0.13,1, 0.03,0.03,0.03,1, 0,0,0,1}, l[]={0,0.5,0.5,1};   // Glanzkante in der Mitte
    drawGradient(CGRectMake(0,0,1,h),c,l,4);
    [[UIColor colorWithWhite:0.38 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,1,1));
    m=[UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:0 topCapHeight:0]; UIGraphicsEndImageContext();
    memo[@(h)]=m; return m;
}
+ (UIImage *)tabHighlightImage {
    static UIImage*m; if(m) return m;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(13,13),NO,0);
    [[UIColor colorWithWhite:1 alpha:0.14] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,13,13) cornerRadius:4] fill];
    m=[UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:6 topCapHeight:6]; UIGraphicsEndImageContext(); return m;
}
// Umrandeter Leistenknopf in der Leistenfarbe (für eigene Knöpfe in der Navigationsleiste), 30 hoch, dehnbar
+ (UIImage *)barButtonImage {
    static UIImage*m; if(m) return m;
    CGFloat W=16, H=30; UIGraphicsBeginImageContextWithOptions(CGSizeMake(W,H),NO,0);
    UIBezierPath*p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,W-1,H-2) cornerRadius:5];
    [[UIColor colorWithWhite:1 alpha:0.35] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,1.5,W-1,H-2) cornerRadius:5] fill];   // Lichtkante unten
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [p addClip];
    CGFloat r,g,bl,a; [[self barTint] getRed:&r green:&g blue:&bl alpha:&a];   // aus der Leistenfarbe, damit Knöpfe und Leiste zusammenpassen
    CGFloat c[]={MIN(1,r*1.35),MIN(1,g*1.35),MIN(1,bl*1.35),1, r*0.95,g*0.95,bl*0.95,1, r*0.8,g*0.8,bl*0.8,1}, l[]={0,0.5,1}; drawGradient(CGRectMake(0,0,W,H),c,l,3);
    CGContextRestoreGState(cx);
    [[UIColor colorWithRed:r*0.3 green:g*0.3 blue:bl*0.3 alpha:1] setStroke]; p.lineWidth=1; [p stroke];
    m=[UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(0,7,0,7)]; UIGraphicsEndImageContext(); return m;
}
// Glänzende, abgerundete Fläche in einer Farbe (Browse-Kacheln, Knöpfe)
+ (UIImage *)glossyImage:(UIColor *)color radius:(CGFloat)r {   // dehnbar: Mitte genau 1 pt (iOS 5/6 kacheln die Mitte; 2 pt gaben Streifen)
    return [[self glossyImage:color radius:r size:CGSizeMake(r*2+3,r*2+3)] resizableImageWithCapInsets:UIEdgeInsetsMake(r+1,r+1,r+1,r+1)];
}
+ (UIImage *)glossyImage:(UIColor *)color radius:(CGFloat)r size:(CGSize)sz {   // in voller Größe: Glanz über die ganze Höhe
    CGFloat W=sz.width, H=sz.height; UIGraphicsBeginImageContextWithOptions(sz,NO,0);
    UIBezierPath*p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,W,H) cornerRadius:r];
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [p addClip];
    [color setFill]; UIRectFill(CGRectMake(0,0,W,H));
    CGFloat c[]={1,1,1,0.42, 1,1,1,0.12, 1,1,1,0, 0,0,0,0.12}, l[]={0,0.5,0.5,1}; drawGradient(CGRectMake(0,0,W,H),c,l,4);
    CGContextRestoreGState(cx);
    [[UIColor colorWithWhite:0 alpha:0.25] setStroke]; p.lineWidth=1; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,W-1,H-1) cornerRadius:r] stroke];
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
// Abschnittskopf einer einfachen iOS-6-Liste: grau-blauer Verlauf, weiße Schrift mit Schatten (22 hoch)
+ (UIView *)plainSectionHeader:(NSString *)title width:(CGFloat)w {
    static UIImage*band; if(!band){ UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,22),YES,0);
        CGFloat c[]={0.56,0.62,0.67,1, 0.72,0.76,0.79,1}, l[]={0,1}; drawGradient(CGRectMake(0,0,1,22),c,l,2);
        [[UIColor colorWithRed:0.44 green:0.50 blue:0.55 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,1,1));
        [[UIColor colorWithRed:0.60 green:0.65 blue:0.69 alpha:1] setFill]; UIRectFill(CGRectMake(0,21,1,1));
        band=[UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:0 topCapHeight:0]; UIGraphicsEndImageContext(); }
    UIImageView*v=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,w,22)]; v.image=band; v.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(12,0,w-24,22)]; l.text=title; l.font=[UIFont boldSystemFontOfSize:17];
    l.textColor=[UIColor whiteColor]; l.shadowColor=[UIColor colorWithWhite:0 alpha:0.44]; l.shadowOffset=CGSizeMake(0,1); l.backgroundColor=[UIColor clearColor];
    l.autoresizingMask=UIViewAutoresizingFlexibleWidth; [v addSubview:l]; return v;
}
// Überschrift auf Nadelstreifen (gruppierte Liste): grau-blau, fett, weißer Schatten
+ (void)styleGroupedHeader:(UILabel *)l {
    l.textColor=[self groupedHeaderInk]; l.shadowColor=[UIColor colorWithWhite:1 alpha:0.8]; l.shadowOffset=CGSizeMake(0,1); l.backgroundColor=[UIColor clearColor];
    l.font=[UIFont boldSystemFontOfSize:17];
}
// Grüne Auswahl beim Antippen einer Zeile (iOS 6 nimmt Blau; hier im Spotify-Grün)
+ (UIView *)selectionView {
    static UIImage*m; if(!m){ UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,44),YES,0);   // eingedrückt: dunkler als die Zeile, Schatten oben, Schrift bleibt lesbar
        CGFloat c[]={0.70,0.70,0.72,1, 0.80,0.80,0.82,1, 0.78,0.78,0.80,1}, l[]={0,0.18,1}; drawGradient(CGRectMake(0,0,1,44),c,l,3);
        [[UIColor colorWithWhite:0.58 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,1,1));
        m=[UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:0 topCapHeight:0]; UIGraphicsEndImageContext(); }
    UIImageView*v=[[UIImageView alloc] initWithImage:m]; v.contentMode=UIViewContentModeScaleToFill; v.tag=7347; return v;
}
+ (void)skinTable:(UITableView *)t {
    if(!gIOS6) return;
    t.backgroundColor=[self rowColor]; t.separatorStyle=UITableViewCellSeparatorStyleSingleLine; t.separatorColor=rgb(198,199,201);   // wie die Listen der Musik-App
    objc_setAssociatedObject(t,"mmSkin",@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
+ (UIView *)groupedSelectionFirst:(BOOL)first last:(BOOL)last {
    static UIImage*memo[4]; int k=(first?1:0)|(last?2:0);
    if(!memo[k]){ CGFloat r=9, H=44; UIGraphicsBeginImageContextWithOptions(CGSizeMake(2*r+2,H),NO,0);
        UIRectCorner rc=(first?UIRectCornerTopLeft|UIRectCornerTopRight:0)|(last?UIRectCornerBottomLeft|UIRectCornerBottomRight:0);
        UIBezierPath*p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,2*r+2,H) byRoundingCorners:rc cornerRadii:CGSizeMake(r,r)];
        CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [p addClip];
        CGFloat c[]={0.27,0.75,0.38,1, 0.10,0.55,0.22,1}, l[]={0,1}; drawGradient(CGRectMake(0,0,2*r+2,H),c,l,2); CGContextRestoreGState(cx);
        memo[k]=[UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(r,r,r,r)]; UIGraphicsEndImageContext(); }
    return [[UIImageView alloc] initWithImage:memo[k]];
}
+ (void)skinCell:(UITableViewCell *)c {
    if(!gIOS6) return;
    if(!c.backgroundView){   // hellgraue Zeile mit weißer Lichtkante oben (unten zeichnet die Tabelle die graue Linie)
        UIView*bg=[[UIView alloc] initWithFrame:c.bounds]; bg.backgroundColor=[self rowColor];
        UIView*hi=[[UIView alloc] initWithFrame:CGRectMake(0,0,c.bounds.size.width,1)]; hi.backgroundColor=[UIColor whiteColor]; hi.autoresizingMask=UIViewAutoresizingFlexibleWidth; [bg addSubview:hi];
        c.backgroundView=bg; }
    // nur einmal und gleich in Zellengröße: hier läuft es nach dem Layout der Zelle, ein neues 1-pt-Bild blieb sonst 1 pt breit (unsichtbar)
    if(c.selectedBackgroundView.tag!=7347){ UIView*sv=[self selectionView]; sv.frame=c.bounds; sv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; c.selectedBackgroundView=sv; }
    c.selectionStyle=UITableViewCellSelectionStyleBlue;
    UIColor*hl=[UIColor colorWithWhite:0.38 alpha:1];   // beim Antippen grau statt weiß (weiß verschwand kurz auf hellem Grund)
    c.textLabel.highlightedTextColor=hl; c.detailTextLabel.highlightedTextColor=hl;
    NSMutableArray*q=[NSMutableArray arrayWithObject:c.contentView];   // eigene Beschriftungen in der Zelle: beim Antippen weiß
    c.contentView.backgroundColor=[UIColor clearColor];   // sonst verdeckt ein weißer Hintergrund das Grün und die Schrift wird weiß auf weiß
    while(q.count){ UIView*v=q.lastObject; [q removeLastObject];
        if([v isKindOfClass:[UILabel class]]){ ((UILabel*)v).highlightedTextColor=hl; v.backgroundColor=[UIColor clearColor]; }
        [q addObjectsFromArray:v.subviews]; }
}
// Rundes Schattenbild für Cover auf hellem Grund (Cover selbst bleiben eckig)
+ (void)shadowCover:(UIView *)v {
    if(!gIOS6) return;
    v.layer.shadowColor=[UIColor blackColor].CGColor; v.layer.shadowOpacity=0.35; v.layer.shadowRadius=2; v.layer.shadowOffset=CGSizeMake(0,1);
    v.layer.shadowPath=[UIBezierPath bezierPathWithRect:v.bounds].CGPath;
}
+ (void)shadowBehind:(UIView *)v {
    if(!gIOS6 || !v.superview) return;
    UIView*sh=[[UIView alloc] initWithFrame:v.frame]; sh.backgroundColor=[UIColor whiteColor]; sh.autoresizingMask=v.autoresizingMask;
    sh.layer.cornerRadius=v.layer.cornerRadius; sh.layer.shadowColor=[UIColor blackColor].CGColor; sh.layer.shadowOpacity=0.45; sh.layer.shadowRadius=2.5; sh.layer.shadowOffset=CGSizeMake(0,1.5);
    sh.layer.shadowPath=(v.layer.cornerRadius>0?[UIBezierPath bezierPathWithRoundedRect:sh.bounds cornerRadius:v.layer.cornerRadius]:[UIBezierPath bezierPathWithRect:sh.bounds]).CGPath;
    [v.superview insertSubview:sh belowSubview:v];
}
+ (void)groupedTile:(UIView *)t {
    if(!gIOS6) return;
    t.backgroundColor=[UIColor whiteColor]; t.layer.cornerRadius=8; t.clipsToBounds=YES;
    t.layer.borderWidth=1; t.layer.borderColor=[UIColor colorWithWhite:0.67 alpha:1].CGColor;
}
+ (void)styleSectionTitle:(UILabel *)l { if(gIOS6) [self styleGroupedHeader:l]; }
+ (UIImage *)shelfImage:(CGFloat)H {   // in voller Höhe: dehnbare Bilder kacheln unter iOS 5/6 die Mitte (gäbe Streifen)
    static NSMutableDictionary*memo; if(!memo) memo=[NSMutableDictionary dictionary]; UIImage*m=memo[@((int)H)]; if(m) return m;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,H),YES,0);
    CGFloat c[]={0.985,0.985,0.99,1, 0.93,0.935,0.945,1, 0.885,0.89,0.905,1}, l[]={0,0.6,1}; drawGradient(CGRectMake(0,0,1,H),c,l,3);
    [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0,0,1,1));                                   // Lichtkante oben
    [[UIColor colorWithWhite:0.70 alpha:1] setFill]; UIRectFill(CGRectMake(0,H-1,1,1));                 // dunkle Kante unten
    m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); memo[@((int)H)]=m; return m;
}
+ (UIColor *)shelfColor { return rgb(233,235,239); }
+ (UIImage *)glyph:(UIImage *)mask color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(mask.size,NO,0); CGContextRef cx=UIGraphicsGetCurrentContext();
    [mask drawAtPoint:CGPointZero]; CGContextSetBlendMode(cx,kCGBlendModeSourceIn); [color setFill]; CGContextFillRect(cx,CGRectMake(0,0,mask.size.width,mask.size.height));
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
+ (UIColor *)sourceListColor { return rgb(224,228,233); }
+ (UIImage *)sourceSelectionImage:(CGSize)s {   // wie die Tab-Leiste (Moss), oben eine dunkle Kante
    CGFloat r=70/255.0, g=130/255.0, b=84/255.0; UIGraphicsBeginImageContextWithOptions(s,YES,0);
    #define W_(k) r+(1-r)*k,g+(1-g)*k,b+(1-b)*k,1
    CGFloat c[]={W_(0.20), W_(0.04)}, l[]={0,1};
    #undef W_
    drawGradient(CGRectMake(0,0,s.width,s.height),c,l,2);
    [[UIColor colorWithRed:r*0.6 green:g*0.6 blue:b*0.6 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,s.width,1));
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
+ (void)albumHeadBackground:(UIView *)h {
    CGFloat HH=h.bounds.size.height, W=h.bounds.size.width; UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,HH),YES,0);   // in voller Höhe (dehnbare Bilder kacheln unter iOS 5/6)
    CGFloat gc[]={0.60,0.60,0.60,1, 0.92,0.92,0.92,1}, gl[]={0,1}; drawGradient(CGRectMake(0,0,1,HH),gc,gl,2);
    UIImageView*bgv=[[UIImageView alloc] initWithFrame:h.bounds]; bgv.image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    bgv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [h insertSubview:bgv atIndex:0];
    UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(0,HH-1,W,1)]; ln.backgroundColor=[UIColor colorWithWhite:0.74 alpha:1]; ln.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin; [h addSubview:ln];
}
+ (UIColor *)rowColor { return rgb(233,234,236); }   // Zeilen der Musik-App
// In voller Größe gezeichnet (dehnbare Bilder kacheln unter iOS 5/6 die Mitte); je Größe einmal
+ (UIImage *)plateImage:(CGSize)s pressed:(BOOL)p {
    static NSMutableDictionary*memo; if(!memo) memo=[NSMutableDictionary dictionary];
    NSString*k=[NSString stringWithFormat:@"%.0fx%.0f%d",s.width,s.height,p]; UIImage*m=memo[k]; if(m) return m;
    CGFloat W=s.width, H=s.height, r=6; UIGraphicsBeginImageContextWithOptions(CGSizeMake(W,H+1),NO,0);
    [[UIColor colorWithWhite:1 alpha:0.75] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,1,W,H) cornerRadius:r] fill];   // Lichtkante unten
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,W,H) cornerRadius:r] addClip];
    CGFloat n[]={1,1,1,1, 0.985,0.985,0.99,1, 0.95,0.955,0.96,1}, d[]={0.80,0.81,0.83,1, 0.75,0.76,0.78,1, 0.71,0.72,0.74,1}, l[]={0,0.5,1};
    drawGradient(CGRectMake(0,0,W,H),p?d:n,l,3); CGContextRestoreGState(cx);
    UIBezierPath*b=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,W-1,H-1) cornerRadius:r]; b.lineWidth=1;
    [[UIColor colorWithWhite:0.58 alpha:1] setStroke]; [b stroke];
    m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); memo[k]=m; return m;
}
// Spiegelbild: gespiegeltes Cover unter dem Cover, darüber ein Verlauf in Regalfarbe, der es nach unten ausblendet
+ (UIImageView *)shelfCover:(CGRect)f in:(UIView *)tile reflection:(CGFloat)R { return [self shelfCover:f in:tile reflection:R fade:nil]; }
+ (UIImageView *)shelfCover:(CGRect)f in:(UIView *)tile reflection:(CGFloat)R fade:(UIColor *)ground {
    UIImageView*cov=gIOS6&&R>0?[[MMMirrorImageView alloc] initWithFrame:f]:[[UIImageView alloc] initWithFrame:f];
    cov.contentMode=UIViewContentModeScaleAspectFill; cov.clipsToBounds=YES; [tile addSubview:cov];
    if(!gIOS6 || R<=0) return cov;
    UIView*box=[[UIView alloc] initWithFrame:CGRectMake(f.origin.x,CGRectGetMaxY(f)+1,f.size.width,R)]; box.clipsToBounds=YES; box.userInteractionEnabled=NO;
    UIImageView*mi=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,f.size.width,f.size.height)]; mi.contentMode=UIViewContentModeScaleAspectFill; mi.clipsToBounds=YES;
    mi.transform=CGAffineTransformMakeScale(1,-1); [box addSubview:mi]; ((MMMirrorImageView*)cov).mirror=mi;
    CAGradientLayer*g=[CAGradientLayer layer]; g.frame=box.bounds; UIColor*sc=ground?:[self shelfColor];
    g.colors=@[(id)[sc colorWithAlphaComponent:0.42].CGColor,(id)sc.CGColor]; [box.layer addSublayer:g];
    [tile insertSubview:box belowSubview:cov]; return cov;
}
// Nur die Form zählt: UITabBar macht daraus grau (aus) oder den Glanz der Auswahl
+ (UIImage *)tabGlyph:(NSString *)name {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30,30),NO,0); CGContextRef cx=UIGraphicsGetCurrentContext(); [[UIColor blackColor] setFill]; [[UIColor blackColor] setStroke];
    if([name isEqualToString:@"home"]){   // Haus mit Tür
        UIBezierPath*p=[UIBezierPath bezierPath]; CGPoint pts[]={{15,3},{28,15},{24.5,15},{24.5,27},{18,27},{18,19},{12,19},{12,27},{5.5,27},{5.5,15},{2,15}};
        [p moveToPoint:pts[0]]; for(int i=1;i<11;i++) [p addLineToPoint:pts[i]]; [p closePath]; [p fill];
    } else if([name isEqualToString:@"browse"]){   // vier Kacheln
        for(int i=0;i<2;i++) for(int j=0;j<2;j++) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.5+j*12.5,3.5+i*12.5,10.5,10.5) cornerRadius:2] fill];
    } else if([name isEqualToString:@"search"]){   // Lupe
        UIBezierPath*r=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4,3,16,16)]; r.lineWidth=3.6; [r stroke];
        UIBezierPath*h=[UIBezierPath bezierPath]; h.lineWidth=5; h.lineCapStyle=kCGLineCapRound; [h moveToPoint:CGPointMake(18.5,17.5)]; [h addLineToPoint:CGPointMake(25.5,24.5)]; [h stroke];
    } else {   // Bibliothek: zwei Bücher und ein schräges
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4,4,5.5,23) cornerRadius:1] fill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(11.5,4,5.5,23) cornerRadius:1] fill];
        CGContextSaveGState(cx); CGContextTranslateCTM(cx,22,15.5); CGContextRotateCTM(cx,0.30); [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-2.75,-11,5.5,22) cornerRadius:1] fill]; CGContextRestoreGState(cx);
        UIRectFill(CGRectMake(3,27,25,1.5));
    }
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
// Tab-Leiste aus der Farbe der Kopfleiste: oben hell, Glanzkante in der Mitte, unten die Leistenfarbe (wie die getönte Navigationsleiste)
static int gTabVariant=3;   // gewählt: 3 (Moss). Debug "tabbar <0-4>" zeigt die anderen Vorschläge (4 = klassisch schwarz)
+ (void)setTabVariant:(int)v { gTabVariant=v; }
+ (UIImage *)tabBarImage:(CGSize)s {
    CGFloat r,g,b,a; [[self barTint] getRed:&r green:&g blue:&b alpha:&a];
    // Vorschläge: Grundfarbe und Weißanteil oben/unten
    static const CGFloat V[][5]={{56,100,68,0.24,0.10},{36,112,58,0.18,0.02},{24,128,60,0.14,0.00},{70,130,84,0.20,0.06},{0,0,0,0,0}};
    int vi=gTabVariant>=0&&gTabVariant<5?gTabVariant:0; CGFloat k0=V[vi][3], k1=V[vi][4];
    if(vi) { r=V[vi][0]/255.0; g=V[vi][1]/255.0; b=V[vi][2]/255.0; }
    if(vi==4) return [self toolbarImage:s.height];   // klassisch schwarz
    UIGraphicsBeginImageContextWithOptions(s,YES,0);
    // einfarbig wie die untere Hälfte der Kopfleiste: Grundfarbe mit etwas Weiß oben, weniger unten
    #define W_(k) r+(1-r)*k,g+(1-g)*k,b+(1-b)*k,1
    CGFloat c[]={W_(k0), W_(k1)}, l[]={0,1};
    #undef W_
    drawGradient(CGRectMake(0,0,s.width,s.height),c,l,2);
    [[UIColor colorWithRed:r*0.45 green:g*0.45 blue:b*0.45 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,s.width,1));          // dunkle Kante oben
    [[UIColor colorWithWhite:1 alpha:0.30] setFill]; UIRectFill(CGRectMake(0,1,s.width,1));                                       // Lichtkante
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
+ (UIImage *)tabSelectionImage:(CGSize)s {
    UIGraphicsBeginImageContextWithOptions(s,NO,0);
    UIBezierPath*p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,3,s.width-4,s.height-5) cornerRadius:4];
    [[UIColor colorWithWhite:1 alpha:0.22] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,4,s.width-4,s.height-5) cornerRadius:4] fill];   // Lichtkante unten
    [[UIColor colorWithWhite:0 alpha:0.28] setFill]; [p fill];
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
+ (UIImage *)tabGlyph:(NSString *)name selected:(BOOL)sel {
    UIImage*mask=[self tabGlyph:name]; CGSize S=mask.size;
    UIGraphicsBeginImageContextWithOptions(S,NO,0); CGContextRef cx=UIGraphicsGetCurrentContext();   // Form einfärben
    [mask drawAtPoint:CGPointZero]; CGContextSetBlendMode(cx,kCGBlendModeSourceIn);
    if(sel){ CGFloat c[]={1,1,1,1, 0.86,0.97,0.88,1, 0.62,0.90,0.68,1}, l[]={0,0.5,1}; drawGradient(CGRectMake(0,0,S.width,S.height),c,l,3); }
    else { [[UIColor colorWithRed:0.80 green:0.87 blue:0.82 alpha:1] setFill]; CGContextFillRect(cx,CGRectMake(0,0,S.width,S.height)); }   // UIRectFill malt immer deckend (ohne Mischmodus)
    UIImage*col=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    UIGraphicsBeginImageContextWithOptions(S,NO,0); cx=UIGraphicsGetCurrentContext();               // mit dunklem Schatten darüber (eingeprägt)
    CGContextSetShadowWithColor(cx,CGSizeMake(0,-1),sel?1.5:0,[UIColor colorWithWhite:0 alpha:sel?0.5:0.4].CGColor);
    [col drawAtPoint:CGPointZero];
    UIImage*m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return m;
}
+ (void)engrave:(UILabel *)l { if(!gIOS6) return; l.shadowColor=[UIColor colorWithWhite:1 alpha:0.85]; l.shadowOffset=CGSizeMake(0,1); l.backgroundColor=[UIColor clearColor]; }
+ (void)skinPage:(UIView *)page {
    if(!gIOS6 || !page || [page viewWithTag:7346]) return;
    CGFloat W=page.bounds.size.width;
    UIButton*back=nil; UILabel*title=nil; NSMutableArray*left=[NSMutableArray array], *right=[NSMutableArray array];
    for(UIView*v in page.subviews){
        if(v.frame.origin.y>=40 || v.frame.size.height>44 || v.hidden) continue;   // nur der Kopf
        if([v isKindOfClass:[UILabel class]]){ if(!title) title=(UILabel*)v; }
        else if([v isKindOfClass:[UIButton class]]){
            UIButton*b=(UIButton*)v;
            if([[b titleForState:UIControlStateNormal] isEqualToString:NSLocalizedString(@"Back",nil)]) back=b;
            else if(CGRectGetMidX(b.frame)<W/2) [left addObject:b]; else [right addObject:b];
        }
    }
    if(!title && !back && !left.count && !right.count) return;
    UINavigationBar*nb=[[UINavigationBar alloc] initWithFrame:CGRectMake(0,0,W,44)];
    nb.tintColor=[self barTint]; nb.tag=7346; nb.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    MMNavHelper*h=[MMNavHelper new]; h.back=back; h.title=title;
    UINavigationItem*it=[[UINavigationItem alloc] initWithTitle:title.text?:@""]; h.item=it;
    if(title){ [title addObserver:h forKeyPath:@"text" options:0 context:NULL]; title.hidden=YES; }
    // eigene Knöpfe (Download, Zahnrad …) als umrandete Leistenknöpfe; die Seite ändert ihre Bilder weiter selbst
    UIBarButtonItem*(^item)(UIButton*)=^UIBarButtonItem*(UIButton*b){
        [b setBackgroundImage:[self barButtonImage] forState:UIControlStateNormal];
        CGRect f=b.frame; f.size=CGSizeMake(MAX(36,MIN(f.size.width,44)),30);
        NSString*t=[b titleForState:UIControlStateNormal];
        if(t.length){   // Textknopf (z.B. Fertig): weiße fette Schrift mit Schatten, Breite nach Text
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [b setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
            b.titleLabel.shadowOffset=CGSizeMake(0,-1); b.titleLabel.font=[UIFont boldSystemFontOfSize:12]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentCenter;
            f.size.width=ceil([t sizeWithFont:b.titleLabel.font].width)+20; }
        b.frame=f;
        return [[UIBarButtonItem alloc] initWithCustomView:b];
    };
    if(right.count) it.rightBarButtonItem=item(right[0]);
    if(left.count && !back) it.leftBarButtonItem=item(left[0]);
    if(back){ back.hidden=YES; nb.delegate=h; [nb setItems:@[[[UINavigationItem alloc] initWithTitle:NSLocalizedString(@"Back",nil)],it] animated:NO]; }
    else [nb setItems:@[it] animated:NO];
    objc_setAssociatedObject(nb,"helper",h,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for(UIView*v in page.subviews){   // Seiten beginnen bei 46 (alter Kopf); die Leiste ist 44 hoch -> ohne weißen Streifen anschließen
        CGRect f=v.frame; if(f.origin.y>44 && f.origin.y<=49 && f.size.height>60){ f.size.height+=f.origin.y-44; f.origin.y=44; v.frame=f; } }
    [page addSubview:nb];
    for(UIView*v in [page.subviews copy]) if([v isKindOfClass:[UIActivityIndicatorView class]]){
        if(v.frame.origin.y<40){ ((UIActivityIndicatorView*)v).activityIndicatorViewStyle=UIActivityIndicatorViewStyleWhite; [page bringSubviewToFront:v]; }   // Kreisel im Kopf vor die Leiste
        else ((UIActivityIndicatorView*)v).activityIndicatorViewStyle=UIActivityIndicatorViewStyleGray; }   // auf hellem Grund grau
}
+ (UIFont *)h1  { return [UIFont boldSystemFontOfSize:22]; }
+ (UIFont *)h2  { return [UIFont boldSystemFontOfSize:17]; }
+ (UIFont *)body{ return [UIFont systemFontOfSize:15]; }
+ (UIFont *)sub { return [UIFont systemFontOfSize:13]; }
+ (UIFont *)tab { return [UIFont systemFontOfSize:10]; }

// Echtes Spotify-Logo: grüner Kreis + drei schwarze Schallwellen (nach oben gewölbt).
// Eigenes Zeichen der App: grüner Kreis mit Puls-Linie (kein Spotify-Logo – Markenrecht).
+ (UIImage *)logo:(CGFloat)s {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s,s),NO,0);
    [[self green] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,s,s)] fill];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=s*0.075; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    CGFloat y=s/2, pts[7][2]={{0.06,0},{0.33,0},{0.41,-0.18},{0.52,0.21},{0.6,-0.08},{0.65,0},{0.94,0}};
    [p moveToPoint:CGPointMake(s*pts[0][0],y)];
    for(int i=1;i<7;i++) [p addLineToPoint:CGPointMake(s*pts[i][0],y+s*pts[i][1])];
    [[UIColor colorWithRed:0.055 green:0.055 blue:0.063 alpha:1] setStroke]; [p stroke];
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
+ (void)spaced:(UILabel *)label text:(NSString *)text font:(UIFont *)font color:(UIColor *)color kern:(CGFloat)kern {
    if ([label respondsToSelector:@selector(setAttributedText:)]) {   // iOS 6; iOS 5: schlichter Text ohne Laufweite
        MM_IOS6_BEGIN
        label.attributedText = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{NSKernAttributeName:@(kern), NSFontAttributeName:font, NSForegroundColorAttributeName:color}];
        MM_IOS6_END
    } else { label.text = text; label.font = font; label.textColor = color; }
}
+ (UIImage *)ios6BackButtonImage {
    static UIImage*m; if(m) return m;
    CGFloat W=40, H=30, a=10;   // Pfeilspitze links, abgerundet rechts
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(W,H),NO,0);
    UIBezierPath*p=[UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(1,H/2)]; [p addLineToPoint:CGPointMake(a+1,1.5)]; [p addLineToPoint:CGPointMake(W-6,1.5)];
    [p addQuadCurveToPoint:CGPointMake(W-1,6.5) controlPoint:CGPointMake(W-1,1.5)]; [p addLineToPoint:CGPointMake(W-1,H-6.5)];
    [p addQuadCurveToPoint:CGPointMake(W-6,H-1.5) controlPoint:CGPointMake(W-1,H-1.5)]; [p addLineToPoint:CGPointMake(a+1,H-1.5)]; [p closePath];
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [p addClip];
    CGFloat c[]={0.56,0.64,0.75,1, 0.36,0.46,0.60,1, 0.29,0.39,0.54,1}, l[]={0,0.5,1}; drawGradient(CGRectMake(0,0,W,H),c,l,3);
    CGContextRestoreGState(cx);
    [[UIColor colorWithRed:0.20 green:0.27 blue:0.38 alpha:1] setStroke]; p.lineWidth=1; [p stroke];
    m=[UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(0,a+4,0,8)]; UIGraphicsEndImageContext(); return m;
}
+ (void)styleBackButton:(UIButton *)b {
    if(gIOS6){
        [b setImage:nil forState:UIControlStateNormal];
        [b setBackgroundImage:[self ios6BackButtonImage] forState:UIControlStateNormal];
        [b setTitle:NSLocalizedString(@"Back",nil) forState:UIControlStateNormal]; [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal]; b.titleLabel.shadowOffset=CGSizeMake(0,-1);
        b.titleLabel.font=[UIFont boldSystemFontOfSize:12]; b.titleEdgeInsets=UIEdgeInsetsMake(0,6,0,0);
        b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentCenter;
        CGSize ts=[[b titleForState:UIControlStateNormal] sizeWithFont:b.titleLabel.font];   // Breite nach Text wie bei iOS
        CGRect f=b.frame; f.size=CGSizeMake(ceil(ts.width)+26,30); f.origin.y+= (34-30)/2; b.frame=f; return;
    }
    UIImage*img;   // je Skin andere Farbe -> nicht zwischenspeichern
    { UIGraphicsBeginImageContextWithOptions(CGSizeMake(12,20),NO,0); [[self ink] setStroke];
        UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2.4; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
        [p moveToPoint:CGPointMake(9.5,2.5)]; [p addLineToPoint:CGPointMake(2.5,10)]; [p addLineToPoint:CGPointMake(9.5,17.5)]; [p stroke];
        img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); }
    [b setImage:img forState:UIControlStateNormal];
    [b setTitle:NSLocalizedString(@"Back",nil) forState:UIControlStateNormal]; [b setTitleColor:[self ink] forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:15]; b.titleEdgeInsets=UIEdgeInsetsMake(0,6,0,0);
    b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
}
+ (UIImage *)downloadedIcon:(CGFloat)d {
    static NSMutableDictionary*memo; if(!memo) memo=[NSMutableDictionary dictionary];
    id key=@(gIOS6?-d:d); UIImage*m=memo[key]; if(m) return m;   // je Skin eigener Eintrag (Haken weiß bzw. schwarz)
    CGFloat k=d/26.0;   // gezeichnet im 26er-Raster wie der Knopf oben rechts
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(d,d),NO,0);
    [[self green] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1*k,1*k,24*k,24*k)] fill];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=MAX(1.5,2*k); p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    [(gIOS6?[UIColor whiteColor]:[UIColor blackColor]) setStroke];   // iOS 6: weißer Haken, sonst schwarz wie bei Spotify
    [p moveToPoint:CGPointMake(7.5*k,13.5*k)]; [p addLineToPoint:CGPointMake(11.5*k,17.5*k)]; [p addLineToPoint:CGPointMake(18.5*k,9*k)]; [p stroke];
    m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); memo[key]=m; return m;
}
+ (UIImage *)downloadsCover:(CGFloat)S {
    static NSMutableDictionary*memo; if(!memo) memo=[NSMutableDictionary dictionary];
    UIImage*m=memo[@(S)]; if(m) return m;
    CGFloat k=S/48.0; UIGraphicsBeginImageContextWithOptions(CGSizeMake(S,S),YES,0); CGContextRef cx=UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB(); CGFloat comps[]={0.16,0.80,0.42,1, 0.04,0.36,0.20,1};
    CGGradientRef g=CGGradientCreateWithColorComponents(cs,comps,NULL,2); CGContextDrawLinearGradient(cx,g,CGPointMake(0,0),CGPointMake(S,S),0);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
    [[UIColor whiteColor] setStroke]; UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=3*k; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    [p moveToPoint:CGPointMake(24*k,13*k)]; [p addLineToPoint:CGPointMake(24*k,32*k)]; [p moveToPoint:CGPointMake(16*k,25*k)]; [p addLineToPoint:CGPointMake(24*k,33*k)]; [p addLineToPoint:CGPointMake(32*k,25*k)];
    [p moveToPoint:CGPointMake(15*k,37*k)]; [p addLineToPoint:CGPointMake(33*k,37*k)]; [p stroke];
    m=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); memo[@(S)]=m; return m;
}
// Spotify-Symbol Zufall: zwei gekreuzte Pfeile; an = grün + Punkt darunter (44x44, Player und iPad-Leiste)
+ (UIImage *)shuffleIcon:(BOOL)on {
    CGFloat B=44, sz=22, o=11;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(B,B),NO,0);
    UIColor*col=on?(gIOS6?rgb(102,219,120):[SpotTheme green]):(gIOS6?[UIColor colorWithWhite:0.80 alpha:1]:[SpotTheme muted]); [col setStroke]; [col setFill];   // iOS 6: hell auf der schwarzen Leiste
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    #define P(x,y) CGPointMake(o+sz*(x),o+sz*(y))
    [p moveToPoint:P(0.05,0.25)]; [p addCurveToPoint:P(0.9,0.75) controlPoint1:P(0.5,0.25) controlPoint2:P(0.45,0.75)];
    [p moveToPoint:P(0.05,0.75)]; [p addCurveToPoint:P(0.9,0.25) controlPoint1:P(0.5,0.75) controlPoint2:P(0.45,0.25)];
    [p moveToPoint:P(0.74,0.1)];  [p addLineToPoint:P(0.92,0.25)]; [p addLineToPoint:P(0.74,0.4)];
    [p moveToPoint:P(0.74,0.6)];  [p addLineToPoint:P(0.92,0.75)]; [p addLineToPoint:P(0.74,0.9)];
    [p stroke];
    if(on) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(B/2-2,o+sz+5,4,4)] fill];
    #undef P
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
// Spotify-Symbol Wiederholen: Schleife mit Pfeil; an = grün + Punkt, "Titel wiederholen" (mode 2) zusätzlich mit kleiner 1
+ (UIImage *)repeatIcon:(NSInteger)mode {
    NSInteger m=mode; CGFloat B=44, sz=22, o=11;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(B,B),NO,0);
    UIColor*col=m?(gIOS6?rgb(102,219,120):[SpotTheme green]):(gIOS6?[UIColor colorWithWhite:0.80 alpha:1]:[SpotTheme muted]); [col setStroke]; [col setFill];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=2; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    #define P(x,y) CGPointMake(o+sz*(x),o+sz*(y))
    // oben: von links unten hoch, nach rechts, Pfeil nach rechts
    [p moveToPoint:P(0.08,0.56)]; [p addLineToPoint:P(0.08,0.42)]; [p addQuadCurveToPoint:P(0.25,0.25) controlPoint:P(0.08,0.25)];
    [p addLineToPoint:P(0.88,0.25)]; [p moveToPoint:P(0.74,0.12)]; [p addLineToPoint:P(0.88,0.25)]; [p addLineToPoint:P(0.74,0.38)];
    // unten: von rechts oben runter, nach links, Pfeil nach links
    [p moveToPoint:P(0.92,0.44)]; [p addLineToPoint:P(0.92,0.58)]; [p addQuadCurveToPoint:P(0.75,0.75) controlPoint:P(0.92,0.75)];
    [p addLineToPoint:P(0.12,0.75)]; [p moveToPoint:P(0.26,0.62)]; [p addLineToPoint:P(0.12,0.75)]; [p addLineToPoint:P(0.26,0.88)];
    [p stroke];
    #undef P
    if(m==2){   // kleine "1" in der Mitte
        NSString*one=@"1"; UIFont*f=[UIFont boldSystemFontOfSize:9]; CGSize ts=[one sizeWithFont:f];
        [one drawAtPoint:CGPointMake(o+sz/2-ts.width/2,o+sz/2-ts.height/2+1) withFont:f];
    }
    if(m) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(B/2-2,o+sz+5,4,4)] fill];
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
@end
