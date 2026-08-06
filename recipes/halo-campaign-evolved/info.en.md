# Halo Campaign Evolved

Tested pack: **Halo.Campaign.Evolved.Premium.Edition.MULTi13-ElAmigos** (g4u / ElAmigos).

Offline installer on Proton-GE: mount ISO → `setup.exe` (silent) → optional numbered updates.

## What this recipe solves

The game wants to sign in with an Xbox / Microsoft account at startup. This recipe sets everything up so that **no sign-in is needed** — the campaign runs offline.

On Linux there was a second hurdle: the game ships a **newer Microsoft runtime** than the one a Wine prefix normally ends up with. With the older version the game crashed the moment it tried to sign in. Rezeptor now installs the matching version automatically from the redist folder that comes with the game. Nothing to do for you — install or repair takes care of it.

## Steam

- **Steam does not have to be installed.** The pack brings its own Steam replacement layer and runs offline.
- **Optional Medizin “Launch via Steam”:** Rezeptor registers a Non-Steam shortcut and starts via the client (prefix stays Rezeptor’s). Steam is only stopped when the shortcut is missing or must be rewritten — not on every launch.
- Without Steam medicine: **quit Steam first** (including `steamwebhelper`), or the offline RUNE start can collide with Steam.

Check: `pgrep -x steam` / `pgrep -x steamwebhelper`.

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

Under **Medizin**:

- **Quality preset** (`HALO_GFX_PRESET`): Very low → Ultra. Default **Recommended (RTX 2060 / 1080p144)** — sharp and fluid; soft VRAM caps on. Ultra skips soft caps.
- Individual toggles (**clear image**, **low-latency**, **VRR**, **gamescope**, **force 6 GB caps**) stay fine-tuning above the preset.
- **Launch via Steam** (optional): Non-Steam “… (Rezeptor)” shortcut with Proton choice and Steam grid art; soft low-latency under Steam. Needs `python-vdf`.

Always on: MSVC runtime, RUNE, real `libHttpClient`. Default remains **original mode** without forced Lumen HWRT CVars (black-screen trap under Proton).

**Shorten intro:** replaces only `LogoParade.mp4` with a valid short black video — `Splash.bmp` is left alone (fake stubs crash at launch).

Community mods are **not shipped** (BYOS). Drop folder:

`<data root>/mods/` (default: `~/.local/share/wine-software/halo-campaign-evolved/mods/`)

A `README.txt` there lists the layout (`ue4ss/`, `viewmodels/`, …). Enable the option → **Repair** or **Start**.

**Unlock all skulls:** before first enable, the save is backed up under `backups/`.

**Trainer (optional):** Rezeptor does not ship trainers. Tested: **`Halo.Campaign.Evolved.v1.0-v20260729.Plus.16.Trainer-FLiNG`**. In Medizin use the folder icon to pick the `.exe` or a trainer folder (copied into `<data root>/trainer/`) — or drop files there manually. Enable **“Launch trainer with the game”** → on Launch the trainer opens after a few seconds in the **same** Wine prefix. Other trainers allowed, no guarantee.

## Notes

- **Shader loading** (“STARTING MJOLNIR SYSTEMS” / progress bar on the main menu): normal, especially on first launch or after a graphics/driver change. Can take **several minutes** — don’t quit the game or it starts over. Then wait 1–2 minutes on the menu before starting a mission (fewer hitches while moving).
- **Graphics / input:** Preset sets the quality ladder; **clear image** turns junk effects off only. **Lower input latency** (default on): winewayland / soft LL under Steam, vkd3d frame queue, FPS near Hz. Log: `Preset=…`, `winewayland.drv aktiv`, `gamescope`, or Steam shortcut AppID. No window → turn options off, or try Plasma X11.
- Xbox/XAL sign-in always runs **inside the game process** (`SteamDeck=1`) — required under Proton, not a Medizin toggle.
- The ISO is **mounted** (no full extract of ~66 GiB); the same volume is reused (no triple mounts).
- Setup runs silently (Inno `/VERYSILENT` + `/LANG` + `/DIR=`). Cancel does not spawn extra installer windows.
- **Nickname / game language:** Silent install skips the ElAmigos wizard. After install, Rezeptor can open the game folder so you can edit configs (or set them in-game after first launch).
- The game binary itself is **never modified**. Everything happens in the Wine prefix and in configuration files.
- BYOS: Rezeptor provides no download links — pack title is in the source dialog under “What to search for”.
