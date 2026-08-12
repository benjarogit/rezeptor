# Handoff — Rezeptor

Public app repo only. Maintainer/RE lab notes and Ghidra tooling live **outside** this tree
(`~/Dokumente/rezeptor-ghidra/`, not on GitHub).

## One source tree

| Path | Role |
|------|------|
| `/home/benny/Dokumente/rezeptor` | Git checkout / Cursor workspace (public product) |
| `~/Dokumente/repowise-ws/rezeptor` | Symlink → same tree (RepoWise multi-repo) |
| `~/.config/rezeptor` | App settings |
| `~/.local/share/wine-software/` | Install data per recipe |
| Flatpak `io.github.benjarogit.Rezeptor` | Installed app (optional) |

## Quickstart

```bash
cd /home/benny/Dokumente/rezeptor
./setup.sh                 # pre-check → launcher (git/tar path)
# REZEPTOR_DEV=1 ./setup.sh
```

`setup.sh` is the **dev/git entry**. Flatpak/AppImage use their own launcher.

## Remotes

- `origin` → `https://github.com/benjarogit/rezeptor.git`
- Do **not** use archived `benjarogit/photoshopCClinux`

## Git / main protection

- Ruleset **Protect main**: no direct push; PR required; CI job `validate` green.
- **No release** until Benny asks. App-visible changes need a release decision when landing.

## Open work

- Latest released: see `VERSION` / GitHub Releases.
- **Local WIP:** Themes Standard / Dracula / Alucard (official Dracula hex; Alucard = light + purple accent).
  Pills/path/activity use `theme_tokens` (no fixed dark `MUTED`). Theme switch = status flash only.
  Home-Links: Favicons + button-like Accent-Rand/Hover. Sidebar-Liste wächst mit Rezepten, Scroll erst wenn Budget voll.
  Fensterhöhe folgt Inhalt (Startseite kompakt); Action-Bar wieder über Home+Rezept. Kein Fixed-Height-Hack am Detail-Stack.
  Beta-Toggle aus der GUI entfernt.
- App-/Spielordner-Symlink in `DATA_ROOT` via `core/recipe-app-link.sh` (done locally).
- Product backlog (when scheduled): Proton-GE management UI, exception→diagnose zip CTA, Snapshot/Restore as own point.

## Halo recipe assets (public)

Under `recipes/halo-campaign-evolved/assets/` only runtime/product files belong
(Steam helper, intro clip, Steam grid). Analysis guides and GDB/Ghidra scripts do **not**.
