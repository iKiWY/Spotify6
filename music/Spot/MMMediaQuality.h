#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MMMediaBitrate) {
    MMMediaBitrateOff = 0,
    MMMediaBitrate96 = 96,
    MMMediaBitrate160 = 160,
    MMMediaBitrate320 = 320
};

@interface MMMediaQuality : NSObject
+ (NSInteger)streamingBitrateForCurrentNetwork;
+ (NSInteger)downloadBitrateForCurrentNetwork;
+ (NSInteger)streamingBitrateForWiFi;
+ (NSInteger)streamingBitrateForMobile;
+ (NSInteger)downloadBitrateForWiFi;
+ (NSInteger)downloadBitrateForMobile;
+ (NSInteger)podcastStreamingBitrateForCurrentNetwork;
+ (NSInteger)podcastDownloadBitrateForCurrentNetwork;
+ (NSInteger)podcastStreamingBitrateForWiFi;
+ (NSInteger)podcastStreamingBitrateForMobile;
+ (NSInteger)podcastDownloadBitrateForWiFi;
+ (NSInteger)podcastDownloadBitrateForMobile;
+ (void)setStreamingBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi;
+ (void)setDownloadBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi;
+ (void)setPodcastStreamingBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi;
+ (void)setPodcastDownloadBitrate:(NSInteger)bitrate forWiFi:(BOOL)wifi;
+ (NSString *)labelForBitrate:(NSInteger)bitrate;
+ (NSString *)streamingSummary;
+ (NSString *)downloadSummary;
+ (NSString *)podcastStreamingSummary;
+ (NSString *)podcastDownloadSummary;
@end
