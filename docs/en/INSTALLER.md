# Reference pattern: Offline installer

**Audience: recipe authors.** Example recipe: `photoshop` · Template: `recipes/_template-installer/`

## When to use this pattern

Windows ships an **offline installer** (folder with `Set-up.exe` / `Setup.exe` + packages, or a single setup `.exe`). Rezeptor creates a prefix, runs the installer under Proton-GE, stores app data under **Target** (data folder).

| GUI | Meaning |
|-----|---------|
| **Source** | Installer folder or `.exe` (BYOS — not in the repo) |
| **Target** | Data folder / Wine prefix (`RECIPE_DATA_ROOT`) |

## Typical `recipe.yml` corners

- `install_type` / `source_kind`: installer or folder with setup
- `install_steps`: often `module: recipe_<id>::install` instead of a long step list
- `version_detect`: e.g. `json_key` / `pe_field` against the offline source
- `uninstall` → `purge_recipe_data` (prefix + shortcuts; do not delete the user’s installer)

## Pitfalls

| Pitfall | Note |
|---------|------|
| GPU/OpenGL in Adobe apps | Recipe sets prefs; maintainer notes only if needed |
| Source ≠ repo path | User brings the offline media; heuristic: `Downloads/` with `Set-up.exe` |
| Empty target | Default from `target_default` / data folder |

Quick start & type overview: [ENTWICKLER.md](ENTWICKLER.md) · Spec: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
