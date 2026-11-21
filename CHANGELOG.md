# Changelog

Alle nennenswerten Änderungen an Knippi.

## [0.2.0] — 2026-11-21

### Neu

- **Scroll-Aufnahme:** Nimmt eine lange Seite als ein durchgehendes Bild auf, zum Beispiel
  eine Webseite, eine Mail oder ein PDF. Im Menü „Scroll-Aufnahme“ oder mit option + shift + 6
  einen Bereich wählen, dann „Aufnahme starten“ und selbst scrollen, oder „Automatisch“, dann
  scrollt Knippi bis zum Seitenende von allein. „Fertig“ beendet, Esc bricht ab.
- **Feste Kopf- und Fußleisten** einer Seite erscheinen im Bild nur einmal.
- **Zu schnell gescrollt:** Reißt der Anschluss ab, wird der Rahmen orange und Knippi zeigt
  „Zu schnell – etwas zurückscrollen“. Scrollst du zurück, setzt die Aufnahme dort wieder an.
  Knippi setzt nie an einer unsicheren Stelle an, auch nicht bei Seiten, deren Zeilen sich
  stark ähneln (Tabellen, Listen, Protokolle).
- **Höchstlänge:** Bei 30 000 Pixeln endet die Aufnahme mit dem Hinweis „Maximale Länge
  erreicht – der Rest der Seite fehlt“.

### Hinweise

- „Automatisch“ braucht die Freigabe **Gerätesteuerung und Datenzugriff**
  (Systemeinstellungen → Datenschutz & Sicherheit). Fehlt sie, fragt macOS beim ersten Mal.
- Gemessen an 400 Zeilen langen Seiten: Safari, Mail und Vorschau ohne doppelte oder
  fehlende Zeilen, 13 bis 24 Sekunden.

## [0.1.3] — 2026-11-21

### Geändert

- **Hintergrund mit runden Ecken:** Das ganze Bild samt Hintergrund hat jetzt abgerundete
  Ecken, passend zu den Ecken der Aufnahme. Außerhalb ist es durchsichtig (PNG). Die Vorschau
  im Editor zeigt die Ecken genauso.
- **Editor-Vorschau passt sich an:** Änderst du Hintergrund, Format oder Abstand oder klappst
  den Bereich „Hintergrund“ auf, zeigt der Editor wieder das ganze Bild. Vorher blieb der Zoom
  stehen und das Bild lief unten aus dem Fenster. Hast du selbst gezoomt, bleibt dein Zoom.
- **Editor-Vorschau mit Hintergrund:** Durchsichtige Stellen zeigen den Hintergrund statt eines
  Karomusters, so wie im fertigen Bild.

### Behoben

- **Editor:** „Hintergrund“ und „Vertrauliches finden“ stehen jetzt fest rechts neben Sichern
  und Teilen. In einem schmalen Editor-Fenster waren sie vorher aus der Werkzeugleiste
  herausgeschoben, ohne dass man es sah.
- **Editor:** Die Auswahl Verpixeln / Weichzeichnen / Schwarzer Balken steht jetzt in einer
  eigenen Zeile unter der Werkzeugleiste, sobald das Verpixeln-Werkzeug aktiv ist.

## [0.1.2] — 2026-11-21

### Neu

- **Nach Updates suchen** jetzt auch direkt im Menü der Menüleiste.
- **Update-Hinweis im Menü:** Findet Knippi im Hintergrund eine neue Version, steht oben im
  Menü „Update auf … verfügbar“. Vorher öffnete sich dafür ein Fenster, das hinter anderen
  Programmen verschwinden konnte.

### Geändert

- **Vertrauliches finden verpixelt jetzt** statt schwarz zu balken. Die Klötzchen sind so groß
  wie die Textzeile hoch ist und bekommen zusätzlich eine zufällige Helligkeit. Dadurch lässt
  sich der Text praktisch nicht zurückrechnen. Ruhiger als der schwarze Balken.
- **Editor:** Der Knopf für Hintergrund und Format (16:9, 1:1, 4:5) heißt jetzt „Hintergrund“
  statt nur ein Symbol zu zeigen.
- **Letzte Farben** zeigen neben dem Farbcode die Farbe.

### Behoben

- **Editorleiste:** Die Auswahl Verpixeln / Weichzeichnen / Schwarzer Balken überdeckte das
  Farbfeld. Der Fenstertitel des Editors ist jetzt deutsch.
- **Sichern aus dem Editor:** Schlägt das Speichern fehl, bleibt der Editor offen, die
  Bearbeitung geht nicht mehr verloren.
- **Dateinamen** haben jetzt in jeder Region dasselbe Datumsformat (vorher z. B. mit
  buddhistischer Jahreszahl, wenn der Mac so eingestellt war).
- **Farbwert HSL** zeigt bei Rottönen nicht mehr „360“, sondern richtig „0“.
- Knippi verlangt keine Mikrofon-Berechtigung mehr (Bildschirmvideo ist noch nicht enthalten).

## [0.1.1] — 2026-11-20

### Behoben

- **Updates:** In 0.1.0 startete die Update-Suche nicht („Update nicht erfolgreich“). Ab 0.1.1
  sucht Knippi wieder selbst nach neuen Versionen. Wer 0.1.0 installiert hat, lädt 0.1.1 einmal
  von Hand, danach kommen Updates automatisch.

## [0.1.0] — 2026-11-20

Erste Fassung. Knippi ist eine schlanke Screenshot-App für die Menüleiste, entstanden aus
[Capso](https://github.com/lzhgus/Capso) von lzhgus (MIT).

### Neu

- **Aufnehmen:** Bereich, Fenster oder ganzer Bildschirm. Eigene Kürzel ab Werk, auf Wunsch
  auch command + shift + 3, 4 und 5.
- **Schnellzugriff:** Nach jeder Aufnahme erscheint ein Vorschaubild in der Ecke. Alternativ
  öffnet sich gleich der Editor, oder Knippi sichert still. Einstellbar unter „Nach der Aufnahme“.
- **Editor** mit Pfeilen, Text, Markierungen, Zählern und Verpixeln.
- **Vertrauliches finden:** Knippi schlägt E-Mail-Adressen, Telefonnummern, IBAN,
  Kartennummern und Zugangsschlüssel zum Schwärzen vor. Offene Vorschläge werden vor jedem
  Export geschwärzt.
- **Schwarzer Balken** als Standard zum Schwärzen, deckend statt durchscheinend.
- **Color Picker** als eigene Aufnahmeart (option + shift + 9) mit Lupe, mehreren
  Farbformaten und „Letzte Farben“ in der Menüleiste.
- **Hintergründe:** drei Verläufe (Polarlicht, Abendglut, Graphit), eigenes Bild, Formate
  16:9, 1:1 und 4:5. Fenster-Aufnahmen behalten auf Wunsch einen durchsichtigen Hintergrund
  mit Schatten.
- **Texterkennung:** Text aus einem Bildschirmbereich kopieren.
- **Teilen-Menü** im Schnellzugriff (AirDrop, Nachrichten und mehr). command + P heftet die
  Aufnahme an.
- **Speichern:** Ordner wählbar, ab Werk `Bilder/Knippi`, Dateiname „Knippi JJJJ-MM-TT um
  HH.MM.SS“. Knippi überschreibt nie eine fremde Datei und meldet Speicherfehler sichtbar.
- **Ohne Bildschirmaufnahme-Freigabe** zeigt Knippi einen Hinweis mit „Einstellungen öffnen“,
  statt still ein leeres Bild zu liefern.
- **Updates** kommen automatisch über einen signierten Update-Feed.
