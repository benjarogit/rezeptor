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
```

## Test-Struktur

- `test_helper.bash` - Gemeinsame Helper-Funktionen für alle Tests
- `test_security.bats` - Tests für das Security-Modul
- `test_i18n.bats` - Tests für das i18n-Modul

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
    source "$BATS_TEST_DIRNAME/../scripts/security.sh"
}

@test "test description" {
    run security::validate_path "/tmp"
    [ "$status" -eq 1 ]
}
```

