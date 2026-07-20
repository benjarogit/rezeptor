# Schnellstart

Rezeptor installiert und startet Windows-Software unter Linux mit getesteten **Rezepten** und **Proton-GE**.

## Voraussetzungen

- Linux (x86_64), Desktop-Umgebung
- Netzwerk beim ersten Lauf (Proton-GE-Download laut `core/runtime.lock`)

**Je nach Installationsweg:**

| Weg | Host-PyQt6 nötig? |
|-----|-------------------|
| Git-Clone oder **`tar.gz`** + `./setup.sh` | **Ja** — Distro-Paket `python-pyqt6` (Arch/CachyOS) bzw. Entsprechung; optional `PyQt6-Fluent-Widgets` |
| **AppImage** (Release) | **Nein** — Python und PyQt6 sind im Bundle (empfohlen auf Bazzite / immutable Distros) |
| **Flatpak** (Release) | **Nein** — Python, PyQt6 und Proton-GE sind im Bundle |

## Installation

### Aus dem Repository (Host-PyQt6 nötig)

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

### AppImage (kein Host-PyQt6)

1. `rezeptor-*-x86_64.AppImage` und `SHA256SUMS` von [GitHub Releases](https://github.com/benjarogit/rezeptor/releases) laden
2. Prüfen: `sha256sum -c SHA256SUMS`
3. `chmod +x rezeptor-*-x86_64.AppImage && ./rezeptor-*-x86_64.AppImage`

### Flatpak (kein Host-PyQt6)

```bash
flatpak install --user rezeptor-<version>-x86_64.flatpak
flatpak run io.github.benjarogit.Rezeptor
```

Lokal bauen: `scripts/build-flatpak.sh` (benötigt `flatpak-builder` und Runtime `org.freedesktop.Platform//25.08`).

### tar.gz-Release (Host-PyQt6 nötig)

1. `rezeptor-*.tar.gz` laden und `sha256sum -c SHA256SUMS`
2. Entpacken und `./setup.sh`

## Erste Schritte in der GUI

1. Rezept in der Sidebar wählen
2. **Quelle** setzen (Installer, Portable-Ordner, EXE — je nach Rezept; BYOS)
3. Bei Portable ggf. **Ziel** wählen
4. **Installieren** → Fortschritt im Vorgangs-Log
5. Status prüfen (optional automatisch beim Start; jederzeit **F5**)
6. **Starten**

## Wo liegen die Daten?

| Pfad | Inhalt |
|------|--------|
| `~/.local/share/wine-software/<id>/` | Rezept-State, Prefix (`prefix/`), `recipe.env` |
| `~/.local/share/wine-software/runtime/proton-ge/` | Geteiltes Proton-GE (überlebt Deinstall) |
| `~/.local/share/wine-software/logs/` | Install-/Validate-Logs |
| `~/.local/share/wine-software/rezeptor/settings.json` | Launcher-Einstellungen |
| Portable-/Spielordner | Oft **außerhalb** (z. B. `~/Dokumente/…`, Steam-Bibliothek) |

## Entwicklermodus

```bash
REZEPTOR_DEV=1 ./setup.sh
```

Oder in den Einstellungen **Entwicklermodus** aktivieren (Rezept-Dateien in der GUI bearbeiten).

## Weiterlesen

- [Benutzerhandbuch](USER-GUIDE.md)
- [Trust / Integrität](TRUST.md)
- [GUI-Launcher](LAUNCHER.md)
