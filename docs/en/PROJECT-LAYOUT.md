# Project layout

Overview of the Rezeptor repository — where things live and which contracts apply.

## Top level

```
rezeptor/
├── core/                 # Shared Bash modules (DRY)
│   └── runtime.lock      # Pinned Proton-GE version + SHA256
├── recipes/
│   ├── <id>/             # Official recipes
│   ├── community/<id>/   # Community (not in manifest)
│   ├── _template*/       # Templates (not in manifest)
│   ├── catalog.json      # GUI catalog + trust
│   ├── manifest.json     # SHA256 integrity
│   └── recipe.schema.json
├── launcher/             # PyQt6 GUI (host PyQt6 for clone/tar.gz; AppImage/Flatpak bundle it)
│   ├── launcher.py          # RezeptorWindow, menus/tabs, delegates
│   ├── recipe_process.py    # RecipeProcessOps — QProcess orchestration
│   ├── recipe_discovery.py  # RecipeInfo / discover
│   └── …                    # see [GUI launcher](LAUNCHER.md) / [Architecture](ARCHITECTURE-LAUNCHER.md)
├── scripts/              # Lint, manifest, new-recipe, builds
├── tests/                # bats + Python
├── docs/{de,en}/         # This site (MkDocs)
├── setup.sh              # Entry → launcher
├── VERSION               # SemVer (release trigger)
└── Makefile              # validate, test, recipe-lint, …
```

## `recipes/<id>/` — required files

Every recipe:

| File | Required | Role |
|------|----------|------|
| `recipe.yml` | yes | Metadata, `install_steps`, hook paths incl. `uninstall:` |
| `install.sh` | yes | First-time install |
| `repair.sh` | yes | validate → fix only what is missing |
| `validate.sh` | yes | Structured `OK:` / `FAIL:` / `WARN:` output |
| `launch.sh` | yes | Launch |
| `uninstall.sh` | yes | Full removal via `purge_recipe_data` |
| `kill.sh` | yes | Kill processes (YAML `kill:`) |

Optional: `info.de.txt` / `info.en.txt`, `assets/`, `optional/`.

!!! warning "Repair is not reinstall"

    `repair.sh` runs `validate.sh`, fixes gaps, validates again — **not** a full re-install.

## `core/` — shared core

Do **not** duplicate new logic in recipes — centralize in `core/` first.

| Module | Responsibility |
|--------|----------------|
| `recipe-hooks.sh` | Hook entry, profiles, `purge_recipe_data` |
| `recipe-install-steps.sh` | Declarative `install_steps` |
| `recipe-updates.sh` | Numbered post-install updates |
| `recipe-iso.sh` | Mount game ISOs (udisksctl) |
| `recipe-prefix.sh` | Create/update prefix |
| `recipe-winetricks.sh` | Winetricks under Proton; retry only exit 139 |
| `recipe-win10.sh` | Windows 10 version (registry, no winecfg) |
| `recipe-validate.sh` | Reusable checks |
| `wine-runtime.sh` | Proton-GE, graphics DLLs |
| `recipe-desktop.sh` | `.desktop` + icons |
| `paths.sh` / `env-file.sh` / `output.sh` | Paths, state, GUI tags |
| `sharedFuncs.sh` | Shared helpers; `launcher()` is **LEGACY** (see [Core API](CORE-API.md)) |

Deep reference: [Core API](CORE-API.md). App updates: `scripts/rezeptor-update.sh` only.

### AppRun / `PATH` exposure

`AppDir/AppRun` prepends `PROJECT_ROOT/core` to `PATH` so legacy helpers resolve by name. **Recipe hooks must not rely on ambient `PATH`:** use `recipe_hooks::load` and `CORE_DIR`/`recipe_hooks::_source` instead. Do not add new recipe dependencies on `PATH`-visible `core/` modules.

## Runtime: Proton-GE only

- **Default pin** in `core/runtime.lock` (`PROTON_GE_TAG`, URL, SHA256) — AppImage/Flatpak bundle this tag
- **Per recipe:** optional `proton_ge_tag:` in `recipe.yml` (e.g. Halo → `GE-Proton11-3`); URL/SHA from lock `PROTON_GE_ALT_*` or `proton_ge_url` / `proton_ge_sha256`
- **Medicine:** recipes may expose a Proton test toggle (Photoshop: `PHOTOSHOP_PROTON_GE_11`, default off = 10-28)
- Recipes set `runtime: proton-ge`
- **No** system Wine fallback in recipe scripts
- Graphics: `wine_runtime::deploy_proton_graphics_dlls()` — **no** winetricks dxvk
- Win10: `recipe_win10::ensure` — **no** winetricks winecfg

Proton install location: `~/.local/share/wine-software/runtime/proton-ge/<tag>/` (shared; survives uninstall; alternate tags on demand).

## `launcher/`

PyQt6 app: catalog, trust, settings, hook processes, activity log.  
`RezeptorWindow` (`launcher.py`) + `RecipeProcessOps` (`recipe_process.py`) for install/repair/…/launch.  
See [GUI launcher](LAUNCHER.md) and [Architecture](ARCHITECTURE-LAUNCHER.md).

## Runtime data locations

| Path | Role |
|------|------|
| `~/.local/share/wine-software/<id>/` | Canonical `data_root` |
| `$DATA_ROOT/prefix` | Always the Wine prefix |
| `$DATA_ROOT/recipe.env` | Persistent state (`env_file_*`, never `source`) |
| `$DATA_ROOT/data_root.path` | GUI override for the chosen data location |

## CI & quality

```bash
make validate    # shellcheck, syntax, compile, i18n-check, ruff, recipes-check, recipe-lint, manifest
make test        # bats
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh
```

`shellcheck` in `make validate` covers `core/`, `recipes/wiso-steuer`, `recipes/photoshop`, `recipes/premiere`, `launcher/`, `scripts/` — not every recipe (e.g. not `photoshop-m0nkrus`, Halo, community). `bash -n` (`syntax`) checks all `recipes/*/*.sh`.

Workflows: `.github/workflows/ci.yml`, `docs.yml`, `release.yml`.

## Next

- [Recipe authoring](RECIPE-AUTHORING.md)
- [Core API](CORE-API.md)
- [Trust & manifest](TRUST.md)
