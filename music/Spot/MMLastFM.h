#import <Foundation/Foundation.h>

@interface MMLastFM : NSObject
+ (BOOL)hasAppCredentials;
+ (BOOL)isConnected;
+ (NSString *)connectedUsername;
+ (NSString *)configuredAPIKey;
+ (NSString *)configuredAPISecret;
+ (NSString *)pendingAuthorizationURL;
+ (void)beginAuthorizationWithAPIKey:(NSString *)apiKey secret:(NSString *)secret completion:(void (^)(NSString *authorizationURL, NSString *error))done;
+ (void)completeAuthorization:(void (^)(BOOL ok, NSString *username, NSString *error))done;
+ (void)disconnect;
+ (void)updateNowPlayingTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album duration:(double)duration;
+ (void)scrobbleTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album duration:(double)duration timestamp:(long long)timestamp;
+ (void)flushQueuedScrobbles;
@end
