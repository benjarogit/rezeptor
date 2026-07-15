# Developer — Rezeptor recipes

Want to ship an app on Linux via Wine/Rezeptor? **One pattern for every recipe** — Photoshop, WISO, and community recipes share the same architecture.

## Quick start (5 minutes)

```bash
cd photoshopCClinux   # or your clone

# 1. Create a recipe (CLI or GUI: Rezeptor → New recipe…)
./scripts/new-recipe.sh my-app "My App"
# or offline installer:
./scripts/new-recipe.sh my-setup "My Setup" --type installer

# 2. Edit
$EDITOR recipes/my-app/recipe.yml   # including install_steps
# Optional: core/recipe-my-app.sh for module: steps

# 3. Lint & test
./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh
# In the GUI: select your recipe → Install

# 4. Before a pull request
./scripts/recipe-manifest.sh
git add recipes/manifest.json recipes/my-app/
```

## How the recipe system works

```
recipe.yml          → contract (metadata + install_steps)
install.sh          → thin: recipe_hooks::load + recipe_install_steps::run
core/recipe-install-steps.sh → executes install_steps
core/recipe-<id>.sh → app logic (module: recipe_foo::bar)
recipes/recipe.schema.json + recipe-lint.sh → rules (CI)
manifest.json       → SHA256 trust in the launcher
```

**Rule of thumb:** `recipe.yml` = contract. Hooks = lifecycle. Core = execution. Lint/schema/CI = rules. Manifest = integrity.

Every hook script **starts the same way**:

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install   # launch | validate | repair | kill
recipe_install_steps::run    # install.sh only
```

Reference:

| Type | Template | Example |
|------|----------|---------|
| Portable | `recipes/_template/` | `wiso-steuer` (full `install_steps` breakdown) |
| Offline installer | `recipes/_template-installer/` | `photoshop` (`module: recipe_photoshop::install`) |
| Steam trainer | (see `za4-trainer`) | EXE + Steam compatdata |
| Steam + BYOS fix | (see `house-of-ashes`) | game folder `link`, fix validate, Proton launch — see [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) |

**Version detection:** every recipe with `version_guaranteed` needs `version_detect` (lint ERROR otherwise). Engine: `launcher/version_detect.py`.

## Checklist

- [ ] `recipe.yml`: required fields + **`install_steps`** + **`version_detect`** (when a guaranteed version is set)
- [ ] All `*.sh` use `core/recipe-hooks.sh`
- [ ] `./scripts/recipe-lint.sh` clean (includes schema check)
- [ ] Tested with `REZEPTOR_DEV=1 ./setup.sh`
- [ ] `recipe-manifest.sh` after file changes
- [ ] No binaries in the repo (BYOS)

## Full specification

→ **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)** (fields, `install_steps`, API, GPU)

## Help

- GUI: **Help → Developer documentation…**
- Translations: [CONTRIBUTING-TRANSLATIONS.md](../CONTRIBUTING-TRANSLATIONS.md)
- Issues: [github.com/benjarogit/rezeptor/issues](https://github.com/benjarogit/rezeptor/issues)
