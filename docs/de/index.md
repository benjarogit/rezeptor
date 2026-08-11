---
title: Start
hide:
  - toc
---

<div class="rz-hero" markdown>

![Rezeptor](../assets/rezeptor-icon.svg){ loading=eager }

<div class="rz-hero__text" markdown>

<div class="rz-hero__meta" markdown>
<span class="rz-chip rz-chip--tested">:material-check-bold: Getestet</span>
<span class="rz-chip rz-chip--byos">:material-package-variant: BYOS</span>
<span class="rz-chip rz-chip--experimental">:material-flask-outline: Proton-GE</span>
</div>

# Rezeptor Dokumentation

Offizielles **Handbuch** für Rezeptor — Windows-Software unter **Proton-GE** auf Linux installieren, prüfen, starten und sauber entfernen. Für Nutzer und Rezept-Autoren.

<div class="rz-hero__actions" markdown>
[Releases herunterladen](https://github.com/benjarogit/rezeptor/releases){ .md-button .md-button--primary }
[Schnellstart](GETTING-STARTED.md){ .md-button }
[GitHub](https://github.com/benjarogit/rezeptor){ .md-button }
</div>

</div>

</div>

!!! info "Wichtig für Einsteiger"

    Rezeptor **verteilt keine Windows-Programme**. Du bringst deine legale Quelle mit (**BYOS**). Jedes Rezept weiß, wie Installation, Reparatur, Validierung, Start und Deinstallation unter Proton-GE funktionieren.

!!! tip "Schnellstart in vier Schritten"

    1. [Release](https://github.com/benjarogit/rezeptor/releases) laden **oder** `./setup.sh` im Klon
    2. Rezept wählen → Quelle setzen → **Installieren**
    3. Status prüfen (++f5++) → **Starten**
    4. Überblick → [Benutzerhandbuch](USER-GUIDE.md)

    Sprache umschalten: oben rechts (**DE / EN**).

## Pfade

=== "Nutzer"

    | Ziel | Seite |
    |------|--------|
    | Installation & erste Schritte | [Schnellstart](GETTING-STARTED.md) |
    | GUI, Quellen, Lifecycle | [Benutzerhandbuch](USER-GUIDE.md) |
    | Was ist mitgeliefert? | [Rezept-Katalog](CATALOG.md) |

    [:octicons-download-24: AppImage / Flatpak / tar.gz](https://github.com/benjarogit/rezeptor/releases){ .md-button .md-button--primary }

=== "Rezept-Autoren"

    | Ziel | Seite |
    |------|--------|
    | Einstieg & Rezept-Typen | [Entwickler](ENTWICKLER.md) |
    | `recipe.yml` / `install_steps` | [RECIPE-AUTHORING](RECIPE-AUTHORING.md) |
    | Shared Core | [CORE-API](CORE-API.md) |
    | Validate → Repair | [VALIDATE-REPAIR](VALIDATE-REPAIR.md) |

    [:octicons-code-24: Mitmachen](CONTRIBUTING.md){ .md-button .md-button--primary }

## Themen

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } __Schnellstart__

    ---

    Installation, erste Schritte und Datenorte.

    [:octicons-arrow-right-24: Zum Schnellstart](GETTING-STARTED.md)

-   :material-book-open-page-variant:{ .lg .middle } __Benutzerhandbuch__

    ---

    GUI, Quellen, Validieren, Reparieren, Deinstallieren.

    [:octicons-arrow-right-24: Zum Handbuch](USER-GUIDE.md)

-   :material-package-variant:{ .lg .middle } __Rezept-Katalog__

    ---

    Offizielle vs. Community-Rezepte, Vertrauen, Multi-Source.

    [:octicons-arrow-right-24: Zum Katalog](CATALOG.md)

-   :material-code-braces:{ .lg .middle } __Für Entwickler__

    ---

    Rezepte schreiben, Core-API, Validate/Repair-Vertrag.

    [:octicons-arrow-right-24: Entwickler-Übersicht](ENTWICKLER.md)

-   :material-file-tree:{ .lg .middle } __Projektstruktur__

    ---

    Repo-Layout, `recipes/`, `core/`, `launcher/`.

    [:octicons-arrow-right-24: Layout](PROJECT-LAYOUT.md)

-   :material-shield-check:{ .lg .middle } __Trust & Manifest__

    ---

    SHA256-Integrität, Dev-Mode, Community-Pfad.

    [:octicons-arrow-right-24: Trust](TRUST.md)

-   :material-shape-outline:{ .lg .middle } __Muster__

    ---

    Installer, Portable, Steam+Fix, Updates, Trainer.

    [:octicons-arrow-right-24: Offline-Installer](INSTALLER.md)

-   :material-handshake:{ .lg .middle } __Mitwirken__

    ---

    PRs, Lint, Tests, Übersetzungen.

    [:octicons-arrow-right-24: Contributing](CONTRIBUTING.md)

</div>

## Status-Farben (Marke)

| Chip | Bedeutung |
|------|-----------|
| <span class="rz-chip rz-chip--tested">Getestet</span> | Garantierte / geprüfte Heilung im Rezept |
| <span class="rz-chip rz-chip--experimental">Experimentell</span> | Noch nicht hart abgesichert |
| <span class="rz-chip rz-chip--byos">BYOS</span> | Quelle bringst du mit — kein Download im Repo |

Siehe [BRAND.md](BRAND.md).

## Im Repository

| Thema | Link |
|-------|------|
| Releases (AppImage / Flatpak / tar.gz) | [GitHub Releases](https://github.com/benjarogit/rezeptor/releases) |
| Projekt-README | [README.md](https://github.com/benjarogit/rezeptor/blob/main/README.md) |
| Mitwirken (Übersetzungen) | [CONTRIBUTING-TRANSLATIONS.md](CONTRIBUTING-TRANSLATIONS.md) |
| Marke | [BRAND.md](BRAND.md) |

```bash
make validate                 # shellcheck, syntax, compile, i18n-check, ruff, recipes-check, recipe-lint, manifest
make test                     # bats
```

!!! success "Lokal die Site prüfen"

    ```bash
    python3 -m venv .venv-docs
    . .venv-docs/bin/activate
    pip install -r requirements-docs.txt
    mkdocs serve
    ```
