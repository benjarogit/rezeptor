# Quick start

Rezeptor installs and launches Windows software on Linux with tested **recipes** and **Proton-GE**.

## Requirements

- Linux (x86_64), desktop environment
- Network on first run (Proton-GE download per `core/runtime.lock`)

**Depends on how you install:**

| Path | Host PyQt6 needed? |
|------|--------------------|
| Git clone or **`tar.gz`** + `./setup.sh` | **Yes** — distro package `python-pyqt6` (Arch/CachyOS) or equivalent; optional `PyQt6-Fluent-Widgets` |
| **AppImage** (release) | **No** — Python and PyQt6 are bundled (recommended on Bazzite / immutable distros) |
| **Flatpak** (release) | **No** — Python, PyQt6, and Proton-GE are bundled |

## Installation

### From the repository (host PyQt6 required)

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

### AppImage (no host PyQt6)

1. Download `rezeptor-*-x86_64.AppImage` and `SHA256SUMS` from [GitHub Releases](https://github.com/benjarogit/rezeptor/releases)
2. Verify: `sha256sum -c SHA256SUMS`
3. `chmod +x rezeptor-*-x86_64.AppImage && ./rezeptor-*-x86_64.AppImage`

### Flatpak (no host PyQt6)

```bash
flatpak install --user rezeptor-<version>-x86_64.flatpak
flatpak run io.github.benjarogit.Rezeptor
```

Build locally: `scripts/build-flatpak.sh` (needs `flatpak-builder` and runtime `org.freedesktop.Platform//25.08`).

### tar.gz release (host PyQt6 required)

1. Download `rezeptor-*.tar.gz` and verify with `sha256sum -c SHA256SUMS`
2. Unpack and run `./setup.sh`

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

Or enable **Developer mode** in Settings (edit recipe files in the GUI).

## Further reading

- [User guide](USER-GUIDE.md)
- [Trust / integrity](TRUST.md)
- [GUI launcher](LAUNCHER.md)
