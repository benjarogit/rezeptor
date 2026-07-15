# Rezept-Authoring (Rezeptor)

Jedes Programm ist ein Rezept — **gleiches Muster**, kein Sonderfall.

## Community: Rezept in 4 Schritten

```bash
./scripts/new-recipe.sh meine-app "Meine App"
./scripts/new-recipe.sh adobe-tool "Mein Tool" --type installer
./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh
./scripts/recipe-manifest.sh
```

Vorlagen: `recipes/_template/`, `recipes/_template-installer/`.  
Referenz: `wiso-steuer` (deklarative `install_steps`), `photoshop` (`module:`).

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
  - module: recipe_wiso::apply_wined3d
  - copy_asset:
      src: assets/foo.sh
      dest: "{data_root}/bin/foo.sh"
  - run_installer      # installer_offline
  - win10
  - fonts_registry
```

| Schritt | Rolle |
|---------|--------|
| `prepare_source` | Quelle → `RECIPE_WORK_ROOT` |
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

Schema: [`recipes/recipe.schema.json`](../../recipes/recipe.schema.json).

**Portable:**

```yaml
install_type: portable_launch
deploy_mode: copy
source_kind: folder
source_formats: zip,tar.gz,tgz
target_default: "~/Dokumente/Meine App"
winetricks: [win10, vcrun2019]
install_steps:
  - prepare_source
  - require_portable
  - prefix
  - winetricks
```

**Installer:**

```yaml
install_type: installer_offline
source_kind: fixed_path
installer_dir: "{repo}/installer"
install_steps:
  - prepare_source
  - prefix
  - winetricks
  - run_installer
```

**Steam-Titel mit externem Fix (BYOS, Launch aus Rezeptor):**

Für Spiele, die im Steam-Ordner bleiben und nur einen selbst eingelegten Fix brauchen
(z. B. `house-of-ashes`). Kein Fix-Vertrieb im Repo — validate prüft Dateien read-only,
Launch setzt Proton + `WINEDLLOVERRIDES` / `SteamAppId`.

Wichtig: kein neuer Steam-Eintrag (Start nur Rezeptor); FakeAppId oft **480/Spacewar**
(muss in Steam installiert sein); Deinstall entfernt nur Rezeptor-Wrapper, nicht Spiel/Fix.

```yaml
install_type: game_portable
deploy_mode: link          # kein Kopieren; Dialog ohne Zielordner
source_kind: folder
steam_appid: "1281590"     # echte Steam-AppID (compatdata)
runtime: proton-ge          # Rezeptor Proton-GE (Prio); Steam-compatdata für Fix/Spacewar
fix_kind: none
exe_glob: "HouseOfAshes.exe"
install_steps:
  - emit_log_paths         # Logik in install.sh / validate.sh / launch.sh
```

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

Verboten (Lint ERROR): `winetricks dxvk`, System-Wine-Fallback, doppeltes win10.

---

## Grafik-Apps — GPU

Siehe [GPU-EXPERIMENTS.md](../maintainer/de/GPU-EXPERIMENTS.md), [HANDOFF-PHOTOSHOP-GPU.md](../maintainer/de/HANDOFF-PHOTOSHOP-GPU.md).  
DXVK nur über `wine_runtime::deploy_proton_graphics_dlls` — **kein** winetricks-dxvk.

---

## Kernmodule

| Datei | Zweck |
|-------|--------|
| `recipe-hooks.sh` | Hook-Einstieg |
| `recipe-install-steps.sh` | Deklarative Installation |
| `recipe-install.sh` | prepare_source / apply_fix |
| `recipe-<id>.sh` | App-Logik |
| `wine-runtime.sh` | Proton-GE |
