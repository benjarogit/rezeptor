# User guide

How to use the Rezeptor GUI. Recipe authors: see [Developer overview](ENTWICKLER.md).

## UI layout

| Element | Role |
|---------|------|
| **Sidebar** | Recipe list (~240 px), status pill, search/order |
| **Main area** | Overview, source/target, info texts |
| **Primary CTA** | Context action (Install / Launch / …) |
| **More ▾** | Secondary actions (Repair, Validate, Uninstall, …) |
| **Activity** | Humanized log lines from hook scripts |

Theme: Fluent Dark + copper (`#B87333`) — see [Brand](BRAND.md).

## Typical flow

1. Pick a recipe
2. Save the **source** (path to installer / portable / EXE)
3. Set a **target** if needed (portable destination)
4. **Install**
5. Optionally validate (F5 or menu)
6. **Launch**
7. On problems: **Repair** (fixes gaps; does not reinstall from scratch)
8. **Uninstall** removes Rezeptor state fully — portable/Steam folders outside stay

## Status & validation

- Optional **validate on startup** (Settings)
- **F5** / Validate: structured `OK:` / `FAIL:` / `WARN:` output
- Green = tested / ready; amber = warning; error = action needed

## Settings

File: `~/.local/share/wine-software/rezeptor/settings.json`

Typical options:

| Setting | Effect |
|---------|--------|
| Language | `de` / `en` (more via locale manifest) |
| Developer mode | Same as `REZEPTOR_DEV=1` |
| Validate on startup | Auto-validate |
| Log retention | Clean old logs |
| Archive passwords | For protected archives |
| Recipe sources | Extra catalogs / paths |
| Hidden recipes | List only; data stays |

## Hide vs uninstall

| Action | Effect |
|--------|--------|
| **Hide** | Removed from the list; data stays |
| **Uninstall** | `uninstall.sh` → `purge_recipe_data` (desktop + data_root) |

Details: [Uninstall](UNINSTALL.md) · [Catalog](CATALOG.md)

## Updates

Releases from GitHub; auto-update where offered. After a manual download, verify assets with `sha256sum`.

## Help & bugs

- In-app: **Help → Developer documentation…** (author pages)
- GitHub issues / bug-report template (clipboard may hold the full report body)
- Session ID is in the report file, not the status bar

## Next

- [Quick start](GETTING-STARTED.md)
- [Trust & manifest](TRUST.md)
- [GUI launcher (technical)](LAUNCHER.md)
