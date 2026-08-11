# Architektur — GUI-Launcher

Technische Übersicht, wie die PyQt6-GUI mit Rezepten, Trust und Prozessen zusammenspielt. UI-Details: [LAUNCHER](LAUNCHER.md). Trust-Policy: [TRUST](TRUST.md).

## Schichten

```text
RezeptorWindow (launcher.py)
  ├── recipe_discovery   — Rezepte finden, Trust-Flags setzen
  ├── recipe_trust       — Manifest SHA-256, Sync nur mit REZEPTOR_DEV
  ├── recipe_catalog     — Remote-Install (Pfad-Containment)
  ├── settings           — UI-Prefs (0600); Passwörter separat verschlüsselt
  ├── recipe_process     — RecipeProcessOps: QProcess / _run_async
  │                        (install/repair/validate/update/relocate/launch/uninstall/kill)
  └── Domänen-UI         — ui_source, ui_settings, ui_catalog, …
```

`RezeptorWindow` hält den Prozess-State (`_busy`, `_process`, …) und dünne Delegates mit denselben Methodennamen; die Orchestrierung liegt in `RecipeProcessOps` (`launcher/recipe_process.py`).

## Trust

| Aktion | Prüfung |
|--------|---------|
| Starten / Installieren / Reparieren / Validieren / Deinstallieren | `_require_trusted_recipe()` — hart blocken wenn `!trust_ok` |
| Manifest-Auto-Sync | nur `REZEPTOR_DEV=1`; danach alle Rezepte **untrusted**, bis Freigabe |
| AppImage / Flatpak (ohne `.git`) | strikte Hash-Prüfung, kein Auto-Sync |

## Secrets

| Datei | Inhalt | Rechte |
|-------|--------|--------|
| `~/.local/share/wine-software/rezeptor/settings.json` | Prefs **ohne** Klartext-Passwörter | `0600`, Dir `0700` |
| `…/archive-passwords.json` | verschlüsselte Archiv-Passwörter | `0600` |
| `…/archive-passwords.key` | lokaler Schlüssel | `0600` |

## Prozesse

- Install/Repair/Validate/Update/Relocate/Uninstall: `QProcess` über `RecipeProcessOps._run_async` (Log → Vorgang-Tab)
- Launch: detached `bash launch.sh`, Alive-Check über Prozessmuster (`RecipeProcessOps`)
- Busy-Guard: `_require_recipe` / `_reject_if_subprocess_busy` blockt bei laufendem QProcess
- Cancel: SIGTERM über `_signal_qprocess_tree`; Force-Kill: SIGKILL über `signal_subprocess_tree`

## Modul-Map (Auszug)

| Modul | Verantwortung |
|-------|----------------|
| `launcher.py` | `RezeptorWindow`, Menüs/Tabs, Status-Refresh, App-Self-Update; Delegates an `_ops` |
| `recipe_process.py` | `RecipeProcessOps` — Install/Repair/Validate/Update/Relocate/Launch/Uninstall/Kill, QProcess-Orchestrierung |
| `recipe_discovery.py` | `RecipeInfo` / `RecipeState`, `discover_recipes` → `DiscoverOutcome` (Trust/Sync-Meldungen, kein `os.environ`), `parse_recipe_yml` |
| `recipe_trust.py` | Manifest-SHA256, Dev-only Sync |
| `recipe_catalog.py` | Remote-Install + Pfad-Containment |
| `settings.py` | Prefs `0600`; Secrets in separater Datei (Fernet) |
| `archive_passwords.py` | Archiv-Probe/Normalisierung (ohne PyQt) |
| `ui_archive_passwords.py` | Passwort-Prompt (PyQt) |
| `app_support.py` | Log-Humanize, Reports `0600`, Releases |
| `ui_*.py` | Reine UI-Schicht (Fluent Dark + Kupfer) |

Weitere Aufteilung von `launcher.py` (z. B. Status-Refresh, Update-Check) nur bei Bedarf; Prozess-Orchestrierung ist bereits in `recipe_process.py`.

## `recipe.yml` Schema

Optionales `schema_version: 1` (Default **1**, wenn fehlend). Parser und GUI tolerieren fehlende Angabe; neue Rezepte sollen das Feld setzen.
