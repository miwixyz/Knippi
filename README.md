<p align="center">
  <img src="assets/Knippi-App_Icon-1024.png" alt="Knippi-Symbol" width="160">
</p>

# Knippi

Knippi ist eine schnelle, schlanke Screenshot-App für die Menüleiste des Mac. Open Source und kostenlos.

## Was Knippi kann

- **Aufnehmen:** Bereich, Fenster oder ganzer Bildschirm, mit eigenen Tastenkürzeln. Auf Wunsch übernimmt Knippi command + shift + 3, 4 und 5.
- **Video und GIF:** Bereich oder ganzer Bildschirm, mit Systemaudio, wahlweise Mikrofon und eingeblendetem Sprecherbild, das der Maus ausweicht. Wird nach dem Stoppen automatisch gesichert.
- **Scroll-Aufnahme:** Lange Seiten (Webseite, Mail, PDF) als ein Bild, von Hand gescrollt oder automatisch bis zum Seitenende. Feste Kopfleisten erscheinen nur einmal.
- **Schnellzugriff:** Nach der Aufnahme erscheint ein Vorschaubild in der Ecke. Von dort kopieren, sichern, teilen, annotieren oder anheften. Wahlweise öffnet sich sofort der Editor, oder Knippi sichert still.
- **Editor:** Pfeil, Linie, Rechteck, Ellipse, Text, Freihand, Textmarker, Zähler, Spotlight und Verpixeln.
- **Vertrauliches finden:** Knippi schlägt E-Mail-Adressen, Telefonnummern, IBAN, Kartennummern und Zugangsschlüssel vor und verpixelt sie so grob (zeilenhohe Klötzchen mit zufälliger Helligkeit), dass sich der Text praktisch nicht zurückrechnen lässt.
- **Farbe aufnehmen:** Color Picker mit Lupe, mehreren Farbformaten und „Letzte Farben“.
- **Hintergründe:** Verläufe, eigene Bilder und Formate wie 16:9, 1:1 und 4:5. Fenster bleiben auf Wunsch transparent mit Schatten.
- **Texterkennung:** Text aus jedem Bildschirmbereich kopieren, auch aus Bildern und Videos.
- **Verlauf mit Suche:** Die letzten 25, 50 oder 100 Aufnahmen aus dem Sicherungsordner als Raster, durchsuchbar nach dem Text im Bild. Klick kopiert, Doppelklick öffnet, Ziehen schickt eine Kopie in eine andere App, Entf legt in den Papierkorb. Ab Werk aus. Den gelesenen Text speichert Knippi als Suchindex auf deinem Mac; du kannst ihn jederzeit löschen.
- **Teilen:** Teilen-Menü von macOS, optional Cloud-Freigabe in den eigenen Speicher.

Die Hilfe in der App (Menü → „Knippi-Hilfe“) erklärt alles Schritt für Schritt.

## Voraussetzungen

- macOS 26 oder neuer
- Mac mit Apple Silicon

## Installieren

1. [Neueste Version](https://github.com/miwixyz/Knippi/releases/latest) laden (`Knippi-x.y.z.zip`), per Doppelklick entpacken und `Knippi.app` in den Ordner Programme ziehen.
2. Knippi starten. Das Symbol erscheint in der Menüleiste.
3. Beim ersten Bildschirmfoto fragt macOS nach der Freigabe. Unter Systemeinstellungen → Datenschutz & Sicherheit → **Bildschirm- und Systemaudioaufnahme** Knippi einschalten.
4. Auf Wunsch: Einstellungen → Allgemein → „Bei Anmeldung starten“.

Knippi ist von Apple notarisiert und startet ohne Warnung.

## Aktualisieren

Knippi aktualisiert sich über [Sparkle](https://sparkle-project.org) und sucht im Hintergrund nach neuen Versionen. Von Hand: Einstellungen → Allgemein → „Nach Updates suchen“. Jedes Update und die Liste der Updates sind signiert; Knippi installiert nichts, dessen Signatur nicht stimmt.

## Stream Deck

Mit dem Plugin `Knippi.streamDeckPlugin` (liegt jedem Release bei) löst du Knippi über Elgatos Stream Deck aus. Datei laden und doppelklicken, Stream Deck installiert sie.

- **Tasten:** Bereich, Fenster, Vollbild, Scroll-Aufnahme, Letzten Bereich wiederholen, Text erkennen, Farbe aufnehmen, Selbstauslöser, Video Bereich, Video Vollbild. In der Stream-Deck-App unter „Knippi“ auf eine Taste ziehen.
- **Regler (Stream Deck +):** Drehen wählt die Aufnahmeart, Drücken oder Tippen nimmt auf. In den Einstellungen des Reglers wählst du Screenshots oder Video.
- **Fertige Profile** für Stream Deck +, Neo und Stream Deck (15 Tasten) werden mitinstalliert. Umschalten in der Stream-Deck-App beim jeweiligen Gerät.
- Vollbild und „Letzten Bereich wiederholen“ werden ohne Auswahl aufgenommen, immer gesichert und mit Hinweis angezeigt, aber nicht automatisch kopiert oder hochgeladen.
- Die Tasten nutzen Knippis Automations-Befehle. Beim ersten Druck fragt Knippi, ob andere Apps steuern dürfen (später: Einstellungen → Allgemein → Automatisierung). Hast du das abgelehnt oder fehlt Knippi, zeigt die Taste ein Warnzeichen.

## Datenschutz

Aufnahmen, Texterkennung und die Suche nach Vertraulichem laufen vollständig auf dem Mac. Der Verlauf ist ab Werk aus; schaltest du ihn ein, liegt der gelesene Text als Suchindex auf dem Mac und lässt sich löschen. Knippi geht nur für die Update-Suche ins Netz und, falls eingerichtet, für die Cloud-Freigabe in den eigenen Speicher. Keine Analyse, kein Konto, keine Werbung.

## Bauen

```bash
brew install xcodegen
xcodegen generate
open Knippi.xcodeproj
```

Stream-Deck-Plugin: `sh StreamDeck/build.sh` (Paket in `dist/streamdeck/`, `make release` baut und hängt es mit an).

## Herkunft

Knippi basiert auf [Capso](https://github.com/lzhgus/Capso) von lzhgus (MIT).

## Lizenz

MIT, siehe [LICENSE](LICENSE). Hinweise zu Fremdsoftware stehen in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Kontakt

Fehler und Wünsche bitte als [Issue](https://github.com/miwixyz/Knippi/issues). Sonst: tippi@mwlr.dev
