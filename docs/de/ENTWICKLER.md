# Entwickler — Rezeptor Rezepte

Du willst eine Anwendung unter Linux per Wine/Rezeptor anbieten? **Ein Muster für alle Rezepte** — Photoshop, WISO und Community-Rezepte nutzen dieselbe Architektur.

## Schnellstart (5 Minuten)

```bash
cd photoshopCClinux   # oder dein Clone

# 1. Rezept anlegen (CLI oder GUI: Rezeptor → Neues Rezept…)
./scripts/new-recipe.sh meine-app "Meine App"
# oder Offline-Installer:
./scripts/new-recipe.sh mein-setup "Mein Setup" --type installer

# 2. Anpassen
$EDITOR recipes/meine-app/recipe.yml   # inkl. install_steps
# Optional: core/recipe-meine-app.sh für module:-Schritte

# 3. Prüfen & testen
./scripts/recipe-lint.sh               # Schema + Hook-Vertrag
REZEPTOR_DEV=1 ./setup.sh
# Im GUI: dein Rezept → Installieren

# 4. Vor Pull Request
./scripts/recipe-manifest.sh
git add recipes/manifest.json recipes/meine-app/
```

## Wie das Rezept-System funktioniert

```
recipe.yml          → Vertrag (Metadaten + install_steps)
install.sh          → dünn: recipe_hooks::load + recipe_install_steps::run
core/recipe-install-steps.sh → führt install_steps aus
core/recipe-<id>.sh → App-Logik (module: recipe_foo::bar)
recipes/recipe.schema.json + recipe-lint.sh → Regeln (CI)
manifest.json       → SHA256-Trust im Launcher
```

**Merksatz:** `recipe.yml` = Vertrag. Hooks = Lifecycle. Core = Ausführung. Lint/Schema/CI = Regeln. Manifest = Integrität.

Jedes Hook-Skript **beginnt identisch**:

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install   # launch | validate | repair | kill
recipe_install_steps::run    # nur bei install.sh
```

Referenz:

| Typ | Vorlage | Beispiel |
|-----|---------|----------|
| Portable | `recipes/_template/` | `wiso-steuer` (volle `install_steps`-Zerlegung) |
| Offline-Installer | `recipes/_template-installer/` | `photoshop` (`module: recipe_photoshop::install`) |
| Steam-Trainer | (wie `za4-trainer`) | EXE + Steam compatdata |
| Steam + BYOS-Fix | (wie `house-of-ashes`) | Spielordner `link`, Fix validate, Proton-Launch — siehe [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) |

**Versionserkennung:** jedes Rezept mit `version_guaranteed` braucht `version_detect` (Lint ERROR sonst). Engine: `launcher/version_detect.py`.

## Pflicht-Checkliste

- [ ] `recipe.yml`: Pflichtfelder + **`install_steps`** + **`version_detect`** (wenn Garantie-Version gesetzt)
- [ ] Alle `*.sh` nutzen `core/recipe-hooks.sh`
- [ ] `./scripts/recipe-lint.sh` ohne Fehler (inkl. Schema-Check)
- [ ] Mit `REZEPTOR_DEV=1 ./setup.sh` getestet
- [ ] `recipe-manifest.sh` nach Datei-Änderungen
- [ ] Keine Binaries im Repo (BYOS)

## Vollständige Spezifikation

→ **[RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)** (Felder, `install_steps`, API, GPU)

## Hilfe

- GUI: **Hilfe → Entwickler-Dokumentation…**
- Übersetzungen: [CONTRIBUTING-TRANSLATIONS.md](../CONTRIBUTING-TRANSLATIONS.md)
- Issues: [github.com/benjarogit/rezeptor/issues](https://github.com/benjarogit/rezeptor/issues)
