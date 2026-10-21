#import "MMBrowseController.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMRootController.h"
#import "MMTrackListController.h"
#import "MeshL10n.h"
#import "MMSpotify.h"
#import "MMKeySetupController.h"

@interface MMBrowseController () <UIAlertViewDelegate>
@end

@implementation MMBrowseController {
    UIScrollView *_sc; CGFloat _W; NSArray *_cats;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(NO)];
    self.view.backgroundColor=[SpotTheme ios6]?[SpotTheme shelfColor]:[SpotTheme pageBackground];   // iOS 6: Grund wie die Startseite
    _W=self.view.bounds.size.width;

    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(16,10,_W-32,30)];
    t.autoresizingMask=UIViewAutoresizingFlexibleWidth; t.text=L(@"Browse all"); t.font=[UIFont boldSystemFontOfSize:22]; t.textColor=[SpotTheme ink]; [self.view addSubview:t];

    _sc=[[UIScrollView alloc] initWithFrame:CGRectMake(0,46,_W,self.view.bounds.size.height-46)];
    _sc.contentInset=UIEdgeInsetsMake(8,0,MMPageBottomInset(84),0); _sc.alwaysBounceVertical=YES;   // Platz für Now-Playing + Download-Leiste
    _sc.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_sc];

    // name / RGB-Farbe / Such-Query (q bereits URL-kodiert: %22 = ")
    _cats=@[
      @{@"name":L(@"Pop"),             @"c":@[@0.90,@0.22,@0.46], @"q":@"genre:%22pop%22"},
      @{@"name":L(@"Hip-Hop"),         @"c":@[@0.95,@0.55,@0.15], @"q":@"genre:%22hip-hop%22"},
      @{@"name":L(@"Rock"),            @"c":@[@0.72,@0.16,@0.16], @"q":@"genre:%22rock%22"},
      @{@"name":L(@"Dance/Electronic"),@"c":@[@0.15,@0.42,@0.85], @"q":@"genre:%22edm%22"},
      @{@"name":L(@"R&B"),             @"c":@[@0.55,@0.20,@0.70], @"q":@"genre:%22r-n-b%22"},
      @{@"name":L(@"Indie"),           @"c":@[@0.10,@0.60,@0.55], @"q":@"genre:%22indie%22"},
      @{@"name":L(@"Chill"),           @"c":@[@0.18,@0.55,@0.45], @"q":@"genre:%22chill%22"},
      @{@"name":L(@"Workout"),         @"c":@[@0.85,@0.25,@0.25], @"q":@"workout"},
      @{@"name":L(@"Focus"),           @"c":@[@0.30,@0.35,@0.45], @"q":@"focus"},
      @{@"name":L(@"Party"),           @"c":@[@0.80,@0.15,@0.55], @"q":@"party"},
      @{@"name":L(@"Jazz"),            @"c":@[@0.50,@0.33,@0.18], @"q":@"genre:%22jazz%22"},
      @{@"name":L(@"Classical"),       @"c":@[@0.20,@0.40,@0.30], @"q":@"genre:%22classical%22"},
      @{@"name":L(@"Metal"),           @"c":@[@0.25,@0.25,@0.28], @"q":@"genre:%22metal%22"},
      @{@"name":L(@"Latin"),           @"c":@[@0.90,@0.45,@0.10], @"q":@"genre:%22latin%22"},
      @{@"name":L(@"Country"),         @"c":@[@0.65,@0.45,@0.20], @"q":@"genre:%22country%22"},
      @{@"name":L(@"Soul"),            @"c":@[@0.55,@0.25,@0.35], @"q":@"genre:%22soul%22"},
    ];
    [self buildGrid];
}

- (void)buildGrid {
    for(UIView*v in [_sc.subviews copy]) if(v.tag>=1000) [v removeFromSuperview];   // Neuaufbau nach dem Drehen: alte Kacheln weg
    NSInteger cols=MMGridColumns(_W);   // iPhone 2, iPad 3-4
    CGFloat gap=12, tileW=(_W-16*2-gap*(cols-1))/cols, tileH=68;
    for(int i=0;i<(int)_cats.count;i++){
        NSDictionary*cat=_cats[i]; NSArray*c=cat[@"c"];
        CGFloat col=i%cols, rowY=(i/cols)*(tileH+gap);
        UIView*tile=[[UIView alloc] initWithFrame:CGRectMake(16+col*(tileW+gap),rowY,tileW,tileH)];
        UIColor*tint=[UIColor colorWithRed:[c[0] floatValue] green:[c[1] floatValue] blue:[c[2] floatValue] alpha:1];
        tile.backgroundColor=tint; tile.layer.cornerRadius=6; tile.clipsToBounds=YES; tile.tag=1000+i;
        if([SpotTheme ios6]){   // glänzender, abgerundeter Knopf mit Schatten
            tile.backgroundColor=[UIColor clearColor]; tile.clipsToBounds=NO; tile.layer.cornerRadius=10;
            UIImageView*g=[[UIImageView alloc] initWithFrame:tile.bounds]; g.image=[SpotTheme glossyImage:tint radius:10 size:tile.bounds.size]; [tile addSubview:g];
            tile.layer.shadowColor=[UIColor blackColor].CGColor; tile.layer.shadowOpacity=0.35; tile.layer.shadowRadius=2; tile.layer.shadowOffset=CGSizeMake(0,1.5);
            tile.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:tile.bounds cornerRadius:10].CGPath; }
        UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(12,8,tileW-24,tileH-16)];
        nm.text=cat[@"name"]; nm.numberOfLines=2; nm.font=[UIFont boldSystemFontOfSize:16]; nm.textColor=[UIColor whiteColor]; nm.backgroundColor=[UIColor clearColor];
        if([SpotTheme ios6]){ nm.shadowColor=[UIColor colorWithWhite:0 alpha:0.4]; nm.shadowOffset=CGSizeMake(0,-1); }
        [tile addSubview:nm];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=i; [tap addTarget:self action:@selector(open:) forControlEvents:UIControlEventTouchUpInside]; [tile addSubview:tap];
        [_sc addSubview:tile];
    }
    int rows=((int)_cats.count+(int)cols-1)/(int)cols; _sc.contentSize=CGSizeMake(_W,rows*(tileH+gap)+10);
}
- (void)relayoutForSize:(CGSize)size { _W=size.width; [self buildGrid]; }   // iPad gedreht

- (void)open:(UIButton *)b {
    if(b.tag>=(int)_cats.count) return;
    if(![MMSpotify hasSearchKey]){   // Durchsuchen = Suche: braucht den eigenen Entwicklerschlüssel
        UIAlertView*a=[[UIAlertView alloc] initWithTitle:L(@"Unlock search") message:L(@"Browse uses search, which needs your own free Spotify developer key.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Set up"),nil];
        [a show]; return; }
    NSDictionary*cat=_cats[b.tag];
    NSString*path=[NSString stringWithFormat:@"search?q=%@&type=track&limit=10",cat[@"q"]];   // mehr als 10 pro Seite lehnt die Web-API für Entwicklerschlüssel ab (400); weitere Seiten lädt die Liste beim Scrollen
    MMTrackListController*tl=[[MMTrackListController alloc] initWithTitle:cat[@"name"] path:path];
    [[MMRootController shared] pushContent:tl];   // im Inhaltsbereich -> untere Leisten bleiben sichtbar
}
- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)i {
    if(i!=a.firstOtherButtonIndex) return;
    MMKeySetupController*k=[[MMKeySetupController alloc] init]; k.skippable=NO;
    k.onDone=^(BOOL saved){ [[MMRootController shared] popContent]; };
    [[MMRootController shared] pushContent:k];
}
@end
