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
├── launcher/             # PyQt6 GUI
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
| `recipe-prefix.sh` | Create/update prefix |
| `recipe-winetricks.sh` | Winetricks under Proton; retry only exit 139 |
| `recipe-win10.sh` | Windows 10 version (registry, no winecfg) |
| `recipe-validate.sh` | Reusable checks |
| `wine-runtime.sh` | Proton-GE, graphics DLLs |
| `recipe-desktop.sh` | `.desktop` + icons |
| `paths.sh` / `env-file.sh` / `output.sh` | Paths, state, GUI tags |

Deep reference: [Core API](CORE-API.md).

## Runtime: Proton-GE only

- Pin in `core/runtime.lock` (`PROTON_GE_TAG`, URL, SHA256)
- Recipes set `runtime: proton-ge`
- **No** system Wine fallback in recipe scripts
- Graphics: `wine_runtime::deploy_proton_graphics_dlls()` — **no** winetricks dxvk
- Win10: `recipe_win10::ensure` — **no** winetricks winecfg

Proton install location: `~/.local/share/wine-software/runtime/proton-ge/<tag>/` (shared; survives uninstall).

## `launcher/`

PyQt6 app: catalog, trust, settings, hook processes, activity log. See [GUI launcher](LAUNCHER.md).

## Runtime data locations

| Path | Role |
|------|------|
| `~/.local/share/wine-software/<id>/` | Canonical `data_root` |
| `$DATA_ROOT/prefix` | Always the Wine prefix |
| `$DATA_ROOT/recipe.env` | Persistent state (`env_file_*`, never `source`) |
| `$DATA_ROOT/data_root.path` | GUI override for the chosen data location |

## CI & quality

```bash
make validate    # shellcheck, bash -n, compileall, recipes-check, recipe-lint, manifest-check
make test        # bats
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh
```

`shellcheck` in `make validate` covers only `core/`, `photoshop`, `wiso-steuer`, `launcher/`, `scripts/` — not every recipe. `bash -n` checks all `recipes/*/*.sh`.

Workflows: `.github/workflows/ci.yml`, `docs.yml`, `release.yml`.

## Next

- [Recipe authoring](RECIPE-AUTHORING.md)
- [Core API](CORE-API.md)
- [Trust & manifest](TRUST.md)
