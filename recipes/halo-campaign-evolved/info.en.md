# Halo Campaign Evolved

Tested pack: **Halo.Campaign.Evolved.Premium.Edition.MULTi13-ElAmigos** (g4u / ElAmigos).

Offline installer on Proton-GE: mount ISO → `setup.exe` (silent) → optional numbered updates.

## What this recipe solves

The game wants to sign in with an Xbox / Microsoft account at startup. This recipe sets everything up so that **no sign-in is needed** — the campaign runs offline.

On Linux there was a second hurdle: the game ships a **newer Microsoft runtime** than the one a Wine prefix normally ends up with. With the older version the game crashed the moment it tried to sign in. Rezeptor now installs the matching version automatically from the redist folder that comes with the game. Nothing to do for you — install or repair takes care of it.

## Steam

- **Steam does not have to be installed.** The pack brings its own Steam replacement layer and runs offline.
- **If Steam is installed, quit it first** — completely, including the background process `steamwebhelper`. Otherwise the launch stops with a message. This is the most common pitfall.

You can check in a terminal with `pgrep -x steam` and `pgrep -x steamwebhelper` — neither may print anything.

## Source and target

- **Source:** Pack folder with the ISO, **or** the ISO file — do not rename files
- Optional under the source: `updates/` with `1 - …/` (also `updates/<Name>/1 - …/`)
- Or separate update field / **More → Apply update**
- **Target:** free folder on a drive with enough space. The Windows installer writes the game under `prefix/drive_c/Games/…` (Wine). Rezeptor also creates a visible **`HaloCampaignEvolved/`** folder in the target (link to the same tree) — that is where the game files appear when you open the target. Alongside: `prefix/`, `recipe.env`, optional `mods/`.

## Updates

See [UPDATES.md](UPDATES.md). ElAmigos packs: folder `1 - Halo … update …/` with `.exe` + `elamigos-1.bin`.

## Co-op / online

**Online co-op is not possible with this install.** Shared campaign mode depends on Halo online services and needs a real signed-in account with a purchased copy. This recipe deliberately runs without sign-in — that is why single-player campaign starts reliably offline.

Community “GDK / OnlineFix” packs target the Microsoft Store build (AppX / Developer Mode) and do not work under Proton. “Install Spacewar” notes from some guides do not apply to that package.

**Local splitscreen** on the same machine may work (second controller, fireteam in the menu) — no extra files, no Steam. That is not online co-op.

## Mods & graphics (Medizin)

Under **Medizin** you can choose optional graphics presets and mods before launch. Always on: MSVC runtime, RUNE, real `libHttpClient`. Default is **original mode** (no forced Lumen/HWRT CVars) — those caused a black screen/crash after the intro under Proton. Only enable graphics options if you need them.

Community mods are **not shipped** (BYOS). Drop folder:

`<data root>/mods/` (default: `~/.local/share/wine-software/halo-campaign-evolved/mods/`)

A `README.txt` there lists the layout (`ue4ss/`, `viewmodels/`, …). Enable the option → **Repair** or **Start**.

**Unlock all skulls:** before first enable, the save is backed up under `backups/`.

**Trainer (optional):** Rezeptor does not ship trainers. Tested: **`Halo.Campaign.Evolved.v1.0-v20260729.Plus.16.Trainer-FLiNG`**. In Medizin use the folder icon to pick the `.exe` or a trainer folder (copied into `<data root>/trainer/`) — or drop files there manually. Enable **“Launch trainer with the game”** → on Launch the trainer opens after a few seconds in the **same** Wine prefix. Other trainers allowed, no guarantee.

## Notes

- **Shader loading** (“STARTING MJOLNIR SYSTEMS” / progress bar on the main menu): normal, especially on first launch or after a graphics/driver change. Can take **several minutes** — don’t quit the game or it starts over. Then wait 1–2 minutes on the menu before starting a mission (fewer hitches while moving).
- **Graphics / mouse:** Medizin **Clear image** = junk effects off only; quality stays around **Medium** (not Very Low). **Lower mouse latency** (default on): enables the real **winewayland** driver (no XWayland — that was the main lag on KDE), plus Engine.ini lock, Reflex/NVAPI, FPS cap near monitor Hz. Launch log should say `winewayland.drv aktiv`. If the window never appears: turn the option off, or try a Plasma X11 session.
- Xbox/XAL sign-in always runs **inside the game process** (`SteamDeck=1`) — required under Proton, not a Medizin toggle.
- The ISO is **mounted** (no full extract of ~66 GiB); the same volume is reused (no triple mounts).
- Setup runs silently (Inno `/VERYSILENT` + `/LANG` + `/DIR=`). Cancel does not spawn extra installer windows.
- **Nickname / game language:** Silent install skips the ElAmigos wizard. After install, Rezeptor can open the game folder so you can edit configs (or set them in-game after first launch).
- The game binary itself is **never modified**. Everything happens in the Wine prefix and in configuration files.
- BYOS: Rezeptor provides no download links — pack title is in the source dialog under “What to search for”.
