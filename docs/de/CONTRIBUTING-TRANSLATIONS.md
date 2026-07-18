# Übersetzungen beitragen

Rezeptor freut sich über Community-Übersetzungen für die **Launcher-UI** und die **Entwickler-Doku**.

## Launcher-UI (`launcher/locales/`)

1. `launcher/locales/en.json` → `launcher/locales/<id>.json` kopieren (z. B. `fr.json`).
2. Alle String-Werte übersetzen; Schlüssel unverändert lassen.
3. In `launcher/locales/manifest.json` eintragen:
   ```json
   {"id": "fr", "name": "Français"}
   ```
4. Pull Request öffnen.

Fallback: aktive Locale → `en` → Schlüsselname.

## Entwickler-Dokumentation (`docs/de/`, `docs/en/`)

| Locale | Pfad |
|--------|------|
| Deutsch (Standard) | `docs/de/*.md` |
| Englisch | `docs/en/*.md` |

- **Gleiche Dateinamen** in beiden Locale-Ordnern (`ENTWICKLER.md`, `RECIPE-AUTHORING.md`, …).
- Links zwischen Docs **relativ im gleichen Ordner** (`[text](RECIPE-AUTHORING.md)`).
- Die GUI wählt `docs/{locale}/` anhand der Launcher-Sprache.

### Neue Sprache für Docs (z. B. Französisch)

1. `docs/fr/` anlegen und von `docs/en/` kopieren.
2. Dateien übersetzen.
3. Katalog-Auflösung in `launcher/ui_docs.py` erweitern (oder Issue öffnen).
4. Pull Request öffnen.

## Rezept-Infotexte

Pro Rezept: `recipes/<id>/info.de.txt`, `info.en.txt`.  
Nach Änderungen: `./scripts/recipe-manifest.sh`.

## Was nicht übersetzt wird

- Shell-Meldungen in `core/` (optional / eigene `.lang`-Dateien)
- Code-Identifier, YAML-Schlüssel, Rezept-IDs

## Tipps für Pull Requests

- Eine Sprache oder ein Bereich (UI **oder** Docs) pro PR erleichtert Review.
- Keine Co-Author-Trailer von Editor-Agenten in Commits.
