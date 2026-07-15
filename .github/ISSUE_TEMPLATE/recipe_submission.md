---
name: 📦 Community Recipe Submission
about: Submit or announce a community recipe for review
title: '[RECIPE] '
labels: recipe
assignees: ''
---

## Recipe

- **Name:**
- **ID:** (kebab-case, e.g. `my-app`)

## System

- **Distro:** (e.g. CachyOS, Arch, Ubuntu 24.04)
- **Desktop environment:** (e.g. KDE Plasma, GNOME, Hyprland)
- **Architecture:** (e.g. x86_64)
- **GPU:** (vendor / model / driver, e.g. AMD RX 7800 XT / mesa 24.x)

## Runtime (required)

- **Proton-GE version:** (project standard — no system Wine)
  - How to check: `source core/wine-runtime.sh && wine_runtime::describe`

## Category

- [ ] Productivity / Office
- [ ] Creative / Adobe-like
- [ ] Game
- [ ] Utility / Other

## Test path

How was this tested? Check all that apply and note results:

- [ ] Install (`install.sh`)
- [ ] Launch (`launch.sh`)
- [ ] Validate (`validate.sh`) — OK/FAIL summary
- [ ] Repair (`repair.sh`) if relevant
- [ ] Uninstall / purge if tested

## Link / path

- **PR:** (preferred)
- **or gist / branch:**
- **or path:** `recipes/community/<id>/`

## Notes / known issues

Known limitations, workarounds, GPU quirks, etc.
