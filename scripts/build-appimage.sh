#!/usr/bin/env bash
# Build photoshopCClinux AppImage (core + photoshop recipe + Proton-GE + PyQt6 hint)
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\n' < "$ROOT/VERSION" 2>/dev/null || echo dev)"
APPDIR="$ROOT/AppDir-build"
OUT="$ROOT/photoshopCClinux-${VERSION}-x86_64.AppImage"

# shellcheck source=/dev/null
source "$ROOT/core/runtime.lock"

echo "Building AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/share/photoshopCClinux"

rsync -a \
    --exclude AppDir-build \
    --exclude '.git' \
    --exclude 'logs' \
    --exclude 'photoshop/Set-up.exe' \
    --exclude 'photoshop/packages' \
    --exclude 'photoshop/products' \
    "$ROOT/core" \
    "$ROOT/recipes" \
    "$ROOT/launcher" \
    "$ROOT/setup.sh" \
    "$ROOT/pre-check.sh" \
    "$ROOT/VERSION" \
    "$ROOT/photoshop/README.md" \
    "$ROOT/images" \
    "$APPDIR/usr/share/photoshopCClinux/"

mkdir -p "$APPDIR/usr/share/photoshopCClinux/photoshop"
cp "$ROOT/AppDir/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

mkdir -p "$APPDIR/runtime/proton-ge"
if [ ! -d "$APPDIR/runtime/proton-ge/$PROTON_GE_TAG/files/bin" ]; then
    echo "Downloading Proton-GE $PROTON_GE_TAG for bundle..."
    cache="$ROOT/.cache/proton-ge-build"
    mkdir -p "$cache"
    if [ ! -f "$cache/${PROTON_GE_TAG}.tar.gz" ]; then
        curl -fsSL "$PROTON_GE_URL" -o "$cache/${PROTON_GE_TAG}.tar.gz"
    fi
    if [ -n "${PROTON_GE_SHA256:-}" ]; then
        echo "${PROTON_GE_SHA256}  $cache/${PROTON_GE_TAG}.tar.gz" | sha256sum -c - >/dev/null 2>&1 || {
            echo "Proton-GE SHA256 mismatch — delete $cache/${PROTON_GE_TAG}.tar.gz and retry" >&2
            exit 1
        }
    fi
    tar -xzf "$cache/${PROTON_GE_TAG}.tar.gz" -C "$APPDIR/runtime/proton-ge"
fi

cat > "$APPDIR/photoshopCClinux.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Photoshop CC Linux
Exec=setup.sh
Icon=photoshop
Categories=Graphics;
EOF

echo "Creating AppImage venv with PyQt6..."
python3 -m venv "$APPDIR/venv"
"$APPDIR/venv/bin/pip" install -q --upgrade pip
"$APPDIR/venv/bin/pip" install -q PyQt6

if ! command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool not found. AppDir prepared at: $APPDIR"
    exit 1
fi

ARCH=x86_64 appimagetool "$APPDIR" "$OUT"
echo "Created: $OUT"
