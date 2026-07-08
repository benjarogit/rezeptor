---
name: 🚀 Performance Issue
about: Report performance problems
title: '[PERFORMANCE] '
labels: performance
assignees: ''
---

## 🚀 Problem

Beschreibung des Performance-Problems.

## 📊 Symptome

- [ ] Langsamer Start
- [ ] Bildschirm-Lag
- [ ] Abstürze
- [ ] Hohe CPU/RAM-Nutzung
- [ ] Anderes: _______

## 📋 System

- **CPU:** [z.B. AMD Ryzen 7 5800X]
- **RAM:** [z.B. 16GB]
- **GPU:** [z.B. Nvidia RTX 3060]
- **Distro:** [z.B. CachyOS]
- **Runtime:** Proton-GE — `source core/wine-runtime.sh && wine_runtime::describe`

## 🔧 Bereits versucht

- [ ] GPU in Photoshop deaktiviert
- [ ] Wine-Registry-Tweaks angewendet
- [ ] Andere Apps geschlossen

## 📈 Metriken

```bash
# CPU/RAM während Problem
top -b -n 1 | head -20
free -h
```
