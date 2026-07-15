# Rezeptor

Linux-Launcher für Windows-Software über **Proton-GE** — modulare Rezepte (Photoshop, WISO Steuer, Steam-Wrapper, …).

[![Docs](https://img.shields.io/badge/Doku-Rezeptor%20Docs-B87333)](https://benjarogit.github.io/rezeptor/)
[![Lizenz](https://img.shields.io/badge/Lizenz-GPL--2.0-blue)](LICENSE)

## Dokumentation (Wiki)

**Die ausführliche Anleitung steht im Wiki:**

### → [Rezeptor Docs](https://benjarogit.github.io/rezeptor/)

- [Deutsch](https://benjarogit.github.io/rezeptor/de/README/) · [English](https://benjarogit.github.io/rezeptor/en/README/)
- Lokal: `docs/` · bauen mit `pip install -r requirements-docs.txt && mkdocs serve`

## Schnellstart

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

Benötigt PyQt6 (`python-pyqt6` / Distro-Äquivalent). Daten: `~/.local/share/wine-software/`.

Oder ein **[Release-AppImage](https://github.com/benjarogit/rezeptor/releases)**, sobald veröffentlicht.

## Rezepte

Mitgeliefert unter `recipes/<id>/`. Community: `recipes/community/<id>/` (Einreichung über [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md)).

## English

→ [README.md](README.md) · [Documentation](https://benjarogit.github.io/rezeptor/en/README/)

## Lizenz

GPL-2.0 — siehe [LICENSE](LICENSE).
