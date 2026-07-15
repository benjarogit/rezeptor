# Recipe catalog

Rezeptor lists applications as **recipes**. The catalog distinguishes origin and trust —
not every source is equivalent.

## Official recipes (bundled)

Shipped in the repository under `recipes/<id>/`, indexed in `recipes/catalog.json` (`trust: official`).

Examples: Photoshop, WISO Steuer, House of Ashes, ZA4 trainer.

These recipes ship with Rezeptor and are guarded by CI (`recipe-lint`, manifest checks).

## Community recipes

Custom or shared recipes live under `recipes/community/<id>/`.

Create one with:

```bash
./scripts/new-recipe.sh --community my-app "My App"
```

Community entries are **not** automatically vetted as official — author and content are your responsibility.

## Multiple sources (multi-source)

Rezeptor can merge recipes from several sources:

| Source | Typical use |
|--------|-------------|
| Local repo | Official + `recipes/community/` |
| `catalog.json` on GitHub | Remote index for installing recipes |

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

All recipes require **Proton-GE** (`core/runtime.lock`). No system-Wine fallback in recipe scripts.
Graphics DLLs come from `wine_runtime::deploy_proton_graphics_dlls()` — no winetricks-dxvk.

More: [RECIPES.md](RECIPES.md) · [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
