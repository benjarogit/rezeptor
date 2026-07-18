# Mitwirken

Beiträge zu Rezepten, Launcher, Core und Doku sind willkommen. Bitte klein, testbar und ohne Secrets halten.

## Entwicklungsumgebung

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
# Distro: python-pyqt6, bats-core, shellcheck (Namen variieren)
pip install --user PyQt6-Fluent-Widgets   # optional
make validate
make test
REZEPTOR_DEV=1 ./setup.sh
```

Doku lokal:

```bash
pip install -r requirements-docs.txt
mkdocs serve
```

## Qualitätstor

Vor jedem PR:

```bash
make validate          # shellcheck, syntax, compile, recipes-check, lint, manifest
make test              # bats
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh   # nach Rezept-Dateiänderungen → commit
```

`make validate` → `shellcheck` prüft nur `core/`, `recipes/photoshop`, `recipes/wiso-steuer`, `launcher/`, `scripts/`.  
`bash -n` (Target `syntax`) deckt alle `recipes/*/*.sh` ab; für andere Rezepte zusätzlich `./scripts/recipe-lint.sh`.

## Rezepte

1. `./scripts/new-recipe.sh …` oder GUI **Neues Rezept…**
2. `recipe.yml` + Hooks gemäß [Entwickler-Übersicht](ENTWICKLER.md)
3. Mit echter Quelle testen (Install → Validate → Repair → Launch → Uninstall)
4. Manifest aktualisieren
5. Keine App-Binaries im Repo (BYOS)

Ideen: [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md).

## Doku & Übersetzungen

- Seiten spiegeln unter `docs/de/` und `docs/en/` (gleiche Dateinamen)
- UI-Strings: [Übersetzungen](CONTRIBUTING-TRANSLATIONS.md)
- Marke: [BRAND](BRAND.md) — keine Purple-Themes

## Git-Hinweise

- SemVer über Datei `VERSION` — nur bumpen, wenn ein Release beabsichtigt ist
- Keine Co-Author-Trailer von Editor-Agenten in Commits
- Keine Secrets (Tokens, private Installer) committen

## Releases

- SemVer in `VERSION` bumpen und auf `main` pushen → GitHub Actions baut AppImage/`tar.gz` und veröffentlicht das Release
- Assets: https://github.com/benjarogit/rezeptor/releases

## Weiter

- [Projektstruktur](PROJECT-LAYOUT.md)
- [Trust & Manifest](TRUST.md)
