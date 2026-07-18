# Uninstall

Hard contract: after uninstall the GUI shows **Not installed**, and **no** Rezeptor leftovers remain under `~/.local/share/wine-software/<id>/`.

## Required in every recipe

1. `uninstall:` in `recipe.yml` points to `uninstall.sh`
2. Script uses `recipe_hooks::load minimal`
3. Script calls **`recipe_hooks::purge_recipe_data`**
4. No `recipe_hooks::load kill` (Proton hang)

Templates and CI (`recipes-check`, `tests/uninstall-purge.bats`) enforce this.

## What `purge_recipe_data` removes

Order:

1. `recipe_desktop::remove` (menu + desktop shortcuts, icons) — best effort
2. Chosen `DATA_ROOT` (GUI target / `data_root.path`)
3. Canonical `data_root` from YAML if different and still present

Typically includes: `prefix/`, `recipe.env`, markers, staging, wrappers under the recipe data path.

Safety: deleting `/`, `$HOME`, `/usr`, `/etc`, etc. is blocked.

## What intentionally remains

| Remains | Why |
|---------|-----|
| Portable folders outside `DATA_ROOT` | User property (e.g. WISO under `~/Documents/…`) |
| Steam game folders / online fix | BYOS; wrapper only removes Rezeptor state |
| Shared Proton-GE under `runtime/proton-ge/` | Used by other recipes |
| Launcher settings | Global under `…/rezeptor/settings.json` |

## Minimal `uninstall.sh` example

```bash
#!/usr/bin/env bash
set -euo pipefail
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal
# optional: pkill app processes
recipe_hooks::purge_recipe_data
```

## Forbidden

- Deleting only `prefix/` or only `recipe.env`
- “Soft uninstall” that leaves the GUI showing installed
- Reinventing uninstall logic in recipes instead of `purge_recipe_data`

## Manual check

1. Install → Uninstall
2. GUI shows “Not installed”
3. `ls ~/.local/share/wine-software/<id>/` → empty/missing
4. Portable/Steam outside still present (if used that way before)

## Next

- [Core API](CORE-API.md) — `purge_recipe_data`
- [User guide](USER-GUIDE.md) — hide vs uninstall
