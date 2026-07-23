# Premiere Pro installation files (user-provided)

This directory holds **your** Adobe Premiere Pro 2024 offline installer. This repository does **not** include Adobe files.

## Required structure

```
premiere/
├── Set-up.exe
├── packages/
└── products/
    ├── Driver.xml   # or driver.xml
    └── PPRO/
        └── application.json
```

Nested layouts (e.g. from ISO) also work:

```
premiere/
└── Adobe 2024/
    ├── Set-up.exe
    ├── packages/
    └── products/PPRO/…
```

Or place a single `*.iso` here — Rezeptor extracts it and finds `Set-up.exe`.

## Supported versions

| Status | Version |
|--------|---------|
| **Guaranteed** | Adobe Premiere Pro 2024 **v24.1.0.85** |
| Best effort | Other **v24.x** builds (community often cites 24.0.3.2) |
| Not supported | 2025+ Frontend/`Windows.Data.Json` failures without further work |

## Option 1: Offline installer (recommended)

1. Obtain a licensed Premiere Pro 2024 offline installer from Adobe (or extract an ISO to get `Set-up.exe` + `packages/`).
2. Copy the installer folder here so `premiere/Set-up.exe` or `premiere/Adobe 2024/Set-up.exe` exists.
3. Install via Rezeptor (or `REZEPTOR_DEV=1 ./setup.sh` → Premiere).

## Option 2: Custom installer path

```bash
export PREMIERE_INSTALLER_DIR=/path/to/folder/with-Set-up.exe
# or ISO:
export PREMIERE_INSTALLER_DIR=/path/to/Adobe\ Premiere\ Pro\ -\ 2024\ v24.1.0.85.iso
```

Or pick the folder/ISO in the Rezeptor GUI when installing.

## GPU: NVIDIA vs AMD / Intel

| Host GPU | What Rezeptor does | Expectation in Premiere |
|----------|--------------------|-------------------------|
| **NVIDIA** | Installs [SveSop/nvidia-libs](https://github.com/SveSop/nvidia-libs) into the Wine prefix (not into Proton) | Mercury can use **CUDA** / NVENC |
| **AMD (Radeon) / Intel** | Skips nvidia-libs | No CUDA — often **software** renderer only; DXVK/Vulkan still used for UI |

```bash
# disable CUDA stack on NVIDIA
export PREMIERE_NVIDIA_LIBS=0
# force even if detection fails
export PREMIERE_NVIDIA_LIBS=1
```

Then run **Repair** (or reinstall).

## Legal

You must own a valid Adobe license. This project only automates Wine/Proton setup on Linux.
