#import "MMMediaQuality.h"
#import "MMSpotify.h"

static NSString *const MMStreamWiFiKey = @"mediaQuality.stream.wifi";
static NSString *const MMStreamMobileKey = @"mediaQuality.stream.mobile";
static NSString *const MMDownloadWiFiKey = @"mediaQuality.download.wifi";
static NSString *const MMDownloadMobileKey = @"mediaQuality.download.mobile";
static NSString *const MMPodcastStreamWiFiKey = @"podcastQuality.stream.wifi";
static NSString *const MMPodcastStreamMobileKey = @"podcastQuality.stream.mobile";
static NSString *const MMPodcastDownloadWiFiKey = @"podcastQuality.download.wifi";
static NSString *const MMPodcastDownloadMobileKey = @"podcastQuality.download.mobile";

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
+ (NSInteger)podcastStreamingBitrateForWiFi { return [self valueForKey:MMPodcastStreamWiFiKey fallback:160 allowOff:NO]; }
+ (NSInteger)podcastStreamingBitrateForMobile { return [self valueForKey:MMPodcastStreamMobileKey fallback:96 allowOff:NO]; }
+ (NSInteger)podcastDownloadBitrateForWiFi { return [self valueForKey:MMPodcastDownloadWiFiKey fallback:160 allowOff:NO]; }
+ (NSInteger)podcastDownloadBitrateForMobile { return [self valueForKey:MMPodcastDownloadMobileKey fallback:0 allowOff:YES]; }
+ (NSInteger)streamingBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self streamingBitrateForWiFi]:[self streamingBitrateForMobile]; }
+ (NSInteger)downloadBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self downloadBitrateForWiFi]:[self downloadBitrateForMobile]; }
+ (NSInteger)podcastStreamingBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self podcastStreamingBitrateForWiFi]:[self podcastStreamingBitrateForMobile]; }
+ (NSInteger)podcastDownloadBitrateForCurrentNetwork { return [MMSpotify wifiReachable]?[self podcastDownloadBitrateForWiFi]:[self podcastDownloadBitrateForMobile]; }
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
+ (void)setPodcastStreamingBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi {
    [self setValue:bitrate key:wifi?MMPodcastStreamWiFiKey:MMPodcastStreamMobileKey allowOff:NO];
}
+ (void)setPodcastDownloadBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi {
    [self setValue:bitrate key:wifi?MMPodcastDownloadWiFiKey:MMPodcastDownloadMobileKey allowOff:!wifi];
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
+ (NSString *)podcastStreamingSummary {
    return [NSString stringWithFormat:@"Wi-Fi %@ · Mobile %@",[self labelForBitrate:[self podcastStreamingBitrateForWiFi]],[self labelForBitrate:[self podcastStreamingBitrateForMobile]]];
}
+ (NSString *)podcastDownloadSummary {
    return [NSString stringWithFormat:@"Wi-Fi %@ · Mobile %@",[self labelForBitrate:[self podcastDownloadBitrateForWiFi]],[self labelForBitrate:[self podcastDownloadBitrateForMobile]]];
}
@end
