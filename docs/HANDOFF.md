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

- Latest released: **v1.1.46** (Photoshop Quit #10 exit ladder, Lightroom Classic recipe).
- **Photoshop Quit (#10), the rule to keep:** close windows via `wmctrl -ic`
  (`_NET_CLOSE_WINDOW`), never `xdotool windowclose`. windowclose destroys the X
  window, so Photoshop keeps running with no window and never writes prefs.
  After the window is gone: wait `PHOTOSHOP_EXIT_WAIT_S` (45s), then force.
  No window found at all (user already closed it): wait, then soft
  `taskkill` (WM_CLOSE), only then force — otherwise Quit kills mid-save.
  `wineserver -k` runs once `Photoshop.exe` is gone, otherwise helpers such as
  `CCLibrary` survive and the next launch crashes during init.
- **Datenverlust 2026-08-14 11:58:** Arbeitsbaum wurde auf HEAD zurückgesetzt und
  unversionierte Dateien entfernt (`git reflog`: `reset: moving to HEAD` +
  `checkout: moving from main to main`). Wiederhergestellt aus dem Chat-Transkript:
  `lightroom-classic` komplett. **Verloren:** lokales `photoshop-2026`-Rezept
  (`core/recipe-photoshop-2026-*.sh`, `core/ps2026-*proxy*`) und die Halo-Steam-Arbeit
  (`trainer.sh`, `ensure_steam_nonsteam.py`-Änderungen, Launcher-Anpassungen).
  Lehre: neue Rezepte früh committen (`git add`), unversioniert = ungeschützt.
- Recipe `lightroom-classic` (15.4.1, LTRM) ist **ausgeliefert**, aber noch **nicht
  end-to-end installiert** — echter Testlauf fehlt. Adaptiert von
  [6im0n/lightroom-classic-on-linux](https://github.com/6im0n/lightroom-classic-on-linux)
  (MIT, Danksagung in `info.*.txt`). Module: `core/recipe-lightroom-{stubs,install,launch}.sh`.
  **Nie** winewayland (LrC crasht) — Launch erzwingt X11.
  Bekannte Lücken: HDR upstream nicht unterstützt, KI-Entrauschen ungeprüft.
- **Local (not released):**
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
