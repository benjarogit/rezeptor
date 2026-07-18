# Log-Protokoll

Vertrag zwischen Hook-Skripten (`core/output.sh`) und der GUI (`humanize_log_line` in `launcher/app_support.py`).

## Prinzip

- Skripte emittieren **maschinenlesbare Tags** auf stdout/stderr
- Die GUI **humanisiert** sie für die Activity-Liste
- Interne Tags gehören **nicht** roh in Nutzer-Dialoge

## Tags

| Tag | Emitter (Auszug) | GUI |
|-----|------------------|-----|
| `@progress:<0-100>` | `output::progress` | Fortschrittsanzeige |
| `@step:<msg>` | `output::step` | Schrittzeile (übersetzt/geglättet) |
| `@ok:<msg>` | `output::success` | Erfolg |
| `@error:<msg>` | `output::error` | Fehler |
| `@warn:…` | `output::user_action` u. a. | Warnung / Nutzeraktion |
| `@info:<msg>` | optional | Info |

Kurz-Hooks (validate/repair/uninstall):

```bash
output::progress_begin
output::progress_tick
output::progress_done
```

## Validate-Zeilen

Zusätzlich zum Tag-Protokoll:

```
OK: Prefix vorhanden
FAIL: Grafik-DLLs fehlen
WARN: Version weicht ab
```

`FAIL` → Exit ≠ 0; `WARN` allein nicht.

## LogEvent / Fehlercodes

Strukturierte Fehler im Launcher:

| Code | Typische Situation |
|------|--------------------|
| `E_TRUST_MANIFEST` | Manifest-Hash stimmt nicht |
| `E_UPDATE_APPLY` | Auto-Update fehlgeschlagen |
| `E_UPDATE_ROLLBACK` | Rollback fehlgeschlagen |
| `E_LAUNCH_NO_PROCESS` | App nach Start nicht aktiv |
| `E_SCRIPT_FAILED` | Hook Exit ≠ 0 |

Locale-Keys: `error.<CODE>` in `launcher/locales/*.json`. Neue Pfade: bestehenden Code wiederverwenden oder `log_context` + Locale erweitern — keine Ad-hoc-`QMessageBox`-Parallelwelt.

## Logs auf Disk

`~/.local/share/wine-software/logs/` — Dateinamen pro Rezept/Vorgang.  
`recipe_hooks::emit_log_paths` druckt `RECIPE_LOG_FILE=` / `RECIPE_ERROR_LOG=` für die GUI.

## Verboten

- `print` / Dialoge statt Log-Framework für Vorgangsfehler
- Rohe `@step:`-Strings als Endnutzer-Copy in der Statusleiste (Session-ID nur im Report-File)

## Weiter

- [GUI-Launcher](LAUNCHER.md)
- [I18N](I18N.md)
- [Validate & Repair](VALIDATE-REPAIR.md)
