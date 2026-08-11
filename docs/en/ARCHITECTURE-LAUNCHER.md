# Architecture — GUI launcher

How the PyQt6 GUI relates to recipes, trust, and processes. UI details: [LAUNCHER](LAUNCHER.md). Trust policy: [TRUST](TRUST.md).

## Layers

```text
RezeptorWindow (launcher.py)
  ├── recipe_discovery   — find recipes, set trust flags
  ├── recipe_trust       — manifest SHA-256; sync only with REZEPTOR_DEV
  ├── recipe_catalog     — remote install (path containment)
  ├── settings           — UI prefs (0600); passwords stored separately encrypted
  ├── recipe_process     — RecipeProcessOps: QProcess / _run_async
  │                        (install/repair/validate/update/relocate/launch/uninstall/kill)
  └── Domain UI          — ui_source, ui_settings, ui_catalog, …
```

`RezeptorWindow` owns process state (`_busy`, `_process`, …) and thin delegates with the same method names; orchestration lives in `RecipeProcessOps` (`launcher/recipe_process.py`).

## Trust

| Action | Check |
|--------|--------|
| Launch / Install / Repair / Validate / Uninstall | `_require_trusted_recipe()` — hard block if `!trust_ok` |
| Manifest auto-sync | only `REZEPTOR_DEV=1`; afterwards all recipes **untrusted** until approval |
| AppImage / Flatpak (no `.git`) | strict hash verify, no auto-sync |

## Secrets

| File | Contents | Mode |
|------|----------|------|
| `~/.local/share/wine-software/rezeptor/settings.json` | Prefs **without** plaintext passwords | `0600`, dir `0700` |
| `…/archive-passwords.json` | encrypted archive passwords | `0600` |
| `…/archive-passwords.key` | local key | `0600` |

## Processes

- Install/Repair/Validate/Update/Relocate/Uninstall: `QProcess` via `RecipeProcessOps._run_async` (log → activity tab)
- Launch: detached `bash launch.sh`, alive check via process patterns (`RecipeProcessOps`)
- Busy guard: `_require_recipe` / `_reject_if_subprocess_busy` blocks while a QProcess is running
- Cancel: SIGTERM via `_signal_qprocess_tree`; force-kill: SIGKILL via `signal_subprocess_tree`

## Module map (excerpt)

| Module | Responsibility |
|--------|----------------|
| `launcher.py` | `RezeptorWindow`, menus/tabs, status refresh, app self-update; delegates to `_ops` |
| `recipe_process.py` | `RecipeProcessOps` — install/repair/validate/update/relocate/launch/uninstall/kill, QProcess orchestration |
| `recipe_discovery.py` | `RecipeInfo` / `RecipeState`, `discover_recipes` → `DiscoverOutcome` (trust/sync messages, no `os.environ`), `parse_recipe_yml` |
| `recipe_trust.py` | Manifest SHA-256, dev-only sync |
| `recipe_catalog.py` | Remote install + path containment |
| `settings.py` | Prefs `0600`; secrets in separate file (Fernet) |
| `archive_passwords.py` | Archive probe/normalize (no PyQt) |
| `ui_archive_passwords.py` | Password prompt (PyQt) |
| `app_support.py` | Log humanize, reports `0600`, releases |
| `ui_*.py` | UI layer only (Fluent Dark + copper) |

Further splits of `launcher.py` (e.g. status refresh, update check) only as needed; process orchestration already lives in `recipe_process.py`.

## `recipe.yml` schema

Optional `schema_version: 1` (defaults to **1** when omitted). Parsers tolerate a missing field; new recipes should set it.
