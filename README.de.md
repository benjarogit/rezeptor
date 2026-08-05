<p align="center">
  <img src="images/rezeptor-icon.png" alt="Rezeptor" width="128" height="128">
</p>

<h1 align="center">Rezeptor</h1>

<p align="center">
  <strong>Windows-Software unter Linux installieren und starten</strong> —<br>
  mit getesteten Rezepten, <strong>Proton-GE</strong> und einer einfachen Desktop-Oberfläche.
</p>

<p align="center">
  <a href="https://github.com/benjarogit/rezeptor/releases"><img src="https://img.shields.io/github/v/release/benjarogit/rezeptor?include_prereleases&label=Release&color=B87333&logo=github&logoColor=white" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Lizenz-GPL--2.0-2B6CB0?logo=gnu&logoColor=white" alt="Lizenz"></a>
  <a href="https://benjarogit.github.io/rezeptor/"><img src="https://img.shields.io/badge/Doku-Rezeptor%20Docs-3D7A8C?logo=gitbook&logoColor=white" alt="Doku"></a>
  <img src="https://img.shields.io/badge/AI-unterst%C3%BCtzt-5C5C58?logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJsMS4yIDMuNkwxNyA3bC0zLjggMS40TDEyIDEybC0xLjItMy42TDcgN2wzLjgtMS40TDEyIDJ6bTAgMTBsLjkgMi43TDE2IDE2bC0zLjEgMS4xTDEyIDIwbC0uOS0yLjlMOCAxNmwzLjEtMS4zTDEyIDEyek00IDlsLjcgMi4xTDcgMTJsLTIuMy44TDQgMTVsLS43LTIuMkwxIDEybDIuMy0uOUw0IDl6bTE2IDBsLjcgMi4xTDIzIDEybC0yLjMuOEwyMCAxNWwtLjctMi4yTDE3IDEybDIuMy0uOUwyMCA5eiIvPjwvc3ZnPg%3D%3D" alt="AI-unterstützt">
  <a href="https://www.reddit.com/r/photoshop/comments/1vau4wh/fyi_photoshop_cc_2021_on_ubuntu_finally/"><img src="https://img.shields.io/badge/Reddit-User--Bericht-FF4500?logo=reddit&logoColor=white" alt="Reddit User-Bericht"></a>
</p>

<p align="center">
  <a href="https://github.com/benjarogit/rezeptor/stargazers"><img src="https://img.shields.io/github/stars/benjarogit/rezeptor?style=flat&color=C9A227&logo=github&logoColor=white" alt="Stars"></a>
  <a href="https://github.com/benjarogit/rezeptor/issues"><img src="https://img.shields.io/github/issues/benjarogit/rezeptor?color=5C6B7A&logo=github&logoColor=white" alt="Issues"></a>
  <a href="https://github.com/benjarogit/rezeptor/commits/main"><img src="https://img.shields.io/github/last-commit/benjarogit/rezeptor?label=letzter%20Commit&color=6B7280&logo=git&logoColor=white" alt="Letzter Commit"></a>
  <a href="https://github.com/benjarogit/rezeptor/releases"><img src="https://img.shields.io/github/downloads/benjarogit/rezeptor/total?label=Downloads&color=4A7C59&logo=github&logoColor=white" alt="Downloads"></a>
</p>

Photoshop, Steuerprogramme (WISO), Steam-Spiele mit Online-Fix, Trainer und mehr: Jedes Rezept weiß, wie Installation, Reparatur, Prüfung, Start und saubere Deinstallation funktionieren.

> **Nachfolgeprojekt.**  
> Weiterentwicklung nur noch hier. Die älteren Repositories
> [photoshopCClinux](https://github.com/benjarogit/photoshopCClinux),
> [wiso-steuer-portable-linux](https://github.com/benjarogit/wiso-steuer-portable-linux) und
> [crkcachy](https://github.com/benjarogit/crkcachy)
> sind archiviert — Issues und PRs bitte in **diesem** Repo öffnen.

Support weiterhin über [GitHub Issues](https://github.com/benjarogit/rezeptor/issues) (nicht über Reddit).

## Was du bekommst

- **GUI-Launcher** — Rezept wählen, installieren, starten, reparieren oder entfernen
- **Nur Proton-GE** — kein System-Wine-Fallback in Rezepten
- **Statusprüfung** — optional beim Start; jederzeit neu prüfen (F5)
- **System-Tools** — fehlende Pakete einmalig vorschlagen
- **Katalog & Quellen** — offizielle Rezepte plus Community-Pfad
- **Rezept-Sync** — neue/aktualisierte offizielle Rezepte vom Release-Bundle (Hilfe → Rezepte aktualisieren)
- **Daten unter** `~/.local/share/wine-software/`

![Rezeptor Startseite — Dashboard mit Statistik und GitHub-/Wiki-Karten](images/rezeptor-home-de.png)

## Schnellstart

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
./setup.sh
```

Benötigt **PyQt6** auf dem Host (`python-pyqt6` unter Arch/CachyOS bzw. Distro-Paket) bei **Git-Clone** oder **`tar.gz`**-Release (`./setup.sh`).

Das **`AppImage`** bringt eigenes Python und PyQt6 mit — kein hostseitiges `python-pyqt6` nötig (empfohlen auf Bazzite und anderen immutable Distros).

Das **`Flatpak`** bringt Python, PyQt6 und Proton-GE ebenfalls mit. Installation aus dem Release-Bundle:

```bash
flatpak install --user rezeptor-<version>-x86_64.flatpak
flatpak run io.github.benjarogit.Rezeptor
```

Oder lokal bauen: `scripts/build-flatpak.sh` (benötigt `flatpak-builder`).

Oder ein **[Release](https://github.com/benjarogit/rezeptor/releases)** (`tar.gz`, AppImage oder Flatpak). Portable Builds prüfen mit `sha256sum -c SHA256SUMS` (tar.gz + AppImage).

## Dokumentation

### → [Rezeptor Docs](https://benjarogit.github.io/rezeptor/)

- [Deutsch](https://benjarogit.github.io/rezeptor/) · [English](https://benjarogit.github.io/rezeptor/en/)
- Lokal: `pip install -r requirements-docs.txt && mkdocs serve`

## Rezepte

<details>
<summary><strong>Mitgelieferte offizielle Rezepte</strong> (8 — zum Aufklappen)</summary>

| ID | Name | Kategorie | Hinweis |
|----|------|-----------|---------|
| `photoshop` | Adobe Photoshop CC 2021 | Grafik & Design | Standard-Offline-Installer (22.0.0.35) |
| `photoshop-m0nkrus-220` | Adobe Photoshop CC 2021 (m0nkrus 22.0.0.35) | Grafik & Design | ISO-only-m0nkrus-Pack (nicht Standard / nicht 22.1.1.138) |
| `photoshop-m0nkrus` | Adobe Photoshop CC 2021 (m0nkrus 22.1.1.138) | Grafik & Design | Vollpack + Neural / missing_libs / GenP (optional) |
| `premiere` | Adobe Premiere Pro 2024 | Video & Schnitt | NVIDIA: CUDA via nvidia-libs |
| `wiso-steuer` | WISO Steuer (Portable) | Finanzen & Steuer | Portable unter Proton-GE |
| `halo-campaign-evolved` | Halo Campaign Evolved | Spiele | Pack MULTi13-ElAmigos + nummerierte Updates |

</details>

Volle Liste nach Kategorien: [Rezept-Katalog (Doku)](https://benjarogit.github.io/rezeptor/de/CATALOG/). Index: [`recipes/catalog.json`](recipes/catalog.json).

| Ort | Rolle |
|-----|--------|
| `recipes/<id>/` | Mitgeliefert / offiziell |
| `recipes/community/<id>/` | Community |

Ideen einreichen über [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md).

## Rezepte beitragen & Rezeptor verbessern

Rezeptor wächst durch **erprobte Rezepte** und **gemeinsame Core-Logik** — ein eigener Fork ist nicht nötig.

| Ziel | Einstieg |
|------|----------|
| **Neues Rezept** (App/Spiel, das bei dir läuft) | [Entwickler-Doku](https://benjarogit.github.io/rezeptor/de/ENTWICKLER/) · `./scripts/new-recipe.sh` · `recipes/community/<id>/` |
| **Core/Launcher verbessern** (Prefix, validate, install_steps, GUI) | [CORE-API](https://benjarogit.github.io/rezeptor/de/CORE-API/) · [RECIPE-AUTHORING](https://benjarogit.github.io/rezeptor/de/RECIPE-AUTHORING/) |
| **Idee ohne sofortigen PR** | [Recipe-Submission-Issue](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md) oder [Discussion](https://github.com/benjarogit/rezeptor/discussions) |

PRs mit funktionierendem Rezept **oder** wiederverwendbarer `core/`-/Launcher-Logik sind gleichermaßen willkommen. Vor dem PR: `./scripts/recipe-lint.sh` und `make recipes-check`.

## Versionierung

Releases folgen **SemVer** (`MAJOR.MINOR.PATCH`). Aktuell: **1.1.21**.

## English

→ [README.md](README.md) · [Documentation](https://benjarogit.github.io/rezeptor/en/README/)

## Lizenz

GPL-2.0 — siehe [LICENSE](LICENSE).
