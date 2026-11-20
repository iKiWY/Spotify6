#import "MMPlaylistEditor.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MeshL10n.h"

@interface MMPlaylistEditor () <UIAlertViewDelegate>
@end
@implementation MMPlaylistEditor {
    UIAlertView *_alert;
    NSString *_playlistId;
    NSDictionary *_track;
    void (^_created)(NSDictionary *);
    void (^_renamed)(NSString *);
    BOOL _busy;
}
+ (MMPlaylistEditor *)shared {
    static MMPlaylistEditor*editor; static dispatch_once_t once;
    dispatch_once(&once, ^{ editor=[[self alloc] init]; }); return editor;
}
+ (void)createWithTrack:(NSDictionary *)track completion:(void(^)(NSDictionary *playlist))done {
    MMPlaylistEditor*e=[self shared]; if(e->_alert || e->_busy) return;
    e->_track=track; e->_created=[done copy]; e->_renamed=nil; e->_playlistId=nil;
    [e prompt:L(@"Create playlist") name:@""];
}
+ (void)rename:(NSString *)playlistId name:(NSString *)name completion:(void(^)(NSString *name))done {
    MMPlaylistEditor*e=[self shared]; if(e->_alert || e->_busy) return;
    e->_playlistId=playlistId; e->_renamed=[done copy]; e->_created=nil; e->_track=nil;
    [e prompt:L(@"Rename playlist") name:name];
}
- (void)prompt:(NSString *)title name:(NSString *)name {
    _alert=[[UIAlertView alloc] initWithTitle:title message:nil delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"),nil];
    _alert.alertViewStyle=UIAlertViewStylePlainTextInput;
    UITextField*f=[_alert textFieldAtIndex:0]; f.text=name; f.placeholder=L(@"Playlist name");
    f.autocapitalizationType=UITextAutocapitalizationTypeSentences;
    [_alert show];
}
- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alert {
    return [[[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0;
}
- (void)clear { _alert=nil; _playlistId=nil; _track=nil; _created=nil; _renamed=nil; _busy=NO; }
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
    NSString*name=[[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _alert=nil;
    if(index!=1 || !name.length){ [self clear]; return; }
    _busy=YES;
    if(_playlistId){
        [MMSpotify renamePlaylist:_playlistId name:name completion:^(BOOL ok){
            if(ok && _renamed) _renamed(name);
            if(!ok) [[MMRootController shared] showDownloadMessage:L(@"Couldn't save – please try again")];
            [self clear];
        }]; return;
    }
    [MMSpotify createPlaylist:name completion:^(NSDictionary*p,NSInteger st){
        if(!p){
            [[MMRootController shared] showDownloadMessage:st==429?L(@"Too many requests – wait a moment and retry."):st==403?L(@"Spotify did not allow this change. Please check your account permissions."):L(@"Couldn't save – please try again")];
            [self clear]; return;
        }
        if([_track[@"id"] length]){
            [MMSpotify addTrack:_track[@"id"] toPlaylist:p[@"id"] completion:^(BOOL ok){
                NSString*message=!ok?L(@"Playlist created, but the song could not be added. Please try again."):
                    ![p[@"saved"] boolValue]?L(@"Playlist created, but could not be saved to Library. Open More to retry."):LF(@"Added to %@",p[@"name"]);
                [[MMRootController shared] showDownloadMessage:message];
                if(_created) _created(p); [self clear];
            }];
        } else {
            if(![p[@"saved"] boolValue]) [[MMRootController shared] showDownloadMessage:L(@"Playlist created, but could not be saved to Library. Open More to retry.")];
            if(_created) _created(p); [self clear];
        }
    }];
}
@end
