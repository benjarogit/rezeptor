# Contributing translations

Rezeptor welcomes community translations for the **launcher UI** and **developer docs**.

## Launcher UI (`launcher/locales/`)

1. Copy `launcher/locales/en.json` → `launcher/locales/<id>.json` (e.g. `fr.json`).
2. Translate all string values; keep keys identical.
3. Add to `launcher/locales/manifest.json`:
   ```json
   {"id": "fr", "name": "Français"}
   ```
4. Open a pull request.

Fallback: active locale → `en` → key name.

## Developer documentation (`docs/de/`, `docs/en/`)

| Locale | Path |
|--------|------|
| German (default) | `docs/de/*.md` |
| English | `docs/en/*.md` |
| Maintainer notes | `docs/maintainer/de/`, `docs/maintainer/en/` (not in GUI catalog) |

- Keep the **same filenames** in both author folders (`ENTWICKLER.md`, `RECIPE-AUTHORING.md`, …).
- Links between author docs stay **same-folder relative** (`[text](RECIPE-AUTHORING.md)`).
- Maintainer docs live under `docs/maintainer/{locale}/` and are linked from `docs/{locale}/README.md`.
- The GUI viewer picks `docs/{locale}/` from the launcher language setting (author docs only).

### New language for docs (e.g. French)

1. Create `docs/fr/` and copy from `docs/en/`.
2. Translate files.
3. Extend `launcher/ui_docs.py` catalog resolution (or open an issue asking maintainers to wire `fr`).
4. Open a pull request.

## Recipe info texts

Per recipe: `recipes/<id>/info.de.txt`, `info.en.txt`.  
After changes: `./scripts/recipe-manifest.sh`.

## What not to translate

- Shell script messages in `core/` (optional / separate `.lang` files)
- Code identifiers, YAML keys, recipe IDs

## Pull request tips

- One language or one area (UI **or** docs) per PR keeps review easy.
- Do not add Cursor / AI co-author trailers to commits.
