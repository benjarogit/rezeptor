# Reference pattern: Offline installer

**Audience: recipe authors.** Example recipes: `photoshop`, `photoshop-m0nkrus`, `premiere`, `master-pdf-editor` · Template: `recipes/_template-installer/`

## When to use this pattern

Windows ships an **offline installer** (folder with `Set-up.exe` / `Setup.exe` + packages, or a single setup `.exe`). Rezeptor creates a prefix, runs the installer under Proton-GE, stores app data under **Target** (data folder).

| GUI | Meaning |
|-----|---------|
| **Source** | Installer folder or `.exe` (BYOS — not in the repo) |
| **Target** | Free install location (`RECIPE_DATA_ROOT`) — the app/game (including prefix under `{target}/prefix/…`) lives here. No forced path; only a previously chosen location is restored. |

## Typical `recipe.yml` corners

- `install_type` / `source_kind`: installer or folder with setup
- `install_steps`: often `module: recipe_<id>::install` instead of a long step list
- `version_detect`: e.g. `json_key` / `pe_field` against the offline source
- `source_hints`: pack title / keywords to search (**no URLs**); different packs → separate recipe
- `uninstall` → `purge_recipe_data` (prefix + shortcuts; do not delete the user’s installer)

### Pack folder (m0nkrus-style)

Two Photoshop recipes (one pack = one recipe):

| ID | Pack | Guaranteed |
|----|------|------------|
| `photoshop` | Standard offline (Set-up + packages) | 22.0.0.35 |
| `photoshop-m0nkrus` | Pack 22.1.1.138 + Neural / missing_libs / GenP | 22.1.1.138 |

For `photoshop-m0nkrus`: source = **full pack folder** (ISO + sibling extras). Rezeptor:

1. picks the matching `.iso` as offline installer
2. sets `RECIPE_PACK_ROOT` and after Adobe setup applies extras (`core/recipe-photoshop-pack.sh`): `ps2021_missing_libs.7z`, Neural Filters SFX → Wine `PluginData`
3. does **not** auto-run GenP (ISO pre-patched per pack; manual cure only if activation drops)

Variants share the Photoshop core API via thin wrappers:

- `core/recipe-photoshop-m0nkrus-install.sh` / `-launch.sh`

(`module: recipe_photoshop::install` in `recipe.yml`; without the wrappers `load_app_module` will not find the functions.)

### MSI (Master PDF Editor)

`master-pdf-editor`: BYOS pack folder with `MasterPDFEditor-setup-*.msi` (+ optional `fix/MasterPDFEditor.exe`). Core: `recipe_master_pdf_editor::run_msi` (timeout; success when EXE exists) + `::finalize` (WORK_ROOT / fix). Rezeptor ships neither MSI nor fix.

## Pitfalls

| Pitfall | Note |
|---------|------|
| GPU/OpenGL in Adobe apps | Recipe sets prefs via Proton graphics DLLs |
| Source ≠ repo path | User brings the offline media; heuristic: pack folder / `Downloads/` |
| ISO-only instead of pack | Install ok, Neural Filters / missing_libs missing |
| Empty target | Required choice — no silent default from `target_default` / home |
| Move target | More → **Move target…** (`scripts/recipe-relocate.sh`) |

Quick start & type overview: [ENTWICKLER.md](ENTWICKLER.md) · Spec: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
