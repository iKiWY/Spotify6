// MMRootController.h - Container im Spotify-Look: Inhaltsbereich + Now-Playing-Leiste + Tab-Leiste.
#import <UIKit/UIKit.h>
#define MMStatusH 20   // Höhe der Statusleiste über dem Inhalt (normale Oberfläche)
@interface MMRootController : UIViewController
+ (instancetype)shared;
+ (void)confirmLogout;
+ (void)switchSkin:(NSString *)skin;   // Skin wechseln ohne Neustart: Oberfläche neu aufbauen, Wiedergabe und Warteschlange bleiben   // fragt nach, meldet ab und schließt Spotify6 (beim nächsten Start: Anmeldung)
- (void)showNowPlayingTitle:(NSString *)title artist:(NSString *)artist;  // Now-Playing-Leiste füllen
// Spielt einen echten Track ab (Titel/Artist provisorisch; echte Metadaten + Cover werden nachgeladen).
- (void)playTrackId:(NSString *)trackId title:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover;
// Spielt eine Liste (Dicts mit id/title/artist) ab Index idx -> Weiter/Zurück innerhalb der Liste.
- (void)playList:(NSArray *)list index:(NSInteger)idx;
// dasselbe mit Herkunft {type: playlist|album|artist|liked, id, name, images} für den Verlauf auf der Startseite
- (void)playList:(NSArray *)list index:(NSInteger)idx context:(NSDictionary *)context;
- (void)playNext;
// Warteschlange: Titel {id,title,artist,cover} oben (next=YES) oder unten in die eingereihten Titel; Liste + Position; zu Index springen
- (void)queueTrack:(NSDictionary *)track next:(BOOL)next;
- (NSArray *)queue;
- (NSInteger)queueIndex;
- (void)playQueueIndex:(NSInteger)idx;
- (void)moveQueueFrom:(NSInteger)from to:(NSInteger)to;   // Indizes in queue, beide nach dem laufenden Titel
// Von Hand eingereihte Titel (laufen vor dem Rest der Liste): Liste, umsortieren, zu einem springen
- (NSArray *)userQueue;
- (void)moveUserQueueFrom:(NSInteger)from to:(NSInteger)to;
- (void)playUserQueueIndex:(NSInteger)idx;
@property (nonatomic) BOOL repeatQueue;       // eingereihte Titel endlos wiederholen
@property (nonatomic) BOOL nextUpEnabled;     // aus = nach dem laufenden Titel und der Warteschlange stoppen
- (void)openQueue;                            // Warteschlange als Vollbild
- (void)clearUserQueue;                        // ganze Warteschlange leeren
- (void)removeUserQueueIndex:(NSInteger)idx;   // eingereihten Titel entfernen
- (void)removeQueueIndex:(NSInteger)idx;       // kommenden Titel der Liste entfernen (Index in queue, nach dem laufenden)
// Seite im Inhaltsbereich zeigen; offene Vollbild-Ansichten (Player, Warteschlange) schließen sich vorher
- (void)showContent:(UIViewController *)vc;
// Zufallswiedergabe: mischt die Warteschlange (aktueller Titel bleibt), aus = ursprüngliche Reihenfolge
@property (nonatomic, readonly) BOOL shuffle;
- (void)setShuffle:(BOOL)on;
// Wiederholen: 0 = aus, 1 = ganze Liste, 2 = aktueller Titel
@property (nonatomic, assign) NSInteger repeatMode;
- (void)playPrev;
- (void)openPlayer;
// Aktueller Titel {id,title,artist,cover,index,count,albumId,album,artistId} (Album/Artist leer bis die Metadaten da sind) (nil = nichts geladen), Play/Pause, Modus an/aus
- (NSDictionary *)nowPlaying;
- (void)togglePlayPause;
// Cover Flow im Vollbild-Querformat (öffnet auch automatisch, wenn der iPod quer gedreht wird)
- (void)showCoverFlow;
+ (BOOL)coverFlowOnRotate;                   // Einstellung: Cover Flow beim Querdrehen öffnen (Standard: an)
+ (void)setCoverFlowOnRotate:(BOOL)on;
// Ansicht im Inhaltsbereich öffnen/schließen (bleibt über Tab-/Now-Playing-/Download-Leiste)
- (void)pushContent:(UIViewController *)vc;
- (CGRect)contentBounds;      // Größe des Inhaltsbereichs (iPad: rechts neben der Seitenleiste, über der Player-Leiste)
- (CGFloat)bottomBarsHeight;   // Höhe der gerade sichtbaren Leisten über der Tab-Leiste (Now-Playing + Download)
- (void)popContent;
- (BOOL)hasPushedContent;   // liegt eine Seite (Playlist, Album …) über dem Tab
// globale Offline-Download-Leiste (immer sichtbar wenn aktiv)
- (void)showDownloadProgress:(NSInteger)done total:(NSInteger)total;
- (void)showDownloadMessage:(NSString *)msg;
@end
