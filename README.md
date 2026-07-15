# Rezeptor

Linux launcher for Windows software via **Proton-GE** — modular recipes (Photoshop, WISO Steuer, Steam wrappers, …).

[![Docs](https://img.shields.io/badge/docs-Rezeptor%20Docs-B87333)](https://benjarogit.github.io/rezeptor/)
[![License](https://img.shields.io/badge/license-GPL--2.0-blue)](LICENSE)

## Documentation (Wiki)

**Full guides live in the wiki — start here:**

### → [Rezeptor Docs](https://benjarogit.github.io/rezeptor/)

- [English](https://benjarogit.github.io/rezeptor/en/README/) · [Deutsch](https://benjarogit.github.io/rezeptor/de/README/)
- Local clone: `docs/` · build with `pip install -r requirements-docs.txt && mkdocs serve`

## Quick start

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

Requires PyQt6 (`python-pyqt6` / distro equivalent). Data: `~/.local/share/wine-software/`.

Or use a **[release AppImage](https://github.com/benjarogit/rezeptor/releases)** when published.

## Recipes

Bundled under `recipes/<id>/`. Community recipes: `recipes/community/<id>/` (submit via [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md)).

## Deutsch

→ [README.de.md](README.de.md) · [Dokumentation](https://benjarogit.github.io/rezeptor/de/README/)

## License

GPL-2.0 — see [LICENSE](LICENSE).
