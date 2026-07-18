# GUI-Launcher

Technische Notizen zur PyQt6-Oberfläche unter `launcher/`. Brand und UX-Regeln: [Marke](BRAND.md).

## Start

```bash
./setup.sh                 # pre-check → python3 launcher/launcher.py
REZEPTOR_DEV=1 ./setup.sh  # Entwicklermodus
```

Abhängigkeiten: **PyQt6** Pflicht; optional **PyQt6-Fluent-Widgets** (`ui_fluent.FLUENT_AVAILABLE`).

## Modulübersicht

| Datei | Rolle |
|-------|--------|
| `launcher.py` | Hauptfenster, QProcess-Hooks, Activity, Updates |
| `ui_fluent.py` | Fluent `Theme.DARK` + Kupfer `#B87333` |
| `ui_styles.py` | Host-QSS, Brand-Tokens |
| `ui_rezeptor.py` | Sidebar, Segment-Tabs, Status-Pille |
| `ui_settings.py` | Einstellungsdialog |
| `ui_docs.py` | In-App-Markdown (Autoren-Katalog) |
| `ui_recipe_view.py` / `ui_recipe_wizard.py` | Dev: Editor / Neues Rezept |
| `ui_source.py` | Quelle/Ziel-Picker |
| `recipe_catalog.py` | `catalog.json`, Remote-Install |
| `recipe_trust.py` | Manifest-SHA256 |
| `settings.py` | `~/.local/share/wine-software/rezeptor/settings.json` |
| `log_context.py` | `LogEvent`, stabile Codes `E_*` |
| `app_support.py` | `humanize_log_line`, Bug-Report, Releases |
| `i18n/` + `locales/*.json` | UI-Strings |
| `version_detect.py` | Engine für `version_detect` in YAML |
| `host_deps.py` | Fehlende Host-Tools vorschlagen |

## UI-Konventionen

- Sidebar **fix 240 px**, Primary-CTA + **Mehr ▾**, Segment-Tabs
- Immer Fluent Dark + Kupfer — kein System-Light-Hybrid, kein PyQtDarkTheme
- Fluent-Widgets nicht mit Host-QSS „übermalen“
- Optik-Änderungen (Farben, Radien, Scrollbars) nur mit expliziter Freigabe

## Einstellungen (Auszug)

Persistiert in `settings.json`: Locale, `developer_mode`, `validate_on_startup`, Fenstergeometrie, Rezeptreihenfolge, ausgeblendete IDs, `recipe_sources`, Install-Env, Archiv-Passwörter, Log-Retention.

## Env an Hook-Skripte

Die GUI setzt u. a.:

| Variable | Zweck |
|----------|--------|
| `LAUNCHER_GUI=1` | `@step:` / `@progress:`-Tags aktiv |
| `LAUNCHER_SESSION_ID` | Session für Reports |
| `RECIPE_DATA_ROOT` | Gewählter Datenort |
| `RECIPE_INSTALLER_PATH` / `RECIPE_ARCHIVE_PATH` / `RECIPE_SOURCE_ROOT` | Quelle |
| `RECIPE_TARGET_DIR` / `RECIPE_DEPLOY_MODE` | Portable-Ziel |

## In-App-Doku

`ui_docs.py` → `DOC_CATALOG` listet Autoren-/Nutzer-Seiten unter `docs/{locale}/`. Hilfe-Menü öffnet die lokale Markdown-Ansicht; GitHub-Links über `github_doc_url`.

## Bug-Report (GitHub)

In `app_support.py`:

- **Zwischenablage** = voller Body aus `bug_report.md` (`report_clipboard_text` / `build_issue_body`)
- **URL** kurz + `?template=bug_report.md` (+ Label/Titel); der lange Text kommt per Einfügen
- **Session-ID** (`LAUNCHER_SESSION_ID`) nur in der Report-Datei, nicht in der Statusleiste

## Fehlercodes

Definiert in `log_context.py`, Texte unter `error.*` in Locales — siehe [I18N](I18N.md).

## Weiter

- [Log-Protokoll](LOG-PROTOCOL.md)
- [Trust & Manifest](TRUST.md)
- [Benutzerhandbuch](USER-GUIDE.md)
