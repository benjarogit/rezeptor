# Reference recipe: WISO Steuer (portable)

**Audience: recipe authors.** End-user help lives in the GUI recipe info (`info.de.txt` / `info.en.txt`), not here.

Recipe ID: `wiso-steuer` · Runtime: **Proton-GE** · Launch: **`start.exe`** (not `wiso2026.exe` directly)

## Why this is the reference

Full declarative `install_steps` in `recipe.yml` plus app module `core/recipe-wiso-steuer.sh`. Pattern for:

- Portable source → target (`prepare_source` / deploy)
- Prefix, winetricks, vcrun, Wine-Mono
- App-specific modules (`recipe_wiso::…`)
- Desktop entry, validate/repair/kill

Template: `recipes/_template/` · Spec: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)

## Architecture (short)

```
recipe.yml          → install_steps (contract)
install.sh          → recipe_hooks::load install + recipe_install_steps::run
core/recipe-wiso-steuer.sh → module: steps (portable, Qt fix, desktop, …)
validate.sh / repair.sh / kill.sh / uninstall.sh → lifecycle
```

Guaranteed version: `version_guaranteed` in `recipe.yml` (currently 33.05.3220).

## Design choices

| Topic | Choice |
|-------|--------|
| Launch | `start.exe` in portable root |
| Graphics | **wined3d**, not DXVK (Qt/WebEngine) |
| Fonts | corefonts + Tahoma/Calibri, Segoe → Calibri/Tahoma |
| Qt networking | rename `qnetworklistmanager.dll` (avoids Wine start crash) |
| Data | Prefix under `~/.local/share/wine-software/wiso-steuer/` — portable folder stays user-owned |

## Author smoke

```bash
REZEPTOR_DEV=1 ./setup.sh
# source = portable folder, target e.g. ~/Documents/WISO Steuer 2026
bash recipes/wiso-steuer/validate.sh
bash recipes/wiso-steuer/launch.sh
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh
```

## Known Wine/Qt pitfalls (recipe logic)

| Symptom | Recipe side |
|---------|-------------|
| Mono/wineboot dialogs | `recipe_hooks::hint_wine_popup` |
| Crash after seconds | Qt network plugin + validate/repair |
| Header overlap when maximized | no Wine decorations, windowed ~1600×900 |
| Virtual-desktop leftovers | `kill.sh` cleans `explorer.exe /desktop=wiso` |

Logs: `~/.local/share/wine-software/logs/wiso-steuer_*`

See also: [ENTWICKLER.md](ENTWICKLER.md) · [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) · [RECIPES.md](RECIPES.md)
