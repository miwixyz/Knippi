# Knippi – Messwerte

Ziele (Spec §1): Kürzel → Auswahl < 150 ms · Leerlauf < 40 MB phys_footprint, 0 % CPU · App < 15 MB (arm64, ohne Debug-Symbole)

| Datum | Stand | App-Größe | Leerlauf phys_footprint | CPU Leerlauf | Kürzel → Auswahl | Tests |
|---|---|---|---|---|---|---|
| 2026-11-20 | Capso aba1f64 (universal, ungestrippt) | 48 MB | 18 MB | 0,0 % | nicht gemessen | 547, 3 rot |
| 2026-11-20 | knippi/fork-basis 6ff1b42 (Release, arm64, gestrippt) | 11 MB | 16 MB | 0,0 % | nicht gemessen (Freigabe fehlt) | Pakete 704 + App 235, alle grün |
| 2026-11-20 | knippi/plan-b 56e966b (Release, arm64, gestrippt) | 12 MB | 15 MB | 0,0 % | nicht gemessen | Pakete 811 + App 259, grün (nach Audit-Fixes edf5afe) |

## Arbeitsspeicher während der Aufnahme (2026-11-20, main ad14750)

Release-Build (nicht gestrippt) als Testkopie `dev.mwlr.knippi.sichttest`, MacBook Air M5, Bildschirm 2560×1664 Retina. Ausgelöst per `open -g -b dev.mwlr.knippi.sichttest knippi://grab/fullscreen`, automatisches Kopieren und Sichern aus, „Nach der Aufnahme: Vorschau zeigen“, Vorschaubild schließt nach 5 s. Gemessen mit `footprint -p` (phys_footprint). Echte Aufnahme belegt über das Vorschaubild-Fenster (288×200) in der Fensterliste; ohne Freigabe nimmt Knippi seit B9 nichts auf.

| Zustand | phys_footprint | CPU |
|---|---|---|
| Leerlauf nach dem Start (30 s) | 15 MB | 0,0 % |
| 1 s nach der ersten Vollbild-Aufnahme | 39 MB | 33 % (kurz) |
| Vorschaubild offen (3–6 s) | 35 MB | 0,0 % |
| nach dem Schließen, 25–40 s | 29 MB | 0,0 % |
| Spitze bei 5 Aufnahmen im 2-s-Takt | 44 MB | – |
| nach 16 Aufnahmen, 60 s Ruhe | 31 MB | 0,0 % |

Ergebnis: kein Leck (Ruhewert bleibt nach 6 und nach 16 Aufnahmen bei 31–32 MB). Die erste Aufnahme hebt den Ruhewert einmalig um ~16 MB (Aufnahme-, Bild- und Fenster-Puffer). „15 MB im Leerlauf“ gilt also nur bis zur ersten Aufnahme; im Gebrauch sind es ~31 MB.
