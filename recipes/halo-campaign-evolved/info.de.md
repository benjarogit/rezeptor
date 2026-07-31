# Halo Campaign Evolved

Getestetes Pack: **Halo.Campaign.Evolved.Premium.Edition.MULTi13-ElAmigos** (g4u / ElAmigos).

Offline-Installer unter Proton-GE: ISO mounten → `setup.exe` (still) → optionale nummerierte Updates.

## Quelle

- Pack-Ordner mit der ISO, **oder** die ISO direkt — nichts umbenennen
- Optional unter der Quelle: `updates/` mit `1 - …/` (auch `updates/<Name>/1 - …/`)
- Oder separates Update-Feld / **Mehr → Update anwenden**

## Updates

Siehe [UPDATES.md](UPDATES.md). ElAmigos-Pakete: Ordner `1 - Halo … update …/` mit `.exe` + `elamigos-1.bin`.

## Hinweise

- ISO wird **gemountet** (kein Voll-Extract der ~66 GiB); derselbe Datenträger wird wiederverwendet (kein Mehrfach-Mount).
- Setup läuft still (Inno `/VERYSILENT` + `/LANG` + `/DIR=`). Keine Klick-Kette bei Abbruch.
- **Nickname / Spielsprache:** Bei stiller Installation entfällt der ElAmigos-Wizard. Nach dem Install öffnet Rezeptor optional den Spielordner — dort ggf. Config-Dateien anpassen (oder im Spiel nach dem ersten Start).
- BYOS: Rezeptor liefert keine Download-Links — Pack-Titel unter „Wonach suchen“ im Quellen-Dialog.
