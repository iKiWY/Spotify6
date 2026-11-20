#import "MMEqualizer.h"
#import <math.h>

static const double kMMEqualizerFrequencies[MM_EQUALIZER_BANDS]={31.25,62.5,125,250,500,1000,2000,4000,8000,16000};
static NSString * const kMMEqualizerGainsKey=@"equalizer.gains";
static NSString * const kMMEqualizerEnabledKey=@"equalizer.enabled";

@implementation MMEqualizer
+ (NSUInteger)bandCount { return MM_EQUALIZER_BANDS; }
+ (double)frequencyForBand:(NSUInteger)band { return band<MM_EQUALIZER_BANDS?kMMEqualizerFrequencies[band]:0; }
+ (NSString *)frequencyLabelForBand:(NSUInteger)band {
    static NSArray *labels=nil;
    if(!labels) labels=@[@"31 Hz",@"62 Hz",@"125 Hz",@"250 Hz",@"500 Hz",@"1 kHz",@"2 kHz",@"4 kHz",@"8 kHz",@"16 kHz"];
    return band<labels.count?labels[band]:@"";
}
+ (NSArray *)gains {
    NSArray *saved=[[NSUserDefaults standardUserDefaults] arrayForKey:kMMEqualizerGainsKey];
    NSMutableArray *values=[NSMutableArray arrayWithCapacity:MM_EQUALIZER_BANDS];
    for(NSUInteger i=0;i<MM_EQUALIZER_BANDS;i++){
        double gain=i<saved.count?[saved[i] doubleValue]:0;
        if(gain < -12)gain=-12; if(gain>12)gain=12;
        [values addObject:@(gain)];
    }
    return values;
}
+ (double)gainForBand:(NSUInteger)band { NSArray *values=[self gains]; return band<values.count?[values[band] doubleValue]:0; }
+ (void)saveGain:(double)gain forBand:(NSUInteger)band {
    if(band>=MM_EQUALIZER_BANDS)return;
    if(gain < -12)gain=-12; if(gain>12)gain=12;
    NSMutableArray *values=[[self gains] mutableCopy]; values[band]=@(gain);
    [[NSUserDefaults standardUserDefaults] setObject:values forKey:kMMEqualizerGainsKey];
}
+ (BOOL)isEnabled { return [[NSUserDefaults standardUserDefaults] boolForKey:kMMEqualizerEnabledKey]; }
+ (void)saveEnabled:(BOOL)enabled { [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kMMEqualizerEnabledKey]; }
+ (void)reset { [[NSUserDefaults standardUserDefaults] setObject:@[@0,@0,@0,@0,@0,@0,@0,@0,@0,@0] forKey:kMMEqualizerGainsKey]; }
+ (NSString *)presetName {
    if(![self isEnabled])return @"Off";
    for(NSNumber *gain in [self gains])if(fabs([gain doubleValue])>0.01)return @"Custom";
    return @"Flat";
}
@end
