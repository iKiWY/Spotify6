#import <UIKit/UIKit.h>
// Gemeinsamer Cover-Cache: RAM (NSCache) + Platte (Library/Riff/.spotcache/img im App-Container).
// Verhindert, dass dasselbe Cover auf jedem Screen neu aus dem Netz geladen wird.
@interface MMCovers : NSObject
+ (NSString *)bestURL:(id)images;                                // wählt ein scharfes (mittleres) Cover statt des kleinsten
+ (UIImage *)cached:(NSString *)url;                              // sofort aus RAM, sonst nil
+ (void)load:(NSString *)url into:(UIImageView *)iv;             // RAM->Platte->Netz, setzt Bild auf Main
+ (void)load:(NSString *)url completion:(void(^)(UIImage *img))done;
+ (void)thumb:(NSString *)url size:(CGFloat)pt radius:(CGFloat)r into:(UIImageView *)iv;   // verkleinert + dekodiert im Hintergrund (für lange Listen)
+ (void)prefetch:(NSString *)url;
// Lieblingssongs: Spotifys eigenes Bild; bis es geladen ist (oder offline) lila Fläche mit Herz. Reuse-sicher.
+ (void)likedCoverInto:(UIImageView *)iv;
+ (BOOL)onDisk:(NSString *)url;                                  // liegt das Cover schon auf der Platte?
// Cover aller Playlists + Lieblingssongs nach und nach auf die Platte holen (ohne Dopplungen)
+ (void)precacheLibrary;
// Playlist ohne eigenes Bild: 2x2-Mosaik aus den ersten Album-Covern (wie die Spotify-App), gemerkt auf der Platte.
// done(url) mit einer Bild-URL für load:, oder nil wenn keine Titel/Cover da sind.
+ (void)playlistPlaceholderInto:(UIImageView *)imageView;
+ (void)invalidateEmptyPlaylistCover:(NSString *)playlistId;
+ (void)invalidatePlaylistCover:(NSString *)playlistId;
+ (void)playlistCover:(NSString *)playlistId completion:(void(^)(NSString *url))done;                                // Cover schonend (seriell) auf die Platte holen (Offline)
@end
