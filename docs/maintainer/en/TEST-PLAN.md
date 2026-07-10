# Test plan — wine-software launcher

**Principle (Mythos verify):** *Done = proof.* Each step has an expected artifact. If proof is missing, the step failed — open a GitHub issue.

**Data root:** `~/.local/share/wine-software/`  
**Logs:** `~/.local/share/wine-software/logs/`  
**Issue template:** [bug_report.md](../../.github/ISSUE_TEMPLATE/bug_report.md)

---

## Before you start

```bash
cd /path/to/photoshopCClinux
./pre-check.sh          # must pass (incl. PyQt6)
bash -n recipes/photoshop/install.sh
bash -n recipes/photoshop/launch.sh
python3 -m py_compile launcher/launcher.py
```

Attach to every bug report:
- Distro + DE (e.g. CachyOS, KDE Wayland)
- Output of `source core/wine-runtime.sh && wine_runtime::describe`
- Last 50 lines: `tail -50 ~/.local/share/wine-software/logs/Installation_*.log`

---

## Phase A — Photoshop (CachyOS / your daily driver)

| ID | Step | Command / action | Pass criteria |
|----|------|------------------|---------------|
| A0 | Clean prefix (optional) | `pkill -9 wineserver 2>/dev/null; rm -rf ~/.local/share/wine-software/photoshop/prefix` | — |
| A1 | Pre-check | `./pre-check.sh` | Exit 0, PyQt6 OK |
| A2 | GUI launcher | `./setup.sh` | Window opens, `photoshop` recipe listed |
| A3 | Install | GUI → **Install** (terminal opens) | Adobe flow completes, no hang on EOF |
| A4 | Validate | `bash recipes/photoshop/validate.sh` | Prints `OK: .../Photoshop.exe` |
| A5 | Proton proof | `grep -i proton ~/.local/share/wine-software/logs/Installation_*.log \| tail -3` | Path contains `proton-ge`, **not** `/usr/bin/wine` alone |
| A6 | Start (CLI) | `bash recipes/photoshop/launch.sh` | Photoshop window opens |
| A7 | Start (GUI) | `./setup.sh` → **Start** | Same as A6 |
| A8 | Desktop entry | `grep Exec= ~/.local/share/applications/photoshop.desktop` | Points to `.../launcher/launcher.sh` under data root |
| A9 | Deployed launcher | `bash ~/.local/share/wine-software/photoshop/launcher/launcher.sh` | Works without git repo cwd |

**Fail tracking:** Issue title `[A3]` / `[A6]` + log excerpt + `validate.sh` output.

---

## Phase B — Immutable / AppImage (optional)

| ID | Step | Pass criteria |
|----|------|---------------|
| B1 | Build | `scripts/build-appimage.sh` | SHA256 OK, AppImage created |
| B2 | Run AppImage | `./photoshopCClinux-*-x86_64.AppImage` | Launcher or setup starts |
| B3 | No system wine | `which wine` empty or unused in install log | Proton from bundle or user runtime |

Test on: Bazzite, Silverblue, Kinoite, or Bluefin if available.

---

## Phase C — WISO (optional, Proton experimental)

| ID | Step | Pass criteria |
|----|------|---------------|
| C1 | Install | GUI → wiso-steuer → Install → pick portable folder | `portable.env` exists, no shell errors |
| C2 | Validate | `bash recipes/wiso-steuer/validate.sh` | `OK: portable at ...` |
| C3 | Launch | GUI → Start | WISO window (no virtual desktop; opt-in `WISO_VIRTUAL_DESKTOP=1`) |

---

## Phase D — Regression smoke (after any code change)

```bash
./pre-check.sh
bash recipes/photoshop/validate.sh    # if already installed
bash -n core/wine-runtime.sh
bash -n core/sharedFuncs.sh
python3 -m py_compile launcher/launcher.py
```

---

## Error tracking workflow

1. **Reproduce** with IDs above (note which step).
2. **Collect artifacts** into one paste:
   - `validate.sh` exit code + output
   - `tail -80` newest log in `~/.local/share/wine-software/logs/`
   - `~/.local/share/wine-software/photoshop/wine-error.log` if present
3. **Open issue** on GitHub with template; label `bug` + `photoshop` or `wiso`.
4. **Do not** mark plan todos / releases green until A4+A6 pass on target distro.

---

## Checklist (copy for release)

```
[ ] A1 pre-check
[ ] A3 install
[ ] A4 validate
[ ] A5 proton in log
[ ] A6 launch
[ ] A8 desktop entry
[ ] B1 AppImage (if release)
[ ] README paths match reality
```
