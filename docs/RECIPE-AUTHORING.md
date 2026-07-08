# Rezept-Authoring (Rezeptor)

Offizielle Rezepte leben unter `recipes/<id>/`. Der Launcher lädt nur Rezepte mit gültigem Eintrag in [`recipes/manifest.json`](../recipes/manifest.json) — außer im **Dev-Modus**.

## Runtime

Alle Rezepte nutzen **Prefix + Proton-GE** (kein System-Wine-Fallback). Runtime-Pin: [`core/runtime.lock`](../core/runtime.lock).

## Pflicht-Dateien

| Datei | Zweck |
|-------|--------|
| `recipe.yml` | Metadaten (flache Keys) |
| `install.sh` | Einmalige Einrichtung |
| `launch.sh` | Start |
| `validate.sh` | Prüfung (Exit 0 = OK) |
| `repair.sh` | Reparatur |
| `kill.sh` | Prozesse beenden |

Optional: `uninstall.sh`, `info.de.txt`, `assets/`, `optional/`.

## recipe.yml (Schema v2, flache Keys)

### Pflicht

- `id`, `name`, `data_root`, `runtime` (`proton-ge`)
- `install_type`, `source_kind`, `fix_kind`
- Hooks: `install`, `launch`, `validate`, `repair`, `kill`

### install_type

| Wert | Bedeutung |
|------|-----------|
| `installer_offline` | Offline-Installer-Struktur (z. B. Adobe) |
| `portable_launch` | Portable-Ordner beim User, Prefix nur Runtime |
| `portable_bootstrap` | Archiv → Portable-Baum |
| `game_install` | Installer → Prefix (Platzhalter) |
| `game_portable` | Ordner/Archiv direkt starten (Platzhalter) |

Deprecated Aliase (Lint-Warnung): `adobe_offline`, `portable`.

### source_kind (GUI-Quelldialog)

| Wert | User wählt |
|------|------------|
| `folder` | Verzeichnis (+ optional Fix bei `fix_kind`) |
| `installer` | `.exe`-Datei |
| `archive` | `.zip` / `.tar.gz` / `.tgz` (→ `source_formats`) |
| `fixed_path` | Kein Dialog — Pfad aus `installer_dir` |

### fix_kind

`none` | `optional` | `required`

### Umgebungsvariablen (Launcher → install.sh)

| Variablen | Bei |
|-----------|-----|
| `RECIPE_SOURCE_ROOT`, `RECIPE_FIX_ROOT` | `folder` / portable |
| `RECIPE_INSTALLER_PATH` | `installer` |
| `RECIPE_ARCHIVE_PATH`, `RECIPE_EXTRACT_DIR` | `archive` |

Rezept-spezifische Keys (z. B. `WISO_PORTABLE_ROOT`) bleiben aus Kompatibilitätsgründen unterstützt.

## Sicherheit

- Kein beliebiges Shell aus der GUI — nur die fünf Hook-Skripte aus `recipe.yml`.
- User-Pfade über [`core/security.sh`](../core/security.sh) validieren.
- Keine `curl | bash`, kein `eval` auf User-Input (Lint warnt).
- Logik in **`core/*`-Module** — Rezept-Skripte sind dünne Orchestrierung.

## Manifest

Nach jeder Änderung an Rezept-Dateien:

```bash
./scripts/recipe-manifest.sh
git add recipes/manifest.json
```

CI prüft: `make recipe-manifest-check`.

## Dev-Modus

Lokale Rezepte ohne Manifest-Eintrag testen:

```bash
REZEPTOR_DEV=1 ./setup.sh
# oder
./setup.sh --dev
```

## Lint

```bash
./scripts/recipe-lint.sh
make recipe-lint
```

## Vorlage

Kopieren Sie [`recipes/_template/`](../recipes/_template/) als Startpunkt.

## Phase 2

Signierte Releases (minisign) — noch nicht implementiert.
