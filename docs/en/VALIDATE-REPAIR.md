# Validate & repair

Contract between `validate.sh`, `repair.sh`, and the GUI. **Repair ≠ reinstall.**

## Validate

### Required behavior

1. `recipe_hooks::load validate`
2. Structured lines (`core/recipe-validate.sh`):
   - `OK: …` (stdout)
   - `WARN: …` (stdout) — **does not** fail the exit code
   - `FAIL: …` (stderr) — counts as failure
3. Optional GUI progress: `output::progress_begin` / `tick` / `done`
4. Exit **0** when there is no `FAIL`; exit **1** when there is at least one `FAIL` (the recipe counts failures itself)

### Recommended checks

Use `core/recipe-validate.sh`:

```bash
recipe_validate::prefix_initialized "$WINEPREFIX" || failures=$((failures+1))
recipe_validate::windows_version "$WINEPREFIX" || true   # or fail per recipe
recipe_validate::ok "Prefix present"
```

App-specific: EXE paths, portable root, fix files (Steam), version guarantee.

### Version

With `version_guaranteed` + `version_detect` in `recipe.yml`: mismatch is often a `WARN` (not necessarily a hard fail — depends on recipe policy). Lint requires `version_detect` when `version_guaranteed` is set.

---

## Repair

### Required behavior

1. `recipe_hooks::load repair`
2. Run `validate.sh` first (or equivalent checks)
3. If all OK: at most sync (fonts/graphics/desktop refresh)
4. If FAIL: fix **only missing** components
5. Validate again
6. Exit **0** on success; exit **11** if incomplete (GUI may retry)

### Allowed / forbidden

| Allowed | Forbidden |
|---------|-----------|
| `recipe_winetricks::run` for missing packages | Full `install_steps` / reinstall |
| `recipe_win10::ensure` | winetricks winecfg |
| `recipe_vcrun::ensure` / `recipe_dotnet::ensure` | System Wine fallback |
| `wine_runtime::deploy_proton_graphics_dlls` | winetricks dxvk |
| Desktop `refresh_if_present` | `load kill` |

### Pattern (pseudocode)

```bash
recipe_hooks::load repair
# … validate …
if [[ $failures -eq 0 ]]; then
  # optional: fonts/graphics sync
  exit 0
fi
# targeted fixes for FAIL points only
# validate again
```

### Special cases

- **WISO:** missing prefix → error “please Install”, not repair-from-scratch
- **Photoshop:** often syncs fonts/graphics/post-install even when validate is green

---

## CI

`make recipes-check` requires `validate:` and `repair:` in every `recipe.yml`.  
Manual: break something on purpose → Repair → validate green.

## Next

- [Core API](CORE-API.md)
- [Uninstall](UNINSTALL.md)
- [Log protocol](LOG-PROTOCOL.md)
