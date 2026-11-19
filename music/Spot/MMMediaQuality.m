#import "MMMediaQuality.h"
#import "MMSpotify.h"

static NSString *const MMStreamWiFiKey = @"mediaQuality.stream.wifi";
static NSString *const MMStreamMobileKey = @"mediaQuality.stream.mobile";
static NSString *const MMDownloadWiFiKey = @"mediaQuality.download.wifi";
static NSString *const MMDownloadMobileKey = @"mediaQuality.download.mobile";

static NSInteger normalizedBitrate(NSInteger value, BOOL allowOff) {
    if(allowOff && value == MMMediaBitrateOff) return value;
    if(value == MMMediaBitrate96 || value == MMMediaBitrate160 || value == MMMediaBitrate320) return value;
    return MMMediaBitrate160;
}

@implementation MMMediaQuality
+ (NSInteger)valueForKey:(NSString *)key fallback:(NSInteger)fallback allowOff:(BOOL)allowOff {
    id value=[[NSUserDefaults standardUserDefaults] objectForKey:key];
    return value?normalizedBitrate([value integerValue],allowOff):fallback;
}
+ (NSInteger)streamingBitrateForWiFi { return [self valueForKey:MMStreamWiFiKey fallback:160 allowOff:NO]; }
+ (NSInteger)streamingBitrateForMobile { return [self valueForKey:MMStreamMobileKey fallback:96 allowOff:NO]; }
+ (NSInteger)downloadBitrateForWiFi { return [self valueForKey:MMDownloadWiFiKey fallback:320 allowOff:NO]; }
+ (NSInteger)downloadBitrateForMobile { return [self valueForKey:MMDownloadMobileKey fallback:0 allowOff:YES]; }
+ (NSInteger)streamingBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self streamingBitrateForWiFi]:[self streamingBitrateForMobile]; }
+ (NSInteger)downloadBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self downloadBitrateForWiFi]:[self downloadBitrateForMobile]; }
+ (void)setValue:(NSInteger)bitrate key:(NSString *)key allowOff:(BOOL)allowOff {
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedBitrate(bitrate,allowOff) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
+ (void)setStreamingBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi {
    [self setValue:bitrate key:wifi?MMStreamWiFiKey:MMStreamMobileKey allowOff:NO];
}
+ (void)setDownloadBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi {
    [self setValue:bitrate key:wifi?MMDownloadWiFiKey:MMDownloadMobileKey allowOff:!wifi];
    [MMSpotify resumeQueuedDownloads];
}
+ (NSString *)labelForBitrate:(NSInteger)bitrate {
    if(bitrate<=0) return @"Off";
    return [NSString stringWithFormat:@"%ld kbps",(long)bitrate];
}
+ (NSString *)streamingSummary {
    return [NSString stringWithFormat:@"Wi-Fi %@ · Mobile %@",[self labelForBitrate:[self streamingBitrateForWiFi]],[self labelForBitrate:[self streamingBitrateForMobile]]];
}
+ (NSString *)downloadSummary {
    return [NSString stringWithFormat:@"Wi-Fi %@ · Mobile %@",[self labelForBitrate:[self downloadBitrateForWiFi]],[self labelForBitrate:[self downloadBitrateForMobile]]];
}
@end
