# Handoff — Rezeptor

## One source tree

| Path | Role |
|------|------|
| `/home/benny/Dokumente/rezeptor` | **Only** git checkout / Cursor workspace |
| `~/Dokumente/repowise-ws/rezeptor` | Symlink → same tree (RepoWise multi-repo) |
| `/home/benny/Dokumente/rezeptor-ghidra` | Ghidra lab (not the app repo) |
| `~/.config/rezeptor` | App settings |
| `~/.local/share/wine-software/` | Install data per recipe |
| Flatpak `io.github.benjarogit.Rezeptor` | Installed app (optional) |

## Quickstart

```bash
cd /home/benny/Dokumente/rezeptor
./setup.sh                 # pre-check → launcher (git/tar path)
# REZEPTOR_DEV=1 ./setup.sh
```

`setup.sh` is the **dev/git entry** (not obsolete). Flatpak/AppImage use their own launcher.
Menu: one visible entry → local `~/.local/share/applications/rezeptor.desktop` → `setup.sh`.
Flatpak menu entry is hidden via `NoDisplay=true` override (still: `flatpak run io.github.benjarogit.Rezeptor`).

## Remotes

- `origin` → `https://github.com/benjarogit/rezeptor.git`
- Do **not** use archived `benjarogit/photoshopCClinux`

## Open work

- Pending Quelle/Ziel in header (`launcher/launcher.py`)
- Legacy screenshots removed from `images/`
