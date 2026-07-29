# Referenz-Muster: Offline-Installer

**Zielgruppe: Rezept-Autoren.** Beispiel-Rezepte: `photoshop`, `photoshop-m0nkrus-220`, `photoshop-m0nkrus`, `premiere` · Vorlage: `recipes/_template-installer/`

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
- `source_hints`: Pack-Titel / Keywords zum Suchen (**keine URLs**); abweichende Packs → eigenes Rezept
- `uninstall` → `purge_recipe_data` (Prefix + Shortcuts; kein Mitbringen des Installers löschen)

### Pack-Ordner (m0nkrus-Stil)

Drei Photoshop-Rezepte (ein Pack = ein Rezept):

| ID | Pack | Garantie |
|----|------|----------|
| `photoshop` | Standard Offline (Set-up + packages) | 22.0.0.35 |
| `photoshop-m0nkrus-220` | Ordner `Photoshop.2021` / `Adobe.Photoshop.2021.Multilingual.iso` (ISO-only) | 22.0.0.35 |
| `photoshop-m0nkrus` | Pack 22.1.1.138 + Neural / missing_libs / GenP | 22.1.1.138 |

Bei `photoshop-m0nkrus`: Quelle = **kompletter Pack-Ordner** (ISO + Sibling-Extras). Rezeptor:

1. nimmt die passende `.iso` als Offline-Installer
2. setzt `RECIPE_PACK_ROOT` und wendet nach dem Adobe-Setup Extras an (`core/recipe-photoshop-pack.sh`): `ps2021_missing_libs.7z`, Neural-Filters-SFX → Wine-`PluginData`
3. startet **kein** GenP (ISO laut Pack vorgepatcht; Cure nur manuell bei Aktivierungsverlust)

Bei `photoshop-m0nkrus-220`: Quelle = ISO-only-Pack (kein Neural/GenP); gleiche Core-Install-API.

Varianten teilen die Core-API mit `photoshop` über dünne Wrapper:

- `core/recipe-photoshop-m0nkrus-install.sh` / `-launch.sh`
- `core/recipe-photoshop-m0nkrus-220-install.sh` / `-launch.sh`

(`module: recipe_photoshop::install` in `recipe.yml`; ohne Wrapper findet `load_app_module` die Funktionen nicht.)

## Bekannte Fallen

| Falle | Hinweis |
|-------|---------|
| GPU/OpenGL in Adobe-Apps | Rezept setzt Prefs über Proton-Graphics-DLLs |
| Quelle ≠ Repo-Pfad | Nutzer bringt Offline-Medium mit; Heuristik: Pack-Ordner / `Downloads/` |
| Nur-ISO statt Pack | Install ok, Neural Filters / missing_libs fehlen |
| Ziel leer lassen | Default aus `target_default` / Datenordner |

Schnellstart & Typenübersicht: [ENTWICKLER.md](ENTWICKLER.md) · Spezifikation: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
