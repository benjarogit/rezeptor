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

- **No push / no release** until Benny asks. App-visible changes (1–9) need a release decision at push time; docs-only (10–14) do not.
- Local `main` ahead of `origin/main` (see `git log origin/main..HEAD`).

### Done (committed locally)

| Points | Topic |
|--------|--------|
| 1–5 | Launcher UX (window icon, overview tab, Mehr-menu, empty Vorgang, install dialog) |
| 6 | `make i18n-check` / CI key parity (launcher JSON only) |
| 7 | ruff for `launcher/` |
| 8 | bats coverage (discovery / sync / version_detect) |
| 9 | `launcher/recipe_process.py` (`RecipeProcessOps`) |
| 10–13 | Docs sync: ARCHITECTURE-LAUNCHER, LAUNCHER, CONTRIBUTING, index, PROJECT-LAYOUT, I18N |
| 14 | This handoff file |

### Next backlog

| Points | Topic | Notes |
|--------|--------|--------|
| 15 | `vulture` / `make dead-code` | Process tooling |
| 16 | Shell redundancy check (`core/` vs `recipes/`) | Process tooling |
| 17 | PR workflow / branch protection on `main` | Needs GitHub settings |
| 18–21 | GUI features (diagnose zip, tested-on date, backup hint, activity history) | Plan + freigabe per point |

### Later candidates (not scheduled)

- Key-parity check for Bash `.lang` trees (`core/locales`, `scripts/locales`) — documented gap in I18N.md.
