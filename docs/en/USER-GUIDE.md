# User guide

How to use the Rezeptor GUI. Recipe authors: see [Developer overview](ENTWICKLER.md).

## UI layout

| Element | Role |
|---------|------|
| **Sidebar** | Recipe list, status dot (warn icon only for partial / untrusted), search/order |
| **Main area** | Overview, source/target, info texts |
| **Primary CTA** | Context action (Install / Launch / Approve / **Repair now** / …) |
| **More ▾** | Secondary actions (Validate, Uninstall, …) |
| **Medizin** | Own button next to More — lasting recipe options (see below) |
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

## Medizin (recipe options)

The **Medizin** button (first-aid kit icon) sits next to **More** — not inside the More menu.

Lasting per-recipe toggles (`options.env`). Not installed: the choice applies on the next install. Installed with a stale overlay: **Repair** to apply.

### Photoshop (CC 2021)

Runs on **Proton-GE 11-3** (no Medicine toggle). Under Wine some Windows-like UI features are fragile. Rezeptor therefore applies safe prefs by default (no home screen, tooltips off, legacy New dialog). If the Windows-like UI is stable on your system, you can enable them individually:

| Option | Effect |
|--------|--------|
| Home screen | Like on Windows — if you get a white/empty workspace, turn off + Repair |
| Rich / animated tooltips | Can break Type tool / plugins |
| Modern New dialog | Large New dialog — can cause black fields / white canvas |

Defaults are **off**. Tips in the Medizin dialog have the same guidance.

### Halo Campaign Evolved

| Option | Effect |
|--------|--------|
| **Quality preset** (`HALO_GFX_PRESET`) | Ladder Very low → Ultra. Default **Recommended (RTX 2060 / 1080p144)** — high textures/geometry, medium Lumen/reflections, soft VRAM caps. Ultra skips soft caps (6 GB risk). |
| Clear image / low-latency / VRR / gamescope | Fine-tuning **above** the preset (effects, latency, present). |
| Force 6 GB VRAM caps | Caps even on Ultra; Recommended/Low/High already apply caps. |
| Launch via Steam | Non-Steam shortcut with chosen Proton + launch options; soft low-latency under Steam (no Tear/FinishCurrentFrame). Needs `python-vdf`. |
| Steam Proton | Steam default / system Proton / Rezeptor GE-Proton11-3. |
| Trainer / mods / skip intro | BYOS — see recipe info text. |

After changing preset/graphics: **Repair** or **Launch** once so `Engine.ini` / Halo-*UserSettings apply.

### Prototype

| Option | Effect |
|--------|--------|
| **Mod bundle** | Overlay 1.5.0: PrototypeFix, No-Intro, desktop pin, sprint fix, parkour (default on), German patch, standard skin. No ReShade (Home is dead). Continue Lua stays off. Trainer is under `rezeptor-trainer/` and `trainer/`, not launched with the game (button while running). Allagga/P2/Venom `.tpf` are TexMod and are not injected. On by default. |
| **Game language** | Choice German (default: patch files + `FE_Language=68`) / Standard / French / Italian / Spanish. Not an in-game setting, not the Rezeptor UI language. |
| **Skin** | Choice Standard (default, vanilla) / Venom / Anti-Venom. Same slot, not both. Then Repair or Launch. |
| **Parkour** | Default on. Loose `art/startup_fig.p3d` only (balanced). No Lua — Continue stays. |
| **Load 100% save** | Default off. Writes saves to prefix `Documents/Prototype`; backup first. |
| **PS3 buttons** | Default off. Xbox prompts → PS3. |

After toggling: **Repair**, then **Launch**. Git launcher: `install.sh` / `repair.sh` / `launch.sh` without a GUI restart; `recipe.yml` / `info.*` need a launcher restart.

## Status & validation

- Optional **validate on startup** (Settings)
- **F5** / Validate: structured `OK:` / `FAIL:` / `WARN:` output
- Green = tested / ready; amber = warning; error = action needed
- Sidebar warn icon = repair or trust approval needed — not for “not installed”

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
| **Uninstall** | `uninstall.sh` → `purge_recipe_data` (desktop + data_root + asset cache) |

Details: [Uninstall](UNINSTALL.md) · [Catalog](CATALOG.md)

## Updates

Releases from GitHub; auto-update where offered. After a manual download, verify assets with `sha256sum`.

## Help & bugs

- In-app: **Help → Developer documentation…** (author pages)
- GitHub issues / bug-report template (clipboard may hold the full report body)
- Report file under `~/.local/share/wine-software/logs/github-report_*.txt` (sanitized; includes recent install/winetricks logs when present)
- Session ID is in the report file, not the status bar

## Next

- [Quick start](GETTING-STARTED.md)
- [Trust & manifest](TRUST.md)
- [GUI launcher (technical)](LAUNCHER.md)
