#import "MMLastFMController.h"
#import "MMLayout.h"
#import "SpotTheme.h"
#import "MMRootController.h"
#import "MMLastFM.h"

@interface MMLastFMController () <UITextFieldDelegate, UIAlertViewDelegate>
@end

@implementation MMLastFMController {
    UIScrollView *_scroll;
    UITextField *_key, *_secret;
    UILabel *_status, *_connected;
    UIButton *_connect, *_copyAuth, *_finish, *_disconnect;
    NSString *_authorizationURL;
    CGFloat _W, _y;
}
- (UILabel *)label:(NSString *)text y:(CGFloat)y font:(UIFont *)font color:(UIColor *)color height:(CGFloat)height {
    UILabel *l=[[UILabel alloc] initWithFrame:CGRectMake(16,y,_W-32,height)]; l.text=text; l.font=font; l.textColor=color;
    l.numberOfLines=0; l.backgroundColor=[UIColor clearColor]; [_scroll addSubview:l]; return l;
}
- (UITextField *)field:(NSString *)placeholder secret:(BOOL)secret y:(CGFloat)y {
    UIView *box=[[UIView alloc] initWithFrame:CGRectMake(16,y,_W-32,42)]; box.backgroundColor=[UIColor whiteColor]; box.layer.cornerRadius=6; [_scroll addSubview:box];
    UITextField *f=[[UITextField alloc] initWithFrame:CGRectMake(10,0,_W-52,42)]; f.placeholder=placeholder; f.font=[UIFont systemFontOfSize:15];
    f.textColor=[UIColor blackColor]; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo;
    f.spellCheckingType=UITextSpellCheckingTypeNo; f.clearButtonMode=UITextFieldViewModeWhileEditing; f.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter;
    f.secureTextEntry=secret; f.delegate=self; [box addSubview:f]; return f;
}
- (UIButton *)button:(NSString *)title y:(CGFloat)y action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake(32,y,_W-64,44); b.backgroundColor=[SpotTheme green]; b.layer.cornerRadius=10;
    b.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [b setTitle:title forState:UIControlStateNormal]; [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    if([SpotTheme ios6]){ b.backgroundColor=[UIColor clearColor]; [b setBackgroundImage:[SpotTheme glossyImage:[SpotTheme green] radius:10] forState:UIControlStateNormal]; [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; }
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [_scroll addSubview:b]; return b;
}
- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(NO)]; self.view.backgroundColor=[SpotTheme bg]; _W=self.view.bounds.size.width;
    CGFloat H=self.view.bounds.size.height;
    UIButton *back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,80,34); [SpotTheme styleBackButton:back];
    [back setTitleColor:[SpotTheme ink] forState:UIControlStateNormal]; back.titleLabel.font=[UIFont systemFontOfSize:14]; [back setTitle:@"Back" forState:UIControlStateNormal];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
    UILabel *nav=[[UILabel alloc] initWithFrame:CGRectMake(90,8,_W-180,34)]; nav.text=@"Last.fm Scrobbling"; nav.font=[UIFont boldSystemFontOfSize:16];
    nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];
    _scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(0,46,_W,H-46)]; _scroll.alwaysBounceVertical=YES; _scroll.autoresizingMask=UIViewAutoresizingFlexibleHeight; [self.view addSubview:_scroll];
    _y=12; [self label:@"Spotify6 plays music itself, so the Spotify-to-Last.fm link cannot see it. Connect Last.fm here to scrobble from this player." y:_y font:[SpotTheme sub] color:[SpotTheme muted] height:54]; _y+=62;
    _connected=[self label:@"" y:_y font:[UIFont boldSystemFontOfSize:14] color:[SpotTheme green] height:22]; _y+=30;
    [self label:@"Last.fm API credentials" y:_y font:[UIFont boldSystemFontOfSize:14] color:[SpotTheme ink] height:20]; _y+=24;
    UILabel *help=[self label:@"Create a Last.fm API account at last.fm/api/account/create, then paste its API key and secret below. These are app credentials, not your Last.fm password." y:_y font:[SpotTheme sub] color:[SpotTheme muted] height:54]; (void)help; _y+=60;
    _key=[self field:@"API key (32 characters)" secret:NO y:_y]; _y+=50;
    _secret=[self field:@"API shared secret" secret:YES y:_y]; _y+=54;
    _connect=[self button:@"AUTHORIZE LAST.FM" y:_y action:@selector(connect)]; _y+=54;
    _copyAuth=[self button:@"COPY AUTHORIZATION LINK" y:_y action:@selector(copyAuthorizationLink)]; _y+=54;
    _finish=[self button:@"I APPROVED — FINISH SETUP" y:_y action:@selector(finishAuthorization)]; _y+=54;
    _disconnect=[self button:@"DISCONNECT LAST.FM" y:_y action:@selector(disconnect)]; _y+=54;
    _status=[self label:@"" y:_y font:[SpotTheme sub] color:[SpotTheme muted] height:58]; _y+=64;
    _scroll.contentSize=CGSizeMake(_W,_y+20); [self refreshState];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; tap.cancelsTouchesInView=NO; [_scroll addGestureRecognizer:tap];
    MMAutoMask(self.view);
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshState]; }
- (void)refreshState {
    _key.text=[MMLastFM configuredAPIKey]; _secret.text=[MMLastFM configuredAPISecret];
    _authorizationURL=[MMLastFM pendingAuthorizationURL];
    BOOL connected=[MMLastFM isConnected]; _connected.text=connected?[NSString stringWithFormat:@"Connected as %@",[MMLastFM connectedUsername]]:@"Not connected";
    _disconnect.hidden=!connected; _finish.hidden=![[NSUserDefaults standardUserDefaults] stringForKey:@"lastFmPendingToken"].length;
    _copyAuth.hidden=!_authorizationURL.length;
    if(connected){ _connect.hidden=YES; _key.enabled=NO; _secret.enabled=NO; }
    else { _connect.hidden=NO; _key.enabled=YES; _secret.enabled=YES; }
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return MMShouldAutorotate(o); }
- (BOOL)shouldAutorotate { return MMIsPad(); }
MM_IOS6_BEGIN
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return (UIInterfaceOrientationMask)MMSupportedOrientations(); }
MM_IOS6_END
- (void)hideKeyboard { [_key resignFirstResponder]; [_secret resignFirstResponder]; }
- (void)connect {
    [self hideKeyboard]; _status.textColor=[SpotTheme muted]; _status.text=@"Requesting an authorization token…"; _connect.enabled=NO;
    [MMLastFM beginAuthorizationWithAPIKey:_key.text secret:_secret.text completion:^(NSString *url,NSString *error){
        self->_connect.enabled=YES;
        if(!url.length){ self->_status.textColor=[SpotTheme muted]; self->_status.text=error?:@"Could not contact Last.fm."; return; }
        self->_authorizationURL=url; self->_finish.hidden=NO; self->_status.textColor=[SpotTheme green];
        self->_copyAuth.hidden=NO;
        self->_status.text=@"Approve Spotify6 in Last.fm, then return here and tap “I approved”. If Safari on iOS 6 cannot open the page, copy the link and approve it on another device.";
        NSURL *u=[NSURL URLWithString:url]; if(u && [[UIApplication sharedApplication] canOpenURL:u]) [[UIApplication sharedApplication] openURL:u];
    }];
}
- (void)copyAuthorizationLink {
    if(!_authorizationURL.length) return;
    [UIPasteboard generalPasteboard].string=_authorizationURL;
    _status.textColor=[SpotTheme green]; _status.text=@"Authorization link copied. Open it in a browser, approve Spotify6, then return here.";
}
- (void)finishAuthorization {
    [self hideKeyboard]; _status.textColor=[SpotTheme muted]; _status.text=@"Finishing Last.fm authorization…"; _finish.enabled=NO;
    [MMLastFM completeAuthorization:^(BOOL ok,NSString *username,NSString *error){
        self->_finish.enabled=YES;
        if(ok){ self->_status.textColor=[SpotTheme green]; self->_status.text=[NSString stringWithFormat:@"Connected as %@. New plays will scrobble when they qualify.",username]; [self refreshState]; [MMLastFM flushQueuedScrobbles]; }
        else { self->_status.textColor=[SpotTheme muted]; self->_status.text=error?:@"Authorization failed."; }
    }];
}
- (void)disconnect {
    UIAlertView *a=[[UIAlertView alloc] initWithTitle:@"Disconnect Last.fm?" message:@"Queued scrobbles will be removed from this device." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Disconnect",nil]; a.tag=77; [a show];
}
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(alertView.tag==77 && buttonIndex==1){ [MMLastFM disconnect]; _status.text=@"Last.fm disconnected."; [self refreshState]; }
}
- (void)close { [self hideKeyboard]; [[MMRootController shared] popContent]; }
@end
