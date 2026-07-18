# Handoff — Photoshop unter Rezeptor (GPU)

Stand: 2026-07-09. Runtime: **nur Proton-GE** (`GE-Proton10-28`). Prefix: `~/.local/share/wine-software/photoshop/`.

## Was funktioniert (stabil)

- Photoshop startet sichtbar (kein Virtual Desktop)
- **Neu** und Text-Tool OK, wenn Photoshop-GPU/OpenGL **aus**
- DXVK für Start/UI deployt; PS-interne GPU-Prefs aus
- Text-Skript `Rezeptor-Text-Glatt` + Autostart; `WarnRunningScripts 0`
- WISO: Segoe → Calibri/Tahoma, ClearType Contrast 1400

## Gewünscht

- Photoshop **mit GPU** flüssig + scharfer Canvas-Text (wie „früher“ erinnert)
- Text UI/Canvas nicht pixelig; Export ≈ Bildschirm

## Problematisch

1. Photoshop „Grafikprozessor“ **an** → oft Programmfehler bei Neu/Text (live belegt)
2. Canvas-Text ohne PS-GPU weicher als nativ (Zoom &lt; 100 % verschärft unter Wine)
3. Hardware-GPU ≠ Photoshop-GPU-Schalter (siehe unten)

## Trennung (Missverständnis)

| Ebene | Bedeutung |
|-------|-----------|
| Hardware (RTX 2060) | vorhanden; DXVK/Wine nutzt sie |
| Photoshop GPU/OpenGL/CL | problematischer Pfad unter Wine |

## Bereits getestet (kurz)

| Versuch | Ergebnis |
|---------|----------|
| OpenGL an, kein VD | Programmfehler bei Neu |
| OpenGL an + Virtual Desktop | weiterhin Fail |
| GPUForce 0 + OpenGL aus | Neu/Text OK |
| wined3d + GPU an | langsam / Text-Fehler; pixelig blieb |
| FontSmoothingContrast 106 | UI dünn → zurück **1400** |
| Segoe → Times | WISO unleserlich → **Calibri** |
| Anti-Alias „Ohne“ | absichtlich pixelig |
| Community isatsam/albakhtari | GPU an bricht oft Neu; ToolTips aus |

## Stabile Soll-Config

- `PSUserConfig.txt`: `GPUForce 0`, `UseOpenCL 0`, `AllowGPU 0`, `DisableNativeCanvas 1`, `WarnRunningScripts 0`
- MachinePrefs: OpenGL/nativeGPU/… aus
- UIPrefs: Legacy-Neu an, ToolTips aus
- Launch: `desktop=n`, DXVK, gdiplus native

## Nächster Fokus

Kontrollierte **GPU-Matrix** im gleichen Prefix — siehe [GPU-EXPERIMENTS.md](GPU-EXPERIMENTS.md). Steam nur später als Vergleich, falls Matrix GPU-an nicht stabil macht.

## Kill-Switch

```bash
REZEPTOR_PS_GPU_PROFILE=stable bash recipes/photoshop/repair.sh
# oder:
bash scripts/photoshop-gpu-profile.sh stable
```
