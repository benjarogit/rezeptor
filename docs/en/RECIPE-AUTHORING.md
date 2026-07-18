# Recipe authoring (Rezeptor)

Deep reference for `recipe.yml`, `install_steps`, and hooks.  
**Quick start & patterns** (portable, installer, Steam, trainers): **[ENTWICKLER.md](ENTWICKLER.md)**.

Templates: `recipes/_template/`, `recipes/_template-installer/`.

---

## Architecture

```
recipes/<id>/
  recipe.yml          ← metadata + install_steps + uninstall:
  install.sh          ← recipe_hooks::load + recipe_install_steps::run
  launch.sh / validate.sh / repair.sh / kill.sh / uninstall.sh

core/
  recipe-hooks.sh           ← entry (+ purge_recipe_data)
  recipe-install-steps.sh   ← runs install_steps
  recipe-<id>.sh            ← app logic (module:)
recipes/recipe.schema.json  ← contract
```

### uninstall.sh (required — complete wipe)

Always `recipe_hooks::load minimal` and **`recipe_hooks::purge_recipe_data`** (desktop + `DATA_ROOT` + canonical `data_root` including `data_root.path`).  
Do not only delete `prefix/` or `recipe.env` — the GUI will still show “installed”.  
No `load kill` in uninstall (Proton hang). Portable/game folders outside `DATA_ROOT` stay.

### Thin install.sh

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_install_steps::run
```

### `install_steps` (required)

```yaml
install_steps:
  - prepare_source
  - require_portable   # portable
  - prefix
  - winetricks         # from winetricks: in yml
  - winetricks: [corefonts, gdiplus]
  - module: recipe_my_app::post_deploy
  - copy_asset:
      src: assets/foo.sh
      dest: "{data_root}/bin/foo.sh"
  - run_installer      # installer_offline
  - win10
  - fonts_registry
```

| Step | Role |
|------|------|
| `prepare_source` | Source → `RECIPE_WORK_ROOT` (folder/archive/installer) |
| `require_portable` | expects `portable_folder` |
| `prefix` | Proton + prefix |
| `winetricks` | packages (yml or list); `vcrun*`/`dotnet*`/`win10` special-cased |
| `deploy_graphics` | Proton graphics DLLs |
| `run_installer` | Setup.exe |
| `module` | `recipe_*::function` from core |
| `copy_asset` | deploy a file |
| `env_set` | key in portable.env / file |
| `stabilize_prefix` / `win10` / `fonts_registry` | helpers |

Parser: `scripts/recipe-yaml-read.py` · Schema: `scripts/recipe-schema-check.py` (embedded; optional `jsonschema`).

---

## Required `recipe.yml` fields

`id`, `name`, `icon`, `data_root`, `runtime`, `install_type`, `source_kind`, `fix_kind`, hooks (**including `uninstall`**), **`install_steps`**.

### Icon (required)

```yaml
icon: "{repo}/images/<id>-icon.png"
```

- File under `images/` (PNG or SVG), recommended **256×256**
- GUI: sidebar + header; notify may use the same icon
- Lint checks: field set **and** file exists
- Source e.g. EXE icon (`wrestool`/`icotool`) or Steam library art

### Recommended

| Field | Role |
|------|------|
| `author` | Shown in the overview |
| `notify_title` | Desktop notify `-a` / title; else `name` |
| `version_label` / `version_guaranteed` | Tested version (display + guarantee) |
| `version_detect` | **Required with `version_guaranteed`** — declarative detection (see below) |
| `steam_appid` | Steam AppID: trainer target folder **or** game folder when `deploy_mode: link` |
| `steam_target_folder` | Subfolder under the game dir (default `Trainer`; trainer/copy only) |

**Notify title:** manual (`notify_title`) **or** fallback `name` — no auto-detect from EXE filenames.

### Version detection (`version_detect`)

Rezeptor checks the chosen source against `version_guaranteed`. Rules live in the recipe — the launcher ships the engine.

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

| `kind` | Purpose |
|--------|---------|
| `json_key` | JSON file (`glob` + `key`) |
| `text_regex` | Text line (`glob` + `regex` with group) |
| `path_regex` | Folder/file name |
| `pe_field` | PE `FileVersion` / `ProductVersion` |
| `pe_contains` | Byte markers in EXE → `value` (e.g. trainer family) |
| `filename_regex` | Filename → `value` |
| `stack` | Multiple files + INI keys (Steam+fix) |

Signals run **in order**; first hit wins. `stack` may return a partial-mismatch message.

Lint: `version_guaranteed` without `version_detect` → **ERROR**.

### Info layout (`info.de.txt` / `info.en.txt`)

```
# <Title>

Author: …
Version: …

## Summary
…

## Requirements
• …

## Install
1. …

## Usage
• …

## Notes
• …
```

**Writing style:** professional and clear, easy to read, business tone — accessible for beginners. Keep structure and meaning; only smooth wording. Use technical terms only when needed, with a short explanation. Do not expand the content.

Schema: [`recipes/recipe.schema.json`](https://github.com/benjarogit/rezeptor/blob/main/recipes/recipe.schema.json).

**Portable:**

```yaml
install_type: portable_launch
deploy_mode: copy
source_kind: folder
source_formats: zip,tar.gz,tgz,7z,rar
target_default: "~/Documents/My App"
winetricks: [win10, vcrun2019]
install_steps:
  - prepare_source
  - require_portable
  - prefix
  - winetricks
```

**Installer** (matches `recipes/_template-installer/`):

```yaml
install_type: installer_offline
source_kind: folder          # GUI picks setup folder / .exe
source_label: "Folder with offline installer (setup.exe / Set-up.exe)"
winetricks: [win10, vcrun2015]
install_steps:
  - prepare_source
  - prefix
  - winetricks
  - run_installer
```

Optional (rare): `source_kind: fixed_path` + `installer_dir: "{repo}/installer"` for hard-wired repo paths — the shipped template does **not** use that.

**Steam title with external fix (BYOS, launch from Rezeptor):**

For games that stay in the Steam folder and only need a user-supplied fix
(e.g. `house-of-ashes`). Do not ship the fix in the repo — validate checks files
read-only; launch sets Proton + `WINEDLLOVERRIDES` / `SteamAppId`. Template: `_template-steam-game/`.

Note: no new Steam entry (start via Rezeptor only); FakeAppId is often **480/Spacewar**
(must be installed in Steam); uninstall removes Rezeptor wrapper only, not game/fix.

```yaml
install_type: game_portable
deploy_mode: link          # no copy; dialog without target folder
source_kind: folder
steam_appid: "1281590"     # real Steam AppID (compatdata)
steam_fake_appid: "480"    # often Spacewar — must be installed in Steam
steam_fix_win64_rel: "Binaries/Win64"   # relative to game folder
steam_fix_required:
  - OnlineFix64.dll
  - OnlineFix.ini
steam_api_rel: ""          # optional, relative to game folder
runtime: proton-ge
fix_kind: none
exe_glob: "HouseOfAshes.exe"
install_steps:
  - emit_log_paths         # logic in install.sh / validate.sh / launch.sh
```

| Field | Role |
|-------|------|
| `steam_appid` | Real AppID → Steam game folder / compatdata |
| `steam_fake_appid` | FakeAppId in online-fix INI (often `480`) |
| `steam_fix_win64_rel` | Subfolder with fix DLLs/INI |
| `steam_fix_required` | Required filenames for validate |
| `steam_api_rel` | Optional `steam_api64.dll` path |

Details: [STEAM-WRAPPER.md](STEAM-WRAPPER.md).

| | Trainer (`za4-trainer`) | Steam+fix (`house-of-ashes`) |
|--|-------------------------|------------------------------|
| Source | single `.exe` | game folder |
| Deploy | copy into target subfolder | `link` (remember path) |
| Prefix | game Steam compatdata | same |
| Validate | EXE + wrapper | EXE + fix files + INI AppIDs |
| Uninstall | Rezeptor files only | Rezeptor state only; game/fix stay |

Tokens: `{repo}`, `{data_root}`, `{recipe}`, `~`.

---

## Quality / CI

```bash
./scripts/recipe-lint.sh      # hooks ERROR, install_steps, schema
./scripts/recipe-manifest.sh
make recipe-lint              # CI
REZEPTOR_DEV=1 ./setup.sh
```

### Runtime helpers (required in custom/repair code)

| Task | Only via | Never |
|------|----------|-------|
| Winetricks | `recipe_winetricks::run` (retry **only** exit 139) | Direct `winetricks`, subshell hacks |
| Windows 10 | `recipe_win10::ensure` (registry) | `winetricks winecfg` / duplicate `win10`+`settings win10` |
| Graphics/DXVK | `wine_runtime::deploy_proton_graphics_dlls` | `winetricks dxvk` |
| Prefix | `recipe_prefix::ensure` | System Wine fallback |

Forbidden (lint ERROR): `winetricks dxvk`, system-Wine fallback, duplicate win10.  
API details: [CORE-API.md](CORE-API.md).

---

## GPU graphics apps

See [GPU-EXPERIMENTS.md](maintainer/GPU-EXPERIMENTS.md), [HANDOFF-PHOTOSHOP-GPU.md](maintainer/HANDOFF-PHOTOSHOP-GPU.md).  
DXVK only via `wine_runtime::deploy_proton_graphics_dlls` — **no** winetricks-dxvk.

---

## Core modules

Full API: **[CORE-API.md](CORE-API.md)**. Short:

| File | Role |
|------|------|
| `recipe-hooks.sh` | Hook entry + `purge_recipe_data` |
| `recipe-install-steps.sh` | Declarative install |
| `recipe-install.sh` | prepare_source / apply_fix |
| `recipe-prefix.sh` / `recipe-winetricks.sh` / `recipe-win10.sh` | Prefix, winetricks (retry 139), Win10 |
| `recipe-validate.sh` | OK/FAIL/WARN helpers |
| `recipe-<id>.sh` | App logic |
| `wine-runtime.sh` | Proton-GE + graphics DLLs |

Lifecycle: [VALIDATE-REPAIR.md](VALIDATE-REPAIR.md) · [UNINSTALL.md](UNINSTALL.md) · [LOG-PROTOCOL.md](LOG-PROTOCOL.md)
