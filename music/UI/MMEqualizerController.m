#import "MMEqualizerController.h"
#import "MMAudio.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMRootController.h"
#import "MeshL10n.h"

#define EQ_BAND_COUNT 10

@implementation MMEqualizerController {
    UISwitch *_enabled;
    UISlider *_sliders[EQ_BAND_COUNT];
    UILabel *_values[EQ_BAND_COUNT];
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme pageBackground];
    CGFloat w=self.view.bounds.size.width, h=self.view.bounds.size.height;

    UIButton *back=[UIButton buttonWithType:UIButtonTypeCustom];
    back.frame=CGRectMake(8,8,80,34); [SpotTheme styleBackButton:back];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:back];

    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(90,8,w-180,34)];
    title.text=L(@"Equalizer"); title.textAlignment=NSTextAlignmentCenter;
    title.font=[UIFont boldSystemFontOfSize:16]; title.textColor=[SpotTheme ink];
    title.backgroundColor=[UIColor clearColor]; title.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    UILabel *onLabel=[[UILabel alloc] initWithFrame:CGRectMake(20,56,w-100,40)];
    onLabel.text=L(@"Enable equalizer"); onLabel.textColor=[SpotTheme ink];
    onLabel.font=[UIFont systemFontOfSize:16]; onLabel.backgroundColor=[UIColor clearColor];
    onLabel.autoresizingMask=UIViewAutoresizingFlexibleWidth; [self.view addSubview:onLabel];
    _enabled=[[UISwitch alloc] initWithFrame:CGRectZero];
    _enabled.onTintColor=[SpotTheme green]; _enabled.on=[MMAudio isEqualizerEnabled];
    _enabled.frame=CGRectMake(w-75,60,60,32); _enabled.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [_enabled addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_enabled];

    CGFloat top=112, bottom=62;
    CGFloat controlHeight=MAX(150,MIN(h-top-bottom-58,330));
    CGFloat viewportWidth=w-24;
    BOOL compact=viewportWidth<560;
    CGFloat bandWidth=compact?58:MIN(62,viewportWidth/10.0);
    CGFloat contentWidth=MAX(viewportWidth,bandWidth*EQ_BAND_COUNT);
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(12,top,viewportWidth,controlHeight+48)];
    scroll.backgroundColor=[UIColor clearColor]; scroll.showsHorizontalScrollIndicator=compact;
    scroll.alwaysBounceHorizontal=compact; scroll.contentSize=CGSizeMake(contentWidth,controlHeight+48);
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scroll];

    CGFloat sliderTop=28, sliderHeight=controlHeight-58;
    CGFloat centerY=sliderTop+sliderHeight/2+12;
    UIView *zeroLine=[[UIView alloc] initWithFrame:CGRectMake(0,centerY,contentWidth,1)];
    zeroLine.backgroundColor=[SpotTheme faint]; zeroLine.alpha=0.7; [scroll addSubview:zeroLine];
    UILabel *zero=[[UILabel alloc] initWithFrame:CGRectMake(0,centerY-17,bandWidth,15)];
    zero.text=@"0 dB"; zero.textAlignment=NSTextAlignmentCenter; zero.font=[UIFont systemFontOfSize:10];
    zero.textColor=[SpotTheme faint]; zero.backgroundColor=[SpotTheme pageBackground]; [scroll addSubview:zero];

    NSArray *freq=@[@"31 Hz",@"62 Hz",@"125 Hz",@"250 Hz",@"500 Hz",@"1 kHz",@"2 kHz",@"4 kHz",@"8 kHz",@"16 kHz"];
    NSArray *gains=[[NSUserDefaults standardUserDefaults] arrayForKey:@"equalizer.gains"];
    for(int i=0;i<EQ_BAND_COUNT;i++){
        CGFloat x=i*bandWidth, cx=x+bandWidth/2;
        UILabel *value=[[UILabel alloc] initWithFrame:CGRectMake(x,0,bandWidth,20)];
        value.textAlignment=NSTextAlignmentCenter; value.font=[UIFont systemFontOfSize:11];
        value.textColor=[SpotTheme ink]; value.backgroundColor=[UIColor clearColor];
        [scroll addSubview:value]; _values[i]=value;

        UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(cx-sliderHeight/2,sliderTop+sliderHeight/2,sliderHeight,32)];
        slider.transform=CGAffineTransformMakeRotation(-M_PI_2);
        slider.minimumValue=-12; slider.maximumValue=12;
        slider.value=i<gains.count?[gains[i] floatValue]:0; slider.minimumTrackTintColor=[SpotTheme green];
        slider.tag=i; slider.accessibilityLabel=freq[i];
        [slider addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
        [scroll addSubview:slider]; _sliders[i]=slider;

        UILabel *frequency=[[UILabel alloc] initWithFrame:CGRectMake(x,controlHeight-18,bandWidth,24)];
        frequency.text=freq[i]; frequency.textAlignment=NSTextAlignmentCenter;
        frequency.font=[UIFont systemFontOfSize:11]; frequency.textColor=[SpotTheme muted];
        frequency.backgroundColor=[UIColor clearColor]; [scroll addSubview:frequency];
        [self showValue:i];
    }

    UIButton *reset=[UIButton buttonWithType:UIButtonTypeRoundedRect];
    reset.frame=CGRectMake(20,h-54,w-40,42); reset.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    [reset setTitle:L(@"Reset") forState:UIControlStateNormal];
    [reset setTitleColor:[SpotTheme green] forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reset];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
}

- (void)showValue:(int)i { _values[i].text=[NSString stringWithFormat:@"%+.0f dB",_sliders[i].value]; }
- (void)toggle:(UISwitch *)s { [MMAudio setEqualizerEnabled:s.on]; }
- (void)change:(UISlider *)s { [MMAudio setEqualizerGain:s.value forBand:(NSUInteger)s.tag]; [self showValue:(int)s.tag]; }
- (void)reset {
    for(int i=0;i<EQ_BAND_COUNT;i++){ _sliders[i].value=0; [MMAudio setEqualizerGain:0 forBand:(NSUInteger)i]; [self showValue:i]; }
}
- (void)close { [[MMRootController shared] popContent]; }
@end
