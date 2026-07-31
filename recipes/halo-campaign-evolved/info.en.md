# Halo Campaign Evolved

Tested pack: **Halo.Campaign.Evolved.Premium.Edition.MULTi13-ElAmigos** (g4u / ElAmigos).

Offline installer on Proton-GE: mount ISO → `setup.exe` (silent) → optional numbered updates.

## Source

- Pack folder with the ISO, **or** the ISO file — do not rename files
- Optional under the source: `updates/` with `1 - …/` (also `updates/<Name>/1 - …/`)
- Or separate update field / **More → Apply update**

## Updates

See [UPDATES.md](UPDATES.md). ElAmigos packs: folder `1 - Halo … update …/` with `.exe` + `elamigos-1.bin`.

## Notes

- The ISO is **mounted** (no full extract of ~66 GiB); the same volume is reused (no triple mounts).
- Setup runs silently (Inno `/VERYSILENT` + `/LANG` + `/DIR=`). Cancel does not spawn extra installer windows.
- **Nickname / game language:** Silent install skips the ElAmigos wizard. After install, Rezeptor can open the game folder so you can edit configs (or set them in-game after first launch).
- BYOS: Rezeptor provides no download links — pack title is in the source dialog under “What to search for”.
