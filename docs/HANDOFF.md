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

## Git / main protection

- Ruleset **Protect main** (active): no direct push, no force-push, no branch delete; PR required; CI job `validate` must be green; 0 approving reviews required (solo ok).
- Land local commits via feature branch + `gh pr create` (not `git push origin main`).
- **No release** until Benny asks. App-visible changes need a release decision when landing.

## Open work

- Local `main` ahead of `origin/main` (see `git log origin/main..HEAD`) — land via PR when Benny asks to push.
- Backlog **1–21 complete** locally (Phases A–C). No further scheduled backlog points.

### Done (committed locally, pending PR)

| Points | Topic |
|--------|--------|
| 1–5 | Launcher UX (window icon, overview tab, Mehr-menu, empty Vorgang, install dialog) |
| 6 | `make i18n-check` / CI key parity (launcher JSON only) |
| 7 | ruff for `launcher/` |
| 8 | bats coverage (discovery / sync / version_detect) |
| 9 | `launcher/recipe_process.py` (`RecipeProcessOps`) |
| 10–14 | Docs sync + HANDOFF |
| 15 | `vulture` / `make dead-code` |
| 16 | `make shell-dup-check` + wiso `log_err` → `recipe_hooks::log_err` |
| 17 | PR workflow docs + GitHub ruleset on `main` (+ manifest sync for CI) |
| 18 | Sanitized diagnose zip export |
| 19 | Optional `tested_on` date next to Proton-GE (official recipes unset until confirmed) |
| 20 | Backup hints before relocate / uninstall (WISO names tax data) |
| 21 | Cross-recipe activity history on home (`activity-history.json`) |

### Later candidates (not scheduled)

- Key-parity check for Bash `.lang` trees (`core/locales`, `scripts/locales`) — documented gap in I18N.md.
- Fill confirmed `tested_on` values on official recipes (manual; one line + `make recipe-manifest` each).
- Visual “stale tested_on” hint (separate UI freigabe — not in P19).
