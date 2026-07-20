---
title: Home
hide:
  - toc
---

<div class="rz-hero" markdown>

![Rezeptor](../assets/rezeptor-icon.svg){ loading=eager }

<div class="rz-hero__text" markdown>

# Rezeptor Documentation

Official **handbook** for Rezeptor — install, validate, launch, and cleanly remove Windows software under **Proton-GE** on Linux. For users and recipe authors.

</div>

</div>

!!! info "Important for newcomers"

    Rezeptor **does not redistribute Windows applications**. You bring your legal source (**BYOS**). Each recipe knows how to install, repair, validate, launch, and uninstall under Proton-GE.

!!! tip "Quick start"

    1. Download a [release](https://github.com/benjarogit/rezeptor/releases) **or** run `./setup.sh` in a clone
    2. Pick a recipe → set source → **Install**
    3. Check status (F5) → **Launch**
    4. Overview → [User guide](USER-GUIDE.md)

    Switch language: top right (**DE / EN**).

## Topics

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } __Quick start__

    ---

    Installation, first steps, and data locations.

    [:octicons-arrow-right-24: Quick start](GETTING-STARTED.md)

-   :material-book-open-page-variant:{ .lg .middle } __User guide__

    ---

    GUI, sources, validate, repair, uninstall.

    [:octicons-arrow-right-24: User guide](USER-GUIDE.md)

-   :material-package-variant:{ .lg .middle } __Recipe catalog__

    ---

    Official vs community recipes, trust, multi-source.

    [:octicons-arrow-right-24: Catalog](CATALOG.md)

-   :material-code-braces:{ .lg .middle } __For developers__

    ---

    Authoring recipes, Core API, validate/repair contract.

    [:octicons-arrow-right-24: Developer overview](ENTWICKLER.md)

-   :material-file-tree:{ .lg .middle } __Project layout__

    ---

    Repo layout, `recipes/`, `core/`, `launcher/`.

    [:octicons-arrow-right-24: Layout](PROJECT-LAYOUT.md)

-   :material-shield-check:{ .lg .middle } __Trust & manifest__

    ---

    SHA256 integrity, Dev mode, community path.

    [:octicons-arrow-right-24: Trust](TRUST.md)

-   :material-pattern:{ .lg .middle } __Patterns__

    ---

    Installer, portable, Steam+fix, trainer.

    [:octicons-arrow-right-24: Offline installer](INSTALLER.md)

-   :material-handshake:{ .lg .middle } __Contributing__

    ---

    PRs, lint, tests, translations.

    [:octicons-arrow-right-24: Contributing](CONTRIBUTING.md)

</div>

## In the repository

| Topic | Link |
|-------|------|
| Releases (AppImage / Flatpak / tar.gz) | [GitHub Releases](https://github.com/benjarogit/rezeptor/releases) |
| Project README | [README.md](https://github.com/benjarogit/rezeptor/blob/main/README.md) |
| Contributing (translations) | [CONTRIBUTING-TRANSLATIONS.md](CONTRIBUTING-TRANSLATIONS.md) |
| Brand | [BRAND.md](BRAND.md) |

```bash
make validate                 # shellcheck, syntax, recipe-lint, manifest
make test                     # bats
```

!!! note "Preview the site locally"

    ```bash
    python3 -m venv .venv-docs
    . .venv-docs/bin/activate
    pip install -r requirements-docs.txt
    mkdocs serve
    ```
