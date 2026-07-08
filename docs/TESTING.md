# Test matrix — Proton-GE only, unified data root

User data: `~/.local/share/wine-software/` (prefix, runtime, logs, cache).

Launcher: **PyQt6 required** (`python-pyqt6`).

## Phase tests

| Phase | Test | Success |
|-------|------|---------|
| 0 | `recipes/photoshop/install.sh` | `Photoshop.exe` in prefix, log shows Proton binary |
| 1 | Prefix + runtime paths | Under `~/.local/share/wine-software/` |
| 2 | `./setup.sh` | PyQt launcher; without PyQt6 → pre-check fail |
| 3 | `scripts/build-appimage.sh` | AppImage starts launcher + Proton bundle |
| 4 | WISO recipe | Portable folder + KDE Wayland virtual desktop |

## Commands

```bash
./pre-check.sh
./setup.sh
bash -n recipes/photoshop/install.sh
bash recipes/photoshop/validate.sh
scripts/build-appimage.sh
```

See **[TEST-PLAN.md](TEST-PLAN.md)** for step-by-step manual QA and issue tracking.

- [ ] Photoshop install + launch (Proton-GE)
- [ ] PyQt6 launcher
- [ ] AppImage (optional)
- [ ] WISO portable (optional)
