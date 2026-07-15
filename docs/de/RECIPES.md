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

Referenz-Rezepte:

| ID | Muster |
|----|--------|
| `wiso-steuer` | Portable, deklarative `install_steps` |
| `photoshop` | Offline-Installer (`module:`) |
| `za4-trainer` | Steam-Trainer (EXE → Spielordner, Proton) |
| `house-of-ashes` | Steam-Spiel + BYOS-Fix (`deploy_mode: link`, Launch aus Rezeptor) |

## User-Daten

```
~/.local/share/wine-software/<id>/{prefix,recipe.env,…}
```

## Rezeptor starten

```bash
./setup.sh
```

Doku: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) · Englisch: [docs/en/RECIPES.md](../en/RECIPES.md)
