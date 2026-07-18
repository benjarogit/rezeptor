#!/usr/bin/env bash
# Build portable source package (tar.gz) for ./setup.sh installs — no Proton/AppImage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo dev)"
NAME="rezeptor-${VERSION}"
STAGING="${ROOT}/.cache/release-package/${NAME}"
OUT="${ROOT}/${NAME}.tar.gz"

rm -rf "${ROOT}/.cache/release-package"
mkdir -p "$STAGING"

echo "Building release package ${NAME}.tar.gz..."
rsync -a \
    --exclude '.git' \
    --exclude '.cache' \
    --exclude 'AppDir-build' \
    --exclude 'AppDir' \
    --exclude 'logs' \
    --exclude 'site' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '.cursor' \
    --exclude 'assets' \
    --exclude 'docs/Archiv.zip' \
    --exclude '*.AppImage' \
    --exclude '*.AppImage.sha256' \
    --exclude 'SHA256SUMS' \
    --exclude 'rezeptor-*.tar.gz' \
    --exclude 'photoshop/Set-up.exe' \
    --exclude 'photoshop/packages' \
    --exclude 'photoshop/products' \
    "$ROOT/" "$STAGING/"

# Top-level folder inside archive: rezeptor-X.Y.Z/
tar -C "${ROOT}/.cache/release-package" -czf "$OUT" "$NAME"
ls -lh "$OUT"
echo "Created: $OUT"
