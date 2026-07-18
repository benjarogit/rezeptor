# Log protocol

Contract between hook scripts (`core/output.sh`) and the GUI (`humanize_log_line` in `launcher/app_support.py`).

## Principle

- Scripts emit **machine-readable tags** on stdout/stderr
- The GUI **humanizes** them for the activity list
- Internal tags must **not** appear raw in user dialogs

## Tags

| Tag | Emitter (excerpt) | GUI |
|-----|-------------------|-----|
| `@progress:<0-100>` | `output::progress` | Progress indicator |
| `@step:<msg>` | `output::step` | Step line (translated/smoothed) |
| `@ok:<msg>` | `output::success` | Success |
| `@error:<msg>` | `output::error` | Error |
| `@warn:…` | `output::user_action` etc. | Warning / user action |
| `@info:<msg>` | optional | Info |

Short hooks (validate/repair/uninstall):

```bash
output::progress_begin
output::progress_tick
output::progress_done
```

## Validate lines

In addition to the tag protocol:

```
OK: Prefix present
FAIL: Graphics DLLs missing
WARN: Version mismatch
```

`FAIL` → non-zero exit; `WARN` alone does not.

## LogEvent / error codes

Structured launcher errors:

| Code | Typical situation |
|------|-------------------|
| `E_TRUST_MANIFEST` | Manifest hash mismatch |
| `E_UPDATE_APPLY` | Auto-update failed |
| `E_UPDATE_ROLLBACK` | Rollback failed |
| `E_LAUNCH_NO_PROCESS` | App not active after launch |
| `E_SCRIPT_FAILED` | Hook exit ≠ 0 |

Locale keys: `error.<CODE>` in `launcher/locales/*.json`. New paths: reuse an existing code or extend `log_context` + locale — no ad-hoc `QMessageBox` parallel world.

## On-disk logs

`~/.local/share/wine-software/logs/` — filenames per recipe/run.  
`recipe_hooks::emit_log_paths` prints `RECIPE_LOG_FILE=` / `RECIPE_ERROR_LOG=` for the GUI.

## Forbidden

- `print` / dialogs instead of the log framework for operation errors
- Raw `@step:` strings as end-user copy in the status bar (session ID only in the report file)

## Next

- [GUI launcher](LAUNCHER.md)
- [I18N](I18N.md)
- [Validate & repair](VALIDATE-REPAIR.md)
