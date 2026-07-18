# Photoshop GPU-Experimente (Rezeptor)

Kontrollierte Matrix im **bestehenden** Proton-Prefix. Default bleibt **stable**. Steam ist nicht Teil dieses Schritts.

Siehe auch: [HANDOFF-PHOTOSHOP-GPU.md](HANDOFF-PHOTOSHOP-GPU.md)

## Profile

| Profil | PS-GPU | OpenCL | Zweck |
|--------|--------|--------|-------|
| `stable` | aus | aus | Kill-Switch / Default |
| `dxvk_ui_only` | aus | aus | wie stable (dokumentiert) |
| `ps_gpu_no_opencl` | an | aus | Experiment |
| `ps_gpu_full` | an | an | Fail-Kandidat |

Dateien: `recipes/photoshop/assets/gpu-profiles/<name>/`

## Anwenden

```bash
# Liste + aktives Profil
bash scripts/photoshop-gpu-profile.sh

# Experiment
bash scripts/photoshop-gpu-profile.sh ps_gpu_no_opencl
# Rezeptor → Starten → Tests unten

# Kill-Switch (sofort bei Fail)
bash scripts/photoshop-gpu-profile.sh stable
```

Oder einmalig per Env (ohne Flag dauerhaft zu setzen — Flag wird beim Apply geschrieben):

```bash
REZEPTOR_PS_GPU_PROFILE=ps_gpu_no_opencl bash recipes/photoshop/launch.sh
```

Launch/Repair Self-Heal liest `~/.local/share/wine-software/photoshop/gpu-profile.active` und **überschreibt Experimente nicht still** mit stable — außer das Flag ist `stable` / fehlt.

## Testprotokoll (pro Profil, ~5 Min)

Voraussetzung: Photoshop **beendet**.

1. `bash scripts/photoshop-gpu-profile.sh <profil>`
2. Rezeptor → **Starten**
3. Checks:
   - [ ] Fenster sichtbar (kein blauer VD)
   - [ ] **Datei → Neu** (kein Programmfehler)
   - [ ] Text-Tool: Tippen, Anti-Alias nicht „Ohne“
   - [ ] Zoom **100 %** — Text subjektiv besser/gleich/schlechter
4. Ergebnis in Tabelle eintragen
5. Bei Fail: sofort `bash scripts/photoshop-gpu-profile.sh stable` → Beenden → Starten

## Ergebnisse

| Datum | Profil | Neu | Text-Tool | Text @100% | Notiz |
|-------|--------|-----|-----------|------------|-------|
| 2026-07-09 | stable | OK | OK | weicher als nativ | Baseline |
| | dxvk_ui_only | | | | |
| | ps_gpu_no_opencl | | | | |
| | ps_gpu_full | | | | |

*(Zeilen nach manuellen Tests ausfüllen.)*

## Nicht in diesem Schritt

- Steam Non-Steam / compatdata
- Dauerhaft GPU an als Default ohne grüne Matrix-Ergebnisse
