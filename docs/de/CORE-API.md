# Core-API

Präzise Referenz der öffentlichen Bash-APIs unter `core/`. Rezepte sollen diese Module nutzen — nicht nachbauen.

## Hook-Einstieg

Jedes Hook-Skript:

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load <profil>   # install|launch|validate|repair|kill|minimal
```

`PROJECT_ROOT` wird nach oben gesucht, bis `core/recipe-hooks.sh` existiert (gilt auch für `recipes/community/<id>/`).

### Profile (`recipe_hooks::load`)

| Profil | Geladene Module (Auszug) | Seiteneffekte |
|--------|--------------------------|---------------|
| `minimal` | `paths`, `recipe`, `output` | Nur Env — für **uninstall** |
| `install` | security, wine-runtime, prefix, deploy, install, install-steps, winetricks, win10, … | `wine_wrappers`, `force_prefix`, `WINEARCH=win64` |
| `launch` | env-file, wine-runtime, guard, … | `wine_wrappers`, `force_prefix` |
| `validate` | env-file, `recipe-validate` | Read-only |
| `repair` | wine-runtime, prefix, winetricks, win10, validate, … | `wine_wrappers`, `force_prefix` |
| `kill` | wine-runtime, `recipe-kill` | `force_prefix` |

Danach läuft immer `recipe_hooks::load_app_module` (optional `core/recipe-<id>.sh` / `-install.sh` / `-launch.sh`).

!!! danger "Uninstall"

    Immer `recipe_hooks::load minimal` — **nie** `load kill` (Proton/Hang-Risiko).

---

## `recipe-hooks.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_hooks::load` | Profil laden |
| `recipe_hooks::purge_recipe_data` | Desktop + gewählter + kanonischer `data_root` |
| `recipe_hooks::force_prefix` | `WINEPREFIX` / `WINE_PREFIX` = `$DATA_ROOT/prefix` |
| `recipe_hooks::wine_wrappers` | Shell-Funktionen `wine` / `winetricks` / … → Proton |
| `recipe_hooks::runtime_init` | `wine_runtime::reset; init; export_env` |
| `recipe_hooks::state_set` / `state_get` | Keys in `$DATA_ROOT/recipe.env` |
| `recipe_hooks::emit_log_paths` | `RECIPE_LOG_FILE=` / `RECIPE_ERROR_LOG=` für GUI |
| `recipe_hooks::install_prefix` | Runtime + `recipe_prefix::ensure` |
| `recipe_hooks::install_winetricks_from_recipe` | Pakete aus YAML + `recipe_win10::ensure` |
| `recipe_hooks::paths_expand_tokens` | `{repo}`, `{data_root}`, `~` |
| `recipe_hooks::validate_prefix` | Prefix initialisiert? |
| `recipe_hooks::hint_wine_popup` | `@warn:` User-Aktion (Mono/Dialoge) |

---

## Prefix — `recipe-prefix.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_prefix::ensure <prefix>` | Anlegen/Update: `wineboot -i`/`-u`, Mono-Bootstrap, Virtual Desktop aus |
| `recipe_prefix::wait_ready` | Wartet auf `user.reg` |

Während Bootstrap: `WINEDLLOVERRIDES=mscoree=d;mshtml=d;winemenubuilder.exe=d`.

---

## Winetricks — `recipe-winetricks.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_winetricks::run <log> <pkgs…>` | Haupteinstieg; Timeouts 600 s (900 s fonts/dotnet/vcrun) |
| `recipe_winetricks::prepare` | Runtime + Cache |
| `recipe_winetricks::stabilize_prefix` | `wineboot -u` mit Timeout |

**Invarianten:**

- Aufruf **nur** über `recipe_winetricks::run` (nie rohes `winetricks` in Rezepten)
- **Retry nur bei Exit 139** (SIGSEGV) — einmal wineserver neu, dann Retry
- Vor Aufruf: `unset -f wine wineboot` (Wrapper würden winetricks brechen)
- Kein `recipe_wine_silent::run` um winetricks (SEGV unter Proton)
- `vcrun*` → bevorzugt `recipe_vcrun::ensure`; `dotnet*` → `recipe_dotnet::ensure`; `win10` → `recipe_win10::ensure`

---

## Windows 10 — `recipe-win10.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_win10::ensure` | `HKCU\Software\Wine\Version=win10` + `CurrentVersion=10.0`, `CurrentBuild=19045` |

Nur Registry — **kein** winetricks `winecfg` / doppelte `settings win10` **und** `win10`-Aufrufe.

---

## Validate — `recipe-validate.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_validate::ok` / `fail` / `warn` | `OK:` / `FAIL:` / `WARN:` |
| `recipe_validate::prefix_initialized` | `user.reg` vorhanden |
| `recipe_validate::graphics_dlls_present` | vkd3d + d3d11 in system32 |
| `recipe_validate::windows_version` | win10 in Registry |
| `recipe_validate::vcrun_dll_ok` | `msvcp140.dll` PE-Check |
| `recipe_validate::version_guaranteed_check` | Gegen `version_guaranteed` |
| `recipe_validate::winetricks_done` | Eintrag in `winetricks.log` |

Vertrag: [Validate & Repair](VALIDATE-REPAIR.md).

---

## Install — `recipe-install.sh` / `recipe-install-steps.sh`

### `recipe_install::prepare_source`

Exportiert u. a.:

- `RECIPE_SOURCE_TYPE`: `portable_folder` | `installer_file` | `installer_folder`
- `RECIPE_WORK_ROOT`
- `RECIPE_INSTALLER_PATH` (falls zutreffend)

Eingabe-Reihenfolge: `RECIPE_INSTALLER_PATH` → `RECIPE_ARCHIVE_PATH` → `source_kind: fixed_path` → `RECIPE_SOURCE_ROOT`.

### `recipe_install_steps::run`

Liest `install_steps:` aus YAML (`scripts/recipe-yaml-read.py`).

**Schritt-Typen:** `prepare_source`, `require_portable`, `prefix`, `winetricks`, `deploy_graphics`, `run_installer`, `stabilize_prefix`, `win10`, `fonts_registry`, `emit_log_paths`, `module`, `copy_asset`, `env_set`, `progress`, `vcrun`, `dotnet`.

Tokens: `{repo}`, `{data_root}`, `{recipe}`, `~`.

Exit **11** bei Fehlschlag eines Schritts (GUI kann Retry anbieten).

---

## Wine-Runtime — `wine-runtime.sh`

| Funktion | Rolle |
|----------|--------|
| `wine_runtime::init` | Proton-GE laden/beschreiben |
| `wine_runtime::ensure_proton_ge` | Download/Extract nach Runtime-Dir |
| `wine_runtime::export_env` | `WINE`, `PROTON_PATH`, … |
| `wine_runtime::deploy_proton_graphics_dlls` | DXVK/vkd3d aus Proton → Prefix |
| `wine_runtime::restore_wined3d_dlls` | Zurück zu wined3d (z. B. WISO/Qt) |
| `wine_runtime::winetricks` | `WINE=$_WINE_RUNTIME_BIN winetricks` |
| `wine_runtime::describe` | Menschenlesbare Runtime-Zeile |

Pin: `core/runtime.lock`. System-Wine existiert im Code nur bei explizitem `runtime: system` / Env — in Rezepten **verboten**.

---

## Desktop — `recipe-desktop.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_desktop::install` | `~/.local/share/applications/rezeptor-<id>.desktop` + Desktop-Kopie |
| `recipe_desktop::remove` | Einträge + Icons entfernen |
| `recipe_desktop::refresh_if_present` | Neu schreiben, wenn Marker/Eintrag existiert |

Marker: `$DATA_ROOT/.rezeptor-desktop`.

---

## Deploy — `recipe-deploy.sh`

| Funktion | Rolle |
|----------|--------|
| `recipe_deploy::sync_portable <src> <dst> <mode>` | `copy` (Default), `move`, `link` (`inplace` = Legacy-Alias für `link`) |
| `recipe_deploy::detect_installer <dir>` | Setup-/größte EXE finden |

Schema/`recipe.yml`: `deploy_mode: copy|link|move`. Portable üblich: `copy` oder `link` (Steam).

---

## Pfade & Env

### `paths.sh`

- `wine_software_base` → `~/.local/share/wine-software`
- `recipe_data_root <id>` → `…/<id>`
- `paths_init_recipe` → `DATA_ROOT`, `WINEPREFIX`, …

### `recipe.sh` — `DATA_ROOT`-Auflösung

1. `canonical` = expandiertes `data_root:` aus YAML  
2. `chosen` = `RECIPE_DATA_ROOT` **oder** Inhalt von `$canonical/data_root.path`  
3. `DATA_ROOT = chosen || canonical`

### `env-file.sh`

`env_file_set` / `get` / `write` / `load_export` — **niemals** `source recipe.env` (Injection-Schutz).

### `security.sh`

Pfad-/URL-Validierung, `filesystem::safe_remove` für kontrollierte Löschungen. Purge nutzt eigene Guards.

---

## GUI-Bridge — `output.sh`

Bei `LAUNCHER_GUI=1`:

| Tag | Bedeutung |
|-----|-----------|
| `@progress:<pct>` | Fortschritt 0–100 |
| `@step:<msg>` | Schritt (humanisiert in der GUI) |
| `@ok:` / `@error:` / `@warn:` | Status |

Kurz-Hooks: `output::progress_begin` / `tick` / `done`. Siehe [Log-Protokoll](LOG-PROTOCOL.md).

---

## Weitere Module

| Datei | API (Auszug) |
|-------|----------------|
| `recipe-vcrun.sh` | `recipe_vcrun::ensure` — MS vc_redist |
| `recipe-dotnet.sh` | `ensure`, Mono-Bootstrap |
| `recipe-fonts.sh` | `registry`, `ensure` |
| `recipe-kill.sh` | `recipe_kill::run` |
| `recipe-guard.sh` | `abort_if_running`, Notify |
| `recipe-source.sh` | Archive extract (zip-slip-sicher) |
| `recipe-wine-silent.sh` | Offscreen/xvfb bei `RECIPE_WINE_SILENT=1` |

App-spezifisch: `recipe-photoshop-*.sh`, `recipe-wiso-steuer.sh`, …

---

## Invarianten (kurz)

1. Prefix immer `$DATA_ROOT/prefix` — nie `~/.wine`
2. Repair ≠ Reinstall
3. Uninstall = `purge_recipe_data` + `load minimal`
4. Winetricks nur über `recipe_winetricks::run`
5. Win10 nur über `recipe_win10::ensure`
6. Grafik nur über Proton-DLL-Deploy (oder bewusst wined3d)
7. Env-Dateien nur über `env_file_*`
