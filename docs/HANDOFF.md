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
- **WIP / sandbox:** work on `dev/…` (local first). No PR, no issue comments, no
  VERSION bump until Benny says it works. Then PR → main → release decision.
  Do not change the default branch. Users watch Releases and Issues, not local
  branches.

## Harness (AutoDev, `~/Downloads/dark`)

The harness decides more than the model. For Rezeptor work:

- Node = job, edge = flow, fixed schema on the edge (flags in `recipe.yml`, not ID lists).
- Deterministic gates first (`recipe-lint`, isolation, bats), expensive agents after.
- Review in parallel (correctness / security / quality), one bundled follow-up, not
  sequential “so nicht” loops. Majority + severity, not a single veto. Hard retry
  cap, then split. Follow-up ticket instead of reset.
- Findings stay in this file / chat until Benny wants a GitHub issue.

## Recipe sandbox (add-only)

A maintainer recipe may only add `recipes/<id>/`, optional `core/recipe-<id>-*.sh`,
catalog, icon, own tests/`info.*.txt`. It must not edit other recipes, Photoshop
quit, Halo Steam, or shared ID lists. Shared core (`recipe-hooks`, `wine-runtime`,
`adobe_setup`) stays prefix-scoped and ID-agnostic. Flags live in `recipe.yml`
(`installer_engine`, `launch_wait`, `extra_scripts`, desktop fields).
**`git add` immediately** — untracked is unprotected (reset 2026-08-14).
Lint: `scripts/check-recipe-isolation.sh` (via `make recipes-check`).

## Adobe upstreams (ideas, not a second Wine)

Two sources, two jobs. Runtime stays Proton-GE. Credits in `info.*.txt` are
separate blocks with full URLs. Do not take their Wine tree, Steam compat
tool, or a `user32.dll` swap. No empty feedback-stub hook.

- [PhialsBasement/wine-adobe-installers](https://github.com/PhialsBasement/wine-adobe-installers)
  — installer path (`adobe_setup`: ISO, IE8/MSXML, silent Set-up). Used by
  Photoshop 2026, Lightroom, Premiere.
- [6im0n/lightroom-classic-on-linux](https://github.com/6im0n/lightroom-classic-on-linux)
  — patched d2d1/mfplat, hnetcfg (and Lightroom-only WinRT/fakeram). Used by
  Lightroom Classic (runtime). Photoshop 2026 keeps mfplat/hnetcfg; launch
  uses Proton-11 **builtin** d2d1 and drops leftover native PE. Empty
  `d2d1=` (2021 GDI) is wine exit 53. Wine `n` is native and kept the
  6im0n Wine-11 d2d1 mapped (white). Stay on GE-Proton11-3.

Photoshop 2021 quit ladder stays in `core/recipe-photoshop-cleanup.sh` (v1.1.48).
`steam_proton` is Proton-GE WM_CLASS, not the Steam client.

## Findings (sandbox cut)

Fixed on `dev/recipe-sandbox` (not on main until Benny says it works):

- Kill/uninstall is prefix-scoped (`recipe_kill::pkill_pat` / `uninstall_stop`).
  Patterns live in `recipe.yml` (`kill_patterns` / `launch_process_patterns`).
- Halo Steam stop is gated by `steam_stop_for_config: true` on that recipe only
  (Steam has one client; shortcuts.vdf rewrite needs it down).
- `core/prefix.sh` no longer `pkill wineserver`.
- Portable GUI copy uses generic keys; WISO keeps its own keys in `recipe.yml`.
- Add-only is in Authoring, ENTWICKLER, RECIPES. App-link table uses `source_env`.
- Home: no “Zuletzt” list. Links split into Projekt vs Online-Doku; Phials and
  6im0n cards added.
- Sidebar/detail UX (home cut): collapsible category headers (persisted in
  settings), compact status pills on cards (not dots), search above Home with
  Ctrl+F hint, quieter header watermark, AA path/status text, 16px menu icons,
  danger-colored Uninstall. Brand tokens only (Fluent Dark + Kupfer).
- Header has no `health_chip`. Validate hints stay in the sidebar
  „Hinweis“ pill, Home attention count, and Mehr → Hinweise dialog.
- Progress tab colors: Kupfer only for the **active** step, bar, and spinner.
  Done / idle / info use parchment secondary + FA info (no GitHub blue).
  Errors stay the danger token. No second orange-brown.
- Header watermark: one right-edge path for home + every recipe. Size is
  expand-crop again (fills header height, right ~44% band). Clip uses
  QFrame#headerCard 8px (Fluent CardWidget synced to 8). Opacity ~13%.
- Lightroom “not active after launch”: previous wait/wine64/PE-alias cut was
  not the cause. Runtime log `exit=53` is Wine mapping `c0000135`. Debug:
  `err:module:import_dll Library mfc140u.dll … substrate.dll` not found.
  `recipe_vcrun::ensure` treated CRT (`msvcp140`) as enough and skipped MFC.
  Adobe’s bundled vcredist also failed (manifest 0x80040111). Fix: unpack
  `mfc140u.dll` from Microsoft `vc_redist.x64.exe` (cabextract), validate /
  repair / launch self-heal, fail fast on c0000135 (no 2 min wait).
- Lightroom Quit (this cut): prefix-scoped graceful stop in
  `core/recipe-lightroom-cleanup.sh`. WM close (`wmctrl -ic`) → wait → soft
  stop → force CEF / Crash Processor / CRLogTransport in this prefix.
  `wineserver -k` only after Lightroom.exe is gone. Thin
  `cleanup-orphans.sh` for the launcher filename hook. Photoshop 2021 ladder
  untouched.
- Photoshop 2026 “does not start” (2026-08-18 13:34 / 13:55 / 14:16):
  empty `d2d1=` and drop-only (no prefix `system32/d2d1.dll`) both
  wine exit **53** in ~4s, no Adobe init, no HWND. Launch log
  `launch_photoshop-2026_f9af8b49.log` / runtime 14:16. Launcher
  “not active” is that crash, not a wait/pattern false negative.
  13:19 with `d2d1=n` did start (white) because Wine `n` = native and
  maps still had the 6.1MB 6im0n Wine-11.10 PE. Fix: `d2d1=builtin`
  plus copy Proton-11 builtin PE into prefix system32 (do not leave
  a hole). Exit 53 is a hard fail (no 2 min wait). Stay on
  **GE-Proton11-3**. Phials #3 is a 20px OWL.MenuBar strip via Wine
  `nc_paint` (hide-helper / their Wine binary). We do not take that
  Wine. Live 14:38 with builtin d2d1 + DXVK v3: HWND open, client
  **100% white**. UXP loaded `com.adobe.ccx.start` after home=off,
  then `createWebView` failed. Live 17:57 park of `ccx.*` +
  EdgeWebView + CEPHtmlEngine sat on disk (UXP dir mtime 17:57:13).
  UXP still opened `com.adobe.ccx.start.disabled` and createWebView
  failed again. Client stayed 100% white. WebView overlay is not
  the fill. Live 18:56: `dvaui.Direct2D=false` was written
  (`Adobe/PS/27.7/Debug Database.txt`, log `Drover D2D off`)
  before launch. HWND `0x03800007` client 100% white (`import`).
  Process still mapped Proton-11 `d2d1`, DXVK `d3d11`/`dxgi`,
  Wine `dcomp`. Lightroom leftover
  `dxgi.enableDummyCompositionSwapchain = True` sat in
  `dxvk.conf`. Next lever: dummy composition **off** (2021 has
  no dummy; Phials d2d1 geometry-realization / `nc_paint` stay
  out). 2021 / Lightroom untouched. Beenden, then Launch.
  Do not Launch while Updating.

Still open (not a code hole in this cut):

- Lightroom Classic: installed on this machine (`/mnt/ssd2/Software/Lightroom`).
  Start works (mfc140u). Live Quit still needs one GUI Beenden: no leftover
  CEF / Crash Processor / CRLogTransport, next Start ok.
- Photoshop 2026: `/mnt/ssd2/Software/PS 2026 Test` (`data_root.path`).
  ProductVersion `27.7.0.11`. Git launcher: no GUI restart (launch.sh is
  re-read). Beenden, then Launch once. Runtime log must show
  `Graphics: GE-Proton11-3`, `d2d1=builtin`,
  `dummy-composition=off`, `Drover D2D off`.
  Prefix `dxvk.conf`: `enableDummyCompositionSwapchain = False`.
  Debug DB still has `dvaui.Direct2D` false. d2d1 stays Proton-11
  builtin, not 6im0n. Live session at 18:56 still open (do not
  kill for a screenshot). Do not Launch while Updating.
- Photoshop #10: reporter confirmed v1.1.48. Rare live stall (window gone, EXE
  still up) is why the ladder has a soft `taskkill` before force. Issue stays
  open until Benny says close it.
- Isolation lint flags quoted recipe IDs in shared files. Function names like
  `photoshop::find_exe` are namespaces, not ID lists. That is the intended
  scope, not a broken guard.

## Open work

- Latest released: **v1.1.48** (Photoshop Quit #10 exit ladder, Lightroom Classic recipe).
  Prototype 1.5.x + remote-asset MEGA/SHA-256 ships as **v1.1.49**.
- **Photoshop stalls on exit now and then** (once in four live runs): window gone,
  `Photoshop.exe` alive, prefs never written. The ladder therefore sends a soft
  Wine `taskkill` (WM_CLOSE) before forcing. Cause unknown — if the reporter
  still sees amnesia, this is the thread to pull.
- **Photoshop Quit verified live 2026-08-15** on the relocated prefix
  `/mnt/ssd2/Software/Photoshop 20.0.0.35` (Wayland session): `kill.sh` ran 11s,
  Photoshop exited on its own without force, `Adobe Photoshop 2021 Prefs.psp`
  was rewritten at exit, no Adobe helper survived, Steam stayed open. Note the
  window class there is `steam_proton`, not Photoshop — matching works through
  `_NET_WM_PID`, so never rely on the class alone.
- **Photoshop Quit (#10), the rule to keep:** close windows via `wmctrl -ic`
  (`_NET_CLOSE_WINDOW`), never `xdotool windowclose`. windowclose destroys the X
  window, so Photoshop keeps running with no window and never writes prefs.
  After the window is gone: wait `PHOTOSHOP_EXIT_WAIT_S` (45s), then soft
  `taskkill` for `PHOTOSHOP_EXIT_SOFT_S` (20s), only then force.
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
- Recipe `lightroom-classic` (15.4.1, LTRM): Start works on this machine after
  the mfc140u fix. Quit ladder is in `core/recipe-lightroom-cleanup.sh` (plus
  thin `cleanup-orphans.sh`). Live Beenden still untested. Adaptiert von
  [6im0n/lightroom-classic-on-linux](https://github.com/6im0n/lightroom-classic-on-linux)
  (MIT, Danksagung in `info.*.txt`). Module:
  `core/recipe-lightroom-{stubs,install,launch,cleanup}.sh`.
  **Nie** winewayland (LrC crasht) — Launch erzwingt X11.
  Bekannte Lücken: HDR upstream nicht unterstützt, KI-Entrauschen ungeprüft.
  First start can still take 1–2 min after MFC is present.
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
- **Prototype 1.5.x (Rezept):** `recipes/prototype/`. Quelle
  `/home/benny/Downloads/Prototype-AnkerGames/` (8,4 GB, Steamless-Dump,
  `prototypef.exe` 32-bit DX9). Prefix
  `~/.local/share/wine-software/prototype` (Link auf den Dump).
  Medizin **Mod-Bundle 1.5.0** (Default an). PrototypeFix 1.8 +
  `binkw32Hooked.dll` + DXVK Prefix-d3d9 + LAA + Proton 11 bleiben.
  **ReShade ist nicht im Bundle** (keine DLL, keine Shader, kein Overlay).
  Repair räumt alte Reste neben der EXE (`ReShade32.dll`, Game-Dir-d3d9/dxgi).
  **Wings/Continue-Lua ist nicht im Bundle** (`init.lua` / `wings.lua` /
  `wings.p3d` / `enable_dlc.rcf` gelöscht). Parkour 1.2 ist nur
  `art/startup_fig.p3d`, nicht dieses Lua.
  **Assets:** kleines Overlay (PrototypeFix, ASI, p3d, Trainer-EXE) liegt
  in Git. Deutsch-Patch-ZIP (~942 MB) und TexMod-`.tpf` nicht in Git —
  Hashes in `assets/mod-bundle/remote.yml`. MEGA-Basis:
  `core/recipe-assets.lock` / Settings `mega_assets_base_url`. Der
  Maintainer-Ordner `https://mega.nz/fm/…` ist File-Manager, **kein**
  öffentlicher Share. Bis ein `/folder/` oder `/file/` + Key existiert:
  Download nur aus `~/Downloads` oder Cache. Publish:
  `make recipe-assets-publish` (mega-cmd Login).
  Neu: Deutsch-Patch Bollwurf v1.0–1.3 als lose p3d (Cache
  `~/.local/share/wine-software/cache/prototype-mod-bundle/deu-overlay/`,
  ~1,2 GB, nicht Git; Seed aus `~/Downloads/Prototype_DeuPatchBEP.zip`).
  Default Sprache DE: Bollwurf-Dateien nach `textbible_german.p3d` +
  `fe_textbible` id `german` + `protostart.gfx` „DRUECKEN SIE ENTER“ +
  `FE_Language=68`. Dump hat nur EN/FR/IT/ES in `art.rcf`, Audio nur english.
  Medizin `PROTOTYPE_LANGUAGE`: de (Default) / standard / fr / it / es.
  FR/IT/ES = Dump-Packs, Patch weg. Kein RU. FE=70 allein ließ den Titel
  auf APPUYEZ (French-Chrome). vcdiff-Miss auf Steamless nur ins Log,
  keine GUI-Warnung.
  Standard-Skin Default (Vanilla, keine AzimCrew-p3d), Venom/Anti-Venom extra,
  gleicher Slot (`PROTOTYPE_SKIN`). Sprache Default Deutsch, Standard = Original-Dump.
  Sprint Light Attack Fix vorinstalliert.
  **Parkour 1.2 Balanced Default an** (`PROTOTYPE_PARKOUR`): nur
  `art/startup_fig.p3d`, kein Lua/ASI — Continue bleibt. Sprint-Fix bleibt
  `.p3d.rz`. TexMod-.tpf nicht injiziert.
  **100%-Spielstand Default aus** (`PROTOTYPE_SAVE_100`):
  `Documents/Prototype/` im Prefix (nicht Activision/). Backup nach
  `rezeptor-save-backup/` vor dem Überschreiben.
  **PS3-Tasten Default aus** (`PROTOTYPE_PS3_BUTTONS`).
  Trainer Locke: `GAME_DIR/rezeptor-trainer/prototype.v1001.p7trn.exe` und
  `~/.local/share/wine-software/prototype/trainer/` für den GUI-Button
  „Trainer starten“ (Spiel muss laufen). **Kein** Auto-Inject.
  RAiN ResChanger nur in `tools/` (verliert gegen `force_desktop_res` 1080p
  windowed). No-Intro, kein d3d9-Wrap neben der EXE.
  Extra-Rezeptor zu, Beenden, Reparieren (muss 1.5.0 legen), Starten, Continue.
  Beweis: keine `ReShade32.dll` / `init.lua` neben der EXE. Pos1 tot.
- Product backlog: Proton-GE management UI, exception→diagnose zip CTA, Snapshot/Restore.

## Halo recipe assets (public)

Under `recipes/halo-campaign-evolved/assets/` only runtime/product files belong
(Steam helper, intro clip, Steam grid). Analysis guides and GDB/Ghidra scripts do **not**.
