# Quick start

Rezeptor installs and launches Windows software on Linux with tested **recipes** and **Proton-GE**.

## Requirements

- Linux (x86_64), desktop environment
- **PyQt6** (`python-pyqt6` on Arch/CachyOS, or your distro package)
- Optional: `PyQt6-Fluent-Widgets` for the Fluent UI
- Network on first run (Proton-GE download per `core/runtime.lock`)

## Installation

### From the repository

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

### Release / AppImage

1. Download assets from [GitHub Releases](https://github.com/benjarogit/rezeptor/releases)
2. Verify: `sha256sum -c SHA256SUMS`
3. Make the AppImage executable and run it, or unpack the `tar.gz` and run `./setup.sh`

## First steps in the GUI

1. Pick a recipe in the sidebar
2. Set the **source** (installer, portable folder, EXE — depends on the recipe; BYOS)
3. For portable recipes, set a **target** if needed
4. **Install** — watch progress in the activity log
5. Check status (optional on startup; anytime with **F5**)
6. **Launch**

## Where is the data?

| Path | Contents |
|------|----------|
| `~/.local/share/wine-software/<id>/` | Recipe state, prefix (`prefix/`), `recipe.env` |
| `~/.local/share/wine-software/runtime/proton-ge/` | Shared Proton-GE (survives uninstall) |
| `~/.local/share/wine-software/logs/` | Install/validate logs |
| `~/.local/share/wine-software/rezeptor/settings.json` | Launcher settings |
| Portable / game folders | Often **outside** (e.g. `~/Documents/…`, Steam library) |

## Developer mode

```bash
REZEPTOR_DEV=1 ./setup.sh
```

Enables dev features (recipe editor, manifest sync in a git checkout). Same as the **Developer mode** setting.

## Next

- [User guide](USER-GUIDE.md) — GUI in detail
- [Recipe catalog](CATALOG.md) — official vs community
- [Developer overview](ENTWICKLER.md) — write your own recipe
