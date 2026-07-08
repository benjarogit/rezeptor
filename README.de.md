# Rezeptor

**Rezept-basierter Launcher für Windows-Software auf Linux** — Wine und Proton GE, eine GUI, getrennte Prefixe pro Programm.

![Lizenz](https://img.shields.io/badge/license-GPL--2.0-blue) ![Platform](https://img.shields.io/badge/platform-Linux-green)

> [!NOTE]
> **Entwicklungs-Repo (privates Backup):** [github.com/benjarogit/rezeptor](https://github.com/benjarogit/rezeptor)  
> **Öffentliches Photoshop-Projekt:** [github.com/benjarogit/photoshopCClinux](https://github.com/benjarogit/photoshopCClinux)

---

## Was ist Rezeptor?

Rezeptor ist ein **PyQt6-Launcher**, der Windows-Programme über **Rezepte** einrichtet und startet — Pakete unter `recipes/<id>/` mit `recipe.yml`, Install-/Start-/Reparatur-Skripten und gemeinsamer Logik in `core/`.

| Du lieferst | Rezeptor liefert |
|-------------|------------------|
| Lizensierte Installer (Adobe, Buhl, …) | Wine-Prefix, Runtime, winetricks, Desktop-Eintrag, Logs |
| Portable-Ordner (WISO) | Launcher-Skript, Qt-Fixes, Prüfung |

**Keine Piraterie.** Dieses Repo enthält keine Adobe-, Buhl- oder andere proprietäre Binaries.

---

## Schnellstart

### Voraussetzungen

```bash
# Arch / CachyOS
sudo pacman -S wine winetricks python-pyqt6

# Ubuntu / Debian
sudo apt install wine winetricks python3-pyqt6
```

### Starten

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
chmod +x setup.sh
./setup.sh
```

Optional Menüeintrag:

```bash
./scripts/install-rezeptor-desktop.sh
```

Dann **Rezeptor** im Anwendungsmenü öffnen, Rezept wählen, **Installieren → Prüfen → Starten**.

---

## Rezepte

| Rezept | Software | Runtime | Datenverzeichnis |
|--------|----------|---------|------------------|
| [`photoshop`](recipes/photoshop/) | Adobe Photoshop CC 2021 (v22.x) | **Proton GE** | `~/.local/share/wine-software/photoshop/` |
| [`wiso-steuer`](recipes/wiso-steuer/) | WISO Steuer (Portable) | **System-Wine** | `~/.local/share/wine-software/wiso-steuer/` |

Jedes Rezept setzt `runtime:` in `recipe.yml`. Rezeptor wählt **Proton GE** oder **Distro-Wine** automatisch — beides kann parallel existieren; Prefixe bleiben getrennt.

### Photoshop

1. `Set-up.exe`, `packages/`, `products/` nach [`photoshop/`](photoshop/) — siehe [photoshop/README.md](photoshop/README.md).
2. Rezeptor → **Photoshop** → Installieren (Netzwerk während Adobe-Setup ggf. deaktivieren).
3. Danach in Photoshop: **Bearbeiten → Voreinstellungen → Leistung** → Grafikprozessor deaktivieren.

### WISO Steuer (Portable)

1. Rezeptor → **WISO Steuer** → Installieren → Portable-Root wählen (Ordner mit `Steuersoftware 20XX/`).
2. Unter KDE/Wayland: Reparieren setzt Wine-Grafik auf **X11**.
3. Erscheint **Wine-Mono** für `~/.wine`: **Abbrechen** — Rezeptor → **Reparieren** (Mono still im WISO-Prefix).

---

## Verzeichnisstruktur

```
~/.local/share/wine-software/
├── runtime/proton-ge/GE-Proton10-28/   # bei erstem Photoshop-Start
├── cache/winetricks/
├── logs/
├── photoshop/{prefix,resources}
└── wiso-steuer/{prefix,portable.env,bin/}
```

Projekt:

```
rezeptor/
├── core/           # gemeinsame Bash-Logik
├── launcher/       # PyQt6-GUI
├── recipes/        # ein Ordner pro Programm
├── docs/
├── setup.sh
└── scripts/
```

---

## Dokumentation

| Thema | Datei |
|-------|-------|
| Rezept-Übersicht | [docs/RECIPES.md](docs/RECIPES.md) |
| Neues Rezept schreiben | [docs/RECIPE-AUTHORING.md](docs/RECIPE-AUTHORING.md) |
| Tests | [docs/TESTING.md](docs/TESTING.md) |
| Photoshop-Dateien | [photoshop/README.md](photoshop/README.md) |

---

## Entwicklung

```bash
make validate
./scripts/recipe-manifest.sh    # nach Rezept-Änderungen
REZEPTOR_DEV=1 ./setup.sh     # ohne Manifest-Trust-Check
```

Runtime-Pin: [`core/runtime.lock`](core/runtime.lock)

Logs: `~/.local/share/wine-software/logs/`

---

## Runtime: Wine vs Proton GE

| | System-Wine | Proton GE |
|---|-------------|-----------|
| Binary | `/usr/bin/wine` | unter `~/.local/share/wine-software/runtime/proton-ge/` |
| Gut für | Qt/Büro (WISO) | Spiele, DXVK, Adobe-IE-Installer |
| Im Rezept | `runtime: system` | `runtime: proton-ge` |

Proton GE ist **nicht** „besseres Wine für alles“ — es ist Wine mit Gaming-Patches und Grafik-Stack.

---

## Sprachen

- 🇩🇪 **Deutsch** — diese Seite
- 🇬🇧 **[English Documentation](README.md)**

---

## Support

- **Issues:** [github.com/benjarogit/photoshopCClinux/issues](https://github.com/benjarogit/photoshopCClinux/issues)
- **Hilfe:** `./troubleshoot.sh` oder Rezeptor → Prüfen / Reparieren

---

## Lizenz

**GPL-2.0** — siehe [LICENSE](LICENSE).

Basiert auf [photoshopCClinux](https://github.com/Gictorbit/photoshopCClinux) von Gictorbit.  
Copyright © 2024–2026 Sunny C.

Adobe Photoshop und WISO Steuer sind proprietär — gültige Lizenz erforderlich.
