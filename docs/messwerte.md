# Knippi – Messwerte

Ziele (Spec §1): Kürzel → Auswahl < 150 ms · Leerlauf < 40 MB phys_footprint, 0 % CPU · App < 15 MB (arm64, ohne Debug-Symbole)

| Datum | Stand | App-Größe | Leerlauf phys_footprint | CPU Leerlauf | Kürzel → Auswahl | Tests |
|---|---|---|---|---|---|---|
| 2026-11-20 | Capso aba1f64 (universal, ungestrippt) | 48 MB | 18 MB | 0,0 % | nicht gemessen | 547, 3 rot |
| 2026-11-20 | knippi/fork-basis 6ff1b42 (Release, arm64, gestrippt) | 11 MB | 16 MB | 0,0 % | nicht gemessen (Freigabe fehlt) | Pakete 704 + App 235, alle grün |
| 2026-11-20 | knippi/plan-b 56e966b (Release, arm64, gestrippt) | 12 MB | 15 MB | 0,0 % | nicht gemessen | Pakete 811 + App 259, grün (nach Audit-Fixes edf5afe) |
