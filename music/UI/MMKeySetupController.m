#import "MMKeySetupController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMSpotify.h"
#import "MeshL10n.h"

@interface MMKeySetupController () <UITextFieldDelegate>
@end

@implementation MMKeySetupController {
    UIScrollView *_scroll;
    UITextField *_cid, *_sec;
    UILabel *_cidCount, *_secCount, *_status;
    UIButton *_save;
    CGFloat _y, _W;
}

- (UILabel *)label:(NSString *)text font:(UIFont *)f color:(UIColor *)c x:(CGFloat)x w:(CGFloat)w {
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(x,_y,w,20)];
    l.text=text; l.font=f; l.textColor=c; l.numberOfLines=0; l.backgroundColor=[UIColor clearColor];
    [l sizeToFit]; l.frame=CGRectMake(x,_y,w,l.frame.size.height);
    [_scroll addSubview:l]; [SpotTheme engrave:l]; return l;
}

// Wert zum Abtippen/Kopieren (Adresse, Redirect URI) in einer Box hervorheben
- (void)valueBox:(NSString *)value x:(CGFloat)x {
    UIView*box=[[UIView alloc] initWithFrame:CGRectMake(x,_y,_W-x-16,30)]; box.backgroundColor=[SpotTheme card]; box.layer.cornerRadius=4; [SpotTheme groupedTile:box];
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectInset(box.bounds,8,0)];
    l.text=value; l.font=[UIFont fontWithName:@"Courier-Bold" size:13]; l.textColor=[SpotTheme green]; l.adjustsFontSizeToFitWidth=YES; l.backgroundColor=[UIColor clearColor];
    [box addSubview:l]; [_scroll addSubview:box]; _y+=36;
}

- (void)step:(int)n text:(NSString *)text value:(NSString *)value {
    UIView*dot=[[UIView alloc] initWithFrame:CGRectMake(16,_y,24,24)]; dot.backgroundColor=[SpotTheme green]; dot.layer.cornerRadius=12;
    UILabel*num=[[UILabel alloc] initWithFrame:dot.bounds]; num.text=[NSString stringWithFormat:@"%d",n]; num.font=[UIFont boldSystemFontOfSize:13];
    num.textColor=[UIColor blackColor]; num.textAlignment=NSTextAlignmentCenter; num.backgroundColor=[UIColor clearColor]; [dot addSubview:num];
    [_scroll addSubview:dot];
    _y+=3; UILabel*l=[self label:text font:[SpotTheme body] color:[SpotTheme ink] x:52 w:_W-68];
    _y+=MAX(l.frame.size.height,21)+6;
    if(value) [self valueBox:value x:52];
    _y+=10;
}

- (UITextField *)field:(NSString *)title counter:(UILabel *__strong *)counter {
    [self label:title font:[UIFont boldSystemFontOfSize:13] color:[SpotTheme muted] x:16 w:_W-32];
    UILabel*c=[[UILabel alloc] initWithFrame:CGRectMake(_W-96,_y,80,16)]; c.font=[SpotTheme sub]; c.textColor=[SpotTheme faint]; c.textAlignment=NSTextAlignmentRight; c.text=@"0/32";
    [_scroll addSubview:c]; *counter=c; _y+=20;
    UIView*box=[[UIView alloc] initWithFrame:CGRectMake(16,_y,_W-32,42)]; box.backgroundColor=[UIColor whiteColor]; box.layer.cornerRadius=6; [_scroll addSubview:box];
    UITextField*f=[[UITextField alloc] initWithFrame:CGRectMake(10,0,_W-52,42)];
    f.font=[UIFont fontWithName:@"Courier" size:15]; f.textColor=[UIColor blackColor]; f.adjustsFontSizeToFitWidth=YES; f.minimumFontSize=10;
    f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.spellCheckingType=UITextSpellCheckingTypeNo;
    f.keyboardType=UIKeyboardTypeASCIICapable; f.clearButtonMode=UITextFieldViewModeWhileEditing; f.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter;
    f.placeholder=L(@"32 characters (0-9, a-f)"); f.delegate=self;
    [box addSubview:f]; _y+=56; return f;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return MMShouldAutorotate(o); }   // iPad: dreht mit
- (BOOL)shouldAutorotate { return MMIsPad(); }
MM_IOS6_BEGIN
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return (UIInterfaceOrientationMask)MMSupportedOrientations(); }
MM_IOS6_END
- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(NO)];
    self.view.backgroundColor=[SpotTheme bg];
    _W=self.view.bounds.size.width; CGFloat H=self.view.bounds.size.height, sx=0;
    if(MMIsPad()){ sx=floor((_W-MMPadColumnW)/2); _W=MMPadColumnW; }   // iPad: mittige Spalte, bleibt beim Drehen mittig
    _scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(sx,0,_W,H)]; _scroll.alwaysBounceVertical=YES;
    _scroll.autoresizingMask=UIViewAutoresizingFlexibleHeight|(MMIsPad()?UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin:0); [self.view addSubview:_scroll];
    // Tippen neben die Felder schließt die Tastatur
    UITapGestureRecognizer*tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; tap.cancelsTouchesInView=NO;
    [_scroll addGestureRecognizer:tap];

    _y=8;
    if(!self.skippable){
        UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,_y,80,34);
        [SpotTheme styleBackButton:back]; [back setTitleColor:[SpotTheme ink] forState:UIControlStateNormal];
        back.titleLabel.font=[UIFont systemFontOfSize:14]; back.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        [back addTarget:self action:@selector(skip) forControlEvents:UIControlEventTouchUpInside]; [_scroll addSubview:back];
        if([SpotTheme ios6]){ [back removeFromSuperview]; back.frame=CGRectMake(8,8,80,34); [self.view addSubview:back]; }   // iOS 6: Zurück in die Navigationsleiste
    }
    if([SpotTheme ios6]){   // iOS 6: Titel in der Leiste, Text scrollt darunter
        UILabel*nt=[[UILabel alloc] initWithFrame:CGRectMake(90,8,self.view.bounds.size.width-180,34)]; nt.text=L(@"Search key"); [self.view addSubview:nt];
        _scroll.frame=CGRectMake(_scroll.frame.origin.x,44,_scroll.frame.size.width,H-44); self.view.backgroundColor=[SpotTheme pageBackground]; }
    _y=[SpotTheme ios6]?16:48;   // iOS 6: der Kopf ist die Leiste
    [self label:L(@"Unlock search") font:[SpotTheme h1] color:[SpotTheme ink] x:16 w:_W-32]; _y+=32;
    UILabel*intro=[self label:L(@"Spotify only allows search with your own free developer key. You set it up once, takes about 3 minutes – best on your phone or computer.") font:[SpotTheme sub] color:[SpotTheme muted] x:16 w:_W-32];
    _y+=intro.frame.size.height+20;

    [self step:1 text:L(@"Open this page and log in with your Spotify account:") value:@"developer.spotify.com/dashboard"];
    [self step:2 text:L(@"First time only: accept the terms and confirm your email address if asked.") value:nil];
    [self step:3 text:L(@"Tap \"Create app\". Enter any name and description, e.g. \"Spotify6\".") value:nil];
    [self step:4 text:L(@"For \"Redirect URIs\" enter exactly this and tap \"Add\":") value:@"http://127.0.0.1:8888/callback"];
    [self step:5 text:L(@"Under \"Which API/SDKs\" tick \"Web API\", accept the terms and tap \"Save\".") value:nil];
    [self step:6 text:L(@"Open \"Settings\" of your new app. Copy the \"Client ID\" and tap \"View client secret\" for the secret.") value:nil];
    [self step:7 text:L(@"Type both in here. Only digits and the letters a–f – the fields fix upper case for you.") value:nil];

    _cid=[self field:L(@"CLIENT ID") counter:&_cidCount];
    _sec=[self field:L(@"CLIENT SECRET") counter:&_secCount];
    _cid.returnKeyType=UIReturnKeyNext; _sec.returnKeyType=UIReturnKeyGo;

    _save=[UIButton buttonWithType:UIButtonTypeCustom];
    _save.frame=CGRectMake(40,_y,_W-80,48); _save.backgroundColor=[SpotTheme green]; _save.layer.cornerRadius=24;
    if([SpotTheme ios6]){ _save.backgroundColor=[UIColor clearColor]; _save.layer.cornerRadius=0; [_save setBackgroundImage:[SpotTheme glossyImage:[SpotTheme green] radius:10] forState:UIControlStateNormal]; }
    _save.titleLabel.font=[UIFont boldSystemFontOfSize:15];
    [_save setTitle:L(@"CHECK & SAVE") forState:UIControlStateNormal]; [_save setTitleColor:[SpotTheme ios6]?[UIColor whiteColor]:[UIColor blackColor] forState:UIControlStateNormal];
    if([SpotTheme ios6]){ [_save setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal]; _save.titleLabel.shadowOffset=CGSizeMake(0,-1); }
    [_save addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside]; [_scroll addSubview:_save];
    _y+=58;
    _status=[[UILabel alloc] initWithFrame:CGRectMake(16,_y,_W-32,54)]; _status.font=[SpotTheme sub]; _status.textColor=[SpotTheme muted];
    _status.textAlignment=NSTextAlignmentCenter; _status.numberOfLines=0; _status.backgroundColor=[UIColor clearColor]; [_scroll addSubview:_status];
    _y+=60;

    if(self.skippable){
        UIButton*later=[UIButton buttonWithType:UIButtonTypeCustom]; later.frame=CGRectMake(40,_y,_W-80,36);
        [later setTitle:L(@"Later – I'll do it in Search") forState:UIControlStateNormal]; [later setTitleColor:[SpotTheme muted] forState:UIControlStateNormal];
        later.titleLabel.font=[SpotTheme sub]; [later addTarget:self action:@selector(skip) forControlEvents:UIControlEventTouchUpInside]; [_scroll addSubview:later];
        _y+=44;
    } else if([MMSpotify hasSearchKey]){
        UIButton*rm=[UIButton buttonWithType:UIButtonTypeCustom]; rm.frame=CGRectMake(40,_y,_W-80,36);
        [rm setTitle:L(@"Remove saved key") forState:UIControlStateNormal]; [rm setTitleColor:[SpotTheme faint] forState:UIControlStateNormal];
        rm.titleLabel.font=[SpotTheme sub]; [rm addTarget:self action:@selector(removeKey) forControlEvents:UIControlEventTouchUpInside]; [_scroll addSubview:rm];
        _y+=44;
    }
    _scroll.contentSize=CGSizeMake(_W,_y+(self.skippable?20:80));   // unten Platz für Tab-/Player-Leiste
    [SpotTheme skinPage:self.view];   // auch als eigener Bildschirm nach dem ersten Anmelden
}

// viewDidLoad statt viewWillAppear: im Inhaltsbereich (pushContent) kommt kein viewWillAppear an
- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbHide:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// Tastatur: Inhalt so weit hochschieben, dass das aktive Feld sichtbar bleibt
- (void)kbShow:(NSNotification *)n {
    CGRect kb=[self.view convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap=CGRectGetMaxY(_scroll.frame)-kb.origin.y; if(overlap<0) overlap=0;
    _scroll.contentInset=UIEdgeInsetsMake(0,0,overlap,0); _scroll.scrollIndicatorInsets=_scroll.contentInset;
    UITextField*f=_cid.isFirstResponder?_cid:(_sec.isFirstResponder?_sec:nil);
    if(f){ CGRect r=[_scroll convertRect:f.superview.frame fromView:f.superview.superview]; r.size.height+=70; [_scroll scrollRectToVisible:r animated:YES]; }
}
- (void)kbHide:(NSNotification *)n { _scroll.contentInset=UIEdgeInsetsZero; _scroll.scrollIndicatorInsets=UIEdgeInsetsZero; }
- (void)hideKeyboard { [self.view endEditing:YES]; }

// Nur 0-9 und a-f, Großbuchstaben werden klein, max. 32 Zeichen (auch beim Einfügen)
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)str {
    NSMutableString*clean=[NSMutableString string]; NSString*low=[str lowercaseString];
    for(NSUInteger i=0;i<low.length;i++){ unichar c=[low characterAtIndex:i]; if((c>='0'&&c<='9')||(c>='a'&&c<='f')) [clean appendFormat:@"%C",c]; }
    NSString*next=[tf.text stringByReplacingCharactersInRange:range withString:clean];
    if(next.length>32) next=[next substringToIndex:32];
    tf.text=next; [self updateCounters];
    return NO;
}
- (BOOL)textFieldShouldClear:(UITextField *)tf { tf.text=@""; [self updateCounters]; return NO; }
- (void)updateCounters {
    for(NSArray*p in @[@[_cid,_cidCount],@[_sec,_secCount]]){
        UITextField*f=p[0]; UILabel*c=p[1]; c.text=[NSString stringWithFormat:@"%lu/32",(unsigned long)f.text.length];
        c.textColor=(f.text.length==32)?[SpotTheme green]:[SpotTheme faint];
    }
    _status.text=@"";
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if(tf==_cid) [_sec becomeFirstResponder]; else { [tf resignFirstResponder]; [self save]; }
    return YES;
}

- (void)save {
    [self hideKeyboard];
    if(_cid.text.length!=32 || _sec.text.length!=32){ _status.textColor=[SpotTheme muted]; _status.text=L(@"Client ID and Secret need exactly 32 characters each."); return; }
    if([_cid.text isEqualToString:_sec.text]){ _status.text=L(@"Client ID and Secret are the same – the secret is the second, hidden value."); return; }
    _save.enabled=NO; _save.alpha=0.5; _status.textColor=[SpotTheme muted]; _status.text=L(@"Checking key with Spotify …");
    [MMSpotify saveSearchKeyId:_cid.text secret:_sec.text completion:^(BOOL ok,NSString*err){
        _save.enabled=YES; _save.alpha=1;
        if(!ok){ _status.textColor=[UIColor colorWithRed:0.95 green:0.45 blue:0.45 alpha:1]; _status.text=err; return; }
        _status.textColor=[SpotTheme green]; _status.text=L(@"✅ Search unlocked!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.9*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ if(self.onDone) self.onDone(YES); });
    }];
}
- (void)removeKey {
    [MMSpotify removeSearchKey];
    if(self.onDone) self.onDone(NO);
}
- (void)skip { [self hideKeyboard]; if(self.onDone) self.onDone(NO); }
@end
