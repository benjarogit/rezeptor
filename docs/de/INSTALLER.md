# Referenz-Muster: Offline-Installer

**Zielgruppe: Rezept-Autoren.** Beispiel-Rezept: `photoshop` · Vorlage: `recipes/_template-installer/`

## Wann dieses Muster?

Windows liefert einen **Offline-Installer** (Ordner mit `Set-up.exe` / `Setup.exe` + Pakete, oder eine einzelne Setup-`.exe`). Rezeptor legt Prefix an, startet den Installer unter Proton-GE, speichert App-Daten unter dem **Ziel** (Datenordner).

| GUI | Bedeutung |
|-----|-----------|
| **Quelle** | Installer-Ordner oder `.exe` (BYOS — nicht im Repo) |
| **Ziel** | Datenordner / Wine-Prefix (`RECIPE_DATA_ROOT`) |

## Typische `recipe.yml`-Ecken

- `install_type` / `source_kind`: Installer oder Ordner mit Setup
- `install_steps`: oft `module: recipe_<id>::install` statt langer Schrittliste
- `version_detect`: z. B. `json_key` / `pe_field` gegen die Offline-Quelle
- `uninstall` → `purge_recipe_data` (Prefix + Shortcuts; kein Mitbringen des Installers löschen)

## Bekannte Fallen

| Falle | Hinweis |
|-------|---------|
| GPU/OpenGL in Adobe-Apps | Rezept setzt Prefs; siehe Maintainer-Notizen nur bei Bedarf |
| Quelle ≠ Repo-Pfad | Nutzer bringt Offline-Medium mit; Heuristik: `Downloads/` mit `Set-up.exe` |
| Ziel leer lassen | Default aus `target_default` / Datenordner |

Schnellstart & Typenübersicht: [ENTWICKLER.md](ENTWICKLER.md) · Spezifikation: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
