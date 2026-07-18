# Photoshop GPU experiments (Rezeptor)

Controlled matrix in the **existing** Proton prefix. Default stays **stable**. Steam is not part of this step.

See also: [HANDOFF-PHOTOSHOP-GPU.md](HANDOFF-PHOTOSHOP-GPU.md)

## Profiles

| Profile | PS GPU | OpenCL | Purpose |
|---------|--------|--------|---------|
| `stable` | off | off | Kill switch / default |
| `dxvk_ui_only` | off | off | same as stable (documented) |
| `ps_gpu_no_opencl` | on | off | experiment |
| `ps_gpu_full` | on | on | expected fail candidate |

Files: `recipes/photoshop/assets/gpu-profiles/<name>/`

## Apply

```bash
# List + active profile
bash scripts/photoshop-gpu-profile.sh

# Experiment
bash scripts/photoshop-gpu-profile.sh ps_gpu_no_opencl
# Rezeptor → Start → tests below

# Kill switch (immediately on fail)
bash scripts/photoshop-gpu-profile.sh stable
```

Or once via env (without permanently setting the flag — the flag is written on apply):

```bash
REZEPTOR_PS_GPU_PROFILE=ps_gpu_no_opencl bash recipes/photoshop/launch.sh
```

Launch/repair self-heal reads `~/.local/share/wine-software/photoshop/gpu-profile.active` and **does not silently overwrite experiments** with stable — unless the flag is `stable` / missing.

## Test protocol (per profile, ~5 min)

Prerequisite: Photoshop **quit**.

1. `bash scripts/photoshop-gpu-profile.sh <profile>`
2. Rezeptor → **Start**
3. Checks:
   - [ ] Window visible (no blue virtual desktop)
   - [ ] **File → New** (no program error)
   - [ ] Text tool: type, anti-alias not “None”
   - [ ] Zoom **100%** — text subjectively better/same/worse
4. Record result in table
5. On fail: immediately `bash scripts/photoshop-gpu-profile.sh stable` → quit → start

## Results

| Date | Profile | New | Text tool | Text @100% | Note |
|------|---------|-----|-----------|------------|------|
| 2026-07-09 | stable | OK | OK | softer than native | Baseline |
| | dxvk_ui_only | | | | |
| | ps_gpu_no_opencl | | | | |
| | ps_gpu_full | | | | |

*(Fill rows after manual tests.)*

## Out of scope for this step

- Steam non-Steam / compatdata
- Permanently enabling GPU as default without green matrix results
