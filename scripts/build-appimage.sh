#!/usr/bin/env bash
# Build Rezeptor AppImage (core + recipes + Proton-GE + PyQt6/Fluent + winetricks).
# Snapshot of this repo tree — same code as ./setup.sh / launcher .sh path.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\n' < "$ROOT/VERSION" 2>/dev/null || echo dev)"
APPDIR="$ROOT/AppDir-build"
OUT="$ROOT/rezeptor-${VERSION}-x86_64.AppImage"
SHARE="$APPDIR/usr/share/rezeptor"

# shellcheck source=/dev/null
source "$ROOT/core/runtime.lock"

echo "Building AppDir (Rezeptor ${VERSION})..."
rm -rf "$APPDIR"
mkdir -p "$SHARE"

rsync -a \
    --exclude AppDir-build \
    --exclude '.git' \
    --exclude 'logs' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude 'photoshop/Set-up.exe' \
    --exclude 'photoshop/packages' \
    --exclude 'photoshop/products' \
    "$ROOT/core" \
    "$ROOT/recipes" \
    "$ROOT/launcher" \
    "$ROOT/scripts" \
    "$ROOT/setup.sh" \
    "$ROOT/pre-check.sh" \
    "$ROOT/VERSION" \
    "$ROOT/photoshop/README.md" \
    "$ROOT/images" \
    "$SHARE/"

mkdir -p "$SHARE/photoshop"
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

echo "Bundling winetricks..."
mkdir -p "$APPDIR/runtime/winetricks"
wt_cache="$ROOT/.cache/winetricks-script"
mkdir -p "$wt_cache"
if [ ! -f "$wt_cache/winetricks" ]; then
    curl -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" \
        -o "$wt_cache/winetricks"
fi
cp -f "$wt_cache/winetricks" "$APPDIR/runtime/winetricks/winetricks"
chmod +x "$APPDIR/runtime/winetricks/winetricks"

# Host helpers often missing on immutable distros (winetricks needs them).
mkdir -p "$APPDIR/usr/bin"
for bin in cabextract unzip; do
    if command -v "$bin" >/dev/null 2>&1; then
        cp -f "$(command -v "$bin")" "$APPDIR/usr/bin/$bin"
        chmod +x "$APPDIR/usr/bin/$bin"
    else
        echo "WARNING: host $bin missing — not bundled (winetricks may fail for some verbs)" >&2
    fi
done

cat > "$APPDIR/rezeptor.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Rezeptor
Exec=AppRun
Icon=rezeptor
Categories=Utility;Graphics;
StartupWMClass=rezeptor
EOF
# App icon = Rezeptor (not Photoshop — that confused window/taskbar for all recipes)
if [ -f "$ROOT/images/rezeptor-icon.png" ]; then
    cp -f "$ROOT/images/rezeptor-icon.png" "$APPDIR/rezeptor.png"
elif [ -f "$ROOT/images/rezeptor-icon.svg" ] && command -v magick >/dev/null 2>&1; then
    magick "$ROOT/images/rezeptor-icon.svg" -resize 256x256 "$APPDIR/rezeptor.png"
elif [ -f "$ROOT/images/AdobePhotoshop-icon.png" ]; then
    # Fallback only if Rezeptor icon missing
    cp -f "$ROOT/images/AdobePhotoshop-icon.png" "$APPDIR/rezeptor.png"
fi
if [ ! -f "$APPDIR/rezeptor.png" ] && [ -f "$ROOT/images/AdobePhotoshop-icon.png" ]; then
    cp -f "$ROOT/images/AdobePhotoshop-icon.png" "$APPDIR/rezeptor.png"
fi

echo "Bundling relocatable CPython ${PYTHON_STANDALONE_VERSION} (python-build-standalone)..."
py_cache="$ROOT/.cache/python-build-standalone"
mkdir -p "$py_cache"
py_tgz="$py_cache/cpython-${PYTHON_STANDALONE_VERSION}+${PYTHON_STANDALONE_TAG}-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
if [ ! -f "$py_tgz" ]; then
    curl -fsSL "$PYTHON_STANDALONE_URL" -o "$py_tgz"
fi
if [ -n "${PYTHON_STANDALONE_SHA256:-}" ]; then
    echo "${PYTHON_STANDALONE_SHA256}  $py_tgz" | sha256sum -c - >/dev/null 2>&1 || {
        echo "Python standalone SHA256 mismatch — delete $py_tgz and retry" >&2
        exit 1
    }
fi
rm -rf "$APPDIR/python"
tar -xzf "$py_tgz" -C "$APPDIR"
if [ ! -x "$APPDIR/python/bin/python3" ]; then
    echo "Bundled python missing after extract: $APPDIR/python/bin/python3" >&2
    exit 1
fi

echo "Installing PyQt6 + Fluent Widgets into bundled Python..."
# python-build-standalone is relocatable; venv --copies hardcodes /install and CI paths.
"$APPDIR/python/bin/python3" -m pip install -q --upgrade pip
"$APPDIR/python/bin/python3" -m pip install -q PyQt6 "PyQt6-Fluent-Widgets"

bundled_py="$(readlink -f "$APPDIR/python/bin/python3")"
case "$bundled_py" in
    "$APPDIR"/*) ;;
    *)
        echo "Bundled python escapes AppDir: $bundled_py" >&2
        exit 1
        ;;
esac
prefix="$("$APPDIR/python/bin/python3" -c 'import sys; print(sys.prefix)')"
case "$prefix" in
    "$APPDIR"/*) ;;
    *)
        echo "Bundled python prefix escapes AppDir: $prefix" >&2
        exit 1
        ;;
esac
if ! "$APPDIR/python/bin/python3" -c \
    "import importlib.metadata as m; m.version('PyQt6'); m.version('PyQt6-Fluent-Widgets')"; then
    echo "AppImage python missing PyQt6 or PyQt6-Fluent-Widgets" >&2
    exit 1
fi
if ! "$APPDIR/python/bin/python3" -c "import PyQt6; import PyQt6.QtCore"; then
    echo "AppImage python cannot import PyQt6 (Qt libs missing on build host?)" >&2
    exit 1
fi

echo "Verifying AppDir contents..."
fail=0
for f in \
    "$APPDIR/AppRun" \
    "$APPDIR/rezeptor.desktop" \
    "$APPDIR/rezeptor.png" \
    "$SHARE/scripts/recipe-yaml-read.py" \
    "$SHARE/scripts/recipe-desktop.sh" \
    "$SHARE/core/recipe-desktop.sh" \
    "$SHARE/core/recipe-install-steps.sh" \
    "$SHARE/core/wine-runtime.sh" \
    "$SHARE/recipes/manifest.json" \
    "$SHARE/recipes/photoshop/install.sh" \
    "$SHARE/recipes/photoshop/recipe.yml" \
    "$SHARE/launcher/launcher.py" \
    "$SHARE/launcher/locales/de.json" \
    "$SHARE/images/AdobePhotoshop-icon.png" \
    "$SHARE/images/rezeptor-icon.svg" \
    "$APPDIR/runtime/winetricks/winetricks" \
    "$APPDIR/runtime/proton-ge/$PROTON_GE_TAG/files/bin/wine64"
do
    if [ ! -e "$f" ]; then
        echo "MISSING: $f" >&2
        fail=1
    fi
done
# Trust must be green for photoshop (stale manifest = install blocked in GUI)
if ! "$APPDIR/python/bin/python3" - <<PY
import sys
from pathlib import Path
sys.path.insert(0, "$SHARE/launcher")
from recipe_trust import verify_recipe_trust
ok, reason = verify_recipe_trust(
    Path("$SHARE/recipes/photoshop"),
    Path("$SHARE/recipes/manifest.json"),
    strict=True,
)
print("photoshop trust:", "OK" if ok else f"FAIL {reason}")
sys.exit(0 if ok else 1)
PY
then
    echo "Manifest trust failed — regenerate recipes/manifest.json before packaging" >&2
    fail=1
fi
# No CLI BYOS prompt in AppRun
if grep -qE 'read -r|Enter path to folder' "$APPDIR/AppRun"; then
    echo "AppRun still has interactive BYOS prompt" >&2
    fail=1
fi
# AppRun must not mask broken bundles with host python3
if grep -qE 'elif python3 -c "import PyQt6"|export PYTHON="python3"' "$APPDIR/AppRun"; then
    echo "AppRun still falls back to host python3" >&2
    fail=1
fi
if [ ! -x "$APPDIR/python/bin/python3" ]; then
    echo "Bundled python missing in AppDir" >&2
    fail=1
fi
# AppRun must point at usr/share/rezeptor (same tree as git ./setup.sh)
if ! grep -q 'usr/share/rezeptor' "$APPDIR/AppRun"; then
    echo "AppRun PROJECT_ROOT must be usr/share/rezeptor" >&2
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "AppDir verification OK"

APPIMAGETOOL=""
if command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL="$(command -v appimagetool)"
elif [ -x "$ROOT/.cache/appimagetool/appimagetool-x86_64.AppImage" ]; then
    APPIMAGETOOL="$ROOT/.cache/appimagetool/appimagetool-x86_64.AppImage"
    export APPIMAGE_EXTRACT_AND_RUN=1
fi
if [ -z "$APPIMAGETOOL" ]; then
    echo "appimagetool not found. AppDir prepared at: $APPDIR" >&2
    echo "Install appimagetool or place it at .cache/appimagetool/appimagetool-x86_64.AppImage" >&2
    exit 1
fi

ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUT"
chmod +x "$OUT"
# Drop stale legacy filename so only rezeptor-*.AppImage remains for this version
rm -f "$ROOT/photoshopCClinux-${VERSION}-x86_64.AppImage"
echo "Created: $OUT"
echo "Parity: AppImage == repo tree (setup.sh / recipes / launcher / core)"
