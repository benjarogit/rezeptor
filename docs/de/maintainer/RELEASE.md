# Release & AppImage

Maintainer-Leitfaden für Builds und Veröffentlichungen. SemVer steht in der Datei `VERSION` im Repo-Root.

## Auslöser

`.github/workflows/release.yml`:

- Änderung an `VERSION` auf `main`
- Tag `v*`
- Manuell (`workflow_dispatch`)

Pipeline: Validate → `tar.gz` + AppImage → `SHA256SUMS` → GitHub Release.

**Docs-only-Änderungen:** `VERSION` nicht bumpen — Docs deployen über `.github/workflows/docs.yml` bei Push auf `main`.

## Lokale Builds

```bash
# Vollständiges Quellpaket
./scripts/build-release-package.sh

# AppImage (bundelt Proton-GE laut runtime.lock, PyQt6+Fluent, prüft Manifest)
./scripts/build-appimage.sh
```

Artefakte typischerweise im Repo-Root / Build-Dir; Namen `rezeptor-${VERSION}.tar.gz` und `rezeptor-${VERSION}-x86_64.AppImage`.

AppImage-Entry: `AppDir/AppRun` setzt `PROJECT_ROOT` und `REZEPTOR_APPIMAGE=1`.

## Qualität vor Release

1. `make validate && make test`
2. Checkliste [RELEASE-QA](RELEASE-QA.md)
3. Manuell: [MANUAL-QA](MANUAL-QA.md) / [TEST-PLAN](TEST-PLAN.md)
4. Manifest aktuell (`make recipe-manifest-check`)
5. Nach Publish: `sha256sum -c SHA256SUMS` auf den Assets

## Docs-Site

```bash
pip install -r requirements-docs.txt
mkdocs build
```

Deploy: workflow `docs.yml` → GitHub Pages (`https://benjarogit.github.io/rezeptor/`).  
Falls 404: Repo → Settings → Pages → Source **gh-pages** (peaceiris orphan branch).

## Makefile-Hinweis

Es gibt **kein** `make appimage` / `make docs` — Scripts bzw. `mkdocs` direkt nutzen.

## Weiter

- [RELEASE-QA](RELEASE-QA.md)
- [Trust & Manifest](../TRUST.md)
