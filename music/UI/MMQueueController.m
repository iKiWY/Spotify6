#import "MMQueueController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MMSongMenu.h"
#import "MeshL10n.h"

@interface MMQueueController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, UIGestureRecognizerDelegate>
@end

// Beide Kopf-Symbole auf demselben Raster: 26x26, Zeichen in einem 20x14-Feld mittig (Mitte y=11), Punkt (an) bei y=21.
// So stehen Wiederholen und Weiterspielen exakt gleich hoch und gleich breit.
#define IB 26.0
static UIImage* headerIcon(UIColor*col, BOOL dot, void(^draw)(void)){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(IB,IB),NO,0); [col setStroke]; [col setFill];
    // 20x14-Zeichenfeld in Originalgröße, mittig im Bild
    CGContextRef cx=UIGraphicsGetCurrentContext(); CGContextSaveGState(cx);
    CGContextTranslateCTM(cx,3,4);
    draw();
    CGContextRestoreGState(cx);
    if(dot) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(IB/2-2,19.5,4,4)] fill];
    UIImage*i=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return i;
}
// Wiederholen: abgerundete Schleife mit Pfeil oben rechts und unten links
static UIImage* repeatIcon(UIColor*col, BOOL dot){
    return headerIcon(col,dot,^{
        UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=1.8; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
        [p moveToPoint:CGPointMake(1,8)]; [p addLineToPoint:CGPointMake(1,5)]; [p addQuadCurveToPoint:CGPointMake(4.5,2) controlPoint:CGPointMake(1,2)]; [p addLineToPoint:CGPointMake(18,2)];
        [p moveToPoint:CGPointMake(15,-1)]; [p addLineToPoint:CGPointMake(18,2)]; [p addLineToPoint:CGPointMake(15,5)];
        [p moveToPoint:CGPointMake(19,6)]; [p addLineToPoint:CGPointMake(19,9)]; [p addQuadCurveToPoint:CGPointMake(15.5,12) controlPoint:CGPointMake(19,12)]; [p addLineToPoint:CGPointMake(2,12)];
        [p moveToPoint:CGPointMake(5,9)]; [p addLineToPoint:CGPointMake(2,12)]; [p addLineToPoint:CGPointMake(5,15)];
        [p stroke]; });
}
// Warteschlange leeren: zwei Listenzeilen, rechts unten ein X
static UIImage* clearIcon(UIColor*col){
    return headerIcon(col,NO,^{
        UIRectFill(CGRectMake(1,1,14,1.8)); UIRectFill(CGRectMake(1,6,14,1.8)); UIRectFill(CGRectMake(1,11,7,1.8));
        UIBezierPath*x=[UIBezierPath bezierPath]; x.lineWidth=1.8; x.lineCapStyle=kCGLineCapRound;
        [x moveToPoint:CGPointMake(12,8.5)]; [x addLineToPoint:CGPointMake(18,14.5)]; [x moveToPoint:CGPointMake(18,8.5)]; [x addLineToPoint:CGPointMake(12,14.5)]; [x stroke]; });
}
// Weiterspielen ("Als Nächstes"): drei Listenzeilen, unten rechts ein Play-Dreieck
static UIImage* nextUpIcon(UIColor*col, BOOL dot){
    return headerIcon(col,dot,^{
        UIRectFill(CGRectMake(1,1,14,1.8)); UIRectFill(CGRectMake(1,6,14,1.8)); UIRectFill(CGRectMake(1,11,9,1.8));
        UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(13,8)]; [t addLineToPoint:CGPointMake(13,15)]; [t addLineToPoint:CGPointMake(19,11.5)]; [t closePath]; [t fill]; });
}
// schlanker Ziehgriff (drei dünne Linien) statt des breiten iOS-6-Griffs
static UIImage* gripIcon(void){
    static UIImage*g; if(g) return g;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(18,12),NO,0); [[SpotTheme muted] setFill];
    for(int i=0;i<3;i++) UIRectFill(CGRectMake(1,1+i*4.5,16,1.5));
    g=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return g;
}

@implementation MMQueueController {
    UITableView *_table;
    NSArray *_queue, *_user; NSInteger _idx;   // Liste + Position, eingereihte Titel
    UITapGestureRecognizer *_outsideTap;       // iPad-Fenster: Tippen daneben schließt
}
// iPad: begrenzt breit und mittig von unten (Formular-Blatt), auch über dem großen Player
- (id)init { if((self=[super init]) && MMIsPad()) self.modalPresentationStyle=UIModalPresentationFormSheet; return self; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return MMShouldAutorotate(o); }
- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    UIButton*done=[UIButton buttonWithType:UIButtonTypeCustom]; done.frame=CGRectMake(W-78,8,70,34);
    [done setTitle:L(@"Done") forState:UIControlStateNormal]; [done setTitleColor:[SpotTheme green] forState:UIControlStateNormal];
    done.titleLabel.font=[UIFont boldSystemFontOfSize:15]; done.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight;
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:done];
    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(80,8,W-160,34)]; nav.text=L(@"Queue"); nav.font=[UIFont boldSystemFontOfSize:16];
    nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];
    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,46,W,H-46) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone; _table.rowHeight=52;
    _table.dataSource=self; _table.delegate=self; [SpotTheme skinTable:_table]; [self.view addSubview:_table];
    _table.editing=YES; _table.allowsSelectionDuringEditing=YES;   // Ziehgriff rechts an eingereihten und kommenden Titeln
    __weak MMQueueController*ws=self;
    // lange drücken: Titel-Menü; nach rechts wischen: aus der Warteschlange nehmen (nicht "läuft gerade")
    [MMSongMenu attachToTable:_table swipeToRemove:^BOOL(NSIndexPath*ip, BOOL commit){ MMQueueController*s=ws; if(!s||ip.section==0) return NO;
        if(commit) [s removeAt:ip]; return YES; }
        trackAt:^NSDictionary*(NSIndexPath*ip){ MMQueueController*s=ws; return s?[s trackAt:ip]:nil; }];
    [self reload];
    [SpotTheme skinPage:self.view];   // iOS 6: echte Navigationsleiste mit "Fertig"
    MMAutoMask(self.view);   // iPad: als Formular-Blatt (540 pt) eingeblendet -> Unteransichten passen sich an
}
- (void)reload { MMRootController*r=[MMRootController shared]; _queue=r.queue; _idx=r.queueIndex; _user=r.userQueue; [_table reloadData]; }
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reload]; }
// Abschnitte: 0 = läuft gerade, 1 = eingereiht ("Als Nächstes in der Warteschlange"), 2 = danach aus der Liste
- (NSInteger)upNextCount { NSInteger n=(NSInteger)_queue.count-(_idx+1); return n>0?n:0; }
- (NSDictionary *)trackAt:(NSIndexPath *)ip {
    if(ip.section==0) return [MMRootController shared].nowPlaying;
    if(ip.section==1) return ip.row<(NSInteger)_user.count?_user[ip.row]:nil;
    NSInteger i=_idx+1+ip.row; return (i>=0 && i<(NSInteger)_queue.count)?_queue[i]:nil;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if(s==0) return [MMRootController shared].nowPlaying?1:0;
    if(s==2 && ![MMRootController shared].nextUpEnabled) return 0;   // ausgeschaltet: kommende Titel nicht zeigen
    return s==1?(NSInteger)_user.count:[self upNextCount];
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return (s==2 || [self tableView:tv numberOfRowsInSection:s])?([SpotTheme ios6]?26:40):0; }   // "Als Nächstes" immer (Symbol); Warteschlange nur, wenn etwas drin ist
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    CGFloat W=tv.bounds.size.width; MMRootController*r=[MMRootController shared];
    NSString*title=s==0?L(@"Now playing"):s==1?L(@"Next in queue"):L(@"Next up");
    UIView*v; CGFloat bh=40;
    if([SpotTheme ios6]){ bh=26; v=[SpotTheme plainSectionHeader:title width:W]; CGRect f=v.frame; f.size.height=bh; v.frame=f; v.userInteractionEnabled=YES;
        for(UIView*sub in v.subviews) sub.frame=CGRectMake(sub.frame.origin.x,0,sub.frame.size.width,bh); }   // iOS-6-Abschnittskopf, etwas höher für die Knöpfe
    else { v=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,40)]; v.backgroundColor=[SpotTheme bg];
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(16,10,W-120,24)]; l.text=title;
        l.font=[UIFont boldSystemFontOfSize:17]; l.textColor=[SpotTheme ink]; l.backgroundColor=[UIColor clearColor]; [v addSubview:l]; }
    if(s==1){   // Warteschlange endlos wiederholen (Symbol grün = an)
        UIButton*rb=[UIButton buttonWithType:UIButtonTypeCustom]; rb.frame=[SpotTheme ios6]?CGRectMake(W-44,0,44,bh):CGRectMake(W-20-22,22-11-2,44,IB+4);
        [rb setImage:repeatIcon(r.repeatQueue?[SpotTheme green]:[SpotTheme muted],r.repeatQueue) forState:UIControlStateNormal];
        [rb addTarget:self action:@selector(toggleRepeat) forControlEvents:UIControlEventTouchUpInside]; [v addSubview:rb];
        UIButton*cb=[UIButton buttonWithType:UIButtonTypeCustom]; cb.frame=CGRectOffset(rb.frame,-44,0);   // links daneben: Warteschlange leeren
        [cb setImage:clearIcon([SpotTheme muted]) forState:UIControlStateNormal];
        [cb addTarget:self action:@selector(askClear) forControlEvents:UIControlEventTouchUpInside]; [v addSubview:cb];
    } else if(s==2){   // "Als Nächstes" an/aus (Symbol wie Wiederholen): aus = nach dem laufenden Titel und der Warteschlange ist Schluss
        UIButton*nb=[UIButton buttonWithType:UIButtonTypeCustom]; nb.frame=[SpotTheme ios6]?CGRectMake(W-44,0,44,bh):CGRectMake(W-20-22,22-11-2,44,IB+4);
        [nb setImage:nextUpIcon(r.nextUpEnabled?[SpotTheme green]:[SpotTheme muted],r.nextUpEnabled) forState:UIControlStateNormal];
        [nb addTarget:self action:@selector(toggleNextUp) forControlEvents:UIControlEventTouchUpInside]; [v addSubview:nb];
    }
    return v;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width;
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:MMCellID(@"r",tv)];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MMCellID(@"r",tv)]; c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(16,7,38,38)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; cov.clipsToBounds=YES; cov.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(66,8,W-82,19)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.autoresizingMask=UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(66,27,W-82,17)]; ar.tag=3; ar.font=[SpotTheme sub]; ar.textColor=[SpotTheme muted]; ar.autoresizingMask=UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:ar]; }
    NSDictionary*t=[self trackAt:ip];
    UILabel*ti=(UILabel*)[c.contentView viewWithTag:2]; ti.text=t[@"title"]; ti.textColor=ip.section==0?[SpotTheme green]:[SpotTheme ink];
    ((UILabel*)[c.contentView viewWithTag:3]).text=t[@"artist"];
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1]; cov.image=nil; [MMCovers load:t[@"cover"] into:cov];
    return c;
}
// ---- Ziehen zum Umsortieren: innerhalb der eingereihten bzw. innerhalb der kommenden Titel ----
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewCellEditingStyleNone; }
// Den System-Ziehgriff (iOS 6: UITableViewCellReorderControl mit einem Bild) gegen den schlanken tauschen
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat right=MIN(c.contentView.bounds.size.width,c.bounds.size.width);   // Titel/Artist enden vor dem Ziehgriff (sonst laufen lange Titel darunter)
    for(UIView*v in c.subviews) if([NSStringFromClass([v class]) rangeOfString:@"Reorder"].location!=NSNotFound){
        right=MIN(right,v.frame.origin.x);
        if(![SpotTheme ios6]) for(UIView*iv in v.subviews) if([iv isKindOfClass:[UIImageView class]]){ UIImageView*im=(UIImageView*)iv;   // iOS 6: echter iOS-Griff
            im.image=gripIcon(); im.contentMode=UIViewContentModeCenter; im.frame=v.bounds; } }
    if(tv.editing && [self tableView:tv canMoveRowAtIndexPath:ip]) right=MIN(right,c.bounds.size.width-44);   // Griff ist noch nicht angelegt
    for(NSInteger tag=2;tag<=3;tag++){ UIView*l=[c.contentView viewWithTag:tag]; if(l && right-66-8>40){ l.autoresizingMask=UIViewAutoresizingNone; CGRect f=l.frame; f.size.width=right-66-8; l.frame=f; } }
}
- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return NO; }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return ip.section>0; }
- (NSIndexPath *)tableView:(UITableView *)tv targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if(to.section==from.section) return to;
    NSInteger last=[self tableView:tv numberOfRowsInSection:from.section]-1;   // über die Abschnittsgrenze -> an deren Rand halten
    return [NSIndexPath indexPathForRow:(to.section<from.section?0:last) inSection:from.section];
}
- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    MMRootController*r=[MMRootController shared];
    if(from.section==1) [r moveUserQueueFrom:from.row to:to.row];
    else [r moveQueueFrom:_idx+1+from.row to:_idx+1+to.row];
    _queue=r.queue; _idx=r.queueIndex; _user=r.userQueue;   // Tabelle hat die Zeile schon verschoben -> nur die Daten nachziehen
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];   // Auswahl nicht stehen lassen (sonst bleibt die Schrift weiß)
    if(ip.section==0) return;
    if(ip.section==1) [[MMRootController shared] playUserQueueIndex:ip.row];
    else [[MMRootController shared] playQueueIndex:_idx+1+ip.row];
    [self reload];
}
- (void)askClear {
    UIAlertView*a=[[UIAlertView alloc] initWithTitle:L(@"Clear queue?") message:L(@"Removes all songs from Next in queue.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Clear"),nil];
    [a show];
}
- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)i { if(i==a.firstOtherButtonIndex){ [[MMRootController shared] clearUserQueue]; [self reload]; } }
- (void)toggleRepeat { MMRootController*r=[MMRootController shared]; r.repeatQueue=!r.repeatQueue; [self reload]; }
- (void)toggleNextUp { MMRootController*r=[MMRootController shared]; r.nextUpEnabled=!r.nextUpEnabled; [self reload]; }
- (void)removeAt:(NSIndexPath *)ip {
    MMRootController*r=[MMRootController shared];
    if(ip.section==1) [r removeUserQueueIndex:ip.row]; else [r removeQueueIndex:_idx+1+ip.row];
    _queue=r.queue; _idx=r.queueIndex; _user=r.userQueue;
    [_table deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationLeft];
    if(ip.section==1 && !_user.count) [_table reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];   // Überschrift ausblenden
}
- (void)close { if(self.onClose) self.onClose(); else [self dismissViewControllerAnimated:YES completion:nil]; }
// iPad (Fenster in der Mitte): irgendwo daneben tippen schließt die Warteschlange
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    if(MMIsPad() && self.presentingViewController && !self.parentViewController && !_outsideTap){   // nur als eigenes Fenster, nicht eingebettet
        _outsideTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(outsideTap:)];
        _outsideTap.cancelsTouchesInView=NO; _outsideTap.delegate=self; [self.view.window addGestureRecognizer:_outsideTap]; }
}
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [_outsideTap.view removeGestureRecognizer:_outsideTap]; _outsideTap=nil; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return g!=_outsideTap || ![t.view isDescendantOfView:self.view]; }
- (void)outsideTap:(UITapGestureRecognizer *)g { if(g.state==UIGestureRecognizerStateEnded) [self close]; }
@end
