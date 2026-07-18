# GUI launcher

Technical notes for the PyQt6 UI under `launcher/`. Brand and UX rules: [Brand](BRAND.md).

## Start

```bash
./setup.sh                 # pre-check → python3 launcher/launcher.py
REZEPTOR_DEV=1 ./setup.sh  # developer mode
```

Dependencies: **PyQt6** required; optional **PyQt6-Fluent-Widgets** (`ui_fluent.FLUENT_AVAILABLE`).

## Module map

| File | Role |
|------|------|
| `launcher.py` | Main window, QProcess hooks, activity, updates |
| `ui_fluent.py` | Fluent `Theme.DARK` + copper `#B87333` |
| `ui_styles.py` | Host QSS, brand tokens |
| `ui_rezeptor.py` | Sidebar, segment tabs, status pill |
| `ui_settings.py` | Settings dialog |
| `ui_docs.py` | In-app markdown (author catalog) |
| `ui_recipe_view.py` / `ui_recipe_wizard.py` | Dev: editor / new recipe |
| `ui_source.py` | Source/target pickers |
| `recipe_catalog.py` | `catalog.json`, remote install |
| `recipe_trust.py` | Manifest SHA256 |
| `settings.py` | `~/.local/share/wine-software/rezeptor/settings.json` |
| `log_context.py` | `LogEvent`, stable codes `E_*` |
| `app_support.py` | `humanize_log_line`, bug report, releases |
| `i18n/` + `locales/*.json` | UI strings |
| `version_detect.py` | Engine for YAML `version_detect` |
| `host_deps.py` | Suggest missing host tools |

## UI conventions

- Sidebar **fixed 240 px**, primary CTA + **More ▾**, segment tabs
- Always Fluent Dark + copper — no system light hybrid, no PyQtDarkTheme
- Do not override Fluent widgets with host QSS
- Visual changes (colors, radii, scrollbars) only with explicit approval

## Settings (excerpt)

Persisted in `settings.json`: locale, `developer_mode`, `validate_on_startup`, window geometry, recipe order, hidden IDs, `recipe_sources`, install env, archive passwords, log retention.

## Env passed to hook scripts

The GUI sets among others:

| Variable | Purpose |
|----------|---------|
| `LAUNCHER_GUI=1` | Enables `@step:` / `@progress:` tags |
| `LAUNCHER_SESSION_ID` | Session for reports |
| `RECIPE_DATA_ROOT` | Chosen data location |
| `RECIPE_INSTALLER_PATH` / `RECIPE_ARCHIVE_PATH` / `RECIPE_SOURCE_ROOT` | Source |
| `RECIPE_TARGET_DIR` / `RECIPE_DEPLOY_MODE` | Portable target |

## In-app docs

`ui_docs.py` → `DOC_CATALOG` lists author pages under `docs/{locale}/` (no maintainer handoffs under `docs/{locale}/maintainer/`). The Help menu opens the local markdown view; GitHub links via `github_doc_url`.

## Bug report (GitHub)

In `app_support.py`:

- **Clipboard** = full body from `bug_report.md` (`report_clipboard_text` / `build_issue_body`)
- **URL** short + `?template=bug_report.md` (+ label/title); paste supplies the long text
- **Session ID** (`LAUNCHER_SESSION_ID`) only in the report file, not in the status bar

## Error codes

Defined in `log_context.py`, strings under `error.*` in locales — see [I18N](I18N.md).

## Next

- [Log protocol](LOG-PROTOCOL.md)
- [Trust & manifest](TRUST.md)
- [User guide](USER-GUIDE.md)
