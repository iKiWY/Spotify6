#import <Foundation/Foundation.h>

#define MM_EQUALIZER_BANDS 10

@interface MMEqualizer : NSObject
+ (NSUInteger)bandCount;
+ (double)frequencyForBand:(NSUInteger)band;
+ (NSString *)frequencyLabelForBand:(NSUInteger)band;
+ (NSArray *)gains;
+ (double)gainForBand:(NSUInteger)band;
+ (void)saveGain:(double)gain forBand:(NSUInteger)band;
+ (BOOL)isEnabled;
+ (void)saveEnabled:(BOOL)enabled;
+ (void)reset;
+ (NSString *)presetName;
@end
