# Recipe catalog

Rezeptor lists applications as **recipes**. The catalog distinguishes origin and trust —
not every source is equivalent.

## Official recipes (bundled)

Shipped under `recipes/<id>/`, indexed in `recipes/catalog.json` (`trust: official`).
Guarded by CI (`recipe-lint`, manifest checks).

Currently **6** official product recipes in **5** categories.

### Graphics & Design

| ID | Name | Description |
|----|------|-------------|
| `photoshop` | Adobe Photoshop CC 2021 | Standard offline installer (22.0.0.35) on Proton-GE |
| `photoshop-m0nkrus` | Adobe Photoshop CC 2021 (m0nkrus 22.1.1.138) | Full pack incl. Neural Filters / missing_libs / GenP (optional) |

### Video

| ID | Name | Description |
|----|------|-------------|
| `premiere` | Adobe Premiere Pro 2024 | Proton-GE. NVIDIA: CUDA via nvidia-libs. AMD/Intel: often software renderer only |

### Finance

| ID | Name | Description |
|----|------|-------------|
| `wiso-steuer` | WISO Steuer (Portable) | Portable on Proton-GE — pick source, copy to target folder, launch |

### Documents & PDF

| ID | Name | Description |
|----|------|-------------|
| `master-pdf-editor` | Master PDF Editor | MSI 5.9 on Proton-GE — BYOS pack with setup, optional `fix/` |

### Games

| ID | Name | Description |
|----|------|-------------|
| `halo-campaign-evolved` | Halo Campaign Evolved | ElAmigos/RUNE, graphics presets (default Recommended RTX 2060), optional Steam Non-Steam, BYOS trainer |

Templates under `recipes/_template*` and entries under `recipes/community/` are **not** bundled product recipes.

## Community recipes

Custom or shared recipes live under `recipes/community/<id>/`.

Create one with:

```bash
./scripts/new-recipe.sh --community my-app "My App"
```

Community entries are **not** automatically vetted as official — author and content are your responsibility.

## Recipe sync (official updates without app reinstall)

Packaged builds ship a read-only `recipes/` tree. Rezeptor can still pull **newer official recipes** from the GitHub Release asset `rezeptor-recipes-<version>.tar.gz` (listed in `SHA256SUMS`).

| Piece | Location |
|-------|----------|
| Overlay | `~/.local/share/rezeptor/recipes/` (wins over bundled same `id`) |
| Overlay manifest | `~/.local/share/rezeptor/manifest.overlay.json` |
| State | `~/.local/share/rezeptor/sync-state.json` |

In the GUI: **Help → Update recipes…** (also checked quietly after startup). Changes need confirmation before apply.

Catalog fields for sync:

| Field | Meaning |
|-------|---------|
| `min_app_version` | Recipe needs this Rezeptor version (core APIs). Older apps see **blocked** — update the app. |
| `deprecated` | Recipe should not be newly installed; installed data is not auto-deleted. |

## Recipe options (Medizin)

Lasting per-recipe settings (not “install once”). The **Medizin** button (icon `kit-medical`) **next to** **More** (its own button) opens a dialog with toggles, **choice combos**, and explanations. Values in `{data_root}/options.env` steer install/repair/launch.

After toggling, the primary CTA may become **Repair now** — run it once so prefs/prefix catch up.

Only use when the option changes behaviour (e.g. opt-out). Not for actions Install/Repair already perform.

Photoshop: three UI toggles (`PHOTOSHOP_UI_HOME_SCREEN`, `PHOTOSHOP_UI_RICH_TOOLTIPS`, `PHOTOSHOP_UI_MODERN_NEW`), default `false` — see [User guide](USER-GUIDE.md#medizin-recipe-options).

Halo: quality preset (`HALO_GFX_PRESET`, default `balanced` / Recommended RTX 2060), graphics toggles, optional **Launch via Steam** + Proton choice — see [User guide](USER-GUIDE.md#medizin-recipe-options).

```yaml
options:
  - id: gfx_preset
    env: HALO_GFX_PRESET
    type: choice
    default: balanced
    choices:
      - id: balanced
        label: { de: "Empfohlen …", en: "Recommended …" }
    label: { de: "…", en: "…" }
    tip: { de: "…", en: "…" }
  - id: nvidia_libs
    env: PREMIERE_NVIDIA_LIBS
    type: bool
    default: true
    when: nvidia
    label: { de: "…", en: "…" }
    tip: { de: "…", en: "…" }
```

## Multiple sources (multi-source)

Rezeptor can merge recipes from several sources:

| Source | Typical use |
|--------|-------------|
| Local repo | Official + `recipes/community/` |
| Release recipes bundle | Overlay sync for official recipes |
| `catalog.json` on GitHub | Remote index for community / BYOS installs |

!!! warning "Check trust"
    Recipes from external sources run scripts on your system.
    Review `recipe.yml` and hooks before installing. The GUI may warn when trust differs (`trust`).

## Hide vs. uninstall

| Action | Effect |
|--------|--------|
| **Hide** | Recipe disappears from the list; **data remains** (`~/.local/share/wine-software/<id>/`). Show again later. |
| **Uninstall** | Runs `uninstall.sh` and fully removes Rezeptor state, shortcuts, and the chosen `data_root` (`recipe_hooks::purge_recipe_data`). |

Portable folders or Steam games **outside** `data_root` are left untouched on uninstall (see [STEAM-WRAPPER.md](STEAM-WRAPPER.md)).

## Runtime: Proton-GE

All recipes require **Proton-GE**. Default pin: `core/runtime.lock`. Individual recipes may diverge via `proton_ge_tag` (Photoshop and Halo → GE 11). No system-Wine fallback in recipe scripts.
Graphics DLLs come from `wine_runtime::deploy_proton_graphics_dlls()` — no winetricks-dxvk.

More: [ENTWICKLER.md](ENTWICKLER.md) · [TRUST.md](TRUST.md) · [UNINSTALL.md](UNINSTALL.md)
