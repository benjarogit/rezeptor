# Rezeptor

**Recipe-driven launcher for Windows software on Linux** — Wine and Proton GE, one GUI, separate prefixes per app.

![License](https://img.shields.io/badge/license-GPL--2.0-blue) ![Platform](https://img.shields.io/badge/platform-Linux-green)

> [!NOTE]
> **Development repository (private backup):** [github.com/benjarogit/rezeptor](https://github.com/benjarogit/rezeptor)  
> **Public Photoshop lineage:** [github.com/benjarogit/photoshopCClinux](https://github.com/benjarogit/photoshopCClinux)

---

## What is Rezeptor?

Rezeptor is a **PyQt6 launcher** that installs and runs Windows applications through **recipes** — small packages under `recipes/<id>/` with `recipe.yml`, install/launch/repair scripts, and shared logic in `core/`.

| You provide | Rezeptor provides |
|-------------|-------------------|
| Licensed installer files (Adobe, Buhl, …) | Wine prefix, runtime, winetricks, desktop entry, logs |
| Portable folder path (WISO) | Launcher script, Qt fixes, validation |

**No piracy.** This repo never ships Adobe, Buhl, or other proprietary binaries.

---

## Quick start

### Requirements

```bash
# Arch / CachyOS
sudo pacman -S wine winetricks python-pyqt6

# Ubuntu / Debian
sudo apt install wine winetricks python3-pyqt6
```

### Run

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
chmod +x setup.sh
./setup.sh
```

Optional desktop entry:

```bash
./scripts/install-rezeptor-desktop.sh
```

Then open **Rezeptor** from the application menu, pick a recipe, and use **Install → Validate → Launch**.

---

## Recipes

| Recipe | Software | Runtime | Data directory |
|--------|----------|---------|----------------|
| [`photoshop`](recipes/photoshop/) | Adobe Photoshop CC 2021 (v22.x) | **Proton GE** | `~/.local/share/wine-software/photoshop/` |
| [`wiso-steuer`](recipes/wiso-steuer/) | WISO Steuer (Portable) | **System Wine** | `~/.local/share/wine-software/wiso-steuer/` |

Each recipe declares `runtime:` in `recipe.yml`. Rezeptor picks **Proton GE** or **distro Wine** automatically — both can coexist; prefixes stay separate.

### Photoshop

1. Place `Set-up.exe`, `packages/`, `products/` in [`photoshop/`](photoshop/) — see [photoshop/README.md](photoshop/README.md).
2. Rezeptor → **Photoshop** → Install (disable network when prompted during Adobe setup).
3. After install: **Edit → Preferences → Performance** → disable GPU in Photoshop.

### WISO Steuer (Portable)

1. Rezeptor → **WISO Steuer** → Install → select your portable root (folder containing `Steuersoftware 20XX/`).
2. On KDE/Wayland: repair sets Wine graphics to **X11** automatically.
3. If a **Wine-Mono** dialog appears for `~/.wine`: click **Cancel** — use Rezeptor → **Repair** (installs Mono silently in the WISO prefix).

---

## Directory layout

```
~/.local/share/wine-software/
├── runtime/proton-ge/GE-Proton10-28/   # downloaded on first Photoshop use
├── cache/winetricks/
├── logs/                             # install, repair, launch logs
├── photoshop/{prefix,resources}
└── wiso-steuer/{prefix,portable.env,bin/}
```

Project tree:

```
rezeptor/
├── core/           # shared bash: wine-runtime, recipes, security, i18n
├── launcher/       # PyQt6 GUI (Rezeptor)
├── recipes/        # one folder per application
├── docs/           # authoring & testing
├── setup.sh        # entry point → launcher
└── scripts/        # manifest, lint, AppImage, desktop file
```

---

## Documentation

| Topic | File |
|-------|------|
| Recipe overview | [docs/RECIPES.md](docs/RECIPES.md) |
| Write a new recipe | [docs/RECIPE-AUTHORING.md](docs/RECIPE-AUTHORING.md) |
| Testing | [docs/TESTING.md](docs/TESTING.md) |
| Brand / naming | [docs/BRAND.md](docs/BRAND.md) |
| Photoshop files | [photoshop/README.md](photoshop/README.md) |

---

## Development

```bash
# lint + syntax + recipe manifest check
make validate

# regenerate trust manifest after recipe edits
./scripts/recipe-manifest.sh

# dev mode (skip manifest trust check)
REZEPTOR_DEV=1 ./setup.sh
```

Runtime pin: [`core/runtime.lock`](core/runtime.lock) (Proton GE tag + optional SHA256).

Logs: `~/.local/share/wine-software/logs/`

---

## Runtime: Wine vs Proton GE

| | System Wine | Proton GE |
|---|-------------|-----------|
| Binary | `/usr/bin/wine` | `~/.local/share/wine-software/runtime/proton-ge/…` |
| Best for | Qt/office (WISO) | Games, DXVK, Adobe IE installer |
| Per recipe | `runtime: system` | `runtime: proton-ge` |

Proton GE is **not** “better Wine for everything” — it is Wine plus gaming-oriented patches and graphics stacks.

---

## Languages

- 🇬🇧 **English** — this file
- 🇩🇪 **[Deutsche Dokumentation](README.de.md)**

---

## Support & contributing

- **Issues (public Photoshop repo):** [github.com/benjarogit/photoshopCClinux/issues](https://github.com/benjarogit/photoshopCClinux/issues)
- **Automatic checks:** `./troubleshoot.sh` or Rezeptor → Validate / Repair

---

## License

**GPL-2.0** — see [LICENSE](LICENSE).

Based on [photoshopCClinux](https://github.com/Gictorbit/photoshopCClinux) by Gictorbit.  
Copyright © 2024–2026 Sunny C.

Adobe Photoshop and WISO Steuer are proprietary; you must own valid licenses.
