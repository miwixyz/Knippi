# Knippi

Knippi wohnt in der Menüleiste. Ein Klick auf das Symbol öffnet das Knippi-Fenster mit den Aufnahmearten als runden Knöpfen und deinen letzten Bildschirmfotos (wenn der Verlauf an ist). Ein Rechtsklick (oder option-Klick) öffnet das vollständige Menü mit allen Funktionen; dorthin führt auch „…“ unten im Fenster. Die Tastenkürzel funktionieren überall.

Beim Auslösen spielt Knippi einen kurzen, leisen Ton („Tock“). Abschalten unter Einstellungen → Allgemein → „Auslöserton“.

## Erste Schritte

Beim allerersten Start zeigt Knippi einmal ein Begrüßungsfenster: das Kürzel für ein Bildschirmfoto, wo Bildschirmfotos landen, und ob die Freigabe schon erteilt ist. Danach erscheint es nicht wieder.

Beim ersten Bildschirmfoto fragt macOS nach der Freigabe **Bildschirm- und Systemaudioaufnahme**. Ohne sie kann Knippi nichts aufnehmen und zeigt einen Hinweis mit „Einstellungen öffnen“. Die Freigabe findest du unter Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- und Systemaudioaufnahme.

## Tastenkürzel ab Werk

| Kürzel | Aktion |
|---|---|
| option + shift + 1 | Bereich aufnehmen |
| option + shift + 2 | Vollbild aufnehmen |
| option + shift + 3 | Fenster aufnehmen |
| option + shift + 4 | Text erfassen (Texterkennung) |
| option + shift + 5 | Bereich als Video oder GIF aufzeichnen |
| option + shift + 6 | Scroll-Aufnahme (lange Seite) |
| option + shift + 7 | Bereich in die Zwischenablage |
| option + shift + 8 | Bereich aufnehmen & bearbeiten |
| option + shift + 9 | Farbe aufnehmen (Pipette) |
| option + shift + 0 | Aufnehmen und in Cloud teilen |
| option + shift + H | Bildschirmfoto-Verlauf öffnen |

Alle Kürzel änderst du unter Einstellungen → Tastenkürzel.

**command + shift + 3, 4 und 5 für Knippi:** Diese Kürzel gehören ab Werk macOS. Schalte sie unter Systemeinstellungen → Tastatur → Tastaturkurzbefehle → Bildschirmfotos aus. Danach bietet Knippi unter Einstellungen → Tastenkürzel den Knopf „⇧⌘3 / ⇧⌘4 / ⇧⌘5 verwenden“ an: Vollbild, Bereich und „Alles in einem“.

## Nach der Aufnahme

Unter Einstellungen → Bildschirmfotos → „Nach der Aufnahme“ wählst du:

- **Vorschau zeigen:** Ein Vorschaubild erscheint in der Ecke (der **Schnellzugriff**). Von dort kopierst, sicherst, teilst, bearbeitest oder heftest du das Bildschirmfoto an.
- **Editor öffnen:** Das Bildschirmfoto öffnet sich sofort im Editor.
- **Still:** Knippi kopiert in die Zwischenablage und sichert im Ablageordner, ohne etwas anzuzeigen.

Ab Werk kopiert Knippi jedes Bildschirmfoto in die Zwischenablage und sichert es als Datei im Ablageordner (ab Werk Bilder/Knippi). Ist unter Einstellungen → Bildschirmfotos „Automatisch sichern“ aus, landet es dort nur, wenn du in der Vorschau „Sichern“ klickst. Wer Knippi vor Version 0.8.0 installiert hat, behält seine bisherige Einstellung.

## Video und GIF

1. Im Menü **Bereich aufzeichnen** (option + shift + 5) oder **Ganzen Bildschirm aufzeichnen** wählen und den Bereich aufziehen.
2. In der Leiste einstellen: **Mikrofon** (wahlweise), **Systemaudio**, **Kamera** für dein Sprecherbild.
3. Mit dem roten Knopf aufzeichnen, mit **GIF aufzeichnen** als GIF. Pausieren und Stoppen in der kleinen Steuerleiste; die Pause fehlt im fertigen Video.

Nach dem Stoppen sichert Knippi das Video sofort in deinen Ablageordner und meldet „Aufzeichnung gesichert in …“. Klappt das Sichern nicht, bleibt die Vorschau mit „Sichern“ und „Kopieren“ offen. Ist unter Einstellungen → Aufzeichnung „Video-Editor nach der Aufzeichnung öffnen“ an, öffnet sich stattdessen der Video-Editor zum Kürzen und Exportieren.

**Kamerabild:** Klick auf das Kamera-Symbol öffnet die Einstellungen (Kamera, Form, Größe, Spiegeln). Sie bleiben offen, bis du daneben klickst. Vor dem Start ziehst du das Kamerabild an seinen Platz. Während der Aufzeichnung weicht es der Maus aus und kehrt danach zurück. Mit gedrückter **command**-Taste bleibt es stehen und lässt sich verschieben. Ein Klick darauf schaltet auf Vollbild-Kamera.

**Freigaben:** Mikrofon und Kamera fragt macOS beim ersten Einschalten. Später findest du sie unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon bzw. Kamera.

**Lange GIFs** werden ruckeliger und kleiner, damit der Speicher reicht. Für lange Aufzeichnungen ist ein Video besser.

## Scroll-Aufnahme

Für Seiten, die länger sind als der Bildschirm: Webseiten, Mails, PDFs.

1. Im Menü **Scroll-Aufnahme** wählen (oder option + shift + 6) und den Bereich aufziehen, der gescrollt wird.
2. **Aufnahme starten** und selbst scrollen, oder **Automatisch**: Knippi scrollt dann von allein und hört am Seitenende auf. Die Maus dabei nicht bewegen.
3. **Fertig** beendet die Aufnahme, **Esc** oder **Abbrechen** verwirft sie.

Feste Kopf- und Fußleisten der Seite erscheinen im Bild nur einmal.

**Rahmen wird orange („Zu schnell – etwas zurückscrollen“):** Du hast schneller gescrollt, als Knippi Bilder machen kann, und der Anschluss fehlt. Scroll ein Stück zurück, bis der Rahmen wieder blau ist, dann weiter. Knippi setzt nie an einer unsicheren Stelle an.

**„Automatisch“** braucht die Freigabe **Gerätesteuerung und Datenzugriff** unter Systemeinstellungen → Datenschutz & Sicherheit. Beim ersten Mal fragt macOS danach.

**Höchstlänge:** Bei 30 000 Pixeln endet die Aufnahme mit dem Hinweis „Maximale Länge erreicht“. Für noch längere Seiten in zwei Teilen aufnehmen.

## Sichern und Ablageordner

Gesicherte Bildschirmfotos und Videos landen im **Ablageordner**, ab Werk **Bilder/Knippi**, als „Knippi JJJJ-MM-TT um HH.MM.SS“. Ablageordner, Dateiname und Bildschirmfotoformat stellst du unter Einstellungen → Exportieren ein. Knippi überschreibt nie eine fremde Datei. Gesicherte Bildschirmfotos kennzeichnet Knippi für das System als Bildschirmfoto (wie macOS), damit Spotlight und Apps wie Gnotchi sie finden; ältere Dateien bleiben, wie sie sind. Kann eine Datei nicht gesichert werden, sagt Knippi das sichtbar.

Ist „Automatisch sichern“ an und du bearbeitest das Bildschirmfoto im Editor, ersetzt Knippi die gesicherte Datei durch die bearbeitete Fassung, egal ob du sicherst, kopierst, anheftest oder „Sichern unter“ wählst. So bleibt kein ungeschwärztes Original im Ordner liegen.

## Editor

Pfeil, Linie, Rechteck, Ellipse, Text, Freihand, Textmarker, Zähler, Spotlight und Verpixeln. command + Z widerruft den letzten Schritt. Mit „Kopieren“ (command + C) landet das fertige Bild in der Zwischenablage, mit „Sichern“ im Ablageordner.

**Hintergrund:** Im Editor rechts oben, neben Sichern und Teilen, öffnet der Knopf „Hintergrund“ die Einstellungen. Damit legst du einen Rahmen um das Bildschirmfoto: einen der Verläufe Polarlicht, Abendglut oder Graphit, eine Farbe oder ein eigenes Bild. Die Formate 16:9, 1:1 und 4:5 passen für Folien und soziale Netzwerke. Das ganze Bild bekommt dabei abgerundete Ecken, außen durchsichtig; im Format JPEG gibt es keine Durchsichtigkeit. Fensteraufnahmen können „Transparent mit Schatten“ bleiben.

## Vertrauliches finden

Der Knopf **„Vertrauliches finden“** im Schnellzugriff und im Editor sucht E-Mail-Adressen, Telefonnummern, IBAN, Kartennummern und Zugangsschlüssel und verpixelt sie grob: Die Klötzchen sind so groß wie die Zeile hoch ist und bekommen eine zufällige Helligkeit, der Text lässt sich praktisch nicht zurückrechnen. „Alle verpixeln“ übernimmt alle Vorschläge. Ein gestrichelter Rahmen ist ein unsicherer Treffer: Klicken behält ihn oder lässt ihn aus.

**Gesichter:** Die Suche schlägt auch Gesichter vor (Einstellungen → Bildschirmfotos → „Gesichter mitsuchen“, ab Werk an). Das ist eine Hilfe, kein Schutz: Knippi findet gut sichtbare Gesichter, kleine, verdeckte oder abgewandte können fehlen, und manchmal wird ein Zeichentrick- oder Plakatgesicht mitgerahmt. Sieh das Bild deshalb vor dem Teilen an und ergänze fehlende Stellen von Hand. Jedes Gesicht ist ein eigener Rahmen (gestrichelt = unsicher), er wird etwas größer als das Gesicht gezogen und grob verpixelt.

Offene Vorschläge werden vor jedem Kopieren, Sichern und Teilen verpixelt. Die Suche läuft vollständig auf deinem Mac.

Von Hand schwärzt das Werkzeug **Verpixeln**. Sein Schwärzungsmodus ist ab Werk **Schwarzer Balken**; daneben gibt es Verpixeln, Weichzeichnen und **Entfernen**. Entfernen baut die Stelle aus den Pixeln rundherum nach: Auf einfarbigem Grund oder weichem Verlauf ist nichts mehr zu sehen, auf Mustern und Fotos bleibt ein Fleck. Vom alten Inhalt geht nichts in die Füllung ein. Der schwarze Balken deckt vollständig ab. Von Hand verpixelter Text lässt sich bei kleinen Klötzchen manchmal zurückrechnen; für Vertrauliches deshalb „Vertrauliches finden“ oder den schwarzen Balken nehmen.

## Farbe aufnehmen

option + shift + 9 zeigt eine Lupe unter dem Zeiger. Die Pfeiltasten verschieben pixelgenau, ein Klick kopiert die Farbe. Das Format (zum Beispiel HEX oder RGB) wählst du unter Einstellungen → Bildschirmfotos → Farbformat. Die zuletzt aufgenommenen Farben stehen im Menü unter „Letzte Farben“.

## Texterkennung

option + shift + 4 und einen Bereich aufziehen: Knippi erkennt den Text darin und kopiert ihn. Das funktioniert auch bei Text, den man sonst nicht markieren kann, etwa in Bildern oder Videos. Die Erkennung läuft auf deinem Mac.

## Teilen und Anheften

Im Schnellzugriff öffnet „Teilen“ das Teilen-Menü von macOS: AirDrop, Nachrichten, Mail und mehr. command + P heftet das Bildschirmfoto als schwebendes Fenster an den Bildschirm.

**Cloud-Freigabe** (optional): Knippi lädt in **deinen eigenen** Cloud-Speicher hoch, zum Beispiel einen Cloudflare-R2-Bucket, nie auf fremde Server. Einrichten unter Einstellungen → Cloud-Freigabe. Hochgeladene Bildschirmfotos bleiben öffentlich, bis du sie löschst: im Vorschaubild über „…“ → „Link löschen“, oder in den Einstellungen → Cloud-Freigabe → „Hochgeladen“ (einzeln oder alle).

## Stream Deck

Mit dem Plugin `Knippi.streamDeckPlugin` löst du Knippi über ein Elgato Stream Deck aus. Du lädst es aus dem Menü der Menüleiste: „Stream-Deck-Plugin laden …“ öffnet den Download im Browser. Datei doppelklicken, Stream Deck installiert sie.

- **Tasten:** Bereich, Fenster, Vollbild, Scroll-Aufnahme, Letzten Bereich wiederholen, Text erkennen, Farbe aufnehmen, Selbstauslöser, Video Bereich, Video Vollbild, Screenshot-Verlauf (so heißen die Tasten im Plugin). In der Stream-Deck-App aus der Kategorie „Knippi“ auf eine Taste ziehen.
- **Regler (Stream Deck +):** Drehen wählt die Aufnahmeart, Drücken oder Tippen nimmt auf. In den Einstellungen des Reglers wählst du „Screenshots“ oder „Video“.
- **Fertige Profile** für Stream Deck +, Neo und Stream Deck (15 Tasten) kommen mit. Umschalten in der Stream-Deck-App beim jeweiligen Gerät.

Vollbild und „Letzten Bereich wiederholen“ vom Stream Deck (oder aus einer anderen App) nimmt Knippi ohne Auswahl auf. Diese Bildschirmfotos werden immer gesichert und mit einem Hinweis angezeigt, kommen aber nicht automatisch in die Zwischenablage oder in die Cloud. Kopieren geht über das Vorschaubild.

Beim ersten Tastendruck fragt Knippi, ob andere Apps Aufnahmen starten dürfen. Später änderst du das unter Einstellungen → Allgemein → Automatisierung. Hast du abgelehnt, zeigt die Taste ein Warnzeichen.

## Verlauf und Suche

Menüleiste → „Bildschirmfoto-Verlauf …“, option + shift + H oder die Stream-Deck-Taste „Screenshot-Verlauf“ zeigt die letzten Bildschirmfotos aus deinem Ablageordner als Raster. Ab Werk ist der Verlauf aus; im Fenster schaltest du ihn mit „Verlauf einschalten“ ein, die Anzahl (25, 50 oder 100) stellst du unter Einstellungen → Bildschirmfotos → „Bildschirmfoto-Verlauf“ → „Verlauf behalten“ ein.

Im Suchfeld findest du ein Bildschirmfoto über den Text im Bild. Groß- und Kleinschreibung und Akzente spielen keine Rolle. Return kopiert den neuesten Treffer.

- **Klick** wählt ein Bild und kopiert es. **Shift- oder command-Klick** wählt mehrere (oder nimmt eins wieder heraus), ohne etwas zu kopieren. command + A wählt alle, Esc hebt die Auswahl auf.
- **Doppelklick** öffnet das Bild, **Leertaste** zeigt es in der Schnellansicht (Pfeiltasten blättern weiter).
- **Ziehen** schickt eine Kopie in eine andere App.
- **Entf** legt die Auswahl in den Papierkorb, **command + Z** holt die letzte Auswahl zurück (auch im Menü mit den drei Punkten: „Papierkorb rückgängig“). Knippi überschreibt dabei nie eine Datei, die inzwischen wieder unter dem alten Namen liegt.
- **Rechtsklick** bietet außerdem „Teilen …“, „Im Editor öffnen“ und „Im Finder zeigen“. Kopieren, Teilen und Papierkorb gelten für die ganze Auswahl.

Der Verlauf liest nur Bildschirmfotos im Ablageordner. Ist „Automatisch sichern“ aus, fehlen neue Bildschirmfotos dort; das Fenster bietet an, es einzuschalten. Den Text liest Knippi nur, solange das Fenster offen ist. Beim Ausschalten und über „Index löschen“ wird der gelesene Text gelöscht. Beides findest du im Verlauf-Fenster unter dem Symbol mit den drei Punkten neben dem Suchfeld und in den Einstellungen unter Bildschirmfotos → „Bildschirmfoto-Verlauf“.

## Updates

Ab Werk fragt Knippi nicht von selbst bei GitHub nach neuen Versionen. Von Hand: Menüleiste → „Nach Updates suchen …“ oder Einstellungen → Allgemein → „Nach Updates suchen“. Die automatische Suche schaltest du unter Einstellungen → Allgemein → Updates ein. Findet Knippi dann im Hintergrund eine neue Version, steht oben im Menü „Update auf … verfügbar“. Updates sind signiert; Knippi installiert nur Versionen, deren Signatur stimmt.

## Datenschutz

Aufnahmen, Texterkennung und die Suche nach Vertraulichem bleiben auf deinem Mac. Schaltest du den Verlauf ein, legt Knippi den gelesenen Text als Suchindex auf deinem Mac ab (unverschlüsselt, nur für dein Benutzerkonto lesbar, er kann in Backups landen); du kannst ihn jederzeit löschen. Ins Netz geht Knippi nur für die Update-Suche und, wenn du sie einrichtest, für die Cloud-Freigabe.

## Fehler melden

Probleme und Wünsche: Einstellungen → Allgemein → „Fehler melden“ bzw. „Funktion vorschlagen“, oder direkt auf github.com/miwixyz/Knippi.
