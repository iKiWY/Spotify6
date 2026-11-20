#import <UIKit/UIKit.h>

@interface MMPlaylistEditor : NSObject
// Creates an unpublished playlist and optionally adds the song before opening/calling back.
+ (void)createWithTrack:(NSDictionary *)track completion:(void(^)(NSDictionary *playlist))done;
+ (void)rename:(NSString *)playlistId name:(NSString *)name completion:(void(^)(NSString *name))done;
@end
