# Changelog

Alle nennenswerten Änderungen an Knippi.

## [0.5.2] — 2026-11-23

### Neu

- **Verlauf: Mehrfachauswahl.** Shift- oder command-Klick wählt mehrere Aufnahmen, command + A alle.
  Kopieren, Teilen und Papierkorb gelten dann für die ganze Auswahl.
- **Verlauf: Schnellansicht.** Die Leertaste zeigt die Aufnahme groß, die Pfeiltasten blättern durch die Liste.
- **Verlauf: Return kopiert den neuesten Treffer** der Suche.
- **Verlauf: Rückgängig.** command + Z (oder „Papierkorb rückgängig“ im Menü mit den drei Punkten)
  holt die zuletzt weggelegten Aufnahmen aus dem Papierkorb zurück. Eine Datei, die inzwischen wieder
  unter dem alten Namen liegt, wird nie überschrieben.
- **Verlauf: „Teilen …“** im Rechtsklick-Menü, mit dem Teilen-Menü von macOS.

### Hinweise

- Ideen dazu stammen aus dem Open-Source-Programm Tendedero (MIT, Alejandro Buján); der Code ist neu geschrieben.

## [0.5.1] — 2026-11-23

### Neu

- **Tastenkürzel für den Screenshot-Verlauf:** option + shift + H öffnet ihn, ändern kannst du es unter
  Einstellungen → Tastenkürzel → „Screenshot-Verlauf“. Auch im Menü steht das Kürzel jetzt hinter
  „Screenshot-Verlauf …“.
- **Stream-Deck-Taste „Screenshot-Verlauf“:** Das Plugin hat eine neue Taste, die den Verlauf öffnet.
  Sie steht in der Aktionsliste der Stream-Deck-App unter „Knippi“; in die mitgelieferten Profile
  ist sie nicht eingebaut. Der Befehl dahinter ist `knippi://grab/history`.
- **Verlauf-Fenster:** Neben dem Suchfeld gibt es ein Menü mit „Index löschen“ und „Verlauf ausschalten“,
  damit du beides nicht in den Einstellungen suchen musst.

## [0.5.0] — 2026-11-23

### Neu

- **Screenshot-Verlauf mit Textsuche:** Menüleiste → „Screenshot-Verlauf …“ zeigt die letzten
  Aufnahmen aus deinem Sicherungsordner, auch aus Monatsordnern. Im Suchfeld findest du eine
  Aufnahme über den Text im Bild; Groß- und Kleinschreibung und Akzente spielen keine Rolle. Klick
  kopiert das Bild, Doppelklick öffnet es, Ziehen schickt eine Kopie in eine andere App, Entf legt
  es in den Papierkorb. Im Rechtsklick-Menü stehen außerdem „Im Editor öffnen“ und „Im Finder
  zeigen“.
- **Ab Werk aus:** Einstellungen → Bildschirmfotos → „Screenshot-Verlauf“. Du wählst 25, 50 oder
  100 Aufnahmen. Ist der Verlauf aus, liest Knippi nichts und legt keinen Index an. Beim
  Ausschalten wird der gelesene Text gelöscht, „Index löschen“ tut das auch bei eingeschaltetem
  Verlauf.

### Hinweise

- Der Verlauf zeigt nur Aufnahmen im Sicherungsordner. Ist „Automatisch sichern“ aus, landen neue
  Aufnahmen dort nicht; das Verlauf-Fenster bietet an, es einzuschalten.
- Knippi liest den Text nur, solange das Verlauf-Fenster offen ist. Gemessen an 100 Bildern: etwa
  25 Sekunden beim ersten Mal, dabei kurzzeitig bis zu 650 MB Arbeitsspeicher. Danach kostet das
  Öffnen praktisch nichts.
- Der gelesene Text liegt unverschlüsselt im Ordner „Application Support“, nur für dein
  Benutzerkonto lesbar, und kann in Backups landen.
- Ersetzt der Editor ein gesichertes Original (etwa nach dem Verpixeln), vergisst der Index den
  alten Text sofort. Ein Bild, das du in den Papierkorb legst, verschwindet auch aus dem Index.

### Intern

- Suchindex und Ordner-Leser im Paket OCRKit. Sehr hohe Aufnahmen (Scroll-Aufnahme) werden für die
  Texterkennung in Streifen gelesen, sonst wäre der Text zu klein geworden (gefunden im Audit).

## [0.4.4] — 2026-11-21

### Behoben

- **Bild-Editor:** Ein Klick zum Auswählen legt keinen leeren Rückgängig-Schritt mehr an. Eine
  Stilvorlage ist ein einziger Rückgängig-Schritt. Höchstens 100 Rückgängig-Schritte. Esc beim
  Schreiben übernimmt erst den Text. Überfahren des Zieh-Symbols verpixelt die Vorschläge von
  „Vertrauliches finden“ nicht mehr vorzeitig. Kann Knippi das Bild nicht exportieren oder
  skalieren, sagt es das.
- **Verpixeln von Hand** bekommt dasselbe Zufallsrauschen wie „Vertrauliches finden“, damit sich
  Text nicht zurückrechnen lässt. Die Blöcke wirken dadurch etwas fleckiger.
- **All-in-One:** Kann Knippi die Anmerkungen nicht übernehmen, wird nichts unbearbeitet
  weitergegeben. Rückgängig trennt Farbe, Füllung und Muster.
- **Scroll-Aufnahme:** Return und Enter funktionieren in anderen Apps wieder, sobald die Aufnahme
  läuft. Wird der Bildschirm abgesteckt, bricht sie ab, statt ein anderes Display aufzunehmen.
- **Selbstauslöser:** Ein Abbruch kurz vor Null löst nicht mehr trotzdem aus.
- **Video:** Zeitanzeige läuft auch bei offenem Menü weiter. Esc während des Countdowns bleibt
  zuverlässig. Mauszeiger-Daten sammeln sich nicht mehr an. Neustart einer Aufnahme meldet Fehler.
  Fehlermeldungen beim Export sind verständlich und deutsch. Hochformat-Videos werden für
  „Social“ und „Web“ verkleinert. Der Aufnahme-Rahmen sitzt enger.
- **Texterkennung:** „Alles kopieren“ beachtet die Einstellung für Zeilenumbrüche, Meldungen sind
  deutsch.
- **Cloud-Freigabe:** Tencent-COS-Uploads sind enger signiert und kürzer gültig. Fehlerseiten von
  WLAN-Anmeldeseiten erscheinen nicht mehr als HTML in der Meldung. Ein http://-Ziel zeigt einen
  Hinweis.
- **Dateinamen:** Fenstertitel können keine versteckten Dateien, unsichtbare Steuerzeichen oder
  Platzhalter mehr in den Namen bringen.
- **Einstellungen:** Der Schalter „andere Apps dürfen steuern“ zeigt nach der Rückfrage sofort den
  richtigen Stand.

### Intern

- Nicht genutzte Bibliothek „Defaults“ entfernt, ebenso toter Code (u. a. aus dem Capso-Erbe).
- Release-Scripts: Wiederanlauf-Hinweis auch bei Abbruch, Probelauf ohne Plugin-Notarisierung.

## [0.4.3] — 2026-11-21

### Behoben

- **Video-Export stürzte ab**, wenn sich während der Aufnahme lange nichts bewegte (Bildrate unter
  1 Bild pro Sekunde). Jetzt exportiert Knippi mit fester Bildrate.
- **Video nicht mehr länger als die Aufnahme:** Bei wenig Bewegung hängte der Export mit
  Hintergrund oder Effekt hinten Sekunden Standbild an (gemessen 8,6 statt 12,5 Sekunden).
- **Mikrofon im Export:** Mit Hintergrund, Effekt, Mauszeiger oder Schnitt landeten Systemton und
  Mikrofon in zwei getrennten Spuren, viele Player spielten nur eine davon. Jetzt ist es eine Spur.
- **Weichzeichnen im Video bleibt beim Zoom über dem Inhalt**, statt ihn beim Heranzoomen
  freizugeben.
- **Video-Editor:** Glättung und Stil des Mauszeigers wirken jetzt sofort. Schließen mit dem roten
  Knopf stoppt die Wiedergabe. Die angezeigte Dauer stimmt auch bei überlappenden Schnitten. Die
  Zwischendatei beim Export mit Schnitten liegt im temporären Ordner statt im Zielordner.
- **Bild-Editor:** Farbe, Größe und Modus lassen sich rückgängig machen (Schieberegler als ein
  Schritt). Drehen und Spiegeln lassen sich nicht mehr rückgängig machen, dafür entsteht nie mehr
  ein falscher Ausschnitt. „Ausgabe skalieren“ bleibt beim Ändern des Zuschnitts und beim Drehen im
  Seitenverhältnis und ist auf 16384 Pixel begrenzt. Ein noch offener Text geht beim Schließen
  nicht mehr ohne Rückfrage verloren. Verpixeln ruckelt beim Zeichnen nicht mehr. Nach dem
  Zuschneiden sucht „Vertrauliches finden“ nicht noch einmal (keine doppelten Verpixelungen).
- **All-in-One:** Farbe ändern macht eine Verpixelung nicht mehr schwächer, Stiländerungen sind
  rückgängig zu machen.
- **Aufnahme:** Selbstauslöser, „Wiederholen“ und Sofort-Texterkennung nehmen auf 1×- und
  3×-Bildschirmen in der richtigen Auflösung auf. Feste Größen und freie Auswahl bleiben im
  Bildschirm. Esc bricht den Selbstauslöser jetzt zuverlässig ab.
- **Video und Kamera:** Ein zweites Aufnahme-Kürzel lässt keine verwaiste Leiste mehr zurück. Eine
  abgesteckte Kamera wird gemeldet, statt eine leere Kamerablase mitzufilmen. Die Kamera bremst die
  Oberfläche nicht mehr. Schließen der Vorschau nach fehlgeschlagenem Sichern fragt nach.
- **Cloud-Freigabe:** Waren die Zugangsdaten beim Start nicht lesbar (Schlüsselbund gesperrt),
  versucht Knippi es beim nächsten Teilen erneut und sagt sonst, dass es am Schlüsselbund liegt.
  Eine einzelne nicht löschbare alte Datei blockiert Ziehen und Teilen nicht mehr. Die Testdatei
  der Einrichtung wird auch bei Netzfehlern wieder entfernt.

## [0.4.2] — 2026-11-21

### Behoben

- **Verpixelung bleibt stark:** Farbe oder Modus einer ausgewählten Verpixelung aus „Vertrauliches
  finden“ ändern macht die Blöcke nicht mehr kleiner (vorher wurde der Text teils wieder lesbar).
- **Rückgängig nach Vergrößern:** Im All-in-One-Editor sprangen Markierungen nach Bereich vergrößern
  und Rückgängig an alte Stellen, Schwärzungen lagen neben dem Inhalt.
- **Drehen im Zuschnitt:** Bild und Zuschnittrahmen drehen jetzt in dieselbe Richtung.
- **Scroll-Aufnahme automatisch:** Verliert Knippi die Seite, hört es auf zu scrollen und meldet
  „vorzeitig beendet“, statt ein still abgeschnittenes Bild zu liefern. Bewegt sich am Seitenende
  etwas (Video, Ladekreisel), endet die Aufnahme trotzdem von selbst.
- **Kein Overlay im Bild:** Vollbild-, Fenster- und Wiederholen-Kürzel wirken nicht mehr, solange
  eine Auswahl auf dem Bildschirm ist.
- **Video:** Doppelklick auf Stopp zeigt keine falsche Fehlermeldung mehr. Stoppt Knippi selbst
  (Platte voll, Freigabe entzogen), sagt die Meldung jetzt, ob schon gesichert ist. Die Kamera
  startet nicht mehr, wenn die Aufnahme während der Kamera-Abfrage von macOS abgebrochen wurde.
  Ein Absturz während des Sicherns verliert die Aufnahme nicht mehr. Der Export mit Mikrofon und
  Systemton hängt bei voller Platte nicht mehr endlos.
- **Vorschaubild:** Schließt sich nicht mehr, solange ein Cloud-Upload läuft oder fehlgeschlagen ist.
- **Cloud-Freigabe zurücksetzen:** Noch offene Vorschaubilder laden danach nicht mehr mit den alten
  Zugangsdaten hoch.
- **Kein ungeschwärztes Original mehr:** Ist „Automatisch sichern“ an, ersetzen jetzt auch Kopieren,
  Anheften und „Sichern unter“ aus dem Editor die gesicherte Datei durch die bearbeitete Fassung.
  Vorher blieb dabei das unbearbeitete, zum Beispiel ungeschwärzte, Original im Ordner liegen.
- **Andere Apps:** In der Rückfrage „Andere App will Knippi steuern“ ist „Nicht erlauben“ jetzt der
  Standardknopf. Wer die Steuerung in den Einstellungen selbst aus- oder einschaltet, wird später
  nicht noch einmal gefragt.

## [0.4.1] — 2026-11-21

### Behoben

- **Abbrechen setzt die Aktion zurück:** Wer „Bereich aufnehmen & teilen“ (oder „& anheften“,
  „& kopieren“, „& bearbeiten“) mit Esc abbrach, bekam die Aktion bei der nächsten Vollbild-,
  Fenster- oder Scroll-Aufnahme trotzdem, also zum Beispiel einen ungewollten Cloud-Upload.
- **Pause im Bildschirmvideo:** Bei stillem Bild schnitt Knippi zu viel heraus und verlor den Ton
  nach dem Fortsetzen. Jetzt fehlt genau die Zeit zwischen Pause und Fortsetzen.

### Geändert

- **Aufnahmen, die eine andere App auslöst** (`knippi://grab/fullscreen` und `/last-area`, auch
  vom Stream Deck), landen nicht mehr automatisch in der Zwischenablage oder in der Cloud. Sie
  werden immer gesichert, ein Hinweis zeigt sie an, und zwei solche Befehle kurz hintereinander
  nimmt Knippi nicht an. So kann keine andere App über Knippi den Bildschirm mitlesen.

## [0.4.0] — 2026-11-21

### Neu

- **Stream Deck:** Plugin `Knippi.streamDeckPlugin` mit zehn Tasten (Bereich, Fenster, Vollbild,
  Scroll-Aufnahme, Letzten Bereich wiederholen, Text erkennen, Farbe, Selbstauslöser, Video
  Bereich, Video Vollbild), einem Regler für Stream Deck + und fertigen Profilen für Stream
  Deck +, Neo und Stream Deck (15 Tasten). Tastenbilder im Glas-Stil der App-Familie.

## [0.3.0] — 2026-11-21

### Neu

- **Bildschirmvideo und GIF:** Im Menü „Bereich aufzeichnen“ (option + shift + 5) oder „Ganzen
  Bildschirm aufzeichnen“. In der Leiste wählst du Video oder GIF, Systemaudio und wahlweise
  das Mikrofon. Pausieren ist möglich, die Pause fehlt im fertigen Video.
- **Sprecherbild:** Über das Kamera-Symbol in der Leiste blendest du dein Kamerabild ein, in
  Kreis-, Quadrat-, Quer- oder Hochformat und drei Größen. Vor dem Start ziehst du es an seinen
  Platz. Während der Aufnahme weicht es der Maus sanft aus und kehrt danach zurück; mit
  gedrückter command-Taste lässt es sich auch während der Aufnahme greifen. Die Einstellungen
  bleiben offen, bis du daneben klickst.
- **Automatisch gesichert:** Nach dem Stoppen landet das Video sofort im Sicherungsordner.

### Hinweise

- Mikrofon und Kamera fragt macOS erst, wenn du sie zum ersten Mal einschaltest.
- Lange GIFs werden zuerst ruckeliger (bis 10 Bilder pro Sekunde), dann kleiner, damit der
  Speicher nicht überläuft (gemessen: 150 Bilder in voller Größe brauchten 3,6 GB).
- Bricht eine Aufnahme ab (Freigabe entzogen, Datei nicht schreibbar), sagt Knippi es und
  sichert, was bis dahin aufgenommen war.

### Behoben

- **Speicher nach der Aufnahme:** Knippi hielt das zuletzt aufgenommene Bild dauerhaft im
  Speicher, auch nachdem das Vorschaubild geschlossen war. Bei einer langen Scroll-Aufnahme
  waren das rund 180 MB (gemessen: 229 MB statt etwa 50 MB im Ruhezustand). Jetzt gibt Knippi
  das Bild frei, sobald es nirgends mehr angezeigt wird.

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
