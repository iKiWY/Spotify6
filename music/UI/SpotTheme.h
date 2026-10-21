// SpotTheme.h - Farben & Fonts im Spotify-Look (dunkel, grüner Akzent).
#import <UIKit/UIKit.h>
@interface SpotTheme : NSObject
// Skins: "spotify" (dunkel, Standard) oder "ios6" (heller iOS-6-Look). Wird beim Start gelesen; Wechsel gilt nach Neustart der App.
+ (NSString *)skin;
+ (void)setSkin:(NSString *)skin;
+ (BOOL)ios6;
+ (void)applySkin;   // gespeicherten Skin übernehmen (beim Start und beim Wechsel)
+ (UIColor *)chromeInk;   // Text/Symbole auf Leisten (Tab-, Now-Playing-, Download-Leiste): in beiden Skins hell
+ (UIColor *)headerInk;    // Symbole im Seitenkopf: iOS 6 weiß (auf der grünen Leiste), sonst wie ink
+ (UIColor *)barTint;      // iOS 6: Tönung der Navigations- und Suchleisten (Spotify-Grün, dunkel)
+ (UIColor *)pageBackground;   // iOS 6: Nadelstreifen (gruppierte Seiten), sonst bg
+ (UIColor *)groupedHeaderInk; // iOS 6: Überschriften auf Nadelstreifen
+ (UIImage *)toolbarImage:(CGFloat)height;      // iOS 6: schwarzer Glanz (Tab-Leiste, Now-Playing)
+ (UIImage *)tabHighlightImage;                 // iOS 6: graue Fläche hinter dem gewählten Tab (dehnbar)
+ (UIImage *)barButtonImage;                    // iOS 6: umrandeter Leistenknopf (grün), dehnbar
+ (UIImage *)glossyImage:(UIColor *)color radius:(CGFloat)r;
+ (UIImage *)glossyImage:(UIColor *)color radius:(CGFloat)r size:(CGSize)size;   // dasselbe in fester Größe (große Kacheln)   // glänzende abgerundete Fläche, dehnbar
+ (UIView *)plainSectionHeader:(NSString *)title width:(CGFloat)w;   // iOS-6-Abschnittskopf einer einfachen Liste (22 hoch)
+ (void)styleGroupedHeader:(UILabel *)l;        // Überschrift auf Nadelstreifen
+ (UIView *)selectionView;                      // grüne Auswahl beim Antippen
+ (UIView *)groupedSelectionFirst:(BOOL)first last:(BOOL)last;   // dasselbe für gruppierte Zellen: runde Ecken oben/unten wie die Zelle
+ (void)skinCell:(UITableViewCell *)c;          // iOS 6: grüne Auswahl, weiße Schrift beim Antippen
+ (void)skinTable:(UITableView *)t;            // iOS 6: weiße Liste mit grauen Trennlinien; ihre Zellen bekommen die grüne Auswahl
+ (void)shadowCover:(UIView *)v;                // iOS 6: leichter Schatten unter Covern
+ (void)shadowBehind:(UIView *)v;               // iOS 6: Schatten hinter einer (beschnittenen) Ansicht, als eigene Ansicht darunter
+ (void)groupedTile:(UIView *)tile;             // iOS 6: weiße Kachel mit grauem Rand und runden Ecken (wie eine gruppierte Zelle)
+ (void)styleSectionTitle:(UILabel *)l;         // Abschnittstitel einer Seite: iOS 6 wie gruppierte Überschrift, sonst unverändert
+ (UIImage *)shelfImage:(CGFloat)height;       // iOS 6: helles Band hinter einem Abschnitt (wie das App-Store-Regal), 1 pt breit, in voller Höhe gezeichnet
+ (UIColor *)shelfColor;
+ (UIColor *)rowColor;
+ (void)albumHeadBackground:(UIView *)head;     // iOS 6: grauer Verlauf + Linie unten wie der Kopf eines Albums in der Musik-App                          // iOS 6: hellgraue Listenzeile (Musik-App)                        // iOS 6: Regal hinter den Cover-Reihen der Startseite
+ (UIImage *)plateImage:(CGSize)size pressed:(BOOL)pressed;   // iOS 6: gewölbte Kachel (umrandeter Knopf), 1 pt höher für die Lichtkante
+ (UIImageView *)shelfCover:(CGRect)frame in:(UIView *)tile reflection:(CGFloat)height;   // Cover; iOS 6 mit Spiegelbild darunter (wie Cover Flow)
+ (UIImageView *)shelfCover:(CGRect)frame in:(UIView *)tile reflection:(CGFloat)height fade:(UIColor *)ground;   // dasselbe auf anderem Grund (blendet in diese Farbe aus)
+ (UIImage *)tabGlyph:(NSString *)name;
+ (UIImage *)tabGlyph:(NSString *)name selected:(BOOL)sel;   // iOS 6: fertig gefärbt (weiß mit Glanz / helles Grün), mit Schatten
+ (UIImage *)tabBarImage:(CGSize)size;
+ (UIImage *)glyph:(UIImage *)mask color:(UIColor *)color;   // Form (z.B. tabGlyph) in einer Farbe
+ (UIImage *)sourceSelectionImage:(CGSize)size;  // iOS 6: gewählte Zeile der iPad-Seitenleiste (Grün der Tab-Leiste)
+ (UIColor *)sourceListColor;                    // iOS 6: Grund der iPad-Seitenleiste
+ (void)setTabVariant:(int)v;                    // Debug: Farbvorschlag 0-4 für die Tab-Leiste           // iOS 6: Glanz wie die Kopfleiste, in voller Größe
+ (UIImage *)tabSelectionImage:(CGSize)size;     // iOS 6: eingedrückte Fläche hinter dem gewählten Tab          // iOS 6: gefülltes 30er-Symbol für die echte Tab-Leiste (das System färbt es)
+ (void)engrave:(UILabel *)l;                   // iOS 6: weißer Schatten unter dunkler Schrift auf Nadelstreifen
+ (void)skinPage:(UIView *)page;                // iOS 6: echte Navigationsleiste über dem Seitenkopf (Titel, Zurück, Knöpfe)
+ (UIColor *)bg;        // 121212
+ (UIColor *)bar;       // 181818 (Leisten)
+ (UIColor *)card;      // 282828
+ (UIColor *)green;     // 1DB954
+ (UIColor *)ink;       // weiß
+ (UIColor *)muted;     // b3b3b3
+ (UIColor *)faint;     // 727272
+ (UIColor *)line;      // 2a2a2a
+ (UIFont *)h1;         // 22 bold
+ (UIFont *)h2;         // 17 semibold
+ (UIFont *)body;       // 15
+ (UIFont *)sub;        // 13 (muted)
+ (UIFont *)tab;        // 10
+ (UIImage *)logo:(CGFloat)size;
+ (UIImage *)downloadedIcon:(CGFloat)size;
+ (UIImage *)downloadsCover:(CGFloat)size;   // Cover der Liste "Heruntergeladen": grüner Verlauf, weißer Pfeil   // offline: grüner Kreis mit schwarzem Haken (Kopf, Zeilen, Bibliothek)
+ (UIImage *)shuffleIcon:(BOOL)on;        // 44x44, an = grün + Punkt (Player, iPad-Leiste)
+ (UIImage *)repeatIcon:(NSInteger)mode;  // 0 aus, 1 Liste, 2 Titel (mit kleiner 1)
+ (void)styleBackButton:(UIButton *)b;   // großer Pfeil + "Zurück" (statt des kleinen ‹ im Text)
// Text mit Buchstabenabstand (iOS 6+); unter iOS 5 normaler Text in gleicher Schrift und Farbe
+ (void)spaced:(UILabel *)label text:(NSString *)text font:(UIFont *)font color:(UIColor *)color kern:(CGFloat)kern;   // eigenes Zeichen: grüner Kreis mit Puls-Linie
@end
