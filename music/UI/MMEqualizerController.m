#import "MMEqualizerController.h"
#import "MMAudio.h"
#import "MMEqualizer.h"
#import "SpotTheme.h"
#import "MMLayout.h"
#import "MMRootController.h"
#import "MeshL10n.h"
#import <QuartzCore/QuartzCore.h>

#define EQ_BAND_COUNT 10

@implementation MMEqualizerController {
    UIButton *_backButton;
    UIButton *_resetButton;
    UILabel *_titleLabel;
    UIView *_enabledRow;
    UILabel *_enabledTitle;
    UISwitch *_enabled;
    UIView *_panel;
    UIView *_zeroLine;
    UILabel *_plusTwelve;
    UILabel *_zero;
    UILabel *_minusTwelve;
    UILabel *_activeValue;
    UISlider *_sliders[EQ_BAND_COUNT];
    UILabel *_frequencies[EQ_BAND_COUNT];
    NSUInteger _valueGeneration;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:MMPageFrame(YES)];
    self.view.backgroundColor=[SpotTheme pageBackground];

    _backButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [_backButton setTitle:L(@"Back") forState:UIControlStateNormal];
    [SpotTheme styleBackButton:_backButton];
    [_backButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_backButton];

    _titleLabel=[[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text=L(@"Equalizer");
    _titleLabel.textAlignment=NSTextAlignmentCenter;
    _titleLabel.font=[UIFont boldSystemFontOfSize:16];
    _titleLabel.textColor=[SpotTheme ink];
    _titleLabel.backgroundColor=[UIColor clearColor];
    [self.view addSubview:_titleLabel];

    _resetButton=[UIButton buttonWithType:UIButtonTypeCustom];
    _resetButton.frame=CGRectMake(0,0,72,44);
    [_resetButton setTitle:L(@"Flat") forState:UIControlStateNormal];
    [SpotTheme styleActionButton:_resetButton primary:NO];
    // Keep the action legible in the Spotify skin, where action buttons have
    // no filled background. On classic iOS the native toolbar face stays intact.
    if(![SpotTheme ios6]) [_resetButton setTitleColor:[SpotTheme green] forState:UIControlStateNormal];
    _resetButton.accessibilityLabel=L(@"Set all equalizer bands to flat");
    [_resetButton addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];

    _enabledRow=[[UIView alloc] initWithFrame:CGRectZero];
    if([SpotTheme ios6]) [SpotTheme groupedTile:_enabledRow];
    else {
        _enabledRow.backgroundColor=[SpotTheme card];
        _enabledRow.layer.cornerRadius=4;
    }
    [self.view addSubview:_enabledRow];
    [_enabledRow addSubview:_resetButton];

    _enabledTitle=[[UILabel alloc] initWithFrame:CGRectZero];
    _enabledTitle.text=L(@"Enable equalizer");
    _enabledTitle.font=[UIFont systemFontOfSize:16];
    _enabledTitle.textColor=[SpotTheme ink];
    _enabledTitle.backgroundColor=[UIColor clearColor];
    [_enabledRow addSubview:_enabledTitle];

    _enabled=[[UISwitch alloc] initWithFrame:CGRectZero];
    _enabled.onTintColor=[SpotTheme green];
    _enabled.on=[MMAudio isEqualizerEnabled];
    [_enabled addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    [_enabledRow addSubview:_enabled];

    _panel=[[UIView alloc] initWithFrame:CGRectZero];
    if([SpotTheme ios6]) [SpotTheme groupedTile:_panel];
    else {
        _panel.backgroundColor=[SpotTheme card];
        _panel.layer.cornerRadius=4;
    }
    [self.view addSubview:_panel];

    _activeValue=[[UILabel alloc] initWithFrame:CGRectZero];
    _activeValue.textAlignment=NSTextAlignmentCenter;
    _activeValue.font=[UIFont boldSystemFontOfSize:12];
    _activeValue.textColor=[SpotTheme green];
    _activeValue.backgroundColor=[UIColor clearColor];
    _activeValue.alpha=0;
    [_panel addSubview:_activeValue];

    _plusTwelve=[[UILabel alloc] initWithFrame:CGRectZero];
    _zero=[[UILabel alloc] initWithFrame:CGRectZero];
    _minusTwelve=[[UILabel alloc] initWithFrame:CGRectZero];
    for(UILabel *scale in @[_plusTwelve,_zero,_minusTwelve]){
        scale.font=[UIFont systemFontOfSize:9];
        scale.textAlignment=NSTextAlignmentCenter;
        scale.textColor=[SpotTheme muted];
        scale.backgroundColor=[UIColor clearColor];
        [_panel addSubview:scale];
    }
    _plusTwelve.text=@"+12";
    _zero.text=@"0";
    _minusTwelve.text=@"−12";

    _zeroLine=[[UIView alloc] initWithFrame:CGRectZero];
    _zeroLine.backgroundColor=[SpotTheme faint];
    _zeroLine.alpha=0.8;
    [_panel addSubview:_zeroLine];

    NSArray *gains=[MMEqualizer gains];
    for(NSUInteger i=0;i<EQ_BAND_COUNT;i++){
        UISlider *slider=[[UISlider alloc] initWithFrame:CGRectZero];
        slider.transform=CGAffineTransformMakeRotation(-M_PI_2);
        slider.minimumValue=-12;
        slider.maximumValue=12;
        slider.value=[gains[i] floatValue];
        slider.minimumTrackTintColor=[SpotTheme green];
        slider.tag=(NSInteger)i;
        slider.accessibilityLabel=[MMEqualizer frequencyLabelForBand:i];
        slider.accessibilityValue=[NSString stringWithFormat:@"%+.1f dB",slider.value];
        [slider addTarget:self action:@selector(beginChange:) forControlEvents:UIControlEventTouchDown];
        [slider addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(endChange:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        [_panel addSubview:slider];
        _sliders[i]=slider;

        UILabel *frequency=[[UILabel alloc] initWithFrame:CGRectZero];
        NSString *label=[MMEqualizer frequencyLabelForBand:i];
        label=[label stringByReplacingOccurrencesOfString:@" kHz" withString:@"k"];
        label=[label stringByReplacingOccurrencesOfString:@" Hz" withString:@""];
        frequency.text=label;
        frequency.textAlignment=NSTextAlignmentCenter;
        frequency.font=[UIFont systemFontOfSize:9];
        frequency.adjustsFontSizeToFitWidth=YES;
        frequency.textColor=[SpotTheme muted];
        frequency.backgroundColor=[UIColor clearColor];
        frequency.accessibilityElementsHidden=YES;
        [_panel addSubview:frequency];
        _frequencies[i]=frequency;
    }
    self.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=self.view.bounds.size.width;
    CGFloat height=self.view.bounds.size.height;

    _backButton.frame=CGRectMake(12,5,72,34);
    _titleLabel.frame=CGRectMake(84,4,width-96,36);

    CGFloat rowX=12, rowY=50, rowWidth=width-24, rowHeight=52;
    _enabledRow.frame=CGRectMake(rowX,rowY,rowWidth,rowHeight);
    [_enabled sizeToFit];
    CGFloat switchX=rowWidth-16-_enabled.bounds.size.width;
    _enabled.frame=CGRectMake(switchX,(rowHeight-_enabled.bounds.size.height)/2,
                              _enabled.bounds.size.width,_enabled.bounds.size.height);
    CGFloat flatWidth=64;
    CGFloat flatX=switchX-flatWidth-8;
    _resetButton.frame=CGRectMake(flatX,(rowHeight-36)/2,flatWidth,36);
    _enabledTitle.frame=CGRectMake(16,0,MAX(80,flatX-24),rowHeight);

    CGFloat panelWidth=MIN(width-20,620);
    CGFloat panelX=(width-panelWidth)/2;
    CGFloat panelY=112;
    // On iPhone the mini player and download progress bar are sibling overlays
    // above this page. Keep the EQ card clear of their actual visible height.
    CGFloat bottomInset=MMIsPad()?0:[[MMRootController shared] bottomBarsHeight];
    CGFloat panelHeight=MAX(150,height-panelY-14-bottomInset);
    _panel.frame=CGRectMake(panelX,panelY,panelWidth,panelHeight);

    CGFloat axisWidth=28;
    CGFloat left=axisWidth+3;
    CGFloat right=8;
    CGFloat columnsWidth=MAX(10,panelWidth-left-right);
    CGFloat bandWidth=columnsWidth/EQ_BAND_COUNT;
    CGFloat sliderTop=43;
    CGFloat sliderBottom=panelHeight-37;
    CGFloat sliderLength=MAX(90,sliderBottom-sliderTop);
    CGFloat sliderCenterY=(sliderTop+sliderBottom)/2;
    CGFloat trackWidth=MIN(34,MAX(23,bandWidth-3));
    CGFloat axisX=4;

    _activeValue.frame=CGRectMake(left,7,columnsWidth,22);
    _plusTwelve.frame=CGRectMake(axisX,sliderTop-7,axisWidth-3,16);
    _zero.frame=CGRectMake(axisX,sliderCenterY-8,axisWidth-3,16);
    _minusTwelve.frame=CGRectMake(axisX,sliderBottom-9,axisWidth-3,16);
    _zeroLine.frame=CGRectMake(left,sliderCenterY,columnsWidth,1);

    CGFloat frequencyY=panelHeight-29;
    for(NSUInteger i=0;i<EQ_BAND_COUNT;i++){
        CGFloat x=left+i*bandWidth;
        CGFloat centerX=x+bandWidth/2;
        UISlider *slider=_sliders[i];
        slider.bounds=CGRectMake(0,0,sliderLength,trackWidth);
        slider.center=CGPointMake(centerX,sliderCenterY);
        _frequencies[i].frame=CGRectMake(x,frequencyY,bandWidth,18);
    }
}

- (void)showValueForSlider:(UISlider *)slider {
    NSUInteger band=(NSUInteger)slider.tag;
    _activeValue.text=[NSString stringWithFormat:@"%@   %+.1f dB",
                       [MMEqualizer frequencyLabelForBand:band],slider.value];
    slider.accessibilityValue=[NSString stringWithFormat:@"%+.1f dB",slider.value];
    _activeValue.alpha=1;
    _valueGeneration++;
}

- (void)beginChange:(UISlider *)slider { [self showValueForSlider:slider]; }
- (void)change:(UISlider *)slider {
    slider.value=roundf(slider.value*2.0f)/2.0f;
    [MMAudio setEqualizerGain:slider.value forBand:(NSUInteger)slider.tag];
    [self showValueForSlider:slider];
}
- (void)endChange:(UISlider *)slider {
    NSUInteger generation=++_valueGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.9*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(generation==self->_valueGeneration) self->_activeValue.alpha=0;
    });
}
- (void)toggle:(UISwitch *)sender { [MMAudio setEqualizerEnabled:sender.on]; }
- (void)reset {
    [MMEqualizer reset];
    for(NSUInteger i=0;i<EQ_BAND_COUNT;i++){
        _sliders[i].value=0;
        [MMAudio setEqualizerGain:0 forBand:i];
    }
    _activeValue.text=L(@"Flat");
    _activeValue.alpha=1;
    NSUInteger generation=++_valueGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.9*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(generation==self->_valueGeneration) self->_activeValue.alpha=0;
    });
}
- (void)close { [[MMRootController shared] popContent]; }
@end
