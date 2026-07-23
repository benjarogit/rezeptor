# Entwickler — Rezeptor-Rezepte

**Ein Muster für alle Rezepte.** Portable, Offline-Installer, Steam-Spiele (mit Online-Fix), Trainer — dieselbe Architektur.

| Dokument | Rolle |
|----------|--------|
| **Diese Seite** | Schnellstart, Struktur, Rezept-Typen |
| [PROJECT-LAYOUT.md](PROJECT-LAYOUT.md) | Repo-, `recipes/`- und `core/`-Layout |
| [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) | Tiefenreferenz: Felder, `install_steps`, `version_detect` |
| [CORE-API.md](CORE-API.md) | Präzise `core/`-APIs (Hooks, Prefix, Winetricks, …) |
| [VALIDATE-REPAIR.md](VALIDATE-REPAIR.md) · [UNINSTALL.md](UNINSTALL.md) | Lifecycle-Verträge |
| [TRUST.md](TRUST.md) · [LOG-PROTOCOL.md](LOG-PROTOCOL.md) · [LAUNCHER.md](LAUNCHER.md) | Manifest, Logs, GUI |
| **Muster-Referenzen** | [INSTALLER.md](INSTALLER.md) · [WISO.md](WISO.md) · [STEAM-WRAPPER.md](STEAM-WRAPPER.md) · [TRAINER.md](TRAINER.md) |

---

## Schnellstart

```bash
cd rezeptor   # Clone von https://github.com/benjarogit/rezeptor

./scripts/new-recipe.sh meine-app "Meine App"                          # portable
./scripts/new-recipe.sh mein-setup "Mein Setup" --type installer       # Offline-Installer
./scripts/new-recipe.sh mein-spiel "Mein Spiel" --type steam-game      # Steam + Online-Fix
./scripts/new-recipe.sh --community meine-app "Meine App"              # → recipes/community/<id>/

$EDITOR recipes/meine-app/recipe.yml   # inkl. install_steps
# Optional: core/recipe-meine-app.sh für module:-Schritte

./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh             # GUI: Rezept → Quelle → Installieren

./scripts/recipe-manifest.sh          # vor PR (nur Top-Level recipes/<id>/)
git add recipes/manifest.json recipes/meine-app/
```

GUI-Alternative: **Rezeptor → Neues Rezept…** (Dev-Modus)

---

## Architektur (kurz)

```
recipe.yml          → Vertrag (Metadaten + install_steps)
install.sh …        → dünne Hooks → core/recipe-hooks.sh
core/recipe-install-steps.sh → führt install_steps aus
core/recipe-<id>.sh → App-Logik (module:)
manifest.json       → SHA256-Trust im Launcher
```

**Merksatz:** `recipe.yml` = Vertrag. Hooks = Lifecycle. Core = Ausführung. Lint/CI = Regeln. Manifest = Integrität.

Jedes Hook-Skript beginnt gleich:

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install   # launch | validate | repair | kill | minimal
recipe_install_steps::run    # nur install.sh
```

User-Daten liegen unter `~/.local/share/wine-software/<id>/` (Prefix, `recipe.env`, …) — getrennt von **Quelle** (mitgebrachte Dateien) und oft auch vom **Ziel** (Portable-/Spielordner).

---

## Rezept-Typen (Quelle / Ziel)

In der GUI immer **Quelle** und ggf. **Ziel** — unabhängig vom App-Typ.

| Typ | Mitgeliefert | Quelle | Ziel | Referenz |
|-----|--------------|--------|------|----------|
| **Offline-Installer** | `photoshop`, `premiere` | Setup-Ordner / `.exe` | Datenordner (Prefix) | [INSTALLER.md](INSTALLER.md) |
| **Portable** (Ordner/Archiv) | `wiso-steuer` | Ordner oder zip/7z/… | Installationsordner | [WISO.md](WISO.md) |
| **Steam + Online-Fix** | `house-of-ashes` | Fix BYOS; Spiel in Steam | Spielordner (`link`) | [STEAM-WRAPPER.md](STEAM-WRAPPER.md) |
| **Einzel-EXE / Trainer** | `za4-trainer` | eine `.exe` | oft Steam-Unterordner | [TRAINER.md](TRAINER.md) |

Vorlagen: `recipes/_template/` (Portable), `recipes/_template-installer/`, `recipes/_template-steam-game/`.  
Community: `recipes/community/<id>/` (Hooks laden Core über `../../../core/`; nicht im offiziellen Manifest).

---

## Pflicht-Checkliste

- [ ] `recipe.yml`: Pflichtfelder + **`install_steps`** + **`uninstall`**; bei `version_guaranteed` auch **`version_detect`**
- [ ] Alle `*.sh` nutzen `core/recipe-hooks.sh`; `uninstall.sh` → `purge_recipe_data`
- [ ] `./scripts/recipe-lint.sh` ohne Fehler
- [ ] Mit `REZEPTOR_DEV=1 ./setup.sh` getestet (Quelle speichern → Installieren)
- [ ] `recipe-manifest.sh` nach Datei-Änderungen
- [ ] Keine App-Binaries im Repo (BYOS)

---

## Weiter

Vollständige Spezifikation → **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)**

Hilfe in der App: **Hilfe → Entwickler-Dokumentation…** · Übersetzungen: [CONTRIBUTING-TRANSLATIONS.md](CONTRIBUTING-TRANSLATIONS.md)
