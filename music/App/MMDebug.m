// MMDebug.m - nur in Debug-Builds (gmake ohne FINALPACKAGE): Fernsteuerung über SSH zum Testen auf dem 3GS.
// Befehle zeilenweise in Library/Riff/.cmd schreiben; die App liest die Datei jede Sekunde, führt aus und löscht sie.
//   shot                     alle Fenster -> Library/Riff/shot.png (ohne Statusleiste, die zeichnet das System)
//   api <pfad>               GET über apiUser -> Library/Riff/api.json
//   ext <kind> <uri>         roher extended-metadata-Payload als Protobuf-Baum -> Library/Riff/ext.txt
//   call <ziel> <selector>   ziel = root | pushed | tab | player | alert (Button-Index als selector: alert 1)
//   queue next|last <id> <titel>   ·   unqueue <titel>   ·   move <von> <nach>   ·   closesheet
//   fakeswipe began|changed|ended|cancelled <dx>   Wischen nach rechts auf Zeile 1 nachspielen
//   playrow [abschnitt] <zeile>  Zeile der obersten geöffneten Liste antippen
//   menu                     Titel-Menü (wie lange drücken) für den laufenden Titel
//   raw <spclient-pfad>      ungefilterte JSON-Antwort -> Library/Riff/raw.json
//   push album|artist <id> [name]   ·   tab <n>   ·   search <text>
//   layout                   Rahmen aller Ansichten -> Library/Riff/layout.txt   ·   orient 1-4   ·   authexpired
#ifdef DEBUG
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <pthread.h>
#import <dlfcn.h>
#import "MMSpotify.h"
#import "MMAudio.h"
#import "MMRootController.h"
#import "SpotTheme.h"
#import "MMTrackListController.h"
#import "MMArtistController.h"
#import "MMSongMenu.h"
#import "MMSheet.h"

// Unechter Wisch-Erkenner: liefert feste Werte, damit swipePan: ohne Finger getestet werden kann
@interface MMFakePan : UIPanGestureRecognizer
@property (nonatomic) CGPoint fakeT, fakeLoc; @property (nonatomic) UIGestureRecognizerState fakeState; @property (nonatomic,weak) UIView *fakeView;
@end
@implementation MMFakePan
- (CGPoint)translationInView:(UIView *)v { return self.fakeT; }
- (CGPoint)locationInView:(UIView *)v { return self.fakeLoc; }
- (CGPoint)velocityInView:(UIView *)v { return CGPointMake(self.fakeT.x<0?-500:500,0); }
- (UIGestureRecognizerState)state { return self.fakeState; }
- (UIView *)view { return self.fakeView; }
@end
static MMFakePan *gFake;

@interface MMSpotify (Debug)
+ (NSData *)debugExt:(NSString *)uri kind:(int)kind;
+ (NSData *)debugRaw:(NSString *)path;
@end

static uint64_t dvar(const unsigned char*b,NSUInteger len,NSUInteger*p){uint64_t r=0;int s=0;while(*p<len){unsigned char c=b[(*p)++];r|=(uint64_t)(c&0x7f)<<s;if(!(c&0x80))break;s+=7;}return r;}
// Protobuf ohne Schema als Baum ausgeben: Länge-Felder werden als Untermeldung versucht, sonst als Text/Hex.
static BOOL dump(NSData*m,int depth,NSMutableString*out){
    const unsigned char*b=m.bytes; NSUInteger len=m.length,pos=0; NSMutableString*tmp=[NSMutableString string];
    while(pos<len){ uint64_t tag=dvar(b,len,&pos); int f=(int)(tag>>3),wt=(int)(tag&7); if(f==0) return NO;
        NSString*ind=[@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0];
        if(wt==0){ [tmp appendFormat:@"%@%d: %llu\n",ind,f,dvar(b,len,&pos)]; }
        else if(wt==2){ uint64_t l=dvar(b,len,&pos); if(pos+l>len) return NO; NSData*v=[m subdataWithRange:NSMakeRange(pos,(NSUInteger)l)]; pos+=(NSUInteger)l;
            NSMutableString*sub=[NSMutableString string];
            NSString*txt=[[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding];
            BOOL printable=txt.length && [txt rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location==NSNotFound;
            if(printable) [tmp appendFormat:@"%@%d: \"%@\"\n",ind,f,txt];
            else if(depth<6 && v.length && dump(v,depth+1,sub)) [tmp appendFormat:@"%@%d {\n%@%@}\n",ind,f,sub,ind];
            else { NSMutableString*h=[NSMutableString string]; const unsigned char*vb=v.bytes; for(NSUInteger i=0;i<v.length&&i<24;i++)[h appendFormat:@"%02x",vb[i]];
                [tmp appendFormat:@"%@%d: <%lu B %@>\n",ind,f,(unsigned long)v.length,h]; } }
        else if(wt==5){ pos+=4; [tmp appendFormat:@"%@%d: (32bit)\n",ind,f]; }
        else if(wt==1){ pos+=8; [tmp appendFormat:@"%@%d: (64bit)\n",ind,f]; }
        else return NO;
        if(pos>len) return NO;
    }
    [out appendString:tmp]; return YES;
}

static void shot(void){
    UIWindow*kw=[UIApplication sharedApplication].keyWindow; CGSize sz=kw.bounds.size;
    UIGraphicsBeginImageContextWithOptions(sz,YES,1);
    for(UIWindow*w in [UIApplication sharedApplication].windows) if(!w.hidden) [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    NSData*png=UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()); UIGraphicsEndImageContext();
    [png writeToFile:MMPath(@"shot.png") atomically:YES]; MMLog(@"debug: shot %lu B", (unsigned long)png.length);
}
static UIAlertView* findAlert(UIView*v){ if([v isKindOfClass:[UIAlertView class]]) return (UIAlertView*)v; for(UIView*s in v.subviews){ UIAlertView*a=findAlert(s); if(a) return a; } return nil; }

static double gCellSum, gCellMax; static int gCellN;
// Scroll-Messung: scrollt die Liste wie ein Finger (px pro Frame) und loggt Frame-Zeiten
@interface MMScrollTest : NSObject { @public UIScrollView*sv; CGFloat step; int left, n, slow; double last, sum, worst; CADisplayLink*dl; }
@end
@implementation MMScrollTest
- (void)tick:(CADisplayLink *)l {
    if(last>0){ double dt=l.timestamp-last; sum+=dt; n++; if(dt>worst){ worst=dt; MMLog(@"debug: scrolltest slow frame %.0fms at frame %d y=%.0f rows=%ld", dt*1000, n, sv.contentOffset.y, (long)([sv isKindOfClass:[UITableView class]]?[(UITableView*)sv numberOfRowsInSection:0]:0)); } if(dt>0.020) slow++; }
    last=l.timestamp;
    CGFloat maxY=MAX(0,sv.contentSize.height-sv.bounds.size.height), y=sv.contentOffset.y+step;
    if(y>maxY||y<0){ step=-step; y=MIN(MAX(y,0),maxY); }
    sv.contentOffset=CGPointMake(0,y);
    if(--left<=0){ [dl invalidate]; dl=nil;
        MMLog(@"debug: scrolltest frames=%d avg=%.1fms fps=%.1f worst=%.0fms slow(>20ms)=%d cells=%d cellAvg=%.1fms cellMax=%.0fms cellTotal=%.0fms", n, sum/n*1000, n/sum, worst*1000, slow, gCellN, gCellN?gCellSum/gCellN*1000:0, gCellMax*1000, gCellSum*1000); }
}
@end
static MMScrollTest*gScroll;
// cpusample <s>: CPU-Zeit je Thread über <s> Sekunden (Name, Anteil) plus Verzögerung des Hauptthreads -> Log
static NSDictionary*threadTimes(void){
    NSMutableDictionary*d=[NSMutableDictionary dictionary]; thread_act_array_t th; mach_msg_type_number_t n=0;
    if(task_threads(mach_task_self(),&th,&n)!=KERN_SUCCESS) return d;
    for(mach_msg_type_number_t i=0;i<n;i++){
        thread_basic_info_data_t bi; mach_msg_type_number_t cnt=THREAD_BASIC_INFO_COUNT;
        if(thread_info(th[i],THREAD_BASIC_INFO,(thread_info_t)&bi,&cnt)==KERN_SUCCESS){
            double t=bi.user_time.seconds+bi.user_time.microseconds/1e6+bi.system_time.seconds+bi.system_time.microseconds/1e6;
            char name[64]=""; pthread_t pt=pthread_from_mach_thread_np(th[i]); if(pt) pthread_getname_np(pt,name,sizeof name);
            d[@(th[i])]=@[@(t),[NSString stringWithUTF8String:name]]; }
        mach_port_deallocate(mach_task_self(),th[i]); }
    vm_deallocate(mach_task_self(),(vm_address_t)th,n*sizeof(thread_t)); return d;
}
// Hängt der Hauptthread: seinen Stack abtasten (r7-Kette, armv7) -> Log als Image+Offset, mit atos gegen den Debug-Build auflösen
static thread_t gMainThread;
static void sampleMain(void){
    NSMutableString*o=[NSMutableString string];   // vor dem Anhalten: hält der Hauptthread gerade die malloc-Sperre, hinge sonst alles
    arm_thread_state_t st; mach_msg_type_number_t cnt=ARM_THREAD_STATE_COUNT;
    if(thread_suspend(gMainThread)!=KERN_SUCCESS) return;
    if(thread_get_state(gMainThread,ARM_THREAD_STATE,(thread_state_t)&st,&cnt)==KERN_SUCCESS){
        uintptr_t pcs[40]; int n=0; pcs[n++]=st.__pc; pcs[n++]=st.__lr; uintptr_t fp=st.__r[7];
        while(fp && n<40){ uintptr_t*f=(uintptr_t*)fp; uintptr_t next=f[0], ret=f[1]; if(!ret) break; pcs[n++]=ret; if(next<=fp) break; fp=next; }
        thread_resume(gMainThread);
        for(int i=0;i<n;i++){ Dl_info di; if(dladdr((void*)pcs[i],&di)&&di.dli_fname){ const char*b=strrchr(di.dli_fname,'/');
            [o appendFormat:@" %s+0x%lx(%s)",b?b+1:di.dli_fname,(unsigned long)(pcs[i]-(uintptr_t)di.dli_fbase),di.dli_sname?di.dli_sname:"?"]; } }
    } else thread_resume(gMainThread);
    MMLog(@"debug: stall stack%@",o);
}
static void cpuSample(double secs){
    NSDictionary*a=threadTimes(); double t0=CFAbsoluteTimeGetCurrent();
    __block double lagMax=0; __block int lagN=0, lagSlow=0;
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        while(CFAbsoluteTimeGetCurrent()-t0<secs){ double s0=CFAbsoluteTimeGetCurrent();
            __block volatile BOOL done=NO; dispatch_async(dispatch_get_main_queue(), ^{ done=YES; });
            int k=0; while(!done){ usleep(10000); if(++k%5==0) sampleMain(); } double lag=CFAbsoluteTimeGetCurrent()-s0; lagN++; if(lag>lagMax) lagMax=lag; if(lag>0.05) lagSlow++;
            usleep(50000); }
        NSDictionary*b=threadTimes(); double wall=CFAbsoluteTimeGetCurrent()-t0, tot=0; NSMutableArray*rows=[NSMutableArray array];
        for(NSNumber*k in b){ double d=[b[k][0] doubleValue]-[a[k][0] ?: @0 doubleValue]; tot+=d; if(d>0.01) [rows addObject:@[@(d),[NSString stringWithFormat:@"%@%@",b[k][1],a[k]?@"":@" (new)"],k]]; }
        [rows sortUsingComparator:^NSComparisonResult(NSArray*x,NSArray*y){ return [y[0] compare:x[0]]; }];
        MMLog(@"debug: cpusample %.0fs total %.1f%% threads=%lu mainLagMax=%.0fms mainLag>50ms=%d/%d",wall,100*tot/wall,(unsigned long)b.count,lagMax*1000,lagSlow,lagN);
        for(NSArray*r in rows) MMLog(@"debug: cpusample   %5.1f%% port=%@ %@",100*[r[0] doubleValue]/wall,r[2],r[1]);
    });
}
// Zeit in cellForRow messen (beliebiger Controller): Originalmethode umhüllen
static void timeCells(Class cls){
    static NSMutableSet*done; if(!done) done=[NSMutableSet set]; if([done containsObject:cls]) return; [done addObject:cls];
    SEL sel=@selector(tableView:cellForRowAtIndexPath:); Method m=class_getInstanceMethod(cls,sel); if(!m) return;
    IMP orig=method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^id(id me, UITableView*tv, NSIndexPath*ip){
        CFAbsoluteTime t0=CFAbsoluteTimeGetCurrent(); id c=((id(*)(id,SEL,UITableView*,NSIndexPath*))orig)(me,sel,tv,ip);
        double dt=CFAbsoluteTimeGetCurrent()-t0; gCellSum+=dt; gCellN++; if(dt>gCellMax) gCellMax=dt; return c; }));
}

// layout: Rahmen der Ansichten (Klasse, frame, tag, Drehung) zum Prüfen der iPad-/iPhone-Anordnung ohne Screenshot
static void dumpView(UIView*v,int d,int max,NSMutableString*o){
    [o appendFormat:@"%*s%@ %@",d*2,"",NSStringFromClass([v class]),NSStringFromCGRect(v.frame)];
    if(v.tag) [o appendFormat:@" tag=%ld",(long)v.tag];
    if(!CGAffineTransformIsIdentity(v.transform)) [o appendFormat:@" transform=%@ bounds=%@",NSStringFromCGAffineTransform(v.transform),NSStringFromCGRect(v.bounds)];
    if(v.hidden) [o appendString:@" hidden"];
    [o appendString:@"\n"];
    if(d<max) for(UIView*c in v.subviews) dumpView(c,d+1,max,o);
}
static void layoutDump(void){
    MMRootController*root=[MMRootController shared]; NSMutableString*o=[NSMutableString string];
    UIWindow*kw=[UIApplication sharedApplication].keyWindow; UIViewController*rv=kw.rootViewController;
    [o appendFormat:@"window %@ root=%@ orientation=%ld\n",NSStringFromCGRect(kw.bounds),NSStringFromClass([rv class]),(long)[UIApplication sharedApplication].statusBarOrientation];
    [o appendString:@"== root view\n"]; dumpView(rv.view,0,3,o);
    if(rv==(UIViewController*)root){
        UIViewController*tab=[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        [o appendString:@"== tab page\n"]; dumpView(tab.view,0,4,o);
        UIViewController*top=[[root valueForKey:@"_pushedStack"] lastObject];
        if(top){ [o appendString:@"== pushed page\n"]; dumpView(top.view,0,5,o); }
    }
    int n=0; for(UIViewController*pv=rv.presentedViewController; pv; pv=pv.presentedViewController){
        [o appendFormat:@"== presented %d %@\n",++n,NSStringFromClass([pv class])]; dumpView(pv.view,0,2,o); }
    [o writeToFile:MMPath(@"layout.txt") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void run(NSString*line){
    NSArray*w=[line componentsSeparatedByString:@" "]; NSString*c=w[0]; MMRootController*root=[MMRootController shared];
    NSString*rest=w.count>1?[[w subarrayWithRange:NSMakeRange(1,w.count-1)] componentsJoinedByString:@" "]:@"";
    MMLog(@"debug: %@", line);
    if([c isEqualToString:@"shot"]) shot();
    else if([c isEqualToString:@"api"]) [MMSpotify apiUser:@"GET" path:rest body:nil completion:^(NSDictionary*j,NSInteger st){
        NSData*d=j?[NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted error:NULL]:nil;
        [d?:[NSData data] writeToFile:MMPath(@"api.json") atomically:YES]; MMLog(@"debug: api %@ -> %ld, %lu B",rest,(long)st,(unsigned long)d.length); }];
    else if([c isEqualToString:@"ext"] && w.count>=3) dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSData*pl=[MMSpotify debugExt:w[2] kind:[w[1] intValue]]; NSMutableString*o=[NSMutableString string];
        if(!pl.length || !dump(pl,0,o)) [o appendFormat:@"(kein/unlesbarer Payload, %lu B)\n",(unsigned long)pl.length];
        [o writeToFile:MMPath(@"ext.txt") atomically:YES encoding:NSUTF8StringEncoding error:NULL]; MMLog(@"debug: ext %lu B",(unsigned long)pl.length); });
    else if([c isEqualToString:@"raw"]) dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSData*d=[MMSpotify debugRaw:rest]; [d?:[NSData data] writeToFile:MMPath(@"raw.json") atomically:YES]; MMLog(@"debug: raw %lu B",(unsigned long)d.length); });
    else if([c isEqualToString:@"push"] && w.count==2 && [w[1] isEqualToString:@"diag"]) [root pushContent:[[NSClassFromString(@"MMDiagnosticsController") alloc] init]];   // push diag: Seite "Debug info"
    else if([c isEqualToString:@"push"] && w.count==2 && [w[1] isEqualToString:@"liked"]) [root pushContent:[[MMTrackListController alloc] initWithTitle:@"Liked Songs" path:@"me/tracks?market=from_token&limit=50"]];   // push liked: lange Liste für scrolltest
    else if([c isEqualToString:@"push"] && w.count>=3){
        NSString*name=w.count>3?[[w subarrayWithRange:NSMakeRange(3,w.count-3)] componentsJoinedByString:@" "]:@"Album";
        if([w[1] isEqualToString:@"album"]) [root pushContent:[[MMTrackListController alloc] initWithTitle:name path:[@"albums/" stringByAppendingString:w[2]]]];
        else [root pushContent:[[MMArtistController alloc] initWithArtistId:w[2] name:w.count>3?name:nil]];
    }
    else if([c isEqualToString:@"queue"] && w.count>=4) [root queueTrack:@{@"id":w[2],@"title":[[w subarrayWithRange:NSMakeRange(3,w.count-3)] componentsJoinedByString:@" "],@"artist":@"test",@"cover":@""} next:[w[1] isEqualToString:@"next"]];
    else if([c isEqualToString:@"unqueue"]){   // Test-Einträge wieder entfernen (liegen alle hinter dem laufenden Titel)
        for(NSString*k in @[@"_queue",@"_origQueue",@"_userQueue"]){ NSArray*q=[root valueForKey:k]; if(!q) continue;
            [root setValue:[q filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"title != %@",rest]] forKey:k]; }
        [root performSelector:@selector(saveState)]; }
    else if([c isEqualToString:@"move"] && w.count>=3) [root moveQueueFrom:[w[1] integerValue] to:[w[2] integerValue]];
    else if([c isEqualToString:@"closesheet"]){ for(UIView*v in root.view.subviews) if(v.tag==MMSheetTag && [v respondsToSelector:@selector(tapOutside)]) [v performSelector:@selector(tapOutside)]; }
    else if([c isEqualToString:@"probe"]){   // probe <ms>: wo die oberste geöffnete Ansicht gerade ist (mitten in der Animation)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)([rest doubleValue]*NSEC_PER_MSEC)),dispatch_get_main_queue(),^{
            UIViewController*vc=[[root valueForKey:@"_pushedStack"] lastObject];
            MMLog(@"debug: probe %@ frame=%@ live=%@", NSStringFromClass([vc class]), NSStringFromCGRect(vc.view.frame), NSStringFromCGRect([(CALayer*)vc.view.layer.presentationLayer frame])); }); }
    else if([c isEqualToString:@"keyrefuse"]) [MMSpotify debugFakeKeyRefusals];   // keyrefuse: Konto-verweigert-Popup testen
    else if([c isEqualToString:@"https"]) dispatch_async(dispatch_get_global_queue(0,0), ^{   // https <url>: mit iOS-TLS laden, Fehler ins Log
        NSError*e=nil; NSData*d=[NSData dataWithContentsOfURL:[NSURL URLWithString:rest] options:0 error:&e];
        MMLog(@"debug: https %@ -> %lu B %@", rest, (unsigned long)d.length, e?[NSString stringWithFormat:@"%@ %ld %@ %@",e.domain,(long)e.code,e.localizedDescription,e.userInfo]:@"ok"); });
    else if([c isEqualToString:@"aptest"]) [MMSpotify debugApTest:rest];   // aptest <ip:port>: Verbindungs-Zeitlimit prüfen
    else if([c isEqualToString:@"cdntest"]) [MMSpotify debugCdnTest:rest];   // cdntest <trackId>: jede CDN-Adresse mit iOS-TLS und mbedTLS laden
    else if([c isEqualToString:@"lastrow"]){   // lastrow: wie mit dem Finger ganz nach unten (mit contentInset)
        UIViewController*vc=[[root valueForKey:@"_pushedStack"] lastObject]?:[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        UITableView*tv=[vc valueForKey:@"_table"]; NSInteger sc=tv.numberOfSections-1; while(sc>0 && ![tv numberOfRowsInSection:sc]) sc--;
        CGFloat y=MAX(0,tv.contentSize.height+tv.contentInset.bottom-tv.bounds.size.height); [tv setContentOffset:CGPointMake(0,y) animated:NO];
        MMLog(@"debug: lastrow frame=%@ content=%.0f y=%.0f super=%@",NSStringFromCGRect(tv.frame),tv.contentSize.height,y,NSStringFromCGRect(tv.superview.bounds)); }
    else if([c isEqualToString:@"field"]){   // field: Suchfeld antippen (Tastatur auf)
        UIViewController*vc=[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]]; [[vc valueForKey:@"_field"] becomeFirstResponder]; }
    else if([c isEqualToString:@"kb"]){ UIViewController*vc=[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        MMLog(@"debug: keyboard %@", [[vc valueForKey:@"_field"] isFirstResponder]?@"open":@"closed"); }
    else if([c isEqualToString:@"timesnap"]){   // wie lange das Bild der App beim Runterziehen des Players dauert
        UIView*app=root.view; double t0=CACurrentMediaTime();
        UIGraphicsBeginImageContextWithOptions(app.bounds.size,YES,0); [app.layer renderInContext:UIGraphicsGetCurrentContext()]; UIGraphicsEndImageContext();
        MMLog(@"debug: snapshot %.0f ms (window=%@)",(CACurrentMediaTime()-t0)*1000, app.window?@"ja":@"nein"); }
    else if([c isEqualToString:@"playrow"]){   // Zeile in der obersten geöffneten Liste antippen (Abschnitt 0 bzw. "<abschnitt> <zeile>")
        UIViewController*vc=[[root valueForKey:@"_pushedStack"] lastObject]?:[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        UITableView*tv=[vc valueForKey:@"_table"];
        NSInteger sec=w.count>2?[w[1] integerValue]:0, row=[[w lastObject] integerValue];
        [(id<UITableViewDelegate>)vc tableView:tv didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:sec]]; }
    else if([c isEqualToString:@"fakeswipe"] && w.count>=3){   // fakeswipe began|changed|ended <dx>  auf Zeile 1 der obersten Liste
        UIViewController*vc=root; while(vc.presentedViewController) vc=vc.presentedViewController;   // Warteschlange o. ä. offen?
        if(vc==root || ![vc respondsToSelector:NSSelectorFromString(@"trackAt:")]) vc=[[root valueForKey:@"_pushedStack"] lastObject];
        UITableView*tv=[vc valueForKey:@"_table"];
        NSInteger fsec=w.count>4?[w[3] integerValue]:0, frow=w.count>4?[w[4] integerValue]:1;   // fakeswipe <phase> <dx> [abschnitt zeile]
        if(!gFake){ gFake=[[MMFakePan alloc] init]; }
        UIGestureRecognizer*real=nil; for(UIGestureRecognizer*g in tv.gestureRecognizers) if([g isKindOfClass:[UIPanGestureRecognizer class]] && g!=tv.panGestureRecognizer) real=g;
        gFake.fakeView=tv; gFake.fakeLoc=[tv rectForRowAtIndexPath:[NSIndexPath indexPathForRow:frow inSection:fsec]].origin; gFake.fakeLoc=CGPointMake(100,gFake.fakeLoc.y+20);
        gFake.fakeT=CGPointMake([w[2] floatValue],0);
        gFake.fakeState=[w[1] isEqualToString:@"began"]?UIGestureRecognizerStateBegan:[w[1] isEqualToString:@"changed"]?UIGestureRecognizerStateChanged:UIGestureRecognizerStateEnded;
        MMLog(@"debug: fakeswipe real=%@", real?@"ja":@"nein");
        [MMSongMenu performSelector:NSSelectorFromString(@"debugSwipe:real:") withObject:gFake withObject:real];
    }
    else if([c isEqualToString:@"scrolltest"]){   // scrolltest <px pro Frame> <Frames>
        UIViewController*vc=[[root valueForKey:@"_pushedStack"] lastObject]?:[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        timeCells([vc class]); gCellSum=gCellMax=0; gCellN=0;
        gScroll=[MMScrollTest new]; gScroll->sv=[vc valueForKey:class_getInstanceVariable([vc class],"_table")?@"_table":@"_sc"]; gScroll->step=w.count>1?[w[1] floatValue]:12; gScroll->left=w.count>2?[w[2] intValue]:240;
        gScroll->dl=[CADisplayLink displayLinkWithTarget:gScroll selector:@selector(tick:)]; [gScroll->dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes]; }
    else if([c isEqualToString:@"dlmsg"]){   // dlmsg: Abschlussmeldung mit einem nicht lieferbaren Titel zeigen, 1 s später shot
        [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadDone" object:nil userInfo:@{@"ok":@135,@"unavailable":@1}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ shot(); }); }
    else if([c isEqualToString:@"skin"]) [MMRootController switchSkin:rest];   // skin ios6|spotify: wie die Auswahl in den Einstellungen
    else if([c isEqualToString:@"cpusample"]) cpuSample(w.count>1?[w[1] doubleValue]:10);
    else if([c isEqualToString:@"tabbar"]){   // tabbar <0-4>: Farbvorschlag für die Tab-Leiste (iOS 6) zeigen
        [SpotTheme setTabVariant:[rest intValue]]; UITabBar*tb=[root valueForKey:@"_sysTabBar"]; tb.backgroundImage=[SpotTheme tabBarImage:tb.bounds.size]; }
    else if([c isEqualToString:@"hl"]){   // hl <zeile>: Zeile der Liste oben gedrückt zeigen (wie ein Finger darauf), zum Ansehen des Antipp-Looks
        UIViewController*vc=[[root valueForKey:@"_pushedStack"] lastObject]?:[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        UITableView*tv=[vc valueForKey:@"_table"]; [[tv cellForRowAtIndexPath:[NSIndexPath indexPathForRow:[rest integerValue] inSection:0]] setHighlighted:YES animated:NO]; }
    else if([c isEqualToString:@"scroll"]){   // scroll <y>: Liste im aktuellen Tab bzw. der obersten geöffneten Ansicht
        UIViewController*vc=[[root valueForKey:@"_pushedStack"] lastObject]?:[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        UIScrollView*sv=[vc valueForKey:class_getInstanceVariable([vc class],"_table")?@"_table":@"_sc"];   // Startseite hat keine Tabelle
        [sv setContentOffset:CGPointMake(0,[rest floatValue]) animated:NO]; }
    else if([c isEqualToString:@"fr"]){   // wer ist gerade First Responder (bekommt die Sperrbildschirm-Tasten)?
        UIWindow*kw=[UIApplication sharedApplication].keyWindow; id fr=((id(*)(id,SEL))objc_msgSend)(kw,NSSelectorFromString(@"firstResponder"));
        MMLog(@"debug: firstResponder=%@ rootIsFR=%d presented=%@",fr?NSStringFromClass([fr class]):@"(keiner)",[root isFirstResponder],NSStringFromClass([root.presentedViewController class])); }
    else if([c isEqualToString:@"setbool"] && w.count>=3){ [[NSUserDefaults standardUserDefaults] setBool:[w[2] boolValue] forKey:w[1]]; [[NSUserDefaults standardUserDefaults] synchronize]; }   // setbool <key> 0|1
    else if([c isEqualToString:@"npswipe"] && w.count>=3){   // npswipe began|changed|ended <dx>: Wischen in der Leiste unten nachspielen
        if(!gFake) gFake=[[MMFakePan alloc] init];
        gFake.fakeView=[root valueForKey:@"_npBar"]; gFake.fakeT=CGPointMake([w[2] floatValue],0);
        gFake.fakeState=[w[1] isEqualToString:@"began"]?UIGestureRecognizerStateBegan:[w[1] isEqualToString:@"changed"]?UIGestureRecognizerStateChanged:UIGestureRecognizerStateEnded;
        ((void(*)(id,SEL,id))objc_msgSend)(root,NSSelectorFromString(@"npSwipe:"),gFake); }
    else if([c isEqualToString:@"seekend"]){ [MMAudio seekTo:[MMAudio duration]-2]; MMLog(@"debug: seek to %.0f of %.0f",[MMAudio currentTime],[MMAudio duration]); }   // Titelende testen
    else if([c isEqualToString:@"audiostate"]) MMLog(@"debug: playing=%d ended=%d t=%.1f dur=%.1f buffering=%d",[MMAudio isPlaying],[MMAudio hasEnded],[MMAudio currentTime],[MMAudio duration],[MMAudio isBuffering]);
    else if([c isEqualToString:@"sheetpan"] && w.count>=3){   // sheetpan began|changed|ended <dy>: offenes Menü nach unten ziehen
        UIView*host=root.view; UIViewController*pv=root; while(pv.presentedViewController){ pv=pv.presentedViewController; host=pv.view; }
        UIView*ov=nil; for(UIView*v in host.subviews) if(v.tag==MMSheetTag) ov=v;
        if(!gFake) gFake=[[MMFakePan alloc] init];
        gFake.fakeView=ov; gFake.fakeT=CGPointMake(0,[w[2] floatValue]);
        gFake.fakeState=[w[1] isEqualToString:@"began"]?UIGestureRecognizerStateBegan:[w[1] isEqualToString:@"changed"]?UIGestureRecognizerStateChanged:UIGestureRecognizerStateEnded;
        if(ov) ((void(*)(id,SEL,id))objc_msgSend)(ov,NSSelectorFromString(@"panelPan:"),gFake); MMLog(@"debug: sheetpan %@",ov?@"ok":@"kein Menü"); }
    else if([c isEqualToString:@"menu"]) [MMSongMenu showForTrack:root.nowPlaying];
    else if([c isEqualToString:@"tab"]) ((void(*)(id,SEL,NSInteger))objc_msgSend)(root,NSSelectorFromString(@"selectTab:"),[rest integerValue]);
    else if([c isEqualToString:@"search"]) [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDebugSearch" object:rest];
    else if([c isEqualToString:@"call"] && w.count>=3){
        if([w[1] isEqualToString:@"alert"]){ UIAlertView*a=nil; for(UIWindow*x in [UIApplication sharedApplication].windows){ a=findAlert(x); if(a) break; }
            NSInteger bi=[w[2] integerValue];   // wie ein echter Tipp: erst der Delegate, dann zu
            if([a.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [a.delegate alertView:a clickedButtonAtIndex:bi];
            [a dismissWithClickedButtonIndex:bi animated:NO]; MMLog(@"debug: alert %@",a?@"geklickt":@"nicht gefunden"); return; }
        id t=nil;
        if([w[1] isEqualToString:@"root"]) t=root;
        else if([w[1] isEqualToString:@"pushed"]) t=[[root valueForKey:@"_pushedStack"] lastObject];
        else if([w[1] isEqualToString:@"tab"]) t=[root valueForKey:@"_vcs"][[[root valueForKey:@"_sel"] integerValue]];
        else if([w[1] isEqualToString:@"player"]) t=root.presentedViewController;
        else if([w[1] isEqualToString:@"login"]) t=[UIApplication sharedApplication].keyWindow.rootViewController;   // Login-Bildschirm (vor der App-Oberfläche)
        else if([w[1] isEqualToString:@"modal"]) t=[UIApplication sharedApplication].keyWindow.rootViewController.presentedViewController;
        SEL s=NSSelectorFromString(w[2]);
        if([t respondsToSelector:s]){
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [t performSelector:s];
            #pragma clang diagnostic pop
        } else MMLog(@"debug: %@ kann %@ nicht",t,w[2]);
    }
    else if([c isEqualToString:@"layout"]) layoutDump();
    else if([c isEqualToString:@"orient"]){   // orient 1-4: Gerät drehen (privat, nur Debug): 1 hoch, 2 kopfüber, 3 quer links, 4 quer rechts
        ((void(*)(id,SEL,NSInteger))objc_msgSend)([UIDevice currentDevice],NSSelectorFromString(@"setOrientation:"),[rest integerValue]); }
    else if([c isEqualToString:@"authexpired"]) [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAuthExpired" object:nil];   // Anmeldung abgelaufen nachspielen
    else MMLog(@"debug: unbekannt");
}

@interface MMDebug : NSObject
@end
@implementation MMDebug
+ (void)load {
    gMainThread=mach_thread_self();
    // Test 4-Zoll: liegt Library/Riff/.tall, meldet der Bildschirm 320x568 -> alle Seiten bauen sich wie auf einem iPod touch 5 auf
    // ("shot" speichert dann das ganze 568er-Fenster; auf dem 3GS selbst ist unten etwas abgeschnitten)
    if([[NSFileManager defaultManager] fileExistsAtPath:MMPath(@".tall")]){
        method_setImplementation(class_getInstanceMethod([UIScreen class],@selector(bounds)), imp_implementationWithBlock(^CGRect(id s){ return CGRectMake(0,0,320,568); }));
        method_setImplementation(class_getInstanceMethod([UIScreen class],@selector(applicationFrame)), imp_implementationWithBlock(^CGRect(id s){ return CGRectMake(0,20,320,548); }));
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(poll) userInfo:nil repeats:YES];
    });
}
+ (void)poll {
    NSString*p=MMPath(@".cmd"); NSString*cmds=[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
    if(!cmds) return;
    [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
    for(NSString*l in [cmds componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){
        NSString*t=[l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if(t.length) run(t); }
}
@end
#endif
