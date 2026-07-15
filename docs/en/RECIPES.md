# Recipes (Rezeptor)

Every app is a recipe — **one pattern for all** (portable, installer, Adobe, WISO). See **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)**.

## Community: new recipe

```bash
./scripts/new-recipe.sh my-app "My App"
./scripts/new-recipe.sh my-tool "My Tool" --type installer
./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh
```

## Structure

| File | Purpose |
|------|---------|
| `recipe.yml` | Metadata, runtime, source type, **`install_steps`** |
| Hooks (`*.sh`) | thin wrappers → `core/recipe-hooks.sh` |
| `core/recipe-<id>.sh` | App logic (optional, auto-loaded) |

Templates: `_template` (portable), `_template-installer` (offline installer).

Reference recipes:

| ID | Pattern |
|----|---------|
| `wiso-steuer` | Portable, declarative `install_steps` |
| `photoshop` | Offline installer (`module:`) |
| `za4-trainer` | Steam trainer (EXE → game folder, Proton) |
| `house-of-ashes` | Steam game + BYOS fix (`deploy_mode: link`, launch from Rezeptor) |

## User data

```
~/.local/share/wine-software/<id>/{prefix,recipe.env,…}
```

## Start Rezeptor

```bash
./setup.sh
```

Docs: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
