# Adobe Photoshop Installer für Linux ![Status](https://img.shields.io/badge/status-produktionsreif-green)

> [!NOTE]
> **Produktionsreif - Komplettes Toolset**
> 
> Dieses Projekt hat sich von einem einfachen Installer zu einem **umfassenden, produktionsreifen Toolset** für Photoshop auf Linux entwickelt. Mit modularer Architektur, umfangreichen Features und professionellem Finish ist es bereit für den breiten Einsatz.
> 
> **Jeder Hinweis, Fix oder Idee ist willkommen!** Bitte melde Probleme, teile Lösungen oder trage Verbesserungen über [GitHub Issues](https://github.com/benjarogit/rezeptor/issues) bei.
> 
> Siehe [CHANGELOG.md](CHANGELOG.md) für aktuelle Änderungen!

> [!IMPORTANT]
> **Getestete und funktionierende Versionen**
> 
> ✅ **Adobe Photoshop CC 2021 (v22.x)** und **WISO Steuer** — beide Proton-GE. Runtime pro Rezept in `recipe.yml`.

> **Datenverzeichnis**: `~/.local/share/wine-software/photoshop/`. Runtime: `~/.local/share/wine-software/runtime/proton-ge/`.

> **Launcher**: PyQt6 Pflicht (`python-pyqt6`). `./setup.sh` startet die GUI.
> 
> **Hinweis zu Versionsnummern**: Die von mir getestete spezifische Version ist **v22.0.0.35**, aber **jede Photoshop v22.x Version sollte funktionieren**. Die genaue Build-Nummer kann variieren, je nachdem woher du deine Installationsdateien hast.
> 
> 💡 **Wichtig**: Nur CC 2021 (v22.x) wurde getestet. Andere Versionen wurden nicht getestet.
> 
> 
> ✅ **Getestet auf**: CachyOS Linux (Arch-basiert) mit KDE Desktop-Umgebung

![Photoshop on Linux](images/Screenshot.png)

![Lizenz](https://img.shields.io/badge/license-GPL--2.0-blue) ![Platform](https://img.shields.io/badge/platform-Linux-green) ![OS](https://img.shields.io/badge/OS-CachyOS-blue) ![Desktop](https://img.shields.io/badge/Desktop-KDE-blue) ![Wine](https://img.shields.io/badge/Wine-5.0%2B-red) ![Photoshop](https://img.shields.io/badge/Photoshop-CC%202021-blue)

**Adobe Photoshop nativ auf Linux mit Wine ausführen**

Ein einfacher, automatisierter Installer, der dir hilft, Photoshop auf Linux einzurichten. Funktioniert auf CachyOS, Arch, Ubuntu, Fedora und allen großen Linux-Distributionen.

---

## 🌍 Sprachen / Languages

- 🇩🇪 **Deutsche Dokumentation** - Diese Seite
- 🇬🇧 **[English Documentation](README.md)** - Vollständige Anleitung

---

# Deutsche Dokumentation

## 📋 Inhaltsverzeichnis

- [Features](#-features)
- [Systemanforderungen](#️-systemanforderungen)
- [Wichtiger Hinweis](#️-wichtiger-hinweis)
- [Schnellstart](#-schnellstart)
- [Installationsanleitung](#-installationsanleitung)
- [Bekannte Probleme & Lösungen](#-bekannte-probleme--lösungen)
- [Fehlerbehebung](#-fehlerbehebung)
- [Performance-Tipps](#-performance-tipps)
- [Deinstallation](#-deinstallation)
- [Mithelfen](#-mithelfen)
- [Lizenz](#-lizenz)

---

## ✨ Features

### Kern-Installation
- ✅ **Lokale Installation** - Verwendet lokale Installationsdateien (keine Downloads von Adobe)
- ✅ **Automatisches Setup** - Installiert Wine-Komponenten und Abhängigkeiten automatisch
- ✅ **Multi-Distribution Support** - Funktioniert auf CachyOS, Arch, Ubuntu, Fedora und mehr
- ✅ **Vorinstallationsprüfung** - Validiert System vor Installation mit distro-spezifischen Hinweisen
- ✅ **Desktop-Integration** - Erstellt Menü-/Desktop-Eintrag
- ✅ **Mehrsprachig** - Vollständige i18n-Unterstützung (DE/EN) mit externen Sprachdateien

### Erweiterte Features
- 🔧 **Automatische Fehlerbehebung** - Eingebaute Diagnosetools mit automatischen Fixes
- 📦 **Camera Raw Installer** - Automatisierte Installation mit MD5-Verifikation
- 🔄 **Update-Check-System** - GitHub API-Integration mit Caching und Timeout-Schutz
- 💾 **Checkpoint/Rollback** - Sichere Installation mit Wiederherstellungspunkten
- 🔒 **Security-Modul** - Pfad-Validierung, sichere Operationen, Shell-Injection-Prävention
- 📊 **System-Informationen** - Cross-Distro System-Erkennung und -Berichte
- 🎨 **Responsive UI** - Banner, Boxen und Header passen sich Terminal-Breite an
- 🔇 **Quiet/Verbose Modi** - `--quiet` / `-q` und `--verbose` / `-v` Flags für CI/Testing
- 📝 **Log-Rotation** - Automatische Kompression (gzip) und Bereinigung alter Logs
- 🚀 **Datei-Öffnen-Support** - Launcher akzeptiert Dateien als Parameter ("Mit Photoshop öffnen")
- ⚙️ **Wine-Konfiguration** - Optionaler winecfg-Helfer (Proton-Prefix; nicht nötig für Install)
- 🛑 **Kill-Utility** - Zwangsbeendigung hängender Prozesse
- 🎯 **GPU-Workarounds** - Fixes für häufige Grafikprobleme

---

## 🖥️ Systemanforderungen

### Erforderlich

- **OS:** 64-bit Linux Distribution
- **RAM:** Minimum 4 GB (8 GB empfohlen)
- **Speicher:** 5 GB freier Speicherplatz in `/home`
- **Grafik:** Beliebige GPU (Intel, Nvidia, AMD) mit aktuellen Treibern

### Erforderliche Pakete (Host)

Rezeptor nutzt **nur Proton-GE** (gepinnt in `core/runtime.lock`) — **kein System-Wine**. Auf dem Host:

- `python-pyqt6` (oder Distro-Äquivalent) für die GUI
- Hilfsprogramme: `curl`/`wget`, `cabextract`, `unzip` (je nach Distro)

Proton-GE liegt unter `~/.local/share/wine-software/runtime/proton-ge/`. System-`wine` ist **nicht** die Runtime.

<details>
<summary><b>Beispiel: CachyOS / Arch (GUI + Helfer)</b></summary>

```bash
sudo pacman -S python-pyqt6 cabextract unzip curl
```
</details>

<details>
<summary><b>Beispiel: Ubuntu / Debian</b></summary>

```bash
sudo apt install python3-pyqt6 cabextract unzip curl
```
</details>

<details>
<summary><b>Beispiel: Fedora</b></summary>

```bash
sudo dnf install python3-pyqt6 cabextract unzip curl
```
</details>

---

## ⚠️ Wichtiger Hinweis

### Du musst Photoshop-Installationsdateien selbst bereitstellen

**Dieses Repository enthält KEINE Photoshop-Installationsdateien.**

Du musst:
1. **Eine gültige Adobe Photoshop CC 2021 Lizenz besitzen**
2. **Den Installer selbst beschaffen** (siehe [Wie bekomme ich Photoshop?](#wie-bekomme-ich-photoshop-dateien))
3. **Dateien im `photoshop/` Verzeichnis platzieren** (siehe [photoshop/README.md](photoshop/README.md))

### ⚡ Versions-Kompatibilität

| Status | Version |
|--------|---------|
| **Garantiert** | Adobe Photoshop CC 2021 **v22.0.0.35** |
| Best effort | Andere **v22.x** Builds |
| Nicht supported | v21, v23+, CC 2019 und älter |

### Installations-Tiers

| Tier | Zielgruppe | Methode |
|------|------------|---------|
| **1** | End-User, Silverblue / Bazzite / immutable | [AppImage Release](https://github.com/benjarogit/rezeptor/releases) |
| **2** | Arch / CachyOS / Entwickler | `git clone` + `./setup.sh` (Proton-GE automatisch) |
| **2** | Arch / CachyOS / Pop!\_OS / Entwickler | `git clone` + `python-pyqt6` + `./setup.sh` |
| **3** | Immutable (Silverblue, Bazzite, Kinoite, Bluefin) | AppImage von Releases (Proton + PyQt6 gebündelt) |

Runtime: gepinntes [Proton-GE](https://github.com/GloriousEggroll/proton-ge-custom) (`core/runtime.lock`), unter `~/.local/share/wine-software/runtime/proton-ge/`.

### Wie bekomme ich Photoshop-Dateien?

#### Option 1: Offiziell von Adobe (Empfohlen)
- Download über Adobe Creative Cloud
- Offline-Installer für Photoshop CC 2021 (v22.x) verwenden

#### Option 2: Von vorhandener Windows-Installation
- Falls du Photoshop unter Windows hast, extrahiere die Installationsdateien
- Windows-Pfad: `C:\Program Files\Adobe\Adobe Photoshop CC 2021\`

**⚖️ Legal:** Du benötigst eine gültige Lizenz. Dieses Script automatisiert nur die Wine-Installation.

---

## 🚀 Schnellstart

### Tier 1: AppImage (empfohlen für immutable Distros)

1. `photoshopCClinux-<version>-x86_64.AppImage` von [Releases](https://github.com/benjarogit/rezeptor/releases) laden
2. `chmod +x photoshopCClinux-*.AppImage`
3. AppImage starten und Ordner mit `Set-up.exe` wählen

Kein System-Wine-Paket nötig.

### Tier 2: Git clone

### 1. Repository klonen

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd photoshopCClinux
```

### 2. Photoshop-Dateien platzieren

Kopiere deine Photoshop CC 2021 Installationsdateien in das `photoshop/` Verzeichnis:

```
photoshop/
├── Set-up.exe
├── packages/
└── products/
```

Siehe [photoshop/README.md](photoshop/README.md) für detaillierte Struktur.

### 3. Vorprüfung ausführen

```bash
chmod +x pre-check.sh
./pre-check.sh
```

Sollte anzeigen: ✅ "Alle kritischen Checks bestanden!"

### 4. Internet deaktivieren (Empfohlen)

```bash
# WLAN
nmcli radio wifi off

# Oder Ethernet
sudo ip link set <interface> down
```

Dies verhindert Adobe-Login-Aufforderungen während der Installation.

### 5. Installation ausführen

```bash
chmod +x setup.sh
./setup.sh
```

### 6. In Rezeptor installieren

1. Rezept **Adobe Photoshop CC 2021** wählen  
2. **Installieren** — Offline-Installer liegt unter `photoshop/`  
3. Bestätigen und warten (10–20 Minuten)

![Setup Screenshot](images/setup-screenshot-de.png)

### 7. Im Adobe Setup-Fenster

- Klicke auf "Installieren"
- Behalte den Standard-Pfad (`C:\Program Files\Adobe\...`)
- Wähle deine Sprache (z.B. de_DE oder en_US)
- Warte 10-20 Minuten

### 8. Internet wieder aktivieren

```bash
nmcli radio wifi on
```

### 9. Photoshop starten

```bash
photoshop
```

Oder suche nach "Adobe Photoshop CC" in deinem Anwendungsmenü.

### 10. GPU deaktivieren (Wichtig!)

Für Stabilität:
1. In Photoshop: `Bearbeiten > Voreinstellungen > Leistung` (Strg+K)
2. Deaktiviere "Grafikprozessor verwenden"
3. Starte Photoshop neu

---

## ⚙️ Befehlszeile

| Befehl | Zweck |
|--------|--------|
| `./setup.sh` | Vorprüfung + Rezeptor GUI |
| `./setup.sh --dev` | Dev-Modus (Rezepte ohne Manifest) |
| `bash recipes/photoshop/install.sh` | Photoshop installieren |
| `bash recipes/photoshop/launch.sh` | Photoshop starten |
| `bash recipes/photoshop/kill.sh` | Prozesse beenden |
| `bash recipes/photoshop/uninstall.sh` | Deinstallation |

Logs: `~/.local/share/wine-software/logs/`

### Rezept-System

Jede App unter `recipes/<id>/` ist ein **Rezept**: `recipe.yml` (Vertrag + deklarative `install_steps`) + dünne Hooks über `core/recipe-hooks.sh`. Gemeinsame Logik in `core/`; Integrität über `recipes/manifest.json` und `./scripts/recipe-lint.sh` (CI).

- Einstieg: [docs/de/ENTWICKLER.md](docs/de/ENTWICKLER.md) · English: [docs/en/ENTWICKLER.md](docs/en/ENTWICKLER.md)
- Spezifikation: [docs/de/RECIPE-AUTHORING.md](docs/de/RECIPE-AUTHORING.md)
- Übersetzungen: [docs/CONTRIBUTING-TRANSLATIONS.md](docs/CONTRIBUTING-TRANSLATIONS.md)
- Im GUI: **Hilfe → Entwickler-Dokumentation…** · **Rezeptor → Neues Rezept…**

---

## 📖 Installationsanleitung

### Detaillierte Schritte

#### Vor der Installation

1. **Host-Pakete** (PyQt6 + Helfer — siehe [Erforderliche Pakete](#erforderliche-pakete-host)). Kein System-Wine.

2. **System prüfen**
   ```bash
   ./pre-check.sh
   ```
   
   Dies validiert:
   - 64-bit Architektur
   - Speicherplatz / RAM
   - Vorhandensein der Installationsdateien
   - Proton-GE / Rezept-Bereitschaft (nicht System-Wine)

#### Während der Installation

1. **Rezeptor-GUI** — `./setup.sh` → Photoshop → Installieren. Komponenten (win10, Fonts, msxml, gdiplus, IE8, VC++ Redist) werden automatisch über Proton-GE gesetzt.

2. **Adobe Photoshop Setup** (10-20 Minuten)
   - Adobe Installer-Fenster erscheint
   - Klicke "Installieren"
   - Wähle Sprache
   - Warte auf Abschluss
   - **Ignoriere** "ARKServiceAdmin" Fehler falls sie erscheinen

Kein manueller Mono-/Gecko-/winecfg-Walkthrough nötig — Rezeptor konfiguriert den Prefix.
#### Nach der Installation

1. **Fehlerbehebung ausführen**
   ```bash
   ./troubleshoot.sh
   ```

2. **Photoshop starten**
   ```bash
   photoshop
   ```
   
   Erster Start dauert 1-2 Minuten (normal!)

3. **GPU deaktivieren**
   - Bearbeiten > Voreinstellungen > Leistung
   - Deaktiviere "Grafikprozessor verwenden"

---


---

## 🐛 Bekannte Probleme & Lösungen

### Problem 1: Photoshop stürzt beim Start ab

**Ursache:** GPU-Beschleunigung Inkompatibilität mit Wine

**Lösung:**
```
1. Starte Photoshop
2. Bearbeiten > Voreinstellungen > Leistung (Strg+K)
3. Deaktiviere "Grafikprozessor verwenden"
4. Deaktiviere "OpenCL verwenden"
5. Starte Photoshop neu
```

### Problem 2: "VCRUNTIME140.dll fehlt"

**Ursache:** Visual C++ Runtime nicht korrekt installiert

**Lösung:** Rezeptor → **Reparieren** (Microsoft VC++ Redist über `recipe_vcrun::ensure`, nicht System-winetricks).
### Problem 3: Liquify-Tool funktioniert nicht

**Ursache:** GPU/OpenCL-Probleme

**Lösung:**
- GPU-Beschleunigung deaktivieren (siehe Problem 1)
- Oder OpenCL deaktivieren: Voreinstellungen > Leistung > Deaktiviere "OpenCL verwenden"

### Problem 4: Verschwommene/Hässliche Schriftarten

**Lösung:** Rezeptor → **Reparieren** (Fonts / Fontsmooth sind Teil des Rezepts).
### Problem 5: Installation hängt bei 100%

**Lösung:**
- Warte 2-3 Minuten
- Falls nichts passiert, schließe Installer (Alt+F4)
- Installation ist wahrscheinlich abgeschlossen
- Überprüfe: `ls ~/.local/share/wine-software/photoshop/prefix/drive_c/Program\ Files/Adobe/`

### Problem 6: "ARKServiceAdmin" Fehler während Installation

**Lösung:**
- Dieser Fehler kann **ignoriert** werden
- Klicke "Ignorieren" oder "Fortfahren"
- Installation wird erfolgreich abgeschlossen

### Problem 7: Langsamer erster Start (1-2 Minuten)

**Kein Problem:**
- Erster Start ist immer langsam
- Weitere Starts dauern 10-30 Sekunden
- Dies ist normales Wine-Verhalten

### Problem 8: Kann nicht als PNG speichern

**Ursache:** Dateiformat-Plugin-Problem in Wine

**Lösung:**
```
1. Datei > Speichern unter
2. Wähle "PNG" aus Format-Dropdown
3. Falls Fehler: Datei > Exportieren > Exportieren als > PNG
4. Alternative: Als PSD speichern, dann mit GIMP als PNG exportieren
```

### Problem 9: Bildschirm aktualisiert nicht sofort (Rückgängig/Wiederholen)

**Ursache:** Wine Rendering-Verzögerung

**Lösung:**
- Dies ist eine bekannte Wine-Einschränkung
- Workaround: Aktualisierung erzwingen mit Strg+0 (An Bildschirm anpassen)
- Lieber Rezeptor → Reparieren statt Virtual Desktop (VD zeigt oft blaue Fläche und ist nicht Standard)

### Problem 10: Zoom ist träge

**Ursache:** GPU-Beschleunigung deaktiviert + Wine-Overhead

**Lösung:**
```
1. Verwende Tastenkürzel (Strg + / Strg -)
2. Zoom mit Mausrad ist langsamer als nativ
3. Dies ist erwartetes Verhalten mit Wine
4. Lieber Tastatur-Zoom; Rezeptor nutzt Proton-GE (nicht wine-staging)
```

### Problem 11: Adobe Installer "Weiter"-Button reagiert nicht

**Ursache:** Adobe Installer verwendet Internet Explorer Engine (mshtml.dll), die in Wine nicht perfekt funktioniert

**Lösung:**
```
1. Installiere IE8 wenn gefragt (dauert 5-10 Minuten, hilft aber erheblich)
2. Warte 15-30 Sekunden - Installer lädt manchmal langsam
3. Verwende Tastaturnavigation:
   - Tab-Taste mehrmals drücken, um Button zu fokussieren
   - Enter drücken zum Klicken
   - Oder: Alt+W (Weiter) / Alt+N (Next)
4. Klicke direkt auf den Button (nicht daneben)
5. Installer-Fenster in den Vordergrund bringen (Alt+Tab)
6. Falls nichts hilft: Rezeptor → **Reparieren**, oder Photoshop-Rezept erneut installieren
```

**Hinweis:** Dies ist eine bekannte Einschränkung von Wine mit IE-basierten Installern. Der Installer hat bereits DLL-Overrides und Registry-Tweaks konfiguriert, um die Kompatibilität zu verbessern.

---

## 🔧 Fehlerbehebung

### Automatische Fehlerbehebung

```bash
./troubleshoot.sh
```

Dieses Tool:
- ✅ Prüft Systemanforderungen
- ✅ Validiert Installation
- ✅ Analysiert Wine-Konfiguration
- ✅ Scannt Logs nach Fehlern
- ✅ Wendet automatische Fixes an wenn möglich
- ✅ Bietet detaillierte Berichte

### Manuelle Fehlerbehebung

#### Logs prüfen

```bash
# Alle Logs werden gespeichert in:
ls ~/.local/share/wine-software/logs/

# Neuestes Log anzeigen
tail -n 50 ~/.local/share/wine-software/logs/*.log | tail -50
```

#### Wine- / Prefix-Einstellungen

Lieber **Rezeptor → Reparieren** statt rohem winecfg. Prefix nur bei Bedarf über Proton-GE / Projekt-Helfer prüfen (nicht System-`/usr/bin/winecfg`).

Rezeptor-Defaults:
- **Windows-Version:** Windows 10
- **Virtual Desktop:** aus (nur als letzter Ausweg bei Vollbild-Problemen)

#### Komponenten neu installieren

Rezeptor → **Reparieren** für das Photoshop-Rezept. Manuelles winetricks gegen System-Wine wird nicht unterstützt.
---

## 🚀 Performance-Tipps

### Essentiell (Für Stabilität)

1. **GPU/OpenCL aus** — Rezeptor setzt das automatisch; bei Drift: Reparieren
2. **Mehrthread-Composing** (ohne GPU): *Bearbeiten → Voreinstellungen → Leistung* manuell an

### Optional (Für Geschwindigkeit)

3. **CSMT** (bereits in Rezept-Registry; bei Drift: Rezeptor → Reparieren)

4. **Kein Virtual Desktop** — Rezeptor lässt VD aus (blaue Fläche). Nur als letzter Ausweg, nicht als Performance-Tipp.
### Erwartete Performance

| Feature | Native Windows | Wine Linux | Notizen |
|---------|---------------|------------|---------|
| Basis-Tools | 100% | 90-95% | Ausgezeichnet |
| Filter | 100% | 80-90% | Gut |
| Liquify | 100% | 70-80% | Nutzbar (GPU aus) |
| 3D Features | 100% | 30-50% | Eingeschränkt |
| Camera Raw | 100% | 60-80% | Nutzbar |
| Startzeit | 5-10s | 10-30s | Nach erstem Start |

**Gesamt:** 85-90% der nativen Performance für Standard-Fotobearbeitung.

---

## 🗑️ Deinstallation

### Über Rezeptor

`./setup.sh` → Photoshop → **Deinstallieren**

### CLI

```bash
bash recipes/photoshop/uninstall.sh
bash recipes/photoshop/kill.sh   # nur hängende Prozesse
```

Entfernt Prefix, Desktop-Eintrag und Symlinks.

### Manuelle Entfernung

```bash
# Installation entfernen
rm -rf ~/.local/share/wine-software/photoshop/

# Desktop-Eintrag entfernen
rm -f ~/.local/share/applications/photoshop.desktop
```

Es gibt kein Produkt-CLI `photoshop` — Start über Rezeptor oder Desktop-Eintrag.
---

## 🤝 Mithelfen

**Wir brauchen deine Hilfe!** Dieses Projekt wird durch Beiträge aus der Community besser.

### Wie du helfen kannst

#### 🐛 Fehler melden
Etwas funktioniert nicht? Lass es uns wissen!
- [Öffne ein GitHub Issue](https://github.com/benjarogit/rezeptor/issues)
- Bitte angeben: Linux-Distribution, Wine-Version, Fehler-Logs, Schritte zur Reproduktion
- Auch wenn du dir nicht sicher bist - melde es trotzdem!

#### 💡 Features vorschlagen
Hast du eine Idee, wie wir das besser machen können?
- [Öffne einen Feature-Request](https://github.com/benjarogit/rezeptor/issues)
- Beschreibe was du dir wünschst
- Erkläre warum es hilfreich wäre

#### 🔧 Fixes & Workarounds teilen
Eine Lösung für ein Problem gefunden?
- Teile sie in den [GitHub Issues](https://github.com/benjarogit/rezeptor/issues)
- Hilf anderen mit dem gleichen Problem
- Deine Erfahrung hilft allen!

#### 📝 Dokumentation verbessern
Etwas in der README unklar gefunden?
- [Öffne ein Issue](https://github.com/benjarogit/rezeptor/issues) oder sende einen Pull Request
- Hilf dabei, das für Anfänger einfacher zu machen
- Übersetze in andere Sprachen

#### 💻 Code beitragen
Möchtest du Code beitragen?
1. Forke das Repository
2. Erstelle einen Feature-Branch
3. Neue Apps: [docs/RECIPE-AUTHORING.md](docs/RECIPE-AUTHORING.md) und `recipes/_template/`
4. Teste deine Änderungen gründlich
5. Sende einen Pull Request mit klarer Beschreibung

**Jeder Beitrag, groß oder klein, macht dieses Projekt besser! 🙏**

---

## 📚 Weitere Ressourcen

### Offizielle Ressourcen

- **English Documentation:** [README.md](README.md)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md) - Siehe aktuelle Änderungen und vorherige Versionen
- **Schnellstart-Anleitung:** Schnellstart-Sektion oben

### Alternative Lösungen

Falls dieser Installer für dich nicht funktioniert, erwäge diese Alternativen:

- **[PhotoGIMP](https://github.com/Diolinux/PhotoGIMP)** - GIMP konfiguriert wie Photoshop
- **[Krita](https://krita.org/)** - Professionelles Malen und Illustration (nativ Linux)
- **[Photopea](https://www.photopea.com/)** - Online Photoshop Alternative (Browser-basiert)

### Originales Projekt

- [Original Gictorbit Projekt](https://github.com/Gictorbit/photoshopCClinux) - Basiert auf diesem Projekt

---

## 📄 Lizenz

Dieses Projekt ist unter der **GPL-2.0 Lizenz** lizenziert - siehe die [LICENSE](LICENSE) Datei für Details.

### Rechtlicher Hinweis

- ⚠️ Adobe Photoshop ist proprietäre Software von Adobe Inc.
- ⚠️ Du benötigst eine gültige Lizenz um Photoshop zu verwenden
- ⚠️ Dieses Script automatisiert nur die Wine-Installation
- ⚠️ Keine Piraterie wird unterstützt oder gefördert
- ✅ Verwendung auf eigene Gefahr

---

## 🙏 Danksagungen

- **[Gictorbit](https://github.com/Gictorbit)** - Original Installer-Script
- **Wine Team** - Windows Kompatibilitätsschicht
- **Community Contributors** - Fehlerberichte und Fixes

---

## 📊 Projekt-Status

![GitHub last commit](https://img.shields.io/github/last-commit/benjarogit/rezeptor)
![GitHub issues](https://img.shields.io/github/issues/benjarogit/rezeptor)
![GitHub stars](https://img.shields.io/github/stars/benjarogit/rezeptor)

**Status:** ✅ Produktionsreif (Komplettes Toolset)

**Getestet auf:**
- CachyOS Linux (Arch-basiert) mit KDE Desktop-Umgebung

---

## ❓ FAQ

<details>
<summary><b>F: Brauche ich ein Adobe-Konto?</b></summary>

Du benötigst eine gültige Photoshop-Lizenz, aber du kannst den Offline-Installer ohne Anmeldung während der Installation verwenden. Deaktiviere die Internetverbindung während des Setups.
</details>

<details>
<summary><b>F: Welche Photoshop-Version funktioniert?</b></summary>

Nur Photoshop CC 2021 (v22.x) wurde getestet und funktioniert. Andere Versionen wurden nicht getestet.
</details>

<details>
<summary><b>F: Kann ich Plugins verwenden?</b></summary>

Die meisten Plugins funktionieren. Installiere sie nach: `~/.local/share/wine-software/photoshop/prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2021/Plug-ins/`
</details>

<details>
<summary><b>F: Funktioniert Camera Raw?</b></summary>

Ja! Nach der Photoshop-Installation:

```bash
bash recipes/photoshop/optional/cameraRawInstaller.sh
```
</details>

<details>
<summary><b>F: Warum ist GPU deaktiviert?</b></summary>

Wine hat eingeschränkte GPU-Beschleunigungsunterstützung. Deaktivierung verhindert Abstürze und verbessert Stabilität.
</details>

<details>
<summary><b>F: Kann ich andere Photoshop-Versionen verwenden?</b></summary>

Nur CC 2021 (v22.x) wurde getestet. Andere Versionen wurden nicht getestet und funktionieren möglicherweise nicht.
</details>

---

## 💬 Support

- 🐛 **Fehlerberichte:** [GitHub Issues](https://github.com/benjarogit/rezeptor/issues)
- 💡 **Feature-Requests:** [GitHub Issues](https://github.com/benjarogit/rezeptor/issues)
- 📖 **Dokumentation:** Siehe Dateien in diesem Repository
- 🔧 **Automatische Hilfe:** Führe `./troubleshoot.sh` aus

---

## 📄 Lizenz & Copyright

**Copyright © 2024-2026 Sunny C.**

Dieses Projekt ist unter der **GPL-2.0 Lizenz** lizenziert.

Basiert auf [photoshopCClinux](https://github.com/Gictorbit/photoshopCClinux) von Gictorbit.

---

**Mit ❤️ für die Linux-Community**

**Gib diesem Repo einen Stern ⭐ wenn es dir geholfen hat!**

