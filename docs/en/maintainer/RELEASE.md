# Release & AppImage

Maintainer guide for builds and publishing. SemVer lives in the root `VERSION` file.

## Triggers

`.github/workflows/release.yml`:

- Change to `VERSION` on `main`
- Tag `v*`
- Manual (`workflow_dispatch`)

Pipeline: Validate → `tar.gz` + AppImage → `SHA256SUMS` → GitHub Release.

**Docs-only changes:** do not bump `VERSION` — docs deploy via `.github/workflows/docs.yml` on push to `main`.

## Local builds

```bash
# Full source package
./scripts/build-release-package.sh

# AppImage (bundles Proton-GE per runtime.lock, PyQt6+Fluent, checks manifest)
./scripts/build-appimage.sh
```

Artifacts typically at repo root / build dir; names `rezeptor-${VERSION}.tar.gz` and `rezeptor-${VERSION}-x86_64.AppImage`.

AppImage entry: `AppDir/AppRun` sets `PROJECT_ROOT` and `REZEPTOR_APPIMAGE=1`.

## Quality before release

1. `make validate && make test`
2. Checklist [RELEASE-QA](RELEASE-QA.md)
3. Manual: [MANUAL-QA](MANUAL-QA.md) / [TEST-PLAN](TEST-PLAN.md)
4. Manifest current (`make recipe-manifest-check`)
5. After publish: `sha256sum -c SHA256SUMS` on the assets

## Docs site

```bash
pip install -r requirements-docs.txt
mkdocs build
```

Deploy: workflow `docs.yml` → GitHub Pages (`https://benjarogit.github.io/rezeptor/`).  
If 404: Repo → Settings → Pages → Source **gh-pages** (peaceiris orphan branch).

## Makefile note

There is **no** `make appimage` / `make docs` — use the scripts or `mkdocs` directly.

## Next

- [RELEASE-QA](RELEASE-QA.md)
- [Trust & manifest](../TRUST.md)
