# Tests für Photoshop CC Linux Installer

Dieses Verzeichnis enthält automatisierte Tests für das Projekt.

## Voraussetzungen

Installiere `bats-core` für die Ausführung der Tests:

```bash
# Arch Linux / CachyOS
sudo pacman -S bats-core

# Ubuntu / Debian
sudo apt-get install bats

# Oder via npm
npm install -g bats
```

## Test-Ausführung

Vom Repository-Root (empfohlen für Agenten und CI):

```bash
make test      # bats tests/
make validate  # shellcheck + syntax + compile + recipe-check
```

Alternativ direkt:
```bash
bats tests/
```

Einzelne Test-Datei ausführen:
```bash
bats tests/test_security.bats
bats tests/test_i18n.bats
bats tests/test_recipe_trust.bats
```

## Test-Struktur

- `test_helper.bash` - Gemeinsame Helper-Funktionen für alle Tests
- `test_security.bats` - Tests für `core/security.sh` (früher `scripts/security.sh`)
- `test_i18n.bats` - Tests für `core/i18n.sh` (früher `scripts/i18n.sh`)
- `test_recipe_trust.bats` - Manifest-Trust via `launcher/recipe_trust.py` (ersetzt `core/recipe-trust.sh`)
- `test_recipe_source.bats` - Archive-Extraktion; Installer-Erkennung über `recipe_deploy::detect_installer`

## Hinzufügen neuer Tests

1. Erstelle eine neue `.bats` Datei in `tests/`
2. Lade `test_helper` mit `load test_helper`
3. Source das zu testende Modul in `setup()`
4. Schreibe Tests mit `@test "description"` Blöcken

Beispiel:
```bash
#!/usr/bin/env bats
load test_helper

setup() {
    source "$BATS_TEST_DIRNAME/../core/security.sh"
}

@test "test description" {
    run security::validate_path "/tmp"
    [ "$status" -eq 1 ]
}
```

## Hinweis zu verschobenen Modulen

- Bash-i18n/Security liegen unter `core/` (nicht mehr `scripts/`).
- Rezept-Trust ist Python (`launcher/recipe_trust.py`); das alte `core/recipe-trust.sh` entfällt.
- GUI-Übersetzungen: `launcher/i18n/` + `launcher/locales/*.json` (nicht von den Bash-i18n-Bats abgedeckt).
