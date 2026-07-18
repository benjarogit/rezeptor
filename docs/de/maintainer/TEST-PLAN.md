# Testplan — Rezeptor

**Prinzip (Mythos verify):** *Done = proof.* Jeder Schritt braucht ein nachprüfbares Artefakt. Fehlt der Beweis, ist der Schritt fehlgeschlagen — GitHub-Issue öffnen.

**Daten-Root:** `~/.local/share/wine-software/`  
**Logs:** `~/.local/share/wine-software/logs/`  
**Issue-Vorlage:** [bug_report.md](https://github.com/benjarogit/rezeptor/blob/main/.github/ISSUE_TEMPLATE/bug_report.md)

Englisch: Sprachumschalter oben rechts (**EN**).

---

## Vorbereitung

```bash
cd /path/to/rezeptor
./pre-check.sh          # muss durchlaufen (inkl. PyQt6)
bash -n recipes/photoshop/install.sh
bash -n recipes/photoshop/launch.sh
python3 -m py_compile launcher/launcher.py
```

Jedem Bug-Report beifügen:
- Distro + DE (z. B. CachyOS, KDE Wayland)
- Ausgabe von `source core/wine-runtime.sh && wine_runtime::describe`
- Letzte 50 Zeilen: `tail -50 ~/.local/share/wine-software/logs/Installation_*.log`

---

## Phase A — Photoshop (CachyOS / Daily Driver)

| ID | Schritt | Befehl / Aktion | Erfolgskriterium |
|----|---------|-----------------|------------------|
| A0 | Prefix leeren (optional) | `pkill -9 wineserver 2>/dev/null; rm -rf ~/.local/share/wine-software/photoshop/prefix` | — |
| A1 | Pre-check | `./pre-check.sh` | Exit 0, PyQt6 OK |
| A2 | GUI-Launcher | `./setup.sh` | Fenster öffnet, Rezept `photoshop` sichtbar |
| A3 | Install | GUI → **Installieren** (Terminal öffnet) | Adobe-Flow fertig, kein Hänger bei EOF |
| A4 | Validate | `bash recipes/photoshop/validate.sh` | Gibt `OK: .../Photoshop.exe` aus |
| A5 | Proton-Nachweis | `grep -i proton ~/.local/share/wine-software/logs/Installation_*.log \| tail -3` | Pfad enthält `proton-ge`, **nicht** nur `/usr/bin/wine` |
| A6 | Start (CLI) | `bash recipes/photoshop/launch.sh` | Photoshop-Fenster öffnet |
| A7 | Start (GUI) | `./setup.sh` → **Starten** | Wie A6 |
| A8 | Desktop-Eintrag | `grep Exec= ~/.local/share/applications/photoshop.desktop` | Zeigt auf `.../launcher/launcher.sh` unter Daten-Root |
| A9 | Deployed Launcher | `bash ~/.local/share/wine-software/photoshop/launcher/launcher.sh` | Funktioniert ohne Git-Repo als cwd |

**Fehler-Tracking:** Issue-Titel `[A3]` / `[A6]` + Log-Auszug + `validate.sh`-Ausgabe.

---

## Phase B — Immutable / AppImage (optional)

| ID | Schritt | Erfolgskriterium |
|----|---------|------------------|
| B1 | Build | `scripts/build-appimage.sh` | SHA256 OK, AppImage erstellt |
| B2 | AppImage starten | `./rezeptor-*-x86_64.AppImage` | Launcher oder Setup startet |
| B3 | Kein System-Wine | `which wine` leer oder ungenutzt im Install-Log | Proton aus Bundle oder User-Runtime |

Test auf: Bazzite, Silverblue, Kinoite oder Bluefin, falls verfügbar.

---

## Phase C — WISO (optional, Proton experimentell)

| ID | Schritt | Erfolgskriterium |
|----|---------|------------------|
| C1 | Install | GUI → wiso-steuer → Installieren → Portable-Ordner wählen | `portable.env` existiert, keine Shell-Fehler |
| C2 | Validate | `bash recipes/wiso-steuer/validate.sh` | `OK: portable at ...` |
| C3 | Start | GUI → Starten | WISO-Fenster (kein Virtual Desktop; Opt-in `WISO_VIRTUAL_DESKTOP=1`) |

---

## Phase D — Regression-Smoke (nach Code-Änderung)

```bash
./pre-check.sh
bash recipes/photoshop/validate.sh    # wenn bereits installiert
bash -n core/wine-runtime.sh
bash -n core/sharedFuncs.sh
python3 -m py_compile launcher/launcher.py
```

---

## Fehler-Workflow

1. **Reproduzieren** mit IDs oben (Schritt notieren).
2. **Artefakte** sammeln:
   - `validate.sh` Exit-Code + Ausgabe
   - `tail -80` des neuesten Logs in `~/.local/share/wine-software/logs/`
   - `~/.local/share/wine-software/photoshop/wine-error.log` falls vorhanden
3. **Issue** auf GitHub mit Vorlage; Label `bug` + `photoshop` oder `wiso`.
4. Plan-Todos / Release **nicht** grün markieren, bis A4+A6 auf Ziel-Distro passieren.

---

## Checkliste (für Release kopieren)

```
[ ] A1 pre-check
[ ] A3 install
[ ] A4 validate
[ ] A5 proton in log
[ ] A6 launch
[ ] A8 desktop entry
[ ] B1 AppImage (if release)
[ ] README paths match reality
```
