# Photoshop installation files (user-provided)

This directory holds **your** Adobe Photoshop CC offline installer. This repository does **not** include Adobe files.

## Required structure

```
photoshop/
├── Set-up.exe
├── packages/
└── products/
    ├── Driver.xml
    └── PHSP/
        └── */Application.json
```

## Supported versions

| Status | Version |
|--------|---------|
| **Guaranteed** | Adobe Photoshop CC 2021 **v22.0.0.35** |
| Best effort | Other **v22.x** builds |
| Not supported | v21, v23+, CC 2019 and older |

## Option 1: Offline installer (recommended)

1. Obtain a licensed CC 2021 offline installer from Adobe.
2. Copy the full installer folder contents here so `Set-up.exe` exists at `photoshop/Set-up.exe`.
3. Run `./pre-check.sh` then `./setup.sh`.

## Option 2: Custom installer path

If files live elsewhere (external drive, secondary disk):

```bash
export PHOTOSHOP_INSTALLER_DIR=/path/to/folder/with/Set-up.exe
./setup.sh
```

The installer must contain `Set-up.exe` plus `packages/` and `products/`.

## Option 3: AppImage (immutable distros)

Download the AppImage from [GitHub Releases](https://github.com/benjarogit/photoshopCClinux/releases). At first run you will be asked for the folder containing `Set-up.exe`.

## Legal

You must own a valid Adobe license. This project only automates Wine/Proton setup on Linux.
