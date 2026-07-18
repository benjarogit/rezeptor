# Steam wrapper recipes

Pattern for Steam games with **BYOS** (Bring Your Own Source): Rezeptor does not distribute the game or online fix.
Reference recipe: `house-of-ashes` — see also `recipes/_template-steam-game/`.

## Principle

1. The game stays in your **normal Steam library** (real AppID, e.g. `1281590`).
2. Rezeptor does **not** add a Steam library entry or modify Steam.
3. **Install** links the game folder (`deploy_mode: link`), verifies fix files, and writes a **launch wrapper** under `~/.local/share/wine-software/<id>/`.
4. **Start** in Rezeptor runs the EXE via **Rezeptor Proton-GE** (fallback: Steam GE-Proton) — not Steam UI “Play”.

## Spacewar / FakeAppId

Many online fixes expect `SteamAppId=480` (**Spacewar**, free Valve tool).

| Term | Meaning |
|------|---------|
| **RealAppId** | The game’s real Steam app (compatdata prefix) |
| **FakeAppId** | Usually `480` — Steam API for the fix |
| **compatdata** | Steam Proton prefix for the game; Rezeptor reuses it, no new prefix |

Typical requirements:

- Steam running and signed in
- Spacewar for **launch** (not for setup alone): `steam steam://install/480` — setup opens the Steam dialog and does not block installation
- Game launched at least once via Steam with Proton/GE (compatdata present)
- Fix stack in the game folder (BYOS — Rezeptor does not ship a fix)

While playing, Steam often shows **Spacewar**, not the game title.

## Wrapper contents (simplified)

The wrapper sets among other things:

- `SteamAppId` / `SteamGameId` = FakeAppId
- `STEAM_COMPAT_DATA_PATH` = compatdata of the RealAppId
- `WINEDLLOVERRIDES` for OnlineFix DLLs
- Proton script: Rezeptor GE → Steam GE-Proton

Details: `recipes/house-of-ashes/launch.sh`, `recipes/_template-steam-game/install.sh`.

## Uninstall

**Uninstall** in Rezeptor only removes:

- Rezeptor entry and state
- Launch wrapper under `data_root`

**Not** removed:

- The Steam game
- The online fix in the game folder
- Spacewar in your library

See `recipes/house-of-ashes/uninstall.sh`.

## New Steam game recipe

```bash
./scripts/new-recipe.sh --type steam-game my-game "My Game"
```

Adjust `steam_appid`, `steam_fake_appid`, fix paths, and `exe_glob` in `recipe.yml`.
