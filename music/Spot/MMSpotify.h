// MMSpotify.h - Spotify-Login über den Access-Point (Handshake + Shannon + Token-Auth).
// Portiert aus den bewiesenen Mac-Tools. Läuft im Hintergrund, meldet Ergebnis auf dem Main-Thread.
#import <Foundation/Foundation.h>

// Alle Daten (Login, Tokens, Downloads, Cache) liegen im App-Container unter Library/Riff:
// Spotify6 ist eine Nutzer-App (IPA) in der Sandbox, /var/mobile ist dort nicht beschreibbar.
NSString *MMDataDir(void);              // <Container>/Library/Riff (wird angelegt)
NSString *MMPath(NSString *relative);   // <Container>/Library/Riff/<relative>
void MMLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);   // ins App-Log (Library/Riff/.spotify-log)

#define MMTrackLoadProgress @"MMTrackLoadProgress"   // Notification beim Laden eines angetippten Titels: {id, frac 0..1}
@interface MMSpotify : NSObject
// Login mit OAuth-Access-Token. done: ok, canonical_username, fehlertext.
+ (void)loginWithToken:(NSString *)token completion:(void(^)(BOOL ok, NSString *username, NSString *error))done;
// Gibt es gespeicherte (wiederverwendbare) Zugangsdaten?
+ (BOOL)hasStoredCreds;
// Hat Spotify die letzte Anmeldung abgelehnt? NO = es lag nur an der Verbindung (dann nicht neu koppeln).
+ (BOOL)lastLoginRejected;
// Netz: ist eine Verbindung da? Beobachtet Änderungen und meldet "MMNetworkChanged" (userInfo reachable=@BOOL).
// Kommt das Netz zurück, verbindet sich die Wiedergabe-Session von selbst neu.
+ (BOOL)networkReachable;
+ (void)startNetworkWatch;
// Auto-Login mit gespeicherten Zugangsdaten (kein Passwort/Browser nötig).
+ (void)loginStoredWithCompletion:(void(^)(BOOL ok, NSString *username, NSString *error))done;
// Nur Metadaten (schnell): info-dict {title, artist, cover-URL}.
+ (void)fetchTrack:(NSString *)trackId completion:(void(^)(NSDictionary *info, NSString *error))done;
// Lädt + entschlüsselt den ganzen Track und spielt ihn ab (MMAudio).
+ (void)playTrack:(NSString *)trackId completion:(void(^)(BOOL ok, NSString *error))done;
+ (void)playTrack:(NSString *)trackId stream:(BOOL)stream completion:(void(^)(BOOL ok, NSString *error))done;   // stream=NO: erst ganz laden
// Lädt + entschlüsselt den nächsten Track im Hintergrund in den Cache (für nahtlosen Übergang).
+ (void)prefetchTrack:(NSString *)trackId;
// --- Offline: Playlists herunterladen ---
+ (BOOL)isDownloaded:(NSString *)trackId;
+ (BOOL)playableOffline:(NSString *)trackId;   // heruntergeladen, im Song-Cache oder im RAM -> spielt ohne Netz
+ (BOOL)allDownloaded:(NSArray *)trackIds;   // sind alle trackIds auf der Platte?
// Reiht Tracks in die globale Download-Warteschlange ein (mehrere Playlists nacheinander).
// Status per Notification: MMDownloadProgress {done,total} · MMDownloadDone {ok} · MMDownloadFull
+ (void)queueDownloadTracks:(NSArray *)trackIds;
+ (void)removeDownloads:(NSArray *)trackIds;
// Offline-Playlists dauerhaft merken -> beim Start werden fehlende Tracks automatisch weitergeladen.
+ (void)markOffline:(NSString *)name trackIds:(NSArray *)trackIds;
+ (void)unmarkOffline:(NSArray *)trackIds;
+ (void)resumeOfflineDownloads;   // beim App-Start aufrufen
+ (NSDictionary *)downloadStatus;   // {queue: noch zu ladende IDs (erste = gerade), done, total, eta: Sekunden oder -1}
+ (NSArray *)downloadedTracks;      // @[ {id, bytes, date} ], neueste zuerst
+ (void)deleteDownload:(NSString *)trackId;   // Datei weg + aus den Offline-Listen (kein Auto-Resume)
+ (void)trackInfos:(NSArray *)trackIds completion:(void(^)(NSDictionary *byId))done;   // {id: {title, artist, cover}} übers Netz
+ (BOOL)isDownloading;            // läuft gerade ein Offline-Download?
+ (long long)freeDiskBytes;   // freier Speicher auf dem Gerät
+ (long long)songCacheBytes;   // zuletzt gespielte Songs auf der Platte (max. 500 MB)
+ (void)clearSongCache;
+ (long long)cacheBytes;      // Größe des Offline-Caches (.spotcache)
+ (NSString *)productType;     // "premium", "free", … (nil bis Spotify es nach dem Login schickt)
+ (NSString *)country;         // Land des Kontos (z.B. "US")
+ (NSString *)keyStatus;       // Song-Schlüssel in dieser Sitzung: ok / verweigert (mit Fehlercode)
+ (NSString *)diagnosticLog;   // gefilterte Log-Zeilen für die Seite "Fehlerinfos" (ohne Zugangsdaten)
+ (void)runConnectionTest:(void(^)(NSString *line))line done:(void(^)(void))done;   // für "Debug info": Netz, Server/Ports, Song-Schlüssel, Download
+ (NSString *)deviceModel;     // z.B. "iPod4,1"
+ (NSData *)httpsGet:(NSURL *)url;   // GET über das eigene TLS (mbedTLS): für Hosts, die das iOS-HTTPS ablehnt (z.B. iOS 7 und Spotifys Bild-CDN). nil bei Fehler/Nicht-200
+ (BOOL)isLoading;   // true während ein Track geladen/entschlüsselt wird
// Eigener Spotify-Entwickler-Schlüssel (nur für die Suche). Wird vor dem Speichern bei Spotify geprüft.
+ (BOOL)hasSearchKey;
+ (void)saveSearchKeyId:(NSString *)cid secret:(NSString *)sec completion:(void(^)(BOOL ok, NSString *error))done;
+ (void)removeSearchKey;
// Abmelden: Wiedergabe und Downloads stoppen, Verbindung trennen, Anmeldung/Tokens, alle Downloads, Playlisten,
// Cover und Einstellungen löschen. Der Suchschlüssel (Client-ID/Secret) gehört zur App und bleibt. done auf Main.
+ (void)logoutCompletion:(void(^)(void))done;
// Suche (Katalog) über Web-API; status 401 = kein Such-Schlüssel auf dem Gerät.
+ (void)webGet:(NSString *)path completion:(void(^)(NSDictionary *json, NSInteger status))done;
// Persönliche Daten (/me/playlists, /me/tracks, …): GET über interne Server, sonst Web-API. method = GET/PUT/DELETE/POST.
+ (void)apiUser:(NSString *)method path:(NSString *)path body:(NSData *)body completion:(void(^)(NSDictionary *json, NSInteger status))done;
// Holt ALLE Seiten einer paginierten Liste (folgt "next"), liefert die rohen items (track-wrapper o. tracks).
+ (void)apiUserAllItems:(NSString *)path completion:(void(^)(NSArray *items, NSInteger status))done;
// GET mit Disk-Cache: liefert sofort die letzten Daten (fresh=NO), dann frische (fresh=YES) - aber nur wenn sie sich geändert haben.
// Ohne Cache und bei Fehler kommt genau ein Aufruf mit fresh=YES (json=nil).
+ (void)apiUserCached:(NSString *)path completion:(void(^)(NSDictionary *json, NSInteger status, BOOL fresh))done;
+ (BOOL)hasUserToken;   // ist der User-Daten-Token vorhanden?

// --- Login mit Code über ein anderes Gerät (wie bei Smart-TVs: spotify.com/pair) ---
// info: device_code, user_code, verification_uri, verification_uri_complete, interval, expires_in
+ (void)deviceLoginStart:(void(^)(NSDictionary *info, NSString *error))done;
// Fragt bei Spotify nach, bis am anderen Gerät bestätigt wurde. Speichert Token + Refresh-Token.
+ (void)deviceLoginPoll:(NSDictionary *)info cancelled:(BOOL(^)(void))cancelled completion:(void(^)(NSString *token, NSString *error))done;
// Schreiben ins Konto (interne Server): Lieblingssongs an/aus, Titel ans Ende einer eigenen Playlist hängen.
+ (void)setLiked:(BOOL)on track:(NSString *)trackId completion:(void(^)(BOOL ok))done;
+ (NSString *)username;                          // Spotify-Benutzername (für "eigene Playlists")
+ (NSNumber *)likedCached:(NSString *)trackId;    // @YES/@NO sofort, nil = noch nicht bekannt
+ (void)isLiked:(NSString *)trackId completion:(void(^)(BOOL liked, BOOL known))done;   // known=NO: Liste nicht ladbar (offline)
+ (void)addTrack:(NSString *)trackId toPlaylist:(NSString *)playlistId completion:(void(^)(BOOL ok))done;
#ifdef DEBUG
+ (void)debugCdnTest:(NSString *)trackId;
+ (void)debugApTest:(NSString *)ipPort;
+ (void)debugFakeKeyRefusals;
#endif
@end
