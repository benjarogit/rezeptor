# Referenz-Muster: Einzel-EXE / Trainer (Direktstart)

**Zielgruppe: Rezept-Autoren.** Beispiel-Rezept: `za4-trainer`

## Wann dieses Muster?

Keine Portable-Suite und kein großer Offline-Installer, sondern eine **einzelne Windows-`.exe`** (Trainer, kleines Tool, „direkt startbar“). Oft mit `steam_appid`: Ziel ist ein Unterordner im Steam-Spielverzeichnis.

| GUI | Bedeutung |
|-----|-----------|
| **Quelle** | Die `.exe` (BYOS) |
| **Ziel** | Ordner, in den kopiert/gestartet wird (häufig Steam-Spiel + `steam_target_folder`) |

In der GUI heißt das trotzdem **Quelle** / **Ziel** — nicht „Trainer-Pfad“.

## Typische `recipe.yml`-Ecken

- `source_kind: installer` (oder vergleichbar) — eine Datei wählen
- `steam_appid` + optional `steam_target_folder` (Default oft `Trainer`)
- Prefix: eigenes Rezeptor-Prefix **oder** Steam-compatdata — je nach Rezept dokumentieren
- `version_detect`: z. B. `pe_contains` / `filename_regex` für die EXE-Familie

## Bekannte Fallen

| Falle | Hinweis |
|-------|---------|
| Spiel muss existieren | Ohne installiertes Steam-Spiel kein sinnvolles Ziel |
| EXE ≠ Spiel | Trainer startet gegen das Spiel; Proton/Bitness müssen passen |
| Kein Online-Fix-Stack | Das ist ein anderes Muster → [STEAM-WRAPPER.md](STEAM-WRAPPER.md) |

Schnellstart: [ENTWICKLER.md](ENTWICKLER.md) · Spezifikation: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
