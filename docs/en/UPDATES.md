# Updates (post-install patches)

Generic update framework for recipes that apply patches after the first install (e.g. ElAmigos updates).

**Not covered:** Rezeptor app/recipe-bundle updates (`rezeptor-update.sh`) — see [LAUNCHER.md](LAUNCHER.md).

## Contract (`recipe.yml`)

| Field | Meaning |
|-------|---------|
| `fix_kind: none\|optional\|required` | Enables updates for the recipe |
| `update: update.sh` | **Required** when `fix_kind != none` (lint ERROR otherwise) |
| `install_steps` → `apply_updates` | Optional: apply updates during install |

Hook `update.sh`:

```bash
recipe_hooks::load update
recipe_hooks::runtime_init || exit 1
recipe_updates::apply_all
```

## Discovery (hybrid)

1. **Under the install source** (auto): folder `updates/`, `Updates/`, or `update/` with numbered children `1 - …`, `2 - …`
2. **Or** numbered folders `1 - …` directly under the root
3. **Plus** optional **Update / Fix** field in the source dialog (`RECIPE_UPDATE_ROOT` / alias `RECIPE_FIX_ROOT`)

Order: **numeric** by leading integer (`1` before `2` before `10`).

Each unit: directory with `.exe` (+ optional `.bin`) or a single `.exe`.

## GUI

- **Install:** optional update field; nested `updates/` is auto-detected.
- **More → Apply update…:** dedicated dialog for the update source only (when installed and `fix_kind != none`).
- Idempotency: applied IDs in `recipe.env` as `APPLIED_UPDATES=1,2,…` — re-runs skip them.

## Core API

[`core/recipe-updates.sh`](../../core/recipe-updates.sh):

| Function | Role |
|----------|------|
| `recipe_updates::discover` | Ordered `ID\|PATH` list |
| `recipe_updates::roots_from_env` | Roots from env |
| `recipe_updates::apply_all` | Run + state |
| `recipe_updates::status` | Log/validate |

Large game ISOs: [`core/recipe-iso.sh`](../../core/recipe-iso.sh) — **mount** (`udisksctl`), no full extract.

## Example layout

```
Halo Campaign Evolved/          ← source
  Halo Campaign Evolved.iso
  updates/
    1 - Halo … update …/
      *.exe
      elamigos-1.bin

# or separate update root:
… update 29.07.2026/
  1 - …
```

Reference recipe: `halo-campaign-evolved`.

## See also

- [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) · [CORE-API.md](CORE-API.md) · [LAUNCHER.md](LAUNCHER.md) · [ENTWICKLER.md](ENTWICKLER.md)
