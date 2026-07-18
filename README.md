<p align="center">
  <img src="images/rezeptor-icon.png" alt="Rezeptor" width="128" height="128">
</p>

# Rezeptor

**Install and run Windows software on Linux** with tested recipes — powered by **Proton-GE**, managed in a simple desktop app.

Photoshop, tax software (WISO), Steam games with online fixes, trainers, and more: each recipe knows how to install, repair, validate, launch, and uninstall cleanly.

[![Docs](https://img.shields.io/badge/docs-Rezeptor%20Docs-B87333)](https://benjarogit.github.io/rezeptor/)
[![License](https://img.shields.io/badge/license-GPL--2.0-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/benjarogit/rezeptor?include_prereleases&label=release)](https://github.com/benjarogit/rezeptor/releases)

## What you get

- **GUI launcher** — pick a recipe, install, start, repair, or remove
- **Proton-GE only** — no system Wine fallback in recipes
- **Status checks** — optional validate on startup; refresh anytime (F5)
- **Host tools check** — missing packages (e.g. `cabextract`, `7z`) suggested once
- **Catalog & sources** — official recipes plus community path
- **Data under** `~/.local/share/wine-software/`

## Quick start

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

Needs **PyQt6** (`python-pyqt6` on Arch/CachyOS, or your distro’s package).

Or download a **[release AppImage](https://github.com/benjarogit/rezeptor/releases)** when available.

## Documentation

Full guides (install patterns, recipe authoring, brand):

### → [Rezeptor Docs](https://benjarogit.github.io/rezeptor/)

- [English](https://benjarogit.github.io/rezeptor/en/README/) · [Deutsch](https://benjarogit.github.io/rezeptor/de/README/)
- Local: `docs/` — `pip install -r requirements-docs.txt && mkdocs serve`

## Recipes

| Location | Role |
|----------|------|
| `recipes/<id>/` | Bundled / official |
| `recipes/community/<id>/` | Community |

Submit ideas via [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md).

## Deutsch

→ [README.de.md](README.de.md) · [Dokumentation](https://benjarogit.github.io/rezeptor/de/README/)

## License

GPL-2.0 — see [LICENSE](LICENSE).
