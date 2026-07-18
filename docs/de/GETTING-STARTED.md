# Schnellstart

Rezeptor installiert und startet Windows-Software unter Linux mit getesteten **Rezepten** und **Proton-GE**.

## Voraussetzungen

- Linux (x86_64), Desktop-Umgebung
- **PyQt6** (`python-pyqt6` unter Arch/CachyOS bzw. Distro-Paket)
- Optional: `PyQt6-Fluent-Widgets` für die Fluent-Oberfläche
- Netzwerk beim ersten Lauf (Proton-GE-Download laut `core/runtime.lock`)

## Installation

### Aus dem Repository

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

### Release / AppImage

1. Assets von [GitHub Releases](https://github.com/benjarogit/rezeptor/releases) laden
2. Prüfen: `sha256sum -c SHA256SUMS`
3. AppImage ausführbar machen und starten, oder `tar.gz` entpacken und `./setup.sh`

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

Aktiviert Dev-Features (Rezept-Editor, Manifest-Sync im Git-Checkout). Entspricht der Einstellung **Entwicklermodus**.

## Weiter

- [Benutzerhandbuch](USER-GUIDE.md) — GUI im Detail
- [Rezept-Katalog](CATALOG.md) — offiziell vs. Community
- [Entwickler-Übersicht](ENTWICKLER.md) — eigenes Rezept
