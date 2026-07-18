# Projektstruktur

Überblick über das Rezeptor-Repository — wo was liegt und welche Verträge gelten.

## Top-Level

```
rezeptor/
├── core/                 # Geteilte Bash-Module (DRY)
│   └── runtime.lock      # Gepinnte Proton-GE-Version + SHA256
├── recipes/
│   ├── <id>/             # Offizielle Rezepte
│   ├── community/<id>/   # Community (nicht im Manifest)
│   ├── _template*/       # Vorlagen (nicht im Manifest)
│   ├── catalog.json      # GUI-Katalog + trust
│   ├── manifest.json     # SHA256-Integrität
│   └── recipe.schema.json
├── launcher/             # PyQt6-GUI
├── scripts/              # Lint, Manifest, new-recipe, Builds
├── tests/                # bats + Python
├── docs/{de,en}/         # Diese Site (MkDocs)
├── setup.sh              # Einstieg → launcher
├── VERSION               # SemVer (Release-Trigger)
└── Makefile              # validate, test, recipe-lint, …
```

## `recipes/<id>/` — Pflichtdateien

Jedes Rezept:

| Datei | Pflicht | Rolle |
|-------|---------|--------|
| `recipe.yml` | ja | Metadaten, `install_steps`, Hook-Pfade inkl. `uninstall:` |
| `install.sh` | ja | Erstinstallation |
| `repair.sh` | ja | validate → nur Fehlendes beheben |
| `validate.sh` | ja | Strukturierte `OK:` / `FAIL:` / `WARN:`-Ausgabe |
| `launch.sh` | ja | Starten |
| `uninstall.sh` | ja | Vollständig entfernen via `purge_recipe_data` |
| `kill.sh` | ja | Prozesse beenden (YAML `kill:`) |

Optional: `info.de.txt` / `info.en.txt`, `assets/`, `optional/`.

!!! warning "Kein erneutes Installieren als Reparatur"

    `repair.sh` ruft `validate.sh`, behebt Abweichungen, validiert erneut — **kein** volles Re-Install.

## `core/` — Shared Core

Neue Logik **nicht** in Rezepten duplizieren — erst in `core/` zentralisieren.

| Modul | Verantwortung |
|-------|----------------|
| `recipe-hooks.sh` | Hook-Einstieg, Profile, `purge_recipe_data` |
| `recipe-install-steps.sh` | Deklarative `install_steps` |
| `recipe-prefix.sh` | Prefix anlegen/aktualisieren |
| `recipe-winetricks.sh` | Winetricks unter Proton; Retry nur Exit 139 |
| `recipe-win10.sh` | Windows-10-Version (Registry, kein winecfg) |
| `recipe-validate.sh` | Wiederverwendbare Checks |
| `wine-runtime.sh` | Proton-GE, Grafik-DLLs |
| `recipe-desktop.sh` | `.desktop` + Icons |
| `paths.sh` / `env-file.sh` / `output.sh` | Pfade, State, GUI-Tags |

Tiefenreferenz: [Core-API](CORE-API.md).

## Runtime: nur Proton-GE

- Pin in `core/runtime.lock` (`PROTON_GE_TAG`, URL, SHA256)
- Rezepte setzen `runtime: proton-ge`
- **Kein** System-Wine-Fallback in Rezept-Skripten
- Grafik: `wine_runtime::deploy_proton_graphics_dlls()` — **kein** winetricks dxvk
- Win10: `recipe_win10::ensure` — **kein** winetricks winecfg

Installationsort Proton: `~/.local/share/wine-software/runtime/proton-ge/<tag>/` (geteilt, überlebt Uninstall).

## `launcher/`

PyQt6-App: Katalog, Trust, Settings, Hook-Prozesse, Activity-Log. Siehe [GUI-Launcher](LAUNCHER.md).

## Datenorte (Laufzeit)

| Pfad | Rolle |
|------|--------|
| `~/.local/share/wine-software/<id>/` | Kanonischer `data_root` |
| `$DATA_ROOT/prefix` | Immer der Wine-Prefix |
| `$DATA_ROOT/recipe.env` | Persistenter State (`env_file_*`, nie `source`) |
| `$DATA_ROOT/data_root.path` | GUI-Override des gewählten Datenorts |

## CI & Qualität

```bash
make validate    # shellcheck, bash -n, compileall, recipes-check, recipe-lint, manifest-check
make test        # bats
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh
```

`shellcheck` in `make validate` deckt nur `core/`, `photoshop`, `wiso-steuer`, `launcher/`, `scripts/` ab — nicht jedes Rezept. `bash -n` prüft alle `recipes/*/*.sh`.

Workflows: `.github/workflows/ci.yml`, `docs.yml`, `release.yml`.

## Weiter

- [Rezept schreiben](RECIPE-AUTHORING.md)
- [Core-API](CORE-API.md)
- [Trust & Manifest](TRUST.md)
