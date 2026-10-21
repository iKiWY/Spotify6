#import "MMRootController.h"
#import "SpotTheme.h"
#import "MMStartController.h"
#import "MMSearchController.h"
#import "MMBrowseController.h"
#import "MMLibraryController.h"
#import "MMPlayerController.h"
#import "MMSpotify.h"
#import "MMSheet.h"
#import "MMCoverFlowView.h"
#import "MMKeepAlive.h"
#import "MMAudio.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMHistory.h"
#import "MMQueueController.h"
#import "MMLayout.h"
#import "MMPadSidebar.h"
#import "MMPadPlayerBar.h"
#import "MMTrackListController.h"
#import "MMSettingsController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

static MMRootController *gRoot;

@interface MMRootController () <AVAudioSessionDelegate, UITabBarDelegate>   // iOS 5: Unterbrechungen kommen über den Session-Delegate
@end

@implementation MMRootController {
    UIView *_content, *_tabBar, *_npBar, *_npCover; UITabBar *_sysTabBar;
    UILabel *_npTitle, *_npArtist;
    UIButton *_npPlay;
    UIActivityIndicatorView *_npSpinner;
    NSArray *_tabs; NSMutableArray *_tabBtns, *_vcs;
    NSInteger _sel;
    NSString *_curId, *_curTitle, *_curArtist, *_curCover;
    __weak MMPlayerController *_player;
    NSArray *_queue; NSInteger _queueIdx;
    NSArray *_origQueue;   // Reihenfolge vor dem Mischen
    NSArray *_userQueue;   // von Hand eingereiht ("Als Nächstes"/"Zur Warteschlange"): läuft vor dem Rest der Liste
    BOOL _fromUser;        // der laufende Titel kam aus _userQueue (die Liste steht dann noch bei _queueIdx)
    NSDictionary *_context;   // woher die Liste kommt {type,id,name,images} (für "Zuletzt gehört" auf der Startseite); nil = Suche o. ä.
    BOOL _shuffle;
    NSInteger _repeatMode;
    MMCoverFlowView *_cflow; BOOL _cflowManual;   // Cover Flow (quer); manual = über Menü geöffnet   // iPod-Modus (liegt über allem, Wiedergabe läuft hier weiter)
    double _resumePos, _pendingSeek; BOOL _needsResume;
    NSTimeInterval _playStartTS;   // wann die aktuelle Wiedergabe tatsächlich startete (gegen Finish-Kaskade)
    UIView *_dlBar, *_dlProg; UILabel *_dlLbl;   // globale Offline-Download-Leiste
    NSTimeInterval _dlSince; BOOL _dlCompact;      // nach ein paar Sekunden nur noch dünne Linie
    NSMutableArray *_pushedStack;                 // im Inhaltsbereich geöffnete Ansichten (Titelliste, Artist, Album …), oberste zuletzt
    NSString *_curAlbumId, *_curAlbum, *_curArtistId;   // zum aktuellen Titel (aus den Metadaten), für Album-/Artist-Seite
    CGFloat _tabH, _npH;
    MMPadSidebar *_sidebar; MMPadPlayerBar *_padBar;   // iPad: Seitenleiste + Player-Leiste (statt Tab- und Now-Playing-Leiste)
    BOOL _loading;                                     // Titel lädt (Kreisel statt Play)
    MMQueueController *_queueDock; UIView *_queueEdge;
    UIView *_npLoad;                                   // iPhone: grüne Ladelinie oben an der Now-Playing-Leiste  // iPad quer: Warteschlange als Spalte rechts (Inhalt wird schmaler)
}
+ (instancetype)shared { return gRoot; }
// Volle Bildschirmhöhe: die Statusleiste liegt über den oberen 20 pt (Inhalt beginnt darunter).
// So ändert Ein-/Ausblenden der Statusleiste (iPod-Modus, Cover Flow) nie das Layout.
- (id)init { if((self=[super init])) self.wantsFullScreenLayout=YES; return self; }
// Drehen: iPad in alle Richtungen (das ganze Layout dreht mit), iPhone bleibt hochkant (quer = Cover Flow, siehe orientationChanged)
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return MMShouldAutorotate(o); }   // iOS 5
- (BOOL)shouldAutorotate { return MMIsPad(); }                                                                 // iOS 6
MM_IOS6_BEGIN
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return (UIInterfaceOrientationMask)MMSupportedOrientations(); }
MM_IOS6_END
- (CGRect)contentBounds { return _content.bounds; }

// ---- iPad: Seitenleiste links, Inhalt rechts daneben, Player-Leiste unten über die ganze Breite ----
- (void)buildPadShell {
    _sidebar=[[MMPadSidebar alloc] initWithFrame:CGRectMake(0,MMStatusH,MMPadSidebarW,self.view.bounds.size.height-MMStatusH-MMPadBarH)];
    __weak MMRootController*ws=self; _sidebar.onSelect=^(NSString*key){ [ws sidebarSelect:key]; };
    [_sidebar setShowsCoverFlow:[MMRootController coverFlowOnRotate]];   // iPad: dieselbe Einstellung blendet den Eintrag aus
    [self.view addSubview:_sidebar];
    _padBar=[[MMPadPlayerBar alloc] initWithFrame:CGRectMake(0,self.view.bounds.size.height-MMPadBarH,self.view.bounds.size.width,MMPadBarH)];
    [self.view addSubview:_padBar];
    // Cover groß in die Seitenleiste und zurück (bleibt über Neustarts gemerkt)
    _padBar.onCoverToSidebar=^{ [ws setCoverInSidebar:YES]; };
    _sidebar.onCoverBack=^{ [ws setCoverInSidebar:NO]; };
    [self layoutPad];
}
- (BOOL)coverInSidebar { return [[NSUserDefaults standardUserDefaults] boolForKey:@"padCoverInSidebar"]; }
- (void)setCoverInSidebar:(BOOL)on {
    if(on && !_curCover.length) return;   // nichts geladen: kein leeres Feld in die Seitenleiste
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"padCoverInSidebar"];
    [_padBar setCoverHidden:on];
    if(on) [_sidebar showCover:_curCover animated:YES]; else [_sidebar hideCoverAnimated:YES];
}
// ---- iPad quer: Warteschlange schiebt sich von rechts als Spalte herein, der Inhalt rückt zusammen ----
#define MMQueueDockW 320
- (void)toggleQueueDock {
    if(_queueDock){ [self closeQueueDock]; return; }
    MMQueueController*q=[[MMQueueController alloc] init];
    __weak MMRootController*ws=self; q.onClose=^{ [ws closeQueueDock]; };
    [self addChildViewController:q];
    CGFloat W=self.view.bounds.size.width, ch=self.view.bounds.size.height-MMStatusH-MMPadBarH;
    q.view.frame=CGRectMake(W,MMStatusH,MMQueueDockW,ch);   // startet rechts außerhalb
    _queueEdge=[[UIView alloc] initWithFrame:CGRectMake(0,0,1,ch)]; _queueEdge.backgroundColor=[SpotTheme line];
    _queueEdge.autoresizingMask=UIViewAutoresizingFlexibleHeight; [q.view addSubview:_queueEdge];
    [q viewWillAppear:YES]; [self.view addSubview:q.view]; [q didMoveToParentViewController:self];
    _queueDock=q;
    [UIView animateWithDuration:0.3 animations:^{ [self layoutPad]; }];
}
- (void)closeQueueDock {
    MMQueueController*q=_queueDock; if(!q) return; _queueDock=nil;
    [q willMoveToParentViewController:nil];
    [UIView animateWithDuration:0.3 animations:^{ [self layoutPad]; q.view.frame=CGRectOffset(q.view.frame,MMQueueDockW,0); }
                     completion:^(BOOL f){ [q.view removeFromSuperview]; [q removeFromParentViewController]; }];
}
- (void)layoutPad {
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height, ch=H-MMStatusH-MMPadBarH;
    if(_queueDock && W<H){ [self closeQueueDock]; return; }   // hochkant ist kein Platz für zwei Spalten
    CGFloat dock=_queueDock?MMQueueDockW:0;
    _sidebar.frame=CGRectMake(0,MMStatusH,MMPadSidebarW,ch);
    _content.frame=CGRectMake(MMPadSidebarW,MMStatusH,W-MMPadSidebarW-dock,ch);
    if(_queueDock) _queueDock.view.frame=CGRectMake(W-dock,MMStatusH,dock,ch);
    _padBar.frame=CGRectMake(0,H-MMPadBarH,W,MMPadBarH);
    if(!_dlBar.hidden) [self layoutDlBar];
    [self placePadCoverFlow];
    if(_vcs.count) [self fitPage:_vcs[_sel]];
    for(UIViewController*vc in _pushedStack) [self fitPage:vc];
}
// Seite auf den Inhaltsbereich setzen; hat sich die Breite geändert (iPad gedreht), baut sie ihren Inhalt neu auf
- (void)fitPage:(UIViewController *)vc {
    BOOL wider=vc.isViewLoaded && vc.view.bounds.size.width!=_content.bounds.size.width;
    vc.view.frame=_content.bounds;
    if(wider && [vc respondsToSelector:@selector(relayoutForSize:)]) [(id<MMRelayout>)vc relayoutForSize:_content.bounds.size];
}
- (void)viewWillLayoutSubviews { [super viewWillLayoutSubviews]; if(MMIsPad()) [self layoutPad]; }   // auch nach dem Drehen
// Unter dem Vollbild-Player gedreht: beim Zurückkommen gibt es nicht immer einen eigenen Layout-Durchgang -> selbst neu anordnen
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; if(MMIsPad()) [self layoutPad]; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if(MMIsPad()) [self layoutPad]; if(!_pushedStack.count) [self tabShown]; }   // auch nach dem Vollbild-Player
- (void)padBarRefresh {
    [_queueDock reload];
    [_padBar showTitle:_curTitle artist:_curArtist coverURL:_curCover];
    if(_sidebar && [self coverInSidebar] && _curCover.length){ [_padBar setCoverHidden:YES]; [_sidebar showCover:_curCover animated:NO]; }
    [_padBar setPlaying:[MMAudio isPlaying] loading:_loading];
}
- (void)sidebarSelect:(NSString *)key {
    if(self.presentedViewController) [self dismissViewControllerAnimated:NO completion:nil];
    NSUInteger tab=[_tabs indexOfObject:key];
    if(tab!=NSNotFound){ [self selectTab:tab]; return; }
    if([key isEqualToString:@"coverflow"]){ [self showCoverFlow]; return; }
    UIViewController*vc=nil;
    if([key isEqualToString:@"settings"]) vc=[[MMSettingsController alloc] init];
    else if([key isEqualToString:@"liked"]) vc=[[MMTrackListController alloc] initWithTitle:L(@"Liked Songs") path:@"me/tracks?market=from_token&limit=50"];
    else if([key hasPrefix:@"playlist:"]) vc=[[MMTrackListController alloc] initWithTitle:[_sidebar nameForKey:key]?:L(@"Playlist")
                                                      path:[NSString stringWithFormat:@"playlists/%@?market=from_token",[key substringFromIndex:9]]];
    if(!vc) return;
    [self popContentImmediate]; [self pushContent:vc]; [_sidebar setSelectedKey:key];
}

// Abmelden: alles vom Konto löschen und Spotify6 beenden. Beenden ist Absicht: so bleibt garantiert nichts vom alten
// Konto im Speicher (Cover, Listen, Warteschlange); beim nächsten Öffnen kommt die Anmeldung.
// Skin wechseln: Zustand sichern, alte Oberfläche abmelden (keine doppelten Reaktionen auf Benachrichtigungen),
// neue aufbauen und überblenden; danach wieder in den Einstellungen. Ein Beenden der App hinterließ beim schnellen Wiederöffnen einen schwarzen Bildschirm.
+ (void)switchSkin:(NSString *)skin {
    MMRootController*old=gRoot; UIWindow*w=old.view.window; if(!old || !w) return;
    // kleines Fenster mit Kreisel, bis die neue Oberfläche steht (nur Kreisel: das Fenster dreht sich auf dem iPad nicht mit)
    UIView*hud=[[UIView alloc] initWithFrame:CGRectMake(0,0,90,90)]; hud.center=CGPointMake(CGRectGetMidX(w.bounds),CGRectGetMidY(w.bounds));
    hud.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    hud.backgroundColor=[UIColor colorWithWhite:0 alpha:0.75]; hud.layer.cornerRadius=12;
    UIActivityIndicatorView*sp=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    sp.center=CGPointMake(45,45); [sp startAnimating]; [hud addSubview:sp];
    hud.alpha=0; [w addSubview:hud]; [UIView animateWithDuration:0.15 animations:^{ hud.alpha=1; }];
    // erst im nächsten Durchlauf umbauen, damit das Fenster vorher zu sehen ist (der Umbau hält den Hauptthread kurz an; der Kreisel dreht weiter)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [old saveState];
        [SpotTheme setSkin:skin]; [SpotTheme applySkin];
        [old retire];
        MMRootController*n=[[MMRootController alloc] init];   // setzt gRoot
        [UIView transitionWithView:w duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowAnimatedContent
                        animations:^{ w.rootViewController=n; [w bringSubviewToFront:hud]; }
                        completion:^(BOOL f){ [w bringSubviewToFront:hud];
                            [UIView animateWithDuration:0.25 delay:0.25 options:0 animations:^{ hud.alpha=0; } completion:^(BOOL g){ [hud removeFromSuperview]; }]; }];
        if(!MMIsPad()) [n selectTab:3];   // zurück in die Einstellungen (iPhone: über die Bibliothek)
        [n pushContent:[[NSClassFromString(@"MMSettingsController") alloc] init]];
    });
}
- (void)retire {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    MM_IOS6_BEGIN if([AVAudioSession sharedInstance].delegate==(id)self) [AVAudioSession sharedInstance].delegate=nil; MM_IOS6_END   // iOS 5: Unterbrechungen gehen an die neue Oberfläche
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
+ (void)confirmLogout {
    [MMSheet showIn:gRoot.view title:L(@"Log out?") subtitle:L(@"Removes your Spotify login, all downloads, playlists and settings from this iPhone. Spotify6 closes afterwards.")
            options:@[L(@"Log out and delete data")] done:^(NSInteger i){
        if(i!=0) return;
        // Sofort sichtbar: abgedunkelt, Kreisel, Text; alles darunter nicht mehr bedienbar
        UIView*host=gRoot.view.window ?: gRoot.view;
        UIView*cover=[[UIView alloc] initWithFrame:host.bounds];
        cover.backgroundColor=[UIColor colorWithWhite:0 alpha:0.82f]; cover.alpha=0;
        cover.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        UIActivityIndicatorView*spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        spin.center=CGPointMake(host.bounds.size.width/2, host.bounds.size.height/2-20); [spin startAnimating]; [cover addSubview:spin];
        UILabel*lab=[[UILabel alloc] initWithFrame:CGRectMake(20, host.bounds.size.height/2+20, host.bounds.size.width-40, 24)];
        lab.text=L(@"Logging out …"); lab.textColor=[UIColor whiteColor]; lab.backgroundColor=[UIColor clearColor];
        lab.textAlignment=NSTextAlignmentCenter; lab.font=[UIFont boldSystemFontOfSize:17]; [cover addSubview:lab];
        [host addSubview:cover];
        [UIView animateWithDuration:0.25 animations:^{ cover.alpha=1; }];
        [MMSpotify logoutCompletion:^{
            [spin stopAnimating]; spin.hidden=YES;
            UILabel*check=[[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 60)];
            check.center=spin.center; check.text=@"✓"; check.textColor=[UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
            check.backgroundColor=[UIColor clearColor]; check.textAlignment=NSTextAlignmentCenter; check.font=[UIFont boldSystemFontOfSize:44];
            [cover addSubview:check];
            lab.text=L(@"Logged out");
            // Normale Schließen-Animation zum Home-Bildschirm, danach den Prozess beenden (frischer Start = Anmeldung)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIApplication*app=[UIApplication sharedApplication];
                if([app respondsToSelector:@selector(suspend)]) [app performSelector:@selector(suspend)];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
            });
        }];
    }];
}

- (void)loadView {
    gRoot = self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(trackFinished) name:@"MMAudioDidFinish" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveState) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveState) name:UIApplicationWillTerminateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlProgress:) name:@"MMDownloadProgress" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlDone:) name:@"MMDownloadDone" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlFull:) name:@"MMDownloadFull" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlError:) name:@"MMDownloadError" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(trackLoadProgress:) name:MMTrackLoadProgress object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(streamFailed) name:@"MMAudioStreamFailed" object:nil];
    // Auto/Bluetooth: Fernsteuer-Tasten + Unterbrechungen (sonst „streitet" es mit der Stock-Musik-App)
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    MM_IOS6_BEGIN
    if(&AVAudioSessionInterruptionNotification) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    else [AVAudioSession sharedInstance].delegate=self;   // iOS 5 (Notification gibt es erst ab 6; der Delegate ist dort veraltet)
    MM_IOS6_END
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    _tabH=49; _npH=52; CGFloat tabH=_tabH, npH=_npH;

    _content = [[UIView alloc] initWithFrame:CGRectMake(0,MMStatusH,W,H-tabH-MMStatusH)];
    [self.view addSubview:_content];

    // Child-VCs
    _tabs = @[@"home",@"browse",@"search",@"library"];
    NSArray *titles=@[L(@"Home"),L(@"Browse"),L(@"Search"),L(@"Library")];
    _vcs=[NSMutableArray arrayWithObjects:[[MMStartController alloc] init],[[MMBrowseController alloc] init],[[MMSearchController alloc] init],[[MMLibraryController alloc] init],nil];
    _pushedStack=[NSMutableArray array];

    if(!MMIsPad()){   // iPhone: Now-Playing-Leiste (iPad: Player-Leiste, siehe buildPadShell)
    // Now-Playing-Leiste
    _npBar=[[UIView alloc] initWithFrame:CGRectMake(0,H-tabH-npH,W,npH)];
    _npBar.backgroundColor=[SpotTheme ios6]?[UIColor colorWithPatternImage:[SpotTheme toolbarImage:npH]]:[UIColor colorWithRed:0.14 green:0.14 blue:0.16 alpha:1];
    UIView*npl=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,0.5f)]; npl.backgroundColor=[SpotTheme bg]; [_npBar addSubview:npl];
    _npCover=[[UIView alloc] initWithFrame:CGRectMake(8,8,36,36)]; _npCover.backgroundColor=[SpotTheme card]; _npCover.layer.cornerRadius=3; _npCover.clipsToBounds=YES; [_npBar addSubview:_npCover];
    _npTitle=[[UILabel alloc] initWithFrame:CGRectMake(54,9,W-54-90,18)]; _npTitle.font=[UIFont boldSystemFontOfSize:13]; _npTitle.textColor=[SpotTheme chromeInk]; _npTitle.backgroundColor=[UIColor clearColor]; [_npBar addSubview:_npTitle];
    _npArtist=[[UILabel alloc] initWithFrame:CGRectMake(54,27,W-54-90,16)]; _npArtist.font=[SpotTheme sub]; _npArtist.textColor=[SpotTheme ios6]?[UIColor colorWithWhite:0.7 alpha:1]:[SpotTheme muted]; _npArtist.backgroundColor=[UIColor clearColor]; [_npBar addSubview:_npArtist];
    UIButton*npTap=[UIButton buttonWithType:UIButtonTypeCustom]; npTap.frame=_npBar.bounds; [npTap addTarget:self action:@selector(openPlayer) forControlEvents:UIControlEventTouchUpInside]; [_npBar addSubview:npTap];
    // Warteschlange links neben Play/Pause (öffnet dieselbe Ansicht wie im Player)
    UIButton*npQ=[UIButton buttonWithType:UIButtonTypeCustom]; npQ.frame=CGRectMake(W-84,8,36,36);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20,16),NO,0); [[SpotTheme chromeInk] setFill];
    for(int i=0;i<3;i++){ UIRectFill(CGRectMake(5,1+i*6,15,2)); UIRectFill(CGRectMake(0,1+i*6,2,2)); }
    [npQ setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [npQ addTarget:self action:@selector(openQueue) forControlEvents:UIControlEventTouchUpInside]; [_npBar addSubview:npQ];
    _npPlay=[UIButton buttonWithType:UIButtonTypeCustom]; _npPlay.frame=CGRectMake(W-44,8,36,36);
    [self drawNpPlay];
    [_npPlay addTarget:self action:@selector(npTogglePlay) forControlEvents:UIControlEventTouchUpInside];
    [_npBar addSubview:_npPlay];
    _npSpinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _npSpinner.frame=CGRectMake(W-44,8,36,36); _npSpinner.hidesWhenStopped=YES; [_npBar addSubview:_npSpinner];
    _npLoad=[[UIView alloc] initWithFrame:CGRectMake(0,0,0,2)]; _npLoad.backgroundColor=[SpotTheme green]; _npLoad.hidden=YES; [_npBar addSubview:_npLoad];
    _npBar.hidden=YES; _npBar.clipsToBounds=YES;
    [self.view addSubview:_npBar];
    // waagrecht wischen: Cover + Titel folgen dem Finger; nach links = nächster, nach rechts = vorheriger Titel (Play-Knopf bleibt stehen)
    UIPanGestureRecognizer*npSwipe=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(npSwipe:)];
    npSwipe.delegate=(id<UIGestureRecognizerDelegate>)self; [_npBar addGestureRecognizer:npSwipe];

    }
    // globale Offline-Download-Leiste - immer sichtbar wenn aktiv, direkt über der Now-Playing-Leiste
    _dlBar=[[UIView alloc] initWithFrame:CGRectMake(0,H-tabH-npH-24,W,24)];
    _dlBar.backgroundColor=[SpotTheme ios6]?[UIColor colorWithPatternImage:[SpotTheme toolbarImage:24]]:[UIColor colorWithRed:0.10 green:0.10 blue:0.11 alpha:1];
    _dlLbl=[[UILabel alloc] initWithFrame:CGRectMake(12,0,W-24,22)]; _dlLbl.font=[UIFont boldSystemFontOfSize:11]; _dlLbl.textColor=[SpotTheme chromeInk]; _dlLbl.textAlignment=NSTextAlignmentCenter; [_dlBar addSubview:_dlLbl];
    _dlProg=[[UIView alloc] initWithFrame:CGRectMake(0,22,0,2)]; _dlProg.backgroundColor=[SpotTheme green]; [_dlBar addSubview:_dlProg];
    _dlBar.hidden=YES; [self.view addSubview:_dlBar];

    if(!MMIsPad()){
    // Tab-Leiste
    _tabBar=[[UIView alloc] initWithFrame:CGRectMake(0,H-tabH,W,tabH)];
    _tabBar.backgroundColor=[SpotTheme ios6]?[UIColor colorWithPatternImage:[SpotTheme toolbarImage:tabH]]:[SpotTheme bar];
    UIView*tl=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,0.5f)]; tl.backgroundColor=[SpotTheme ios6]?[UIColor blackColor]:[SpotTheme line]; [_tabBar addSubview:tl];
    _tabBtns=[NSMutableArray array]; NSUInteger nTabs=_tabs.count; CGFloat tw=W/nTabs;
    if([SpotTheme ios6]){   // iOS 6: echte Tab-Leiste in der Farbe der Kopfleiste (wie WhatsApp6), gefüllte Symbole
        _sysTabBar=[[UITabBar alloc] initWithFrame:_tabBar.bounds]; _sysTabBar.autoresizingMask=UIViewAutoresizingFlexibleWidth;
        _sysTabBar.backgroundImage=[SpotTheme tabBarImage:_tabBar.bounds.size]; _sysTabBar.selectionIndicatorImage=[SpotTheme tabSelectionImage:CGSizeMake(floor(W/nTabs)-4,tabH)];
        _sysTabBar.delegate=self;
        NSMutableArray*items=[NSMutableArray array];
        NSDictionary*(^txt)(UIColor*)=^NSDictionary*(UIColor*c){ return @{UITextAttributeTextColor:c,UITextAttributeTextShadowColor:[UIColor colorWithWhite:0 alpha:0.45],
            UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,-1)],UITextAttributeFont:[UIFont boldSystemFontOfSize:10]}; };
        for(NSUInteger i=0;i<nTabs;i++){ UITabBarItem*it=[[UITabBarItem alloc] initWithTitle:titles[i] image:nil tag:i];   // eigene Farben statt der Systemtönung
            [it setFinishedSelectedImage:[SpotTheme tabGlyph:_tabs[i] selected:YES] withFinishedUnselectedImage:[SpotTheme tabGlyph:_tabs[i] selected:NO]];
            [it setTitleTextAttributes:txt([UIColor colorWithRed:0.82 green:0.89 blue:0.84 alpha:1]) forState:UIControlStateNormal];
            [it setTitleTextAttributes:txt([UIColor whiteColor]) forState:UIControlStateSelected];
            [items addObject:it]; }
        _sysTabBar.items=items; [_tabBar addSubview:_sysTabBar]; nTabs=0;   // keine eigenen Knöpfe
    }
    for(NSUInteger i=0;i<nTabs;i++){
        UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake(i*tw,0,tw,tabH); b.tag=i;
        [b addTarget:self action:@selector(tapTab:) forControlEvents:UIControlEventTouchUpInside];
        if([SpotTheme ios6]){ UIImageView*hl=[[UIImageView alloc] initWithFrame:CGRectInset(b.bounds,2,2)]; hl.image=[SpotTheme tabHighlightImage]; hl.tag=97; hl.hidden=YES; [b addSubview:hl]; }   // iOS 6: graue Fläche hinter dem gewählten Tab
        UIImageView*iv=[[UIImageView alloc] initWithFrame:CGRectMake((tw-24)/2,8,24,24)]; iv.tag=99; [b addSubview:iv];
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(0,33,tw,12)]; l.text=titles[i]; l.font=[SpotTheme ios6]?[UIFont boldSystemFontOfSize:10]:[SpotTheme tab]; l.textAlignment=NSTextAlignmentCenter; l.backgroundColor=[UIColor clearColor]; l.tag=98; [b addSubview:l];
        [_tabBar addSubview:b]; [_tabBtns addObject:b];
    }
    [self.view addSubview:_tabBar];
    } else [self buildPadShell];
    [self selectTab:0];
    [self restoreState];
    [MMSpotify startNetworkWatch];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkChanged:) name:@"MMNetworkChanged" object:nil];
    // Hinweise, warum nichts spielt (je einmal pro App-Start, kommt aus MMSpotify)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(portsBlocked) name:@"MMSpotifyPortsBlocked" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notPremium) name:@"MMSpotifyNotPremium" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keysRefused) name:@"MMSpotifyKeysRefused" object:nil];
    [MMKeepAlive start];   // Offline-Downloads laufen im Hintergrund weiter (auch bei gesperrtem Bildschirm)
    // iPod quer drehen -> Cover Flow
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIDeviceOrientationDidChangeNotification object:nil];
    // Offline-Playlists, deren Download unterbrochen wurde, automatisch weiterladen
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [MMSpotify resumeOfflineDownloads]; });
    // Cover aller Playlists im Hintergrund auf die Platte (Cover Flow + Listen sofort, auch offline)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [MMCovers precacheLibrary]; });
}

// ---- Resume: letzten Zustand speichern/wiederherstellen ----
- (void)saveState {
    NSUserDefaults*u=[NSUserDefaults standardUserDefaults];
    if(_queue.count){
        NSMutableArray*q=[NSMutableArray array];
        for(NSDictionary*t in _queue) [q addObject:@{@"id":t[@"id"]?:@"",@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""}];   // Cover mitspeichern
        [u setObject:q forKey:@"spQueue"]; [u setInteger:_queueIdx forKey:@"spIdx"];
    } else [u removeObjectForKey:@"spQueue"];
    if(_shuffle && _origQueue.count){
        NSMutableArray*o=[NSMutableArray array];
        for(NSDictionary*t in _origQueue) [o addObject:@{@"id":t[@"id"]?:@"",@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""}];
        [u setObject:o forKey:@"spOrigQueue"];
    } else [u removeObjectForKey:@"spOrigQueue"];
    NSMutableArray*uq=[NSMutableArray array];
    for(NSDictionary*t in _userQueue) [uq addObject:@{@"id":t[@"id"]?:@"",@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""}];
    [u setObject:uq forKey:@"spUserQueue"]; [u setBool:_fromUser forKey:@"spFromUser"];
    [u setBool:_shuffle forKey:@"spShuffle"]; [u setInteger:_repeatMode forKey:@"spRepeat"];
    // für das Mitteilungszentrum-Widget ("Playing from …"): SpringBoard reicht eigene Felder der Now-Playing-Infos nicht weiter
    NSString*ctx=_fromUser?nil:([_context[@"type"] isEqual:@"liked"]?L(@"Liked Songs"):([_context[@"name"] isKindOfClass:[NSString class]]?_context[@"name"]:nil));
    if(ctx.length) [u setObject:ctx forKey:@"spContext"]; else [u removeObjectForKey:@"spContext"];
    NSString*cov=_curCover;
    if(!cov.length && _queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) cov=_queue[_queueIdx][@"cover"];   // Fallback: aus Queue-Eintrag
    [u setObject:_curId?:@"" forKey:@"spId"]; [u setObject:_curTitle?:@"" forKey:@"spTitle"];
    [u setObject:_curArtist?:@"" forKey:@"spArtist"]; [u setObject:cov?:@"" forKey:@"spCover"];
    double pos=[MMAudio currentTime]; [u setDouble:(pos>0?pos:0) forKey:@"spPos"];
    [u synchronize];
}
- (void)restoreState {
    NSUserDefaults*u=[NSUserDefaults standardUserDefaults];
    _shuffle=[u boolForKey:@"spShuffle"]; _repeatMode=[u integerForKey:@"spRepeat"];
    NSString*cid=[u stringForKey:@"spId"]; if(!cid.length) return;
    _queue=[u objectForKey:@"spQueue"]?:@[]; _queueIdx=[u integerForKey:@"spIdx"];
    _origQueue=[u objectForKey:@"spOrigQueue"];
    _userQueue=[u objectForKey:@"spUserQueue"]?:@[]; _fromUser=[u boolForKey:@"spFromUser"];
    _curId=cid; _curTitle=[u stringForKey:@"spTitle"]; _curArtist=[u stringForKey:@"spArtist"]; _curCover=[u stringForKey:@"spCover"];
    if(!_curCover.length && _queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) _curCover=_queue[_queueIdx][@"cover"];   // Fallback aus Queue
    _resumePos=[u doubleForKey:@"spPos"]; _needsResume=YES;
    if([MMAudio duration]>0) _needsResume=NO;   // Skin-Wechsel: der Titel läuft noch (oder ist pausiert) -> Play/Pause gilt ihm, nicht dem Neuladen
    _npTitle.text=_curTitle; _npArtist.text=_curArtist; _npBar.hidden=NO; [self drawNpPlay];
    if(_curCover.length)[self loadNpCover:_curCover];
    NSString*rid=_curId;
    [MMSpotify fetchTrack:_curId completion:^(NSDictionary*info,NSString*e){   // Cover + Album/Artist nachladen (auch ohne Abspielen)
        if(![rid isEqualToString:_curId]) return;
        if(!_curCover.length && [info[@"cover"] isKindOfClass:[NSString class]] && [info[@"cover"] length]){ _curCover=info[@"cover"]; [self loadNpCover:_curCover]; }
        _curAlbumId=info[@"albumId"]; _curAlbum=info[@"album"]; _curArtistId=info[@"artistId"];
    }];
    [self prefetchNext];   // nächsten Track schon vorladen
}
- (void)resumePlayback {
    _needsResume=NO; _pendingSeek=_resumePos;
    if(!_fromUser && _queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) [self playCurrentInQueue];
    else [self playTrackId:_curId title:_curTitle artist:_curArtist cover:_curCover];
}

- (void)tapTab:(UIButton *)b { [self selectTab:b.tag]; }
- (void)tabBar:(UITabBar *)tb didSelectItem:(UITabBarItem *)it { [self selectTab:it.tag]; }
- (void)selectTab:(NSInteger)idx {
    [self popContentImmediate];   // offene Playlist schließen beim Tab-Wechsel
    [[_vcs[_sel] view] removeFromSuperview];
    _sel=idx;
    UIViewController*vc=_vcs[idx]; [self fitPage:vc]; [_content addSubview:vc.view]; [SpotTheme skinPage:vc.view]; [self tabShown];
    [_sidebar setSelectedKey:_tabs[idx]];
    if(_sysTabBar) _sysTabBar.selectedItem=_sysTabBar.items[idx];
    for(NSUInteger i=0;i<_tabBtns.count;i++){ UIButton*b=_tabBtns[i];
        BOOL on=((NSInteger)i==idx); [b viewWithTag:97].hidden=!on;
        UIColor*c=[SpotTheme ios6]?(on?[UIColor colorWithRed:0.40 green:0.86 blue:0.47 alpha:1]:[UIColor colorWithWhite:0.55 alpha:1]):(on?[SpotTheme ink]:[SpotTheme faint]);
        ((UIImageView*)[b viewWithTag:99]).image=MMTabIcon(_tabs[i],c,24);
        ((UILabel*)[b viewWithTag:98]).textColor=c; }
}

- (void)showNowPlayingTitle:(NSString *)title artist:(NSString *)artist {
    _npTitle.text=title; _npArtist.text=artist; _npBar.hidden=NO;
}

// ---- Auto / Bluetooth / Lockscreen-Fernsteuerung (kommt über MMApplication in main.m, unabhängig vom First Responder) ----
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if(event.type!=UIEventTypeRemoteControl) return;
    MMLog(@"remote: Taste %ld", (long)event.subtype);   // 100/101 Play/Pause, 103 Umschalten, 104/105 Weiter/Zurück
    switch(event.subtype){
        case UIEventSubtypeRemoteControlTogglePlayPause: [self npTogglePlay]; break;
        case UIEventSubtypeRemoteControlPlay:  [self playOrRestart]; break;
        case UIEventSubtypeRemoteControlPause: [MMAudio setPaused:YES]; [self drawNpPlay]; [self updateNowPlaying]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self playNext]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self playPrev]; break;
        default: break;
    }
}
- (void)audioInterruption:(NSNotification *)n {   // iOS 6 (nur dort registriert)
    MM_IOS6_BEGIN
    NSInteger type=[n.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
    if(type==AVAudioSessionInterruptionTypeBegan) [self interruptionBegan];
    else [self interruptionEndedResume:([n.userInfo[AVAudioSessionInterruptionOptionKey] integerValue] & AVAudioSessionInterruptionOptionShouldResume)!=0];
    MM_IOS6_END
}
- (void)beginInterruption { [self interruptionBegan]; }   // iOS 5
- (void)endInterruptionWithFlags:(NSUInteger)flags { [self interruptionEndedResume:(flags & AVAudioSessionInterruptionFlags_ShouldResume)!=0]; }
- (void)interruptionBegan { [MMAudio setPaused:YES]; [self drawNpPlay]; [self updateNowPlaying]; }
- (void)interruptionEndedResume:(BOOL)resume { if(resume){ [MMAudio setPaused:NO]; [self drawNpPlay]; [self updateNowPlaying]; } }
// Angetippter Titel lädt: wie weit er da ist (grün in der Leiste und im Player); -1 = fertig/aus
- (void)trackLoadProgress:(NSNotification *)n {
    if(![n.userInfo[@"id"] isEqual:_curId]) return;   // auch während er schon spielt (Wiedergabe während des Downloads)
    double f=[n.userInfo[@"frac"] doubleValue];
    [self showLoadProgress:(f>=1 && !_loading)?-1:f];   // ganz geladen und spielt: Balken weg
}
// Download brach ab, während der Titel schon spielte: am Ende des Geladenen stehen bleiben und Bescheid geben
- (void)streamFailed {
    [self showLoadProgress:-1]; [self drawNpPlay]; [self updateNowPlaying];
    [self showPlayError:@"CDN"];
}
- (void)showLoadProgress:(double)f {
    _npLoad.hidden=(f<0); if(f>=0) _npLoad.frame=CGRectMake(0,0,_npBar.bounds.size.width*MIN(1,f),2);
    [_padBar setLoadProgress:f]; [_player setLoadProgress:f];
}
- (void)updateNowPlaying {
    [self padBarRefresh];
    NSMutableDictionary*info=[NSMutableDictionary dictionary];
    if(_curTitle) info[MPMediaItemPropertyTitle]=_curTitle;
    if(_curArtist) info[MPMediaItemPropertyArtist]=_curArtist;
    double dur=[MMAudio duration], cur=[MMAudio currentTime];
    if(dur>0) info[MPMediaItemPropertyPlaybackDuration]=@(dur);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime]=@(cur>0?cur:0);
    info[MPNowPlayingInfoPropertyPlaybackRate]=@([MMAudio isPlaying]?1.0:0.0);
    UIImage*art=[MMCovers cached:_curCover];
    if(art){ MPMediaItemArtwork*a=[[MPMediaItemArtwork alloc] initWithImage:art]; if(a) info[MPMediaItemPropertyArtwork]=a; }
    else if(_curCover.length){
        // Cover noch nicht im Cache (z.B. direkt nach Track-Wechsel) -> async nachladen und dann
        // erneut setzen; sonst zeigt der Sperrbildschirm wieder das normale Hintergrundbild.
        NSString*want=_curCover;
        [MMCovers load:_curCover completion:^(UIImage*img){
            if(img && [want isEqualToString:_curCover]) [self updateNowPlaying];   // jetzt gecacht -> Artwork setzen
        }];
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}

// ---- Ansicht im Inhaltsbereich öffnen (über Tab/Now-Playing/Download-Leiste) ----
- (void)showContent:(UIViewController *)vc {
    if(self.presentedViewController) [self dismissViewControllerAnimated:YES completion:^{ [self pushContent:vc]; }];
    else [self pushContent:vc];
}
- (void)pushContent:(UIViewController *)vc {
    [_pushedStack addObject:vc]; vc.view.frame=_content.bounds; vc.view.clipsToBounds=YES; [_content addSubview:vc.view]; [SpotTheme skinPage:vc.view];
    CGRect f=vc.view.frame; vc.view.frame=CGRectOffset(f,f.size.width,0);
    [UIView animateWithDuration:0.3 animations:^{ vc.view.frame=f; }];   // von rechts reinschieben wie bei iOS
    // untere Leisten immer oben halten, damit sie nie von der Playlist verdeckt werden
    [self.view bringSubviewToFront:_dlBar]; [self.view bringSubviewToFront:_npBar]; [self.view bringSubviewToFront:_tabBar];
    [self keepOverlaysOnTop];
}
// Alles, was die ganze App überdeckt (Panels, Cover Flow), bleibt vor den Leisten
- (void)keepOverlaysOnTop {
    for(UIView*v in [self.view.subviews copy])
        if(v.tag==MMSheetTag || v==(UIView*)_cflow) [self.view bringSubviewToFront:v];
}
- (void)popContent {
    UIViewController*vc=[_pushedStack lastObject]; if(!vc)return; [_pushedStack removeLastObject];
    if(!_pushedStack.count) [_sidebar setSelectedKey:_tabs[_sel]];
    [UIView animateWithDuration:0.25 animations:^{ vc.view.frame=CGRectOffset(vc.view.frame,vc.view.frame.size.width,0); }
                     completion:^(BOOL x){ [vc.view removeFromSuperview]; if(!_pushedStack.count) [self tabShown]; }];
}
- (BOOL)hasPushedContent { return _pushedStack.count>0; }
// Tab-Seite wieder sichtbar: die Startseite zeichnet nur sichtbar neu und holt verdeckte Änderungen hier nach
- (void)tabShown { UIViewController*vc=_vcs[_sel]; if([vc isKindOfClass:[MMStartController class]]) [(MMStartController*)vc pageDidShow]; }
- (void)popContentImmediate { for(UIViewController*vc in _pushedStack) [vc.view removeFromSuperview]; [_pushedStack removeAllObjects]; }

// ---- globale Offline-Download-Leiste ----
- (void)layoutDlBar {
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    CGFloat top = _npBar.hidden ? (H-_tabH) : _npBar.frame.origin.y;   // direkt über Now-Playing (oder Tab-Leiste)
    CGFloat h=_dlCompact?2:24, x=0;
    if(MMIsPad()){ top=H-MMPadBarH; x=MMPadSidebarW; W-=x; }   // iPad: über der Player-Leiste, nur über dem Inhalt
    _dlBar.frame=CGRectMake(x, top-h, W, h); _dlLbl.frame=CGRectMake(12,0,W-24,22); _dlLbl.hidden=_dlCompact;
    CGRect pf=_dlProg.frame; pf.origin.y=h-2; _dlProg.frame=pf;
    [self.view bringSubviewToFront:_dlBar];
    [self keepOverlaysOnTop];
}
- (void)showDownloadProgress:(NSInteger)done total:(NSInteger)total {
    if(_cflow) return;                    // Cover Flow (quer) nicht überdecken – Download läuft weiter
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideDownloadBar) object:nil];
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if(_dlBar.hidden) _dlSince=now;
    _dlCompact=(now-_dlSince>6);                       // Text nur am Anfang, dann dezente Linie
    _dlLbl.text=LF(@"↓  Saving … %ld of %ld",(long)done,(long)total);
    _dlProg.frame=CGRectMake(0,0, [self dlWidth]*(total>0?(CGFloat)done/total:0), 2);
    [self layoutDlBar]; _dlBar.hidden=NO;
}
- (void)showDownloadMessage:(NSString *)msg {
    if(_cflow) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideDownloadBar) object:nil];
    _dlCompact=NO; _dlLbl.text=msg;
    _dlProg.frame=CGRectMake(0,0, [self dlWidth], 2);
    [self layoutDlBar]; _dlBar.hidden=NO;
    [self performSelector:@selector(hideDownloadBar) withObject:nil afterDelay:2.5];
}
- (CGFloat)dlWidth { return self.view.bounds.size.width-(MMIsPad()?MMPadSidebarW:0); }
- (void)hideDownloadBar { _dlBar.hidden=YES; _dlCompact=NO; }
- (CGFloat)bottomBarsHeight { return (MMIsPad()||_npBar.hidden?0:_npH) + (_dlBar.hidden?0:_dlBar.frame.size.height); }   // iPad: Player-Leiste liegt nicht über dem Inhalt
- (void)dlProgress:(NSNotification *)n { NSInteger t=[n.userInfo[@"total"] integerValue]; if(t>0) [self showDownloadProgress:[n.userInfo[@"done"] integerValue] total:t]; }
- (void)dlDone:(NSNotification *)n {
    long ok=(long)[n.userInfo[@"ok"] integerValue], una=(long)[n.userInfo[@"unavailable"] integerValue];
    [self showDownloadMessage:una>0?LF(@"✓  %ld saved offline · %ld not on Spotify",ok,una):LF(@"✓  %ld tracks saved offline",ok)];
}
- (void)dlFull:(NSNotification *)n { [self showDownloadMessage:L(@"Storage full, download stopped")]; }
- (void)dlError:(NSNotification *)n { [self showDownloadMessage:L(@"Connection error, download stopped. Please restart")]; }

// Fisher-Yates; der Titel an idx kommt nach vorn
static NSArray* shuffledFrom(NSArray*list,NSInteger idx){
    NSMutableArray*m=[list mutableCopy]; id first=m[idx]; [m removeObjectAtIndex:idx];
    for(NSUInteger i=m.count;i>1;i--) [m exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
    [m insertObject:first atIndex:0]; return m;
}
- (void)playList:(NSArray *)list index:(NSInteger)idx { [self playList:list index:idx context:nil]; }
- (void)playList:(NSArray *)list index:(NSInteger)idx context:(NSDictionary *)context {
    _context=context;
    _origQueue=list; _fromUser=NO;
    if(_shuffle && idx>=0 && idx<(NSInteger)list.count){ _queue=shuffledFrom(list,idx); _queueIdx=0; }
    else { _queue=list; _queueIdx=idx; }
    [self playCurrentInQueue];
}
- (BOOL)shuffle { return _shuffle; }
- (NSInteger)repeatMode { return _repeatMode; }
- (void)setRepeatMode:(NSInteger)m { _repeatMode=(m<0||m>2)?0:m; [self prefetchNext]; [self saveState]; }
- (void)setShuffle:(BOOL)on {
    if(on==_shuffle) return;
    _shuffle=on;
    if(_queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count){
        if(on){ _origQueue=_queue; _queue=shuffledFrom(_queue,_queueIdx); _queueIdx=0; }
        else if(_origQueue.count){
            NSUInteger k=[_origQueue indexOfObject:_queue[_queueIdx]];
            _queue=_origQueue; _queueIdx=(k==NSNotFound)?0:(NSInteger)k;
        }
        [self prefetchNext];   // der nächste Titel ist jetzt ein anderer
    }
    [self saveState];
}
// ---- Warteschlange von Hand: "Als Nächstes" = oben in _userQueue, "Zur Warteschlange" = unten; läuft nichts, startet der Titel ----
- (void)queueTrack:(NSDictionary *)t next:(BOOL)next {
    if(![t[@"id"] length]) return;
    NSDictionary*e=@{@"id":t[@"id"],@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""};
    if(!_curId.length){ [self playList:@[e] index:0]; return; }
    NSMutableArray*q=[(_userQueue?:@[]) mutableCopy];
    if(next) [q insertObject:e atIndex:0]; else [q addObject:e];
    _userQueue=q; [self prefetchNext]; [self saveState];
}
- (NSArray *)userQueue { return _userQueue?:@[]; }
// Schalter in der Warteschlange (gemerkt): eingereihte Titel endlos wiederholen; "Als Nächstes" (Rest der Liste) aus = danach Schluss
- (BOOL)repeatQueue { return [[NSUserDefaults standardUserDefaults] boolForKey:@"repeatQueue"]; }
- (void)setRepeatQueue:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"repeatQueue"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
- (BOOL)nextUpEnabled { return ![[NSUserDefaults standardUserDefaults] boolForKey:@"nextUpOff"]; }
- (void)setNextUpEnabled:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:!on forKey:@"nextUpOff"]; [[NSUserDefaults standardUserDefaults] synchronize]; [self prefetchNext]; }
- (void)moveUserQueueFrom:(NSInteger)from to:(NSInteger)to {
    if(from==to || from<0 || to<0 || from>=(NSInteger)_userQueue.count || to>=(NSInteger)_userQueue.count) return;
    NSMutableArray*q=[_userQueue mutableCopy]; id e=q[from]; [q removeObjectAtIndex:from]; [q insertObject:e atIndex:to]; _userQueue=q;
    [self prefetchNext]; [self saveState];
}
- (void)playUserQueueIndex:(NSInteger)i {   // springen: die davor eingereihten Titel fallen weg (wie bei Spotify)
    if(i<0 || i>=(NSInteger)_userQueue.count) return;
    NSDictionary*t=_userQueue[i]; NSArray*skipped=[_userQueue subarrayWithRange:NSMakeRange(0,i)];
    _userQueue=[_userQueue subarrayWithRange:NSMakeRange(i+1,_userQueue.count-i-1)];
    if([self repeatQueue]){   // Warteschlange wiederholen: der Titel, der gerade lief (auch aus der Liste), und übersprungene wieder hinten an
        NSMutableArray*q=[_userQueue mutableCopy];
        if(_curId.length) [q addObject:@{@"id":_curId,@"title":_curTitle?:@"",@"artist":_curArtist?:@"",@"cover":_curCover?:@""}];
        [q addObjectsFromArray:skipped]; _userQueue=q; }
    _fromUser=YES; [self playTrackId:t[@"id"] title:t[@"title"] artist:t[@"artist"] cover:t[@"cover"]];
}
// Umsortieren im Rest der Liste (nur Titel nach dem laufenden; Indizes in _queue)
- (void)moveQueueFrom:(NSInteger)from to:(NSInteger)to {
    if(from==to || from<=_queueIdx || to<=_queueIdx || from>=(NSInteger)_queue.count || to>=(NSInteger)_queue.count) return;
    NSMutableArray*q=[_queue mutableCopy]; id e=q[from]; [q removeObjectAtIndex:from]; [q insertObject:e atIndex:to]; _queue=q;
    if(!_shuffle) _origQueue=_queue;   // gemischt: die ungemischte Reihenfolge bleibt wie sie war
    [self prefetchNext]; [self saveState];
}
// Aus der Warteschlange nehmen: eingereihter Titel bzw. kommender Titel der Liste (nicht der laufende)
- (void)clearUserQueue { _userQueue=@[]; [self prefetchNext]; [self saveState]; }
- (void)removeUserQueueIndex:(NSInteger)i {
    if(i<0 || i>=(NSInteger)_userQueue.count) return;
    NSMutableArray*q=[_userQueue mutableCopy]; [q removeObjectAtIndex:i]; _userQueue=q;
    [self prefetchNext]; [self saveState];
}
- (void)removeQueueIndex:(NSInteger)i {
    if(i<=_queueIdx || i>=(NSInteger)_queue.count) return;
    id e=_queue[i]; NSMutableArray*q=[_queue mutableCopy]; [q removeObjectAtIndex:i]; _queue=q;
    if(!_shuffle) _origQueue=_queue;
    else { NSUInteger k=[_origQueue indexOfObjectIdenticalTo:e]; if(k!=NSNotFound){ NSMutableArray*o=[_origQueue mutableCopy]; [o removeObjectAtIndex:k]; _origQueue=o; } }   // auch aus der ungemischten Reihenfolge
    [self prefetchNext]; [self saveState];
}
- (NSArray *)queue { return _queue?:@[]; }
- (NSInteger)queueIndex { return _queueIdx; }
- (void)playQueueIndex:(NSInteger)i { if(i>=0 && i<(NSInteger)_queue.count){ _queueIdx=i; _fromUser=NO; [self playCurrentInQueue]; } }
- (void)playCurrentInQueue {
    if(_queueIdx<0 || _queueIdx>=(NSInteger)_queue.count) return;
    NSDictionary*t=_queue[_queueIdx];
    [self playTrackId:t[@"id"] title:t[@"title"] artist:t[@"artist"] cover:t[@"cover"]];
}
- (void)playNext {
    if(_userQueue.count){ [self playUserQueueIndex:0]; return; }   // erst die eingereihten Titel
    if(!_queue.count) return;
    if(_fromUser){ _fromUser=NO; }   // nach den eingereihten geht die Liste hinter ihrem letzten Titel weiter
    if(_queueIdx+1<(NSInteger)_queue.count){ _queueIdx++; [self playCurrentInQueue]; }
    else if(_repeatMode==1){ _queueIdx=0; [self playCurrentInQueue]; }   // Liste wiederholen: von vorn
}
- (void)playPrev {
    // Wie auf dem iPhone/bei Spotify: nach den ersten 3 Sekunden springt "Zurück" an den Anfang des Titels,
    // erst ein zweites Drücken (oder am Anfang) geht zum vorigen Titel. Ohne Vorgänger: immer an den Anfang.
    BOOL hasPrev=(_fromUser && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) || (_queue.count && _queueIdx>0);
    if(!_needsResume && ![MMSpotify isLoading] && [MMAudio duration]>0 && ([MMAudio currentTime]>3.0 || !hasPrev)){
        [MMAudio seekTo:0]; [self drawNpPlay]; [self updateNowPlaying]; return; }
    [self playPrevTrack];
}
- (void)playPrevTrack {   // ohne die 3-Sekunden-Regel (Wischen in der Leiste unten)
    if(_fromUser && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count){ _fromUser=NO; [self playCurrentInQueue]; return; }   // zurück zum Listentitel davor
    if(_queue.count && _queueIdx>0){ _queueIdx--; [self playCurrentInQueue]; }
}

// Track zu Ende -> automatisch weiter (nahtlos dank Prefetch)
- (void)trackFinished {
    // Schutz gegen Finish-Kaskade: meldet ein Track <2s nach Start "fertig", sind die Audiodaten
    // leer/kaputt (kein echtes Ende). Dann NICHT weiterspringen, sonst rasen wir durch die ganze Liste.
    if(_playStartTS>0 && ([NSDate timeIntervalSinceReferenceDate]-_playStartTS) < 2.0){
        _playStartTS=0; [MMAudio stop]; [self drawNpPlay];
        return;
    }
    if(_repeatMode==2 && _curId.length){ [self playTrackId:_curId title:_curTitle artist:_curArtist cover:_curCover]; return; }   // Titel wiederholen
    if(!_userQueue.count && ![self nextUpEnabled]){ [self drawNpPlay]; [self updateNowPlaying]; return; }   // "Als Nächstes" aus: hier Schluss
    if(_userQueue.count || (_queue.count && (_queueIdx+1<(NSInteger)_queue.count || _repeatMode==1))) [self playNext];
    else [self drawNpPlay];   // Ende der Liste: Button zeigt wieder "Play"
}
// nächsten Track im Hintergrund vorladen
- (void)prefetchNext {
    NSInteger j=_queueIdx+1;   // einen Track voraus vorladen (spart RAM/Socket, v.a. während Downloads)
    if(_repeatMode==2) return;                                   // gleicher Titel kommt nochmal, liegt schon im Cache
    if(_userQueue.count){ NSDictionary*n=_userQueue[0]; if(n[@"id"]) [MMSpotify prefetchTrack:n[@"id"]]; [MMCovers load:n[@"cover"] completion:nil]; return; }   // eingereiht kommt zuerst
    if(![self nextUpEnabled]) return;                            // danach kommt nichts mehr
    if(_repeatMode==1 && j>=(NSInteger)_queue.count) j=0;        // nach dem letzten kommt der erste
    if(_queue.count && j<(NSInteger)_queue.count){ NSDictionary*n=_queue[j]; if(n[@"id"]) [MMSpotify prefetchTrack:n[@"id"]];
        [MMCovers load:n[@"cover"] completion:nil]; }              // Cover des nächsten Titels schon in den Speicher -> Wechsel sofort
    if(_queueIdx>0 && _queueIdx-1<(NSInteger)_queue.count) [MMCovers load:_queue[_queueIdx-1][@"cover"] completion:nil];   // und zurück
}

- (void)playTrackId:(NSString *)trackId title:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover {
    _needsResume=NO;   // neue Wiedergabe: "Play" soll danach diesen Titel fortsetzen, nicht den gespeicherten der letzten Sitzung
    // Länge aus der Liste (ms), damit beim Spielen während des Downloads gleich die Restzeit stimmt; sonst aus den Metadaten unten
    double dur=0; for(NSDictionary*q in [(_userQueue?:@[]) arrayByAddingObjectsFromArray:_queue?:@[]]) if([q[@"id"] isEqual:trackId] && [q[@"dur"] doubleValue]>0){ dur=[q[@"dur"] doubleValue]/1000.0; break; }
    [MMAudio setExpectedDuration:dur];
    // offline: Songs, die nicht gespeichert sind, überspringen statt hängen zu bleiben (höchstens einmal die ganze Liste durch)
    static NSInteger skips=0;
    if(![MMSpotify networkReachable] && ![MMSpotify playableOffline:trackId]){
        if(skips++ <= (NSInteger)(_queue.count+_userQueue.count)){ MMLog(@"offline: überspringe %@",trackId); [self playNext]; return; }
    }
    skips=0;
    _curId=trackId; _curTitle=title; _curArtist=artist; _curCover=cover; _curAlbumId=nil; _curAlbum=nil; _curArtistId=nil;
    _npTitle.text=title; _npArtist.text=artist; _npBar.hidden=NO;
    for(UIView*v in _npCover.subviews)[v removeFromSuperview];
    if(cover.length)[self loadNpCover:cover];
    if(_player)[_player updateTitle:title artist:artist cover:cover];   // SOFORT mit bekannten Daten (nicht erst nach fetchTrack)
    [self updateNowPlaying];
    // echte Metadaten + Cover nachladen - feilt nach, nur wenn noch derselbe Track aktuell ist
    [MMSpotify fetchTrack:trackId completion:^(NSDictionary*info,NSString*e){
        if(info && [trackId isEqualToString:_curId]){   // Schutz gegen veraltete Antwort bei schnellem Skippen
            // Cover aus der Liste behalten: Spotify liefert hier oft eine andere Adresse fürs gleiche Bild -> sonst Flackern + doppeltes Laden
            _curTitle=info[@"title"]?:title; _curArtist=info[@"artist"]?:artist; _curCover=cover.length?cover:(info[@"cover"]?:cover);
            _curAlbumId=info[@"albumId"]; _curAlbum=info[@"album"]; _curArtistId=info[@"artistId"];
            if([info[@"durMs"] doubleValue]>0) [MMAudio setExpectedDuration:[info[@"durMs"] doubleValue]/1000.0];   // Länge, solange der Titel noch lädt
            // Verlauf auf dem iPhone (Spotify erfährt von dieser Wiedergabe nichts) -> Startseite zeigt sie sofort
            [MMHistory recordTrack:@{@"id":trackId,@"title":_curTitle?:@"",@"artist":_curArtist?:@"",@"cover":_curCover?:@"",@"albumId":_curAlbumId?:@"",@"album":_curAlbum?:@"",@"artistId":_curArtistId?:@""}];
            if(_context && !_fromUser) [MMHistory recordContext:_context];
            _npTitle.text=_curTitle; _npArtist.text=_curArtist;
            [self loadNpCover:_curCover];
            if(_player)[_player updateTitle:_curTitle artist:_curArtist cover:_curCover];
            [self updateNowPlaying];
        }
    }];
    // echten Ton starten -> Spinner während des Ladens
    _npPlay.hidden=YES; [_npSpinner startAnimating]; _loading=YES; [self showLoadProgress:0]; [self padBarRefresh];
    _playStartTS=0;
    [MMSpotify playTrack:trackId stream:(_pendingSeek<=0) completion:^(BOOL ok,NSString*e){   // Fortsetzen an gespeicherter Stelle: erst ganz laden (Spulen braucht die Datei)

        [_npSpinner stopAnimating]; _npPlay.hidden=NO; _loading=NO; if(![MMAudio isBuffering]) [self showLoadProgress:-1];   // spielt schon, lädt noch: grün bleibt
        if(!ok) [self showPlayError:e?:@""];
        if(ok){ _playStartTS=[NSDate timeIntervalSinceReferenceDate]; if(_pendingSeek>0){ [MMAudio seekTo:_pendingSeek]; _pendingSeek=0; } [self prefetchNext]; [self saveState]; }
        [self drawNpPlay]; [self updateNowPlaying];
    }];
}

- (void)loadNpCover:(NSString *)url {
    if(!url.length) return;
    [MMCovers load:url completion:^(UIImage*img){
        if(!img) return;
        for(UIView*v in _npCover.subviews)[v removeFromSuperview];
        UIImageView*iv=[[UIImageView alloc] initWithFrame:_npCover.bounds];
        iv.image=img; iv.contentMode=UIViewContentModeScaleAspectFill; [_npCover addSubview:iv];
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if(g.view!=_npBar || ![g isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    CGPoint v=[(UIPanGestureRecognizer*)g velocityInView:_npBar]; return fabs(v.x)>fabs(v.y);   // nur waagrecht
}
- (void)npSlide:(CGFloat)dx { CGAffineTransform t=CGAffineTransformMakeTranslation(dx,0); _npCover.transform=t; _npTitle.transform=t; _npArtist.transform=t; }
- (void)npSwipe:(UIPanGestureRecognizer *)g {
    CGFloat W=_npBar.bounds.size.width, dx=[g translationInView:_npBar].x;
    if(g.state==UIGestureRecognizerStateBegan || g.state==UIGestureRecognizerStateChanged){ [self npSlide:dx]; return; }
    CGFloat vx=[g velocityInView:_npBar].x;
    BOOL go=(g.state==UIGestureRecognizerStateEnded) && (fabs(dx)>W*0.25 || fabs(vx)>600) && dx*vx>=0;
    if(!go){ [UIView animateWithDuration:0.2 animations:^{ [self npSlide:0]; }]; return; }
    BOOL next=dx<0;
    [UIView animateWithDuration:0.15 animations:^{ [self npSlide:next?-W:W]; } completion:^(BOOL f){
        if(next) [self playNext]; else [self playPrevTrack];   // Titel/Artist/Cover sind danach schon die neuen
        [self npSlide:next?W:-W];                               // von der anderen Seite hereinschieben
        [UIView animateWithDuration:0.2 animations:^{ [self npSlide:0]; }];
    }];
}
- (void)drawNpPlay {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20,20),NO,0);
    [[SpotTheme chromeInk] setFill];
    if([MMAudio isPlaying]){ // Pause
        [[UIBezierPath bezierPathWithRect:CGRectMake(5,4,3.5,12)] fill];
        [[UIBezierPath bezierPathWithRect:CGRectMake(11.5,4,3.5,12)] fill];
    } else { // Play
        UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(6,4)];[t addLineToPoint:CGPointMake(6,16)];[t addLineToPoint:CGPointMake(16,10)];[t closePath]; [t fill];
    }
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [_npPlay setImage:img forState:UIControlStateNormal];
    [self padBarRefresh];
}
- (void)npTogglePlay {
    if([MMAudio isPlaying]){ [MMAudio setPaused:YES]; [self drawNpPlay]; [self updateNowPlaying]; return; }
    [self playOrRestart];
}

- (void)portsBlocked {
    [[[UIAlertView alloc] initWithTitle:L(@"Can't reach Spotify") message:L(@"This network seems to block Spotify's ports (4070, 443 and 80), so songs can't load. Library and search still work. Try another Wi-Fi or mobile data.") delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show];
}
- (void)keysRefused {
    [[[UIAlertView alloc] initWithTitle:L(@"Your Spotify account is too new") message:L(@"Spotify doesn't give song keys to new accounts in older apps like Spotify6, so songs can't play or download. Library and search still work.\n\nSpotify blocks this on their side, so Spotify6 can't fix it. To play music, log in with an older Premium account (Settings, Log out). If your account isn't new, try again later.") delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show];
}
- (void)notPremium {
    [[[UIAlertView alloc] initWithTitle:L(@"Spotify Premium needed") message:LF(@"Your Spotify account is \"%@\", not Premium. Spotify only lets Premium accounts play songs in other apps like Spotify6.",[MMSpotify productType]?:@"?") delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show];
}
// kurzer Grund in der Leiste unten, wenn ein Song nicht startet (statt endlosem Kreisel)
- (void)showPlayError:(NSString *)e {
    NSString*m=L(@"Couldn't play this song");
    if([e rangeOfString:@"AudioKey"].location!=NSNotFound) m=L(@"Spotify didn't send the song key");
    else if([e rangeOfString:@"not reachable"].location!=NSNotFound || [e rangeOfString:@"logged in"].location!=NSNotFound || [e rangeOfString:@"apresolve"].location!=NSNotFound) m=L(@"Couldn't reach Spotify");
    else if([e rangeOfString:@"CDN"].location!=NSNotFound) m=L(@"Song download failed");
    else if([e rangeOfString:@"No playable file"].location!=NSNotFound) m=L(@"This song isn't available");
    [self showDownloadMessage:m];
}
- (void)networkChanged:(NSNotification *)n {
    BOOL ok=[n.userInfo[@"reachable"] boolValue];
    [self showDownloadMessage:ok?L(@"Back online"):L(@"Offline – downloaded songs still play")];
}
- (NSDictionary *)nowPlaying {
    if(!_curId.length) return nil;
    return @{@"id":_curId,@"title":_curTitle?:@"",@"artist":_curArtist?:@"",@"cover":_curCover?:@"",@"index":@(_queueIdx+1),@"count":@(_queue.count),
             @"albumId":_curAlbumId?:@"",@"album":_curAlbum?:@"",@"artistId":_curArtistId?:@""};
}
- (void)togglePlayPause { [self npTogglePlay]; }
// Abspielen: nach App-Start dort weiter, wo du warst; war der Titel zu Ende (z. B. "Als Nächstes" aus), von vorn; sonst fortsetzen
- (void)playOrRestart {
    if(_needsResume){ [self resumePlayback]; return; }
    if(_curId.length && ![MMSpotify isLoading] && ([MMAudio hasEnded] || ![MMAudio isLoaded])){   // zu Ende oder gar nicht geladen: von vorn
        [self playTrackId:_curId title:_curTitle artist:_curArtist cover:_curCover]; return; }
    [MMAudio setPaused:NO]; [self drawNpPlay]; [self updateNowPlaying];
}
+ (BOOL)coverFlowOnRotate { id v=[[NSUserDefaults standardUserDefaults] objectForKey:@"coverFlowOnRotate"]; return v?[v boolValue]:YES; }
+ (void)setCoverFlowOnRotate:(BOOL)on {   // iPhone: Cover Flow beim Querdrehen; iPad: Eintrag in der Seitenleiste
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"coverFlowOnRotate"]; [[NSUserDefaults standardUserDefaults] synchronize];
    if(gRoot) [gRoot->_sidebar setShowsCoverFlow:on];
}
// Statusleiste (Netz, Uhrzeit, Akku) immer, außer im Cover Flow (Vollbild quer).
- (void)updateStatusBar {
    BOOL full=(_cflow!=nil);
    [[UIApplication sharedApplication] setStatusBarHidden:full withAnimation:UIStatusBarAnimationFade];
}
// ---- Cover Flow: die App selbst bleibt hochkant, die Ansicht wird um 90° gedreht eingeblendet ----
- (void)orientationChanged {
    if(MMIsPad()) return;   // iPad: Drehen dreht nur das Layout; Cover Flow gibt es über die Seitenleiste
    UIDeviceOrientation o=[UIDevice currentDevice].orientation;
    if(UIDeviceOrientationIsLandscape(o)){
        if(self.presentedViewController) return;
        if(!_cflow && ![MMRootController coverFlowOnRotate]) return;   // in den Einstellungen ausgeschaltet             // Player offen -> nicht dazwischenfunken
        if(!_cflow) [self openCoverFlow:o]; else [self rotateCoverFlow:o animated:YES];
    } else if(o==UIDeviceOrientationPortrait && _cflow) [self closeCoverFlow];
}
- (void)showCoverFlow {
    UIDeviceOrientation o=[UIDevice currentDevice].orientation;
    _cflowManual=YES;
    if(!_cflow) [self openCoverFlow:UIDeviceOrientationIsLandscape(o)?o:UIDeviceOrientationLandscapeLeft];
}
- (void)openCoverFlow:(UIDeviceOrientation)o {
    CGSize sz=CGSizeMake(self.view.bounds.size.height,self.view.bounds.size.width);
    if(MMIsPad()){ CGSize b=self.view.bounds.size; sz=CGSizeMake(MAX(b.width,b.height),MIN(b.width,b.height)); }   // immer quer, auch wenn das iPad hochkant ist
    _cflow=[[MMCoverFlowView alloc] initWithLandscapeSize:sz];
    __weak MMRootController*ws=self; _cflow.onClose=^{ [ws closeCoverFlow]; };
    _cflow.center=CGPointMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2);
    [self rotateCoverFlow:o animated:NO];
    _cflow.alpha=0; [self.view addSubview:_cflow]; _dlBar.hidden=YES; [self updateStatusBar];
    [UIView animateWithDuration:0.3 animations:^{ _cflow.alpha=1; }];
}
// iPad: quer ohne Drehung über alles, hochkant um 90° gedreht wie am iPhone (nach jedem Drehen aus layoutPad)
- (void)placePadCoverFlow {
    if(!_cflow) return;
    CGSize b=self.view.bounds.size; _cflow.center=CGPointMake(b.width/2,b.height/2);
    _cflow.transform=(b.width>b.height)?CGAffineTransformIdentity:CGAffineTransformMakeRotation(M_PI_2);
    [self.view bringSubviewToFront:_cflow];
}
- (void)rotateCoverFlow:(UIDeviceOrientation)o animated:(BOOL)a {
    if(MMIsPad()){ [self placePadCoverFlow]; return; }
    CGFloat ang=(o==UIDeviceOrientationLandscapeRight)?-M_PI_2:M_PI_2;   // Home-Taste rechts = LandscapeLeft
    [UIView animateWithDuration:a?0.3:0 animations:^{ _cflow.transform=CGAffineTransformMakeRotation(ang); }];
}
- (void)closeCoverFlow {
    UIView*v=_cflow; _cflow=nil; _cflowManual=NO; [self updateStatusBar];
    [UIView animateWithDuration:0.25 animations:^{ v.alpha=0; } completion:^(BOOL f){ [v removeFromSuperview]; }];
}

- (void)openQueue {
    if(MMIsPad() && !self.presentedViewController && UIInterfaceOrientationIsLandscape(self.interfaceOrientation)){ [self toggleQueueDock]; return; }
    if(self.presentedViewController) return;
    [self presentViewController:[[MMQueueController alloc] init] animated:YES completion:nil];
}
- (void)openPlayer {
    if([self.presentedViewController isKindOfClass:[MMPlayerController class]]) return;  // schon offen
    if(self.presentedViewController){ [self dismissViewControllerAnimated:NO completion:nil]; }
    MMPlayerController*pc=[[MMPlayerController alloc] init];
    pc.trackTitle=_curTitle; pc.trackArtist=_curArtist; pc.coverURL=_curCover;
    pc.modalTransitionStyle=UIModalTransitionStyleCoverVertical;
    _player=pc;
    [self presentViewController:pc animated:YES completion:nil];
}
@end
