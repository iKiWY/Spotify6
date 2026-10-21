#import <mach-o/dyld.h>
#import "MMDiagnosticsController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMTrackListController.h"
#import "MeshL10n.h"

// Jailbreak-Tweaks, die MobileSubstrate in diese App geladen hat (nur die können ihr Netz oder ihre Anzeige beeinflussen)
static NSString* loadedTweaks(void) {
    NSMutableArray*names=[NSMutableArray array];
    for(uint32_t i=0;i<_dyld_image_count();i++){ const char*p=_dyld_get_image_name(i); if(!p) continue;
        NSString*path=[NSString stringWithUTF8String:p];
        if([path rangeOfString:@"/MobileSubstrate/DynamicLibraries/"].location==NSNotFound) continue;
        [names addObject:[[path lastPathComponent] stringByDeletingPathExtension]]; }
    [names sortUsingSelector:@selector(caseInsensitiveCompare:)];
    return names.count?[names componentsJoinedByString:@", "]:@"none";
}

@implementation MMDiagnosticsController {
    UITextView *_text;
    UIButton *_testBtn, *_copyBtn;
    NSMutableArray *_test;   // Zeilen des Verbindungstests (nil = noch nicht gelaufen)
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34);
    [SpotTheme styleBackButton:back]; back.titleLabel.font=[UIFont systemFontOfSize:14];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(90,8,W-180,34)]; nav.text=L(@"Debug info"); nav.font=[UIFont boldSystemFontOfSize:16];
    nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; nav.backgroundColor=[UIColor clearColor]; [self.view addSubview:nav];
    UIButton*copy=[UIButton buttonWithType:UIButtonTypeCustom]; copy.frame=CGRectMake(W-72,8,64,34); _copyBtn=copy;
    [copy setTitle:L(@"Copy") forState:UIControlStateNormal]; [copy setTitleColor:[SpotTheme green] forState:UIControlStateNormal];
    copy.titleLabel.font=[UIFont boldSystemFontOfSize:15]; [copy addTarget:self action:@selector(copyText) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:copy];

    // Verbindungstest: prüft Netz, Spotify-Server/Ports, Song-Schlüssel und Download, jeweils mit Zeitlimit
    _testBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _testBtn.frame=CGRectMake(16,50,W-32,36); _testBtn.layer.cornerRadius=18;
    _testBtn.backgroundColor=[SpotTheme ink]; _testBtn.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    [_testBtn setTitle:L(@"Run connection test") forState:UIControlStateNormal]; [_testBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_testBtn addTarget:self action:@selector(runTest) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_testBtn];
    if([SpotTheme ios6]){ _testBtn.backgroundColor=[UIColor clearColor]; [_testBtn setBackgroundImage:[SpotTheme glossyImage:[SpotTheme green] radius:10] forState:UIControlStateNormal];   // grüner Glanzknopf
        [_testBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [_testBtn setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal]; _testBtn.titleLabel.shadowOffset=CGSizeMake(0,-1); }

    _text=[[UITextView alloc] initWithFrame:CGRectMake(0,94,W,H-94)];
    _text.editable=NO; _text.backgroundColor=[SpotTheme bg]; _text.textColor=[SpotTheme ink];
    _text.font=[UIFont fontWithName:@"Courier" size:10]; _text.contentInset=UIEdgeInsetsMake(0,0,MMPageBottomInset(90),0);
    _text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_text];
    _text.text=[self report];
    [SpotTheme skinPage:self.view];   // auch vom Anmeldebildschirm aus (ohne App-Oberfläche)
    MMAutoMask(self.view);   // iPad: Unteransichten folgen der Breite beim Drehen
}
- (NSString *)report {
    NSDictionary*info=[[NSBundle mainBundle] infoDictionary];
    NSDateFormatter*df=[[NSDateFormatter alloc] init]; df.dateFormat=@"yyyy-MM-dd HH:mm";
    NSMutableString*r=[NSMutableString string];
    // Cydia-Paket (z.B. 1.2.1-1): schreibt ipainstall bei der Installation in den App-Ordner; fehlt bei Installation per USB
    NSString*pkg=[[NSString stringWithContentsOfFile:MMPath(@"package-version") encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [r appendFormat:@"Spotify6 %@%@ · %@ · iOS %@\n",info[@"CFBundleShortVersionString"]?:@"?",pkg.length?[NSString stringWithFormat:@" (package %@)",pkg]:@"",[MMSpotify deviceModel],[UIDevice currentDevice].systemVersion];
    [r appendFormat:@"Account: %@ · Country: %@\n",[MMSpotify productType]?:@"unknown",[MMSpotify country]?:@"?"];
    [r appendFormat:@"Song keys: %@\n",[MMSpotify keyStatus]];
    [r appendFormat:@"Network: %@ · Free: %@\n",[MMSpotify networkReachable]?@"online":@"offline",[MMTrackListController fmtBytes:[MMSpotify freeDiskBytes]]];
    [r appendFormat:@"Tweaks in the app: %@\n",loadedTweaks()];
    [r appendFormat:@"Time: %@\n\n",[df stringFromDate:[NSDate date]]];
    if(_test){ [r appendString:@"--- Connection test ---\n"]; [r appendString:[_test componentsJoinedByString:@"\n"]]; [r appendString:@"\n\n--- Log ---\n"]; }
    NSString*log=[MMSpotify diagnosticLog];
    [r appendString:log.length?log:L(@"(no log lines yet: play a song, then open this page again)")];
    return r;
}
- (void)runTest {
    _test=[NSMutableArray arrayWithObject:L(@"running … (up to about a minute)")];
    _testBtn.enabled=NO; _testBtn.alpha=0.5; _text.text=[self report]; [_text setContentOffset:CGPointZero animated:NO];
    [MMSpotify runConnectionTest:^(NSString*l){
        if(_test.count==1 && [_test[0] hasPrefix:@"running"]) [_test removeAllObjects];
        [_test addObject:l]; _text.text=[self report];
    } done:^{ _testBtn.enabled=YES; _testBtn.alpha=1; _text.text=[self report]; }];
}
- (void)copyText {
    [UIPasteboard generalPasteboard].string=_text.text;
    if(!self.presentingViewController){ [[MMRootController shared] showDownloadMessage:L(@"Copied")]; return; }
    [_copyBtn setTitle:@"✓" forState:UIControlStateNormal];   // vom Login-Bildschirm aus gibt es die Meldeleiste noch nicht
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [_copyBtn setTitle:L(@"Copy") forState:UIControlStateNormal]; });
}
// Vom Login-Bildschirm wird die Seite als Vollbild gezeigt (noch keine App-Oberfläche), sonst als Seite im Inhaltsbereich
- (void)close { if(self.presentingViewController) [self dismissViewControllerAnimated:YES completion:nil]; else [[MMRootController shared] popContent]; }
@end
