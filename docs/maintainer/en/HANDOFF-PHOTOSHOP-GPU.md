# Handoff — Photoshop under Rezeptor (GPU)

Status: 2026-07-09. Runtime: **Proton-GE only** (`GE-Proton10-28`). Prefix: `~/.local/share/wine-software/photoshop/`.

## What works (stable)

- Photoshop starts visibly (no virtual desktop)
- **New** and text tool OK when Photoshop GPU/OpenGL **off**
- DXVK deployed for startup/UI; PS-internal GPU prefs off
- Text script `Rezeptor-Text-Glatt` + autostart; `WarnRunningScripts 0`
- WISO: Segoe → Calibri/Tahoma, ClearType contrast 1400

## Desired

- Photoshop **with GPU** smooth + sharp canvas text (as remembered “before”)
- Text UI/canvas not pixelated; export ≈ screen

## Problematic

1. Photoshop “graphics processor” **on** → often program error on New/text (live verified)
2. Canvas text without PS GPU softer than native (zoom &lt; 100% worsens under Wine)
3. Hardware GPU ≠ Photoshop GPU toggle (see below)

## Separation (common misunderstanding)

| Layer | Meaning |
|-------|---------|
| Hardware (RTX 2060) | present; DXVK/Wine uses it |
| Photoshop GPU/OpenGL/CL | problematic path under Wine |

## Already tested (short)

| Attempt | Result |
|---------|--------|
| OpenGL on, no VD | program error on New |
| OpenGL on + virtual desktop | still fail |
| GPUForce 0 + OpenGL off | New/text OK |
| wined3d + GPU on | slow / text errors; stayed pixelated |
| FontSmoothingContrast 106 | thin UI → back to **1400** |
| Segoe → Times | WISO unreadable → **Calibri** |
| Anti-alias “None” | intentionally pixelated |
| Community isatsam/albakhtari | GPU on often breaks New; tooltips off |

## Stable target config

- `PSUserConfig.txt`: `GPUForce 0`, `UseOpenCL 0`, `AllowGPU 0`, `DisableNativeCanvas 1`, `WarnRunningScripts 0`
- MachinePrefs: OpenGL/nativeGPU/… off
- UIPrefs: legacy New on, tooltips off
- Launch: `desktop=n`, DXVK, gdiplus native

## Next focus

Controlled **GPU matrix** in the same prefix — see [GPU-EXPERIMENTS.md](GPU-EXPERIMENTS.md). Steam only later as comparison if matrix does not stabilize GPU-on.

## Kill switch

```bash
REZEPTOR_PS_GPU_PROFILE=stable bash recipes/photoshop/repair.sh
# or:
bash scripts/photoshop-gpu-profile.sh stable
```
