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

- Latest released: **v1.1.44** (Photoshop Quit #10, Proton 11 default, experimental README).
- **Local (not in 1.1.44):**
  - Halo: `data_root.path` → `/mnt/ssd2/Games/Halo Evolved` (echte Installation).
    Leerer Prefix unter `~/.local/share/wine-software/halo-campaign-evolved` war die
    Ursache für „Halo-EXE fehlt“ / Steam-Stack-FAIL.
  - Halo: `winetricks: []` — `vcrun2019` (14.29) hat bei jedem Repair die CRT
    downgraded; CRT kommt über `ensure_modern_crt` (14.40+).
  - Halo trainer: wartet auf `HaloCampaignEvolved.exe`, dann gleiches Proton-Wine
    (`proton-cachyos-slr` `files/bin/wine` + echter Prefix). GUI: `trainer.sh`.
    Log: `/tmp/rezeptor-halo-trainer.log`. System-`wine` sieht die Steam-Session nicht.
  - Halo Steam Launch Options: `gamemoderun`, `KWIN_DRM_ALLOW_TEARING=1`, NVIDIA
    Shader-Cache. Rewrite nur wenn Steam einmal zu ist (sonst pending).
  - `deploy_proton_graphics_dlls` kopiert vkd3d-proton d3d12/d3d12core.
- Product backlog: Proton-GE management UI, exception→diagnose zip CTA, Snapshot/Restore.

## Halo recipe assets (public)

Under `recipes/halo-campaign-evolved/assets/` only runtime/product files belong
(Steam helper, intro clip, Steam grid). Analysis guides and GDB/Ghidra scripts do **not**.
