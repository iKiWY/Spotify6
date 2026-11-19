// MMAudio.h - spielt ein (bereits entschlüsseltes) Spotify-Ogg per AudioQueue ab.
// Dekodiert Ogg/Vorbis streamend mit stb_vorbis; iOS 6 kann Vorbis nicht nativ.
#import <Foundation/Foundation.h>

// Titel, der noch lädt: Puffer in voller Dateigröße, wird vorne nach und nach (entschlüsselt) gefüllt.
// Der Lade-Thread schreibt Bytes und erhöht danach avail; die Wiedergabe liest nie hinter avail.
@interface MMAudioStream : NSObject
- (id)initWithLength:(NSUInteger)length;
@property (nonatomic, readonly) NSMutableData *data;   // feste Größe (wird nie umgelegt)
@property (atomic) NSUInteger avail;                   // so viele Bytes sind schon da
@property (atomic) BOOL complete, failed;
@end

@interface MMAudio : NSObject
// ogg = komplette entschlüsselte Datei (inkl. 167-Byte-Spotify-Vorspann). Startet Wiedergabe.
+ (void)playOgg:(NSData *)ogg;
// Startet, sobald der Anfang da ist; holt die Wiedergabe den Download ein, kommt kurz Stille statt eines Endes.
+ (void)playStream:(MMAudioStream *)stream;
+ (BOOL)isBuffering;     // spielt einen Titel, der noch lädt
+ (MMAudioStream *)currentStream;   // der gerade gespielte Stream (nil = ganze Datei)
+ (void)setExpectedDuration:(double)seconds;   // Länge aus den Metadaten (gilt, bis die ganze Datei da ist; 0 = unbekannt)
+ (void)stop;
+ (void)setPaused:(BOOL)paused;
+ (BOOL)isPlaying;
+ (BOOL)hasEnded;
+ (BOOL)isLoaded;        // zu Ende gespielt: "Weiter" würde nichts tun, der Titel muss neu starten
+ (double)duration;      // Sekunden
+ (double)currentTime;   // Sekunden (echte Abspielposition)
+ (void)seekTo:(double)seconds;   // an Position springen
+ (void)setEqualizerEnabled:(BOOL)enabled;
+ (BOOL)isEqualizerEnabled;
+ (void)setEqualizerGain:(double)gain forBand:(NSUInteger)band;
@end
