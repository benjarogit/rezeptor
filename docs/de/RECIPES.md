# Recipes (Rezeptor)

Jede App ist ein Rezept — **ein Muster für alle** (Portable, Installer, Adobe, WISO). Siehe **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)**.

## Community: neues Rezept

```bash
./scripts/new-recipe.sh meine-app "Meine App"
./scripts/new-recipe.sh mein-tool "Mein Tool" --type installer
./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh
```

## Struktur

| Datei | Zweck |
|-------|--------|
| `recipe.yml` | Metadaten, Runtime, Quell-Typ, **`install_steps`** |
| Hooks (`*.sh`) | dünn → `core/recipe-hooks.sh` |
| `core/recipe-<id>.sh` | App-Logik (optional, auto-geladen) |

Vorlagen: `_template` (Portable), `_template-installer` (Offline-Installer).

Referenz-Rezepte: `wiso-steuer` (deklarative `install_steps`), `photoshop` (`module:`-Feld).

## User-Daten

```
~/.local/share/wine-software/<id>/{prefix,recipe.env,…}
```

## Rezeptor starten

```bash
./setup.sh
```

Doku: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) · Englisch: [docs/en/RECIPES.md](../en/RECIPES.md)
