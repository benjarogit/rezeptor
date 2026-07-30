# Developer — Rezeptor recipes

**One pattern for every recipe.** Portable, offline installer, Steam games (with online fix), trainers — same architecture.

| Document | Role |
|----------|------|
| **This page** | Quick start, layout, recipe types |
| [PROJECT-LAYOUT.md](PROJECT-LAYOUT.md) | Repo, `recipes/`, and `core/` layout |
| [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) | Deep reference: fields, `install_steps`, `version_detect` |
| [CORE-API.md](CORE-API.md) | Precise `core/` APIs (hooks, prefix, winetricks, …) |
| [VALIDATE-REPAIR.md](VALIDATE-REPAIR.md) · [UNINSTALL.md](UNINSTALL.md) | Lifecycle contracts |
| [UPDATES.md](UPDATES.md) | Post-install updates (numbered patches, GUI action) |
| [TRUST.md](TRUST.md) · [LOG-PROTOCOL.md](LOG-PROTOCOL.md) · [LAUNCHER.md](LAUNCHER.md) | Manifest, logs, GUI |
| **Pattern references** | [INSTALLER.md](INSTALLER.md) · [WISO.md](WISO.md) · [STEAM-WRAPPER.md](STEAM-WRAPPER.md) · [TRAINER.md](TRAINER.md) · [UPDATES.md](UPDATES.md) |

---

## Quick start

```bash
cd rezeptor   # clone https://github.com/benjarogit/rezeptor

./scripts/new-recipe.sh my-app "My App"                          # portable
./scripts/new-recipe.sh my-setup "My Setup" --type installer     # offline installer
./scripts/new-recipe.sh my-game "My Game" --type steam-game      # Steam + online fix
./scripts/new-recipe.sh --community my-app "My App"              # → recipes/community/<id>/

$EDITOR recipes/my-app/recipe.yml   # including install_steps
# Optional: core/recipe-my-app.sh for module: steps

./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh             # GUI: recipe → source → Install

./scripts/recipe-manifest.sh          # before PR (top-level recipes/<id>/ only)
git add recipes/manifest.json recipes/my-app/
```

GUI alternative: **Rezeptor → New recipe…** (dev mode)

---

## Get involved

Rezeptor is not a one-app Photoshop script — **every new recipe** and **every improvement to the recipe system** helps everyone.

1. **Add a recipe** — got an app running? `./scripts/new-recipe.sh` or `recipes/community/<id>/`, then open a PR or a [recipe submission issue](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md).
2. **Harden the core** — shared logic belongs in `core/recipe-*.sh` (prefix, winetricks, validate, online fix, …), not copied into every recipe. See [CORE-API.md](CORE-API.md).
3. **Launcher / GUI** — source dialog, validation, log humanization: `launcher/` + [LAUNCHER.md](LAUNCHER.md).
4. **Discuss** — architecture or edge cases: [GitHub Discussions](https://github.com/benjarogit/rezeptor/discussions).

**Rule of thumb:** a good recipe exposes gaps in the core — fixing both in one PR is ideal.

---

## Architecture (short)

```
recipe.yml          → contract (metadata + install_steps)
install.sh …        → thin hooks → core/recipe-hooks.sh
core/recipe-install-steps.sh → runs install_steps
core/recipe-<id>.sh → app logic (module:)
manifest.json       → SHA256 trust in the launcher
```

**Rule of thumb:** `recipe.yml` = contract. Hooks = lifecycle. Core = execution. Lint/CI = rules. Manifest = integrity.

Every hook script starts the same way:

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install   # launch | validate | repair | kill | minimal
recipe_install_steps::run    # install.sh only
```

User data lives under `~/.local/share/wine-software/<id>/` (prefix, `recipe.env`, …) — separate from **source** (files you bring) and often from **target** (portable/game folder).

---

## Recipe types (source / target)

In the GUI always **Source** and optionally **Target** — same labels for every app type.

| Type | Shipped | Source | Target | Reference |
|------|---------|--------|--------|-----------|
| **Offline installer** | `photoshop`, `photoshop-m0nkrus-220`, `photoshop-m0nkrus`, `premiere` | Pack folder / setup / `.iso` | Data folder (prefix) | [INSTALLER.md](INSTALLER.md) |
| **Portable** (folder/archive) | `wiso-steuer` | Folder or zip/7z/… | Install folder | [WISO.md](WISO.md) |
| **Steam + online fix** | `house-of-ashes` | Fix BYOS; game in Steam | Game folder (`link`) | [STEAM-WRAPPER.md](STEAM-WRAPPER.md) |
| **Offline game + updates** | `halo-campaign-evolved` | ISO / pack folder | Prefix | [UPDATES.md](UPDATES.md) |
| **Single EXE / trainer** | `za4-trainer` | one `.exe` | often Steam subfolder | [TRAINER.md](TRAINER.md) |

Templates: `recipes/_template/` (portable), `recipes/_template-installer/`, `recipes/_template-steam-game/`.  
Community: `recipes/community/<id>/` (hooks load core via `../../../core/`; not in the official manifest).

---

## Checklist

- [ ] `recipe.yml`: required fields + **`install_steps`** + **`uninstall`**; with `version_guaranteed` also **`version_detect`**
- [ ] All `*.sh` use `core/recipe-hooks.sh`; `uninstall.sh` → `purge_recipe_data`
- [ ] `./scripts/recipe-lint.sh` clean
- [ ] Tested with `REZEPTOR_DEV=1 ./setup.sh` (save source → Install)
- [ ] `recipe-manifest.sh` after file changes
- [ ] No app binaries in the repo (BYOS)

---

## Next

Full specification → **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)**

In-app help: **Help → Developer documentation…** · Translations: [CONTRIBUTING-TRANSLATIONS.md](CONTRIBUTING-TRANSLATIONS.md)
