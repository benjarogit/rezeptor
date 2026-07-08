# Recipes

Each app is a **recipe** under `recipes/<id>/`. See **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)** for the full schema, manifest workflow, and Dev-Modus.

| File | Purpose |
|------|---------|
| `recipe.yml` | Metadata, data root, runtime, script names |
| `install.sh` | One-time setup (prefix, winetricks, BYOS flow) |
| `launch.sh` | Start the application |
| `validate.sh` | Check installation |

Shared logic lives in `core/` (Proton-GE runtime, paths, i18n, security).

Official recipes are listed in [`recipes/manifest.json`](../recipes/manifest.json) (SHA256). Regenerate after changes:

```bash
./scripts/recipe-manifest.sh
```

## User data layout

```
~/.local/share/wine-software/
├── runtime/proton-ge/GE-Proton10-28/
├── cache/winetricks/
├── logs/
├── photoshop/{prefix,resources}
└── wiso-steuer/{prefix,portable.env}
```

## Bring your own software (BYOS)

The repository **never** ships Adobe or Buhl binaries.

| Recipe | You provide | We provide |
|--------|-------------|------------|
| `photoshop` | `Set-up.exe`, `packages/`, `products/` in `photoshop/` | Prefix + Proton-GE, Adobe installer flow |
| `wiso-steuer` | Licensed WISO Steuer Portable folder | Prefix + system Wine, launcher script in portable tree |

## Adding a recipe

1. Copy `recipes/_template/` to `recipes/myapp/`.
2. Edit `recipe.yml` (flat keys — see RECIPE-AUTHORING.md).
3. Implement hooks; use `core/wine-runtime.sh` — set `runtime: proton-ge` or `runtime: system` in `recipe.yml`.
4. Run `./scripts/recipe-lint.sh` and `./scripts/recipe-manifest.sh`.
5. Test with `REZEPTOR_DEV=1 ./setup.sh` before merging.

The PyQt launcher discovers `recipes/*/recipe.yml` and verifies the manifest (unless Dev-Modus).

## Rezeptor starten (GUI)

Einmalig Desktop-Eintrag installieren:

```bash
cd ~/Dokumente/photoshopCClinux
./scripts/install-rezeptor-desktop.sh
```

Danach: **KDE-Anwendungsmenü → Rezeptor** (kein Terminal nötig). `./setup.sh` ist derselbe Start — nur über Menü bequemer.

## Runtime

Pinned in `core/runtime.lock`. Updated only after QA with target software.
