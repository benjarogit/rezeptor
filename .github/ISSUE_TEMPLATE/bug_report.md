---
name: 🐛 Bug Report
about: Report a bug or issue
title: '[BUG] '
labels: bug
assignees: ''
---

## 🐛 Problem

Kurze Beschreibung des Problems.

## 📋 System

- **Distro:** [z.B. CachyOS, Arch, Ubuntu]
- **Runtime:** Proton-GE (`core/runtime.lock`) — run: `source core/wine-runtime.sh && wine_runtime::describe`
- **Photoshop:** [z.B. CC 2021]

## 🔍 Schritte zum Reproduzieren

1. ...
2. ...
3. ...

## ✅ Erwartetes Verhalten

Was sollte passieren?

## ❌ Tatsächliches Verhalten

Was passiert stattdessen?

## 📸 Logs

```bash
# Relevante Logs
tail -n 50 ~/.local/share/wine-software/logs/*.log
```

## 🔧 Bereits versucht

- [ ] `./pre-check.sh` ausgeführt
- [ ] `./troubleshoot.sh` ausgeführt
- [ ] GPU in Photoshop deaktiviert
- [ ] Logs geprüft
