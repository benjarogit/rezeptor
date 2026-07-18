# Rezept-Authoring (Rezeptor)

Tiefenreferenz für `recipe.yml`, `install_steps` und Hooks.  
**Schnellstart & Muster** (Portable, Installer, Steam, Trainer): **[ENTWICKLER.md](ENTWICKLER.md)**.

Vorlagen: `recipes/_template/`, `recipes/_template-installer/`.

---

## Architektur

```
recipes/<id>/
  recipe.yml          ← Metadaten + install_steps + uninstall:
  install.sh          ← recipe_hooks::load + recipe_install_steps::run
  launch.sh / validate.sh / repair.sh / kill.sh / uninstall.sh

core/
  recipe-hooks.sh           ← Einstieg (+ purge_recipe_data)
  recipe-install-steps.sh   ← führt install_steps aus
  recipe-<id>.sh            ← App-Logik (module:)
recipes/recipe.schema.json  ← Vertrag
```

### uninstall.sh (Pflicht — vollständig)

Immer `recipe_hooks::load minimal` und **`recipe_hooks::purge_recipe_data`** (Desktop + `DATA_ROOT` + kanonischer `data_root` inkl. `data_root.path`).  
Nicht nur `prefix/` oder `recipe.env` löschen — sonst bleibt die GUI bei „installiert“.  
Kein `load kill` in uninstall (Proton/Hang). Portable/Spielordner außerhalb von `DATA_ROOT` bleiben.

### install.sh (immer dünn)

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_install_steps::run
```

### `install_steps` (Pflicht)

```yaml
install_steps:
  - prepare_source
  - require_portable   # portable
  - prefix
  - winetricks         # aus winetricks: in yml
  - winetricks: [corefonts, gdiplus]
  - module: recipe_meine_app::post_deploy
  - copy_asset:
      src: assets/foo.sh
      dest: "{data_root}/bin/foo.sh"
  - run_installer      # installer_offline
  - win10
  - fonts_registry
```

| Schritt | Rolle |
|---------|--------|
| `prepare_source` | Quelle → `RECIPE_WORK_ROOT` (Ordner/Archiv/Installer) |
| `require_portable` | erwartet `portable_folder` |
| `prefix` | Proton + Prefix |
| `winetricks` | Pakete (yml oder Liste); `vcrun*`/`dotnet*`/`win10` speziell |
| `deploy_graphics` | Proton-Grafik-DLLs |
| `run_installer` | Setup.exe |
| `module` | `recipe_*::funktion` aus Core |
| `copy_asset` | Datei deployen |
| `env_set` | Key in portable.env / Datei |
| `stabilize_prefix` / `win10` / `fonts_registry` | Hilfsschritte |

Parser: `scripts/recipe-yaml-read.py` · Schema: `scripts/recipe-schema-check.py` (embedded; optional `jsonschema`).

---

## `recipe.yml` Pflicht

`id`, `name`, `icon`, `data_root`, `runtime`, `install_type`, `source_kind`, `fix_kind`, Hooks (**inkl. `uninstall`**), **`install_steps`**.

### Icon (Pflicht)

```yaml
icon: "{repo}/images/<id>-icon.png"
```

- Datei unter `images/` (PNG oder SVG), empfohlen **256×256**
- GUI: Sidebar + Header; Notify kann dasselbe Icon nutzen
- Lint prüft: Feld gesetzt **und** Datei existiert
- Quelle z. B. EXE-Icon (`wrestool`/`icotool`) oder Steam-Library-Art

### Empfohlen

| Feld | Rolle |
|------|--------|
| `author` | Anzeige in der Übersicht |
| `notify_title` | Desktop-Notify `-a` / Titel; sonst `name` |
| `version_label` / `version_guaranteed` | Getestete Version (Anzeige + Garantie) |
| `version_detect` | **Pflicht bei `version_guaranteed`** — deklarative Erkennung (siehe unten) |
| `steam_appid` | Steam AppID: Trainer-Zielordner **oder** Spielordner bei `deploy_mode: link` |
| `steam_target_folder` | Unterordner im Spielverzeichnis (Default `Trainer`; nur bei copy/Trainer) |

**Notify-Titel:** manuell (`notify_title`) **oder** Fallback `name` — kein Auto-Detect aus EXE-Namen.

### Versionserkennung (`version_detect`)

Rezeptor prüft die gewählte Quelle gegen `version_guaranteed`. Die Regeln stehen im Rezept — der Launcher liefert die Engine.

```yaml
version_guaranteed: "22.0.0.35"
version_detect:
  - kind: json_key
    glob: "products/PHSP/application.json"
    key: ProductVersion
  - kind: pe_field
    glob: "*.exe"
    field: FileVersion
```

| `kind` | Zweck |
|--------|--------|
| `json_key` | JSON-Datei (`glob` + `key`) |
| `text_regex` | Textzeile (`glob` + `regex` mit Gruppe) |
| `path_regex` | Ordner-/Dateiname |
| `pe_field` | PE `FileVersion` / `ProductVersion` |
| `pe_contains` | Byte-Marker in EXE → `value` (z. B. Trainer-Familie) |
| `filename_regex` | Dateiname → `value` |
| `stack` | Mehrere Dateien + INI-Keys (Steam+Fix) |

Signale werden **der Reihe nach** versucht; erstes Ergebnis gewinnt. `stack` kann bei Teilerkennung eine Abweichungs-Meldung liefern.

Lint: `version_guaranteed` ohne `version_detect` → **ERROR**.

### Info-Layout (`info.de.txt` / `info.en.txt`)

```
# <Titel>

Autor: …
Version: …

## Kurzbeschreibung
…

## Voraussetzungen
• …

## Installation
1. …

## Nutzung
• …

## Hinweise
• …
```

**Schreibstil:** professionell und klar, locker lesbar, Business-Ton — auch für Einsteiger verständlich. Struktur und Aussage beibehalten; nur Formulierungen glätten. Fachbegriffe nur wenn nötig, kurz erklären. Keine inhaltliche Aufblähung.

Schema: [`recipes/recipe.schema.json`](https://github.com/benjarogit/rezeptor/blob/main/recipes/recipe.schema.json).

**Portable:**

```yaml
install_type: portable_launch
deploy_mode: copy
source_kind: folder
source_formats: zip,tar.gz,tgz,7z,rar
target_default: "~/Dokumente/Meine App"
winetricks: [win10, vcrun2019]
install_steps:
  - prepare_source
  - require_portable
  - prefix
  - winetricks
```

**Installer** (entspricht `recipes/_template-installer/`):

```yaml
install_type: installer_offline
source_kind: folder          # GUI wählt Setup-Ordner / .exe
source_label: "Ordner mit Offline-Installer (setup.exe / Set-up.exe)"
winetricks: [win10, vcrun2015]
install_steps:
  - prepare_source
  - prefix
  - winetricks
  - run_installer
```

Optional (selten): `source_kind: fixed_path` + `installer_dir: "{repo}/installer"` für fest verdrahtete Repo-Pfade — die mitgelieferte Vorlage nutzt das **nicht**.

**Steam-Titel mit externem Fix (BYOS, Launch aus Rezeptor):**

Für Spiele, die im Steam-Ordner bleiben und nur einen selbst eingelegten Fix brauchen
(z. B. `house-of-ashes`). Kein Fix-Vertrieb im Repo — validate prüft Dateien read-only,
Launch setzt Proton + `WINEDLLOVERRIDES` / `SteamAppId`. Vorlage: `_template-steam-game/`.

Wichtig: kein neuer Steam-Eintrag (Start nur Rezeptor); FakeAppId oft **480/Spacewar**
(muss in Steam installiert sein); Deinstall entfernt nur Rezeptor-Wrapper, nicht Spiel/Fix.

```yaml
install_type: game_portable
deploy_mode: link          # kein Kopieren; Dialog ohne Zielordner
source_kind: folder
steam_appid: "1281590"     # echte Steam-AppID (compatdata)
steam_fake_appid: "480"    # oft Spacewar — muss in Steam installiert sein
steam_fix_win64_rel: "Binaries/Win64"   # relativ zum Spielordner
steam_fix_required:
  - OnlineFix64.dll
  - OnlineFix.ini
steam_api_rel: ""          # optional, relativ zum Spielordner
runtime: proton-ge
fix_kind: none
exe_glob: "HouseOfAshes.exe"
install_steps:
  - emit_log_paths         # Logik in install.sh / validate.sh / launch.sh
```

| Feld | Rolle |
|------|--------|
| `steam_appid` | Echte AppID → Steam-Spielordner / compatdata |
| `steam_fake_appid` | FakeAppId in Online-Fix-INI (häufig `480`) |
| `steam_fix_win64_rel` | Unterordner mit Fix-DLLs/INI |
| `steam_fix_required` | Pflicht-Dateinamen für validate |
| `steam_api_rel` | Optionaler `steam_api64.dll`-Pfad |

Details: [STEAM-WRAPPER.md](STEAM-WRAPPER.md).

| | Trainer (`za4-trainer`) | Steam+Fix (`house-of-ashes`) |
|--|-------------------------|------------------------------|
| Quelle | einzelne `.exe` | Spielordner |
| Deploy | copy in Zielunterordner | `link` (Pfad merken) |
| Prefix | Steam compatdata des Spiels | dasselbe |
| Validate | EXE + Wrapper | EXE + Fix-Dateien + INI-AppIDs |
| Uninstall | nur Rezeptor-Dateien | nur Rezeptor-State; Spiel/Fix bleiben |

Tokens: `{repo}`, `{data_root}`, `{recipe}`, `~`.

---

## Qualität / CI

```bash
./scripts/recipe-lint.sh      # Hooks ERROR, install_steps, Schema
./scripts/recipe-manifest.sh
make recipe-lint              # CI
REZEPTOR_DEV=1 ./setup.sh
```

### Runtime-Helfer (Pflicht in Custom-/Repair-Code)

| Aufgabe | Nur so | Nie |
|---------|--------|-----|
| Winetricks | `recipe_winetricks::run` (Retry **nur** Exit 139) | Direktes `winetricks`, Subshell-Hacks |
| Windows 10 | `recipe_win10::ensure` (Registry) | `winetricks winecfg` / doppeltes `win10`+`settings win10` |
| Grafik/DXVK | `wine_runtime::deploy_proton_graphics_dlls` | `winetricks dxvk` |
| Prefix | `recipe_prefix::ensure` | System-Wine-Fallback |

Verboten (Lint ERROR): `winetricks dxvk`, System-Wine-Fallback, doppeltes win10.  
API-Details: [CORE-API.md](CORE-API.md).

---

## Grafik-Apps — GPU

Siehe [GPU-EXPERIMENTS.md](maintainer/GPU-EXPERIMENTS.md), [HANDOFF-PHOTOSHOP-GPU.md](maintainer/HANDOFF-PHOTOSHOP-GPU.md).  
DXVK nur über `wine_runtime::deploy_proton_graphics_dlls` — **kein** winetricks-dxvk.

---

## Kernmodule

Vollständige API: **[CORE-API.md](CORE-API.md)**. Kurz:

| Datei | Zweck |
|-------|--------|
| `recipe-hooks.sh` | Hook-Einstieg + `purge_recipe_data` |
| `recipe-install-steps.sh` | Deklarative Installation |
| `recipe-install.sh` | prepare_source / apply_fix |
| `recipe-prefix.sh` / `recipe-winetricks.sh` / `recipe-win10.sh` | Prefix, Winetricks (Retry 139), Win10 |
| `recipe-validate.sh` | OK/FAIL/WARN-Helfer |
| `recipe-<id>.sh` | App-Logik |
| `wine-runtime.sh` | Proton-GE + Grafik-DLLs |

Lifecycle: [VALIDATE-REPAIR.md](VALIDATE-REPAIR.md) · [UNINSTALL.md](UNINSTALL.md) · [LOG-PROTOCOL.md](LOG-PROTOCOL.md)
