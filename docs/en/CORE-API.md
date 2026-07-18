# Core API

Precise reference for the public Bash APIs under `core/`. Recipes should use these modules — not reinvent them.

## Hook entry

Every hook script:

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load <profile>   # install|launch|validate|repair|kill|minimal
```

`PROJECT_ROOT` is discovered by walking up until `core/recipe-hooks.sh` exists (also for `recipes/community/<id>/`).

### Profiles (`recipe_hooks::load`)

| Profile | Modules loaded (excerpt) | Side effects |
|---------|--------------------------|--------------|
| `minimal` | `paths`, `recipe`, `output` | Env only — for **uninstall** |
| `install` | security, wine-runtime, prefix, deploy, install, install-steps, winetricks, win10, … | `wine_wrappers`, `force_prefix`, `WINEARCH=win64` |
| `launch` | env-file, wine-runtime, guard, … | `wine_wrappers`, `force_prefix` |
| `validate` | env-file, `recipe-validate` | Read-only |
| `repair` | wine-runtime, prefix, winetricks, win10, validate, … | `wine_wrappers`, `force_prefix` |
| `kill` | wine-runtime, `recipe-kill` | `force_prefix` |

Afterwards `recipe_hooks::load_app_module` always runs (optional `core/recipe-<id>.sh` / `-install.sh` / `-launch.sh`).

!!! danger "Uninstall"

    Always `recipe_hooks::load minimal` — **never** `load kill` (Proton hang risk).

---

## `recipe-hooks.sh`

| Function | Role |
|----------|------|
| `recipe_hooks::load` | Load profile |
| `recipe_hooks::purge_recipe_data` | Desktop + chosen + canonical `data_root` |
| `recipe_hooks::force_prefix` | `WINEPREFIX` / `WINE_PREFIX` = `$DATA_ROOT/prefix` |
| `recipe_hooks::wine_wrappers` | Shell functions `wine` / `winetricks` / … → Proton |
| `recipe_hooks::runtime_init` | `wine_runtime::reset; init; export_env` |
| `recipe_hooks::state_set` / `state_get` | Keys in `$DATA_ROOT/recipe.env` |
| `recipe_hooks::emit_log_paths` | `RECIPE_LOG_FILE=` / `RECIPE_ERROR_LOG=` for GUI |
| `recipe_hooks::install_prefix` | Runtime + `recipe_prefix::ensure` |
| `recipe_hooks::install_winetricks_from_recipe` | Packages from YAML + `recipe_win10::ensure` |
| `recipe_hooks::paths_expand_tokens` | `{repo}`, `{data_root}`, `~` |
| `recipe_hooks::validate_prefix` | Prefix initialized? |
| `recipe_hooks::hint_wine_popup` | `@warn:` user action (Mono/dialogs) |

---

## Prefix — `recipe-prefix.sh`

| Function | Role |
|----------|------|
| `recipe_prefix::ensure <prefix>` | Create/update: `wineboot -i`/`-u`, Mono bootstrap, disable virtual desktop |
| `recipe_prefix::wait_ready` | Wait for `user.reg` |

During bootstrap: `WINEDLLOVERRIDES=mscoree=d;mshtml=d;winemenubuilder.exe=d`.

---

## Winetricks — `recipe-winetricks.sh`

| Function | Role |
|----------|------|
| `recipe_winetricks::run <log> <pkgs…>` | Main entry; timeouts 600 s (900 s fonts/dotnet/vcrun) |
| `recipe_winetricks::prepare` | Runtime + cache |
| `recipe_winetricks::stabilize_prefix` | `wineboot -u` with timeout |

**Invariants:**

- Call **only** via `recipe_winetricks::run` (never raw `winetricks` in recipes)
- **Retry only on exit 139** (SIGSEGV) — one wineserver restart, then retry
- Before invoke: `unset -f wine wineboot` (wrappers would break winetricks)
- No `recipe_wine_silent::run` around winetricks (SEGV under Proton)
- `vcrun*` → prefer `recipe_vcrun::ensure`; `dotnet*` → `recipe_dotnet::ensure`; `win10` → `recipe_win10::ensure`

---

## Windows 10 — `recipe-win10.sh`

| Function | Role |
|----------|------|
| `recipe_win10::ensure` | `HKCU\Software\Wine\Version=win10` + `CurrentVersion=10.0`, `CurrentBuild=19045` |

Registry only — **no** winetricks `winecfg` / duplicate `settings win10` **and** `win10` calls.

---

## Validate — `recipe-validate.sh`

| Function | Role |
|----------|------|
| `recipe_validate::ok` / `fail` / `warn` | `OK:` / `FAIL:` / `WARN:` |
| `recipe_validate::prefix_initialized` | `user.reg` present |
| `recipe_validate::graphics_dlls_present` | vkd3d + d3d11 in system32 |
| `recipe_validate::windows_version` | win10 in registry |
| `recipe_validate::vcrun_dll_ok` | `msvcp140.dll` PE check |
| `recipe_validate::version_guaranteed_check` | Against `version_guaranteed` |
| `recipe_validate::winetricks_done` | Entry in `winetricks.log` |

Contract: [Validate & repair](VALIDATE-REPAIR.md).

---

## Install — `recipe-install.sh` / `recipe-install-steps.sh`

### `recipe_install::prepare_source`

Exports among others:

- `RECIPE_SOURCE_TYPE`: `portable_folder` | `installer_file` | `installer_folder`
- `RECIPE_WORK_ROOT`
- `RECIPE_INSTALLER_PATH` (when applicable)

Input order: `RECIPE_INSTALLER_PATH` → `RECIPE_ARCHIVE_PATH` → `source_kind: fixed_path` → `RECIPE_SOURCE_ROOT`.

### `recipe_install_steps::run`

Reads `install_steps:` from YAML (`scripts/recipe-yaml-read.py`).

**Step types:** `prepare_source`, `require_portable`, `prefix`, `winetricks`, `deploy_graphics`, `run_installer`, `stabilize_prefix`, `win10`, `fonts_registry`, `emit_log_paths`, `module`, `copy_asset`, `env_set`, `progress`, `vcrun`, `dotnet`.

Tokens: `{repo}`, `{data_root}`, `{recipe}`, `~`.

Exit **11** if a step fails (GUI may offer retry).

---

## Wine runtime — `wine-runtime.sh`

| Function | Role |
|----------|------|
| `wine_runtime::init` | Load/describe Proton-GE |
| `wine_runtime::ensure_proton_ge` | Download/extract into runtime dir |
| `wine_runtime::export_env` | `WINE`, `PROTON_PATH`, … |
| `wine_runtime::deploy_proton_graphics_dlls` | DXVK/vkd3d from Proton → prefix |
| `wine_runtime::restore_wined3d_dlls` | Back to wined3d (e.g. WISO/Qt) |
| `wine_runtime::winetricks` | `WINE=$_WINE_RUNTIME_BIN winetricks` |
| `wine_runtime::describe` | Human-readable runtime line |

Pin: `core/runtime.lock`. System Wine exists in code only with explicit `runtime: system` / env — **forbidden** in recipes.

---

## Desktop — `recipe-desktop.sh`

| Function | Role |
|----------|------|
| `recipe_desktop::install` | `~/.local/share/applications/rezeptor-<id>.desktop` + desktop copy |
| `recipe_desktop::remove` | Remove entries + icons |
| `recipe_desktop::refresh_if_present` | Rewrite if marker/entry exists |

Marker: `$DATA_ROOT/.rezeptor-desktop`.

---

## Deploy — `recipe-deploy.sh`

| Function | Role |
|----------|------|
| `recipe_deploy::sync_portable <src> <dst> <mode>` | `copy` (default), `move`, `link` |
| `recipe_deploy::detect_installer <dir>` | Find setup / largest EXE |

---

## Paths & env

### `paths.sh`

- `wine_software_base` → `~/.local/share/wine-software`
- `recipe_data_root <id>` → `…/<id>`
- `paths_init_recipe` → `DATA_ROOT`, `WINEPREFIX`, …

### `recipe.sh` — `DATA_ROOT` resolution

1. `canonical` = expanded `data_root:` from YAML  
2. `chosen` = `RECIPE_DATA_ROOT` **or** contents of `$canonical/data_root.path`  
3. `DATA_ROOT = chosen || canonical`

### `env-file.sh`

`env_file_set` / `get` / `write` / `load_export` — **never** `source recipe.env` (injection safety).

### `security.sh`

Path/URL validation, `filesystem::safe_remove` for controlled deletes. Purge uses its own guards.

---

## GUI bridge — `output.sh`

When `LAUNCHER_GUI=1`:

| Tag | Meaning |
|-----|---------|
| `@progress:<pct>` | Progress 0–100 |
| `@step:<msg>` | Step (humanized in the GUI) |
| `@ok:` / `@error:` / `@warn:` | Status |

Short hooks: `output::progress_begin` / `tick` / `done`. See [Log protocol](LOG-PROTOCOL.md).

---

## Other modules

| File | API (excerpt) |
|------|----------------|
| `recipe-vcrun.sh` | `recipe_vcrun::ensure` — MS vc_redist |
| `recipe-dotnet.sh` | `ensure`, Mono bootstrap |
| `recipe-fonts.sh` | `registry`, `ensure` |
| `recipe-kill.sh` | `recipe_kill::run` |
| `recipe-guard.sh` | `abort_if_running`, notify |
| `recipe-source.sh` | Archive extract (zip-slip safe) |
| `recipe-wine-silent.sh` | Offscreen/xvfb when `RECIPE_WINE_SILENT=1` |

App-specific: `recipe-photoshop-*.sh`, `recipe-wiso-steuer.sh`, …

---

## Invariants (short)

1. Prefix always `$DATA_ROOT/prefix` — never `~/.wine`
2. Repair ≠ reinstall
3. Uninstall = `purge_recipe_data` + `load minimal`
4. Winetricks only via `recipe_winetricks::run`
5. Win10 only via `recipe_win10::ensure`
6. Graphics only via Proton DLL deploy (or intentional wined3d)
7. Env files only via `env_file_*`
