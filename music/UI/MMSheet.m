#import "MMSheet.h"
#import "SpotTheme.h"
#import "MMCovers.h"
#import "MMLayout.h"
#import <QuartzCore/QuartzCore.h>

@interface MMSheetView : UIControl
@property (nonatomic, copy) void (^done)(NSInteger idx);
@property (nonatomic, strong) UIView *panel;
@end
@implementation MMSheetView
- (void)close:(NSInteger)idx {
    CGFloat H=self.bounds.size.height; void (^d)(NSInteger)=self.done; self.done=nil;
    [UIView animateWithDuration:0.22 animations:^{
        self.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
        self.panel.frame=CGRectMake(self.panel.frame.origin.x,H,self.panel.frame.size.width,self.panel.frame.size.height);
    } completion:^(BOOL f){ [self removeFromSuperview]; if(d) d(idx); }];
}
- (void)tapOutside { [self close:-1]; }
// Panel nach unten ziehen: folgt dem Finger; weit genug oder schnell = schließen, sonst zurückfedern
- (void)panelPan:(UIPanGestureRecognizer *)g {
    CGFloat H=self.bounds.size.height, ph=self.panel.bounds.size.height, top=H-ph+20, dy=MAX(0,[g translationInView:self].y);
    if(g.state==UIGestureRecognizerStateBegan || g.state==UIGestureRecognizerStateChanged){
        self.panel.frame=CGRectMake(self.panel.frame.origin.x,top+dy,self.panel.bounds.size.width,ph);
        self.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55*(1-MIN(1,dy/ph))]; return; }
    if(g.state==UIGestureRecognizerStateEnded && (dy>70 || [g velocityInView:self].y>600)){ [self close:-1]; return; }
    [UIView animateWithDuration:0.2 animations:^{ self.panel.frame=CGRectMake(self.panel.frame.origin.x,top,self.panel.bounds.size.width,ph);
        self.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55]; }];
}
- (void)tapRow:(UIControl *)row { [self close:row.tag]; }
- (void)rowDown:(UIControl *)row { row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08]; }
- (void)rowUp:(UIControl *)row { row.backgroundColor=[UIColor clearColor]; }
@end

// ---- iOS 6: Aktionsblatt (dunkles, durchscheinendes Panel, glänzende Knöpfe, "Abbrechen" unten) ----
static void sheetGrad(CGRect r, const CGFloat *c, const CGFloat *l, size_t n){
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB(); CGGradientRef g=CGGradientCreateWithColorComponents(cs,c,l,n);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(),g,CGPointMake(0,r.origin.y),CGPointMake(0,CGRectGetMaxY(r)),0); CGGradientRelease(g); CGColorSpaceRelease(cs);
}
// kind 0 = weiß, 1 = rot (Entfernen), 2 = dunkel (Abbrechen), 3 = gedrückt (grün)
static UIImage* sheetButton(int kind){
    static UIImage*memo[4]; if(memo[kind]) return memo[kind];
    CGFloat W=24, H=44, r=8; UIGraphicsBeginImageContextWithOptions(CGSizeMake(W,H+1),NO,0);
    [[UIColor colorWithWhite:1 alpha:0.25] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,1,W,H) cornerRadius:r] fill];   // Lichtkante unten
    UIBezierPath*p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,W,H) cornerRadius:r];
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx); [p addClip];
    CGFloat w[]={1,1,1,1, 0.93,0.93,0.94,1, 0.85,0.85,0.87,1, 0.80,0.80,0.82,1}, rd[]={0.93,0.42,0.42,1, 0.80,0.13,0.13,1, 0.70,0.05,0.05,1, 0.62,0.02,0.02,1},
            dk[]={0.42,0.43,0.46,1, 0.24,0.25,0.28,1, 0.13,0.14,0.16,1, 0.10,0.10,0.12,1}, gr[]={0.40,0.80,0.48,1, 0.18,0.62,0.28,1, 0.10,0.50,0.20,1, 0.08,0.44,0.17,1}, l[]={0,0.5,0.5,1};
    sheetGrad(CGRectMake(0,0,W,H),kind==1?rd:kind==2?dk:kind==3?gr:w,l,4);
    CGContextRestoreGState(cx);
    [[UIColor colorWithWhite:0 alpha:0.6] setStroke]; p.lineWidth=1; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,W-1,H-1) cornerRadius:r] stroke];
    memo[kind]=[UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(r+1,r+1,r+1,r+1)]; UIGraphicsEndImageContext(); return memo[kind];
}
@implementation MMSheet
+ (void)ios6In:(UIView *)view title:(NSString *)title subtitle:(NSString *)sub imageURL:(NSString *)imageURL options:(NSArray *)options done:(void(^)(NSInteger))done {
    CGFloat SW=view.bounds.size.width, H=view.bounds.size.height, W=MMIsPad()?MIN(MMPadSheetW,SW):SW, px=floor((SW-W)/2);
    MMSheetView*ov=[[MMSheetView alloc] initWithFrame:view.bounds]; ov.done=done; ov.tag=MMSheetTag;
    ov.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; ov.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
    [ov addTarget:ov action:@selector(tapOutside) forControlEvents:UIControlEventTouchUpInside];
    BOOL img=imageURL!=nil; CGFloat bh=44, gap=8, head=img?72:(sub.length?62:(title.length?44:12));
    CGFloat ph=head+options.count*(bh+gap)+gap+bh+16;
    UIView*rowHost=nil; CGFloat maxH=H-30, top=head, fullH=ph;
    if(ph>maxH) ph=maxH;   // viele Knöpfe: scrollen
    UIControl*p=[[UIControl alloc] initWithFrame:CGRectMake(px,H,W,ph+20)];   // 20 pt Überstand nach unten wie beim normalen Blatt (Ziehen)
    p.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1,ph),NO,0);   // dunkles, durchscheinendes Blatt mit heller Oberkante
    CGFloat bc[]={0.30,0.33,0.38,0.92, 0.10,0.11,0.14,0.92, 0.03,0.03,0.05,0.95}, bl[]={0,0.25,1}; sheetGrad(CGRectMake(0,0,1,ph),bc,bl,3);
    [[UIColor colorWithWhite:1 alpha:0.35] setFill]; UIRectFill(CGRectMake(0,0,1,1));
    p.backgroundColor=[UIColor colorWithPatternImage:UIGraphicsGetImageFromCurrentImageContext()]; UIGraphicsEndImageContext();
    if(MMIsPad()){ p.layer.cornerRadius=8; p.clipsToBounds=YES; }
    CGFloat tx=img?72:20;
    if(img){ UIImageView*cv=[[UIImageView alloc] initWithFrame:CGRectMake(16,12,44,44)]; cv.backgroundColor=[UIColor colorWithWhite:0.2 alpha:1]; cv.clipsToBounds=YES;
        cv.contentMode=UIViewContentModeScaleAspectFill; [MMCovers load:imageURL into:cv]; [p addSubview:cv]; }
    if(title.length){ UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(tx,img?16:12,W-tx-20,20)]; t.text=title; t.font=[UIFont boldSystemFontOfSize:15];
        t.textColor=[UIColor whiteColor]; t.textAlignment=img?0:NSTextAlignmentCenter; t.backgroundColor=[UIColor clearColor];
        t.shadowColor=[UIColor blackColor]; t.shadowOffset=CGSizeMake(0,-1); [p addSubview:t]; }
    if(sub.length){ UILabel*s=[[UILabel alloc] initWithFrame:CGRectMake(tx,img?36:32,W-tx-20,img?18:26)]; s.text=sub; s.font=[UIFont systemFontOfSize:13]; s.numberOfLines=2;
        s.textColor=[UIColor colorWithWhite:0.78 alpha:1]; s.textAlignment=img?0:NSTextAlignmentCenter; s.backgroundColor=[UIColor clearColor];
        s.shadowColor=[UIColor blackColor]; s.shadowOffset=CGSizeMake(0,-1); s.adjustsFontSizeToFitWidth=YES; [p addSubview:s]; }
    rowHost=p;
    if(ph<fullH){ UIScrollView*sv=[[UIScrollView alloc] initWithFrame:CGRectMake(0,head,W,ph-head)]; sv.contentSize=CGSizeMake(W,fullH-head); sv.alwaysBounceVertical=YES; [p addSubview:sv]; rowHost=sv; top=0; }
    UIButton*(^btn)(NSString*,int,CGFloat,NSInteger)=^UIButton*(NSString*t,int kind,CGFloat y,NSInteger tag){
        UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake(20,y,W-40,bh); b.tag=tag;
        [b setBackgroundImage:sheetButton(kind) forState:UIControlStateNormal]; [b setBackgroundImage:sheetButton(3) forState:UIControlStateHighlighted];
        [b setTitle:t forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:18]; b.titleLabel.adjustsFontSizeToFitWidth=YES;
        [b setTitleColor:kind==0?[UIColor colorWithWhite:0.2 alpha:1]:[UIColor whiteColor] forState:UIControlStateNormal]; [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
        [b setTitleShadowColor:kind==0?[UIColor whiteColor]:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal]; b.titleLabel.shadowOffset=kind==0?CGSizeMake(0,1):CGSizeMake(0,-1);
        [b addTarget:ov action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside]; return b; };
    for(NSUInteger i=0;i<options.count;i++){
        NSString*o=options[i]; NSString*lo=[o lowercaseString];
        BOOL bad=[lo rangeOfString:@"remove"].location!=NSNotFound || [lo rangeOfString:@"delete"].location!=NSNotFound || [lo rangeOfString:@"log out"].location!=NSNotFound || [lo hasPrefix:@"clear"];   // zerstörend: rot
        [rowHost addSubview:btn(o,bad?1:0,top+i*(bh+gap),(NSInteger)i)];
    }
    [rowHost addSubview:btn(NSLocalizedString(@"Cancel",nil),2,top+options.count*(bh+gap)+gap,-1)];
    ov.panel=p; [ov addSubview:p]; [view addSubview:ov];
    [p addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:ov action:@selector(panelPan:)]];
    [UIView animateWithDuration:0.25 animations:^{ ov.backgroundColor=[UIColor colorWithWhite:0 alpha:0.45]; p.frame=CGRectMake(px,H-ph,W,ph+20); }];
}
+ (void)showIn:(UIView *)view title:(NSString *)title subtitle:(NSString *)sub options:(NSArray *)options done:(void(^)(NSInteger))done {
    [self showIn:view title:title subtitle:sub imageURL:nil options:options done:done];
}
+ (void)showIn:(UIView *)view title:(NSString *)title subtitle:(NSString *)sub imageURL:(NSString *)imageURL options:(NSArray *)options done:(void(^)(NSInteger))done {
    if([SpotTheme ios6]){ [self ios6In:view title:title subtitle:sub imageURL:imageURL options:options done:done]; return; }
    // iPad: Panel begrenzt breit und mittig (wie die Mitteilungszentrale), sonst über die ganze Breite
    CGFloat SW=view.bounds.size.width, H=view.bounds.size.height, W=MMIsPad()?MIN(MMPadSheetW,SW):SW, px=floor((SW-W)/2);
    MMSheetView*ov=[[MMSheetView alloc] initWithFrame:view.bounds]; ov.done=done; ov.tag=MMSheetTag;
    ov.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    ov.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
    [ov addTarget:ov action:@selector(tapOutside) forControlEvents:UIControlEventTouchUpInside];
    BOOL img=imageURL!=nil; CGFloat tx=img?82:20;   // mit Cover: Text rechts daneben
    CGFloat head=img?84:(sub.length?72:56), rowH=52, ph=head+options.count*rowH+16;
    // iPad: viele Zeilen und wenig Höhe -> Zeilen scrollen im Panel (iPhone unverändert)
    UIView*rowHost=nil; CGFloat maxH=H-40, ry=head+8, fullH=ph;
    if(MMIsPad() && ph>maxH) ph=maxH;
    UIControl*p=[[UIControl alloc] initWithFrame:CGRectMake(px,H,W,ph+20)];   // UIControl: Tippen aufs Panel schließt es nicht
    p.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin;
    p.backgroundColor=[UIColor colorWithWhite:0.13 alpha:1]; p.layer.cornerRadius=16; p.clipsToBounds=YES;
    UIView*grip=[[UIView alloc] initWithFrame:CGRectMake(W/2-18,8,36,4)]; grip.backgroundColor=[UIColor colorWithWhite:1 alpha:0.25]; grip.layer.cornerRadius=2; [p addSubview:grip];
    if(img){ UIImageView*cv=[[UIImageView alloc] initWithFrame:CGRectMake(20,22,50,50)]; cv.backgroundColor=[SpotTheme card]; cv.layer.cornerRadius=4; cv.clipsToBounds=YES;
        cv.contentMode=UIViewContentModeScaleAspectFill; [MMCovers load:imageURL into:cv]; [p addSubview:cv]; }
    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(tx,img?28:20,W-tx-20,22)]; t.text=title; t.font=[UIFont boldSystemFontOfSize:17]; t.textColor=[UIColor whiteColor]; t.backgroundColor=[UIColor clearColor]; [p addSubview:t];
    if(sub.length){ UILabel*s=[[UILabel alloc] initWithFrame:CGRectMake(tx,img?52:44,W-tx-20,18)]; s.text=sub; s.font=[UIFont systemFontOfSize:13]; s.textColor=[UIColor colorWithWhite:0.58 alpha:1]; s.backgroundColor=[UIColor clearColor]; [p addSubview:s]; }
    UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(0,head,W,0.5)]; ln.backgroundColor=[UIColor colorWithWhite:1 alpha:0.12]; [p addSubview:ln];
    rowHost=p;
    if(ph<fullH){ UIScrollView*sv=[[UIScrollView alloc] initWithFrame:CGRectMake(0,head+1,W,ph-head-1)];
        sv.contentSize=CGSizeMake(W,fullH-head-1); sv.alwaysBounceVertical=YES; [p addSubview:sv]; rowHost=sv; ry=7; }
    for(NSUInteger i=0;i<options.count;i++){
        UIControl*row=[[UIControl alloc] initWithFrame:CGRectMake(0,ry+i*rowH,W,rowH)]; row.tag=i;
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(20,0,W-60,rowH)]; l.text=options[i]; l.font=[UIFont systemFontOfSize:16]; l.textColor=[UIColor whiteColor]; l.backgroundColor=[UIColor clearColor];
        l.userInteractionEnabled=NO; [row addSubview:l];
        UILabel*chev=[[UILabel alloc] initWithFrame:CGRectMake(W-34,0,20,rowH)]; chev.text=@"›"; chev.font=[UIFont systemFontOfSize:24]; chev.textColor=[UIColor colorWithWhite:0.45 alpha:1]; chev.backgroundColor=[UIColor clearColor];
        chev.userInteractionEnabled=NO; [row addSubview:chev];
        [row addTarget:ov action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:ov action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
        [row addTarget:ov action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchDragExit|UIControlEventTouchCancel];
        [rowHost addSubview:row];
    }
    ov.panel=p; [ov addSubview:p]; [view addSubview:ov];
    [p addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:ov action:@selector(panelPan:)]];
    [UIView animateWithDuration:0.25 animations:^{
        ov.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55];
        p.frame=CGRectMake(px,H-ph,W,ph+20);
    }];
}
@end
