#!/usr/bin/env bash
# Bundle Rezeptor into /app (Python + PyQt6 + Proton-GE + recipes). Called from flatpak-builder.
set -eu

ROOT="${FLATPAK_BUILDER_BUILDDIR:?missing FLATPAK_BUILDER_BUILDDIR}"
SHARE="/app/share/rezeptor"

# shellcheck source=/dev/null
source "$ROOT/core/runtime.lock"
# shellcheck source=/dev/null
source "$ROOT/core/proton-ge-fetch.sh"

echo "Installing Rezeptor application tree..."
mkdir -p "$SHARE"
for item in core recipes launcher scripts setup.sh pre-check.sh VERSION images; do
    cp -a "$ROOT/$item" "$SHARE/"
done
mkdir -p "$SHARE/photoshop"
if [ -f "$ROOT/photoshop/README.md" ]; then
    cp -a "$ROOT/photoshop/README.md" "$SHARE/photoshop/"
fi

install -Dm755 "$ROOT/flatpak/rezeptor-launch" /app/bin/rezeptor-launch
install -Dm644 "$ROOT/flatpak/io.github.benjarogit.Rezeptor.desktop" \
    /app/share/applications/io.github.benjarogit.Rezeptor.desktop
# Keep Flatpak metainfo <release version> in sync with repo VERSION (XML-safe).
ver="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
python3 - "$ROOT/flatpak/io.github.benjarogit.Rezeptor.metainfo.xml" "$ver" \
    /app/share/metainfo/io.github.benjarogit.Rezeptor.metainfo.xml <<'PY'
import re
import sys
from pathlib import Path

src, ver, dest = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
text = src.read_text(encoding="utf-8")
text2, n = re.subn(
    r'(<release\s+version=")[^"]+(")',
    rf"\g<1>{ver}\2",
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"metainfo: expected 1 <release version> replace, got {n}")
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(text2, encoding="utf-8")
PY

if [ -f "$ROOT/images/rezeptor-icon.png" ]; then
    install -Dm644 "$ROOT/images/rezeptor-icon.png" \
        /app/share/icons/hicolor/256x256/apps/io.github.benjarogit.Rezeptor.png
fi

mkdir -p /app/runtime/proton-ge
install_proton_tree() {
    local src="$1"
    if [ -d "$src/$PROTON_GE_TAG/files/bin" ]; then
        cp -a "$src/$PROTON_GE_TAG" /app/runtime/proton-ge/
    elif [ -d "$src/files/bin" ]; then
        mkdir -p "/app/runtime/proton-ge/$PROTON_GE_TAG"
        cp -a "$src/." "/app/runtime/proton-ge/$PROTON_GE_TAG/"
    else
        echo "Unrecognized Proton-GE layout under $src" >&2
        return 1
    fi
}
if [ -d "$ROOT/proton-ge-src" ]; then
    install_proton_tree "$ROOT/proton-ge-src"
    chmod -R u+w /app/runtime/proton-ge || true
elif [ ! -d "/app/runtime/proton-ge/$PROTON_GE_TAG/files/bin" ]; then
    echo "Downloading Proton-GE $PROTON_GE_TAG..."
    cache="/var/tmp/rezeptor-flatpak-cache"
    mkdir -p "$cache"
    if [ ! -f "$cache/${PROTON_GE_TAG}.tar.gz" ]; then
        proton_ge_fetch::download_tarball "$PROTON_GE_URL" "$cache/${PROTON_GE_TAG}.tar.gz"
    fi
    proton_ge_fetch::verify_tarball "$cache/${PROTON_GE_TAG}.tar.gz"
    tar -xzf "$cache/${PROTON_GE_TAG}.tar.gz" -C /app/runtime/proton-ge
    if [ -d "/app/runtime/proton-ge/files/bin" ] && [ ! -d "/app/runtime/proton-ge/$PROTON_GE_TAG/files/bin" ]; then
        mkdir -p "/app/runtime/proton-ge/.tmp"
        mv "/app/runtime/proton-ge"/* "/app/runtime/proton-ge/.tmp/" 2>/dev/null || true
        mkdir -p "/app/runtime/proton-ge/$PROTON_GE_TAG"
        mv "/app/runtime/proton-ge/.tmp"/* "/app/runtime/proton-ge/$PROTON_GE_TAG/"
        rmdir "/app/runtime/proton-ge/.tmp" 2>/dev/null || true
    fi
fi

# Always shim wine→wine64 in Flatpak. The Sdk may exec 32-bit wine during
# build while the Platform runtime cannot (no i386 ld-linux) — so a
# build-time "wine --version" probe is unreliable. Winetricks still calls
# sibling "wine" for syswow64 (msxml3/ie8).
_proton_bin="/app/runtime/proton-ge/$PROTON_GE_TAG/files/bin"
if [ -x "$_proton_bin/wine64" ] && [ -e "$_proton_bin/wine" ]; then
    if head -c 2 "$_proton_bin/wine" | grep -q '#!'; then
        echo "wine already a shim — keep"
    else
        echo "Replacing Proton wine ELF with wine64 shim (Flatpak)..."
        mv "$_proton_bin/wine" "$_proton_bin/wine.real32" 2>/dev/null || rm -f "$_proton_bin/wine"
        printf '#!/bin/sh\nexec "$(dirname "$0")/wine64" "$@"\n' >"$_proton_bin/wine"
        chmod +x "$_proton_bin/wine"
    fi
fi

echo "Bundling winetricks..."
mkdir -p /app/runtime/winetricks
if [ -f "$ROOT/winetricks-src/winetricks" ]; then
    install -Dm755 "$ROOT/winetricks-src/winetricks" /app/runtime/winetricks/winetricks
else
    cache="/var/tmp/rezeptor-flatpak-cache"
    mkdir -p "$cache"
    if [ ! -f "$cache/winetricks" ]; then
        curl -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" \
            -o "$cache/winetricks"
    fi
    install -Dm755 "$cache/winetricks" /app/runtime/winetricks/winetricks
fi

mkdir -p /app/bin
for bin in cabextract unzip; do
    if [ -x "/app/bin/$bin" ]; then
        continue
    fi
    if command -v "$bin" >/dev/null 2>&1; then
        install -Dm755 "$(command -v "$bin")" "/app/bin/$bin"
    else
        echo "WARNING: $bin missing in SDK — some winetricks verbs may fail" >&2
    fi
done

echo "Bundling relocatable CPython ${PYTHON_STANDALONE_VERSION}..."
rm -rf /app/python
if [ -d "$ROOT/python-src/python" ]; then
    cp -a "$ROOT/python-src/python" /app/python
elif [ -x "$ROOT/python-src/bin/python3" ]; then
    cp -a "$ROOT/python-src" /app/python
else
    cache="/var/tmp/rezeptor-flatpak-cache"
    mkdir -p "$cache"
    py_tgz="$cache/cpython-${PYTHON_STANDALONE_VERSION}+${PYTHON_STANDALONE_TAG}-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
    if [ ! -f "$py_tgz" ]; then
        curl -fsSL "$PYTHON_STANDALONE_URL" -o "$py_tgz"
    fi
    if [ -n "${PYTHON_STANDALONE_SHA256:-}" ]; then
        echo "${PYTHON_STANDALONE_SHA256}  $py_tgz" | sha256sum -c -
    fi
    tar -xzf "$py_tgz" -C /app
fi
if [ ! -x /app/python/bin/python3 ]; then
    echo "Bundled python missing after extract" >&2
    exit 1
fi

echo "Installing PyQt6 + Fluent Widgets into bundled Python..."
# python-build-standalone is relocatable; venv --copies hardcodes /install and build paths.
/app/python/bin/python3 -m pip install -q --upgrade pip
/app/python/bin/python3 -m pip install -q PyQt6 "PyQt6-Fluent-Widgets"

bundled_py="$(readlink -f /app/python/bin/python3)"
case "$bundled_py" in
    /app/*) ;;
    *)
        echo "Bundled python escapes /app: $bundled_py" >&2
        exit 1
        ;;
esac
prefix="$(/app/python/bin/python3 -c 'import sys; print(sys.prefix)')"
case "$prefix" in
    /app/*) ;;
    *)
        echo "Bundled python prefix escapes /app: $prefix" >&2
        exit 1
        ;;
esac
if ! /app/python/bin/python3 -c \
    "import importlib.metadata as m; m.version('PyQt6'); m.version('PyQt6-Fluent-Widgets')"; then
    echo "Flatpak python missing PyQt6 packages" >&2
    exit 1
fi
if ! /app/python/bin/python3 -c "import PyQt6; import PyQt6.QtCore"; then
    echo "Flatpak python cannot import PyQt6" >&2
    exit 1
fi

echo "Verifying Flatpak bundle contents..."
fail=0
for f in \
    /app/bin/rezeptor-launch \
    /app/share/applications/io.github.benjarogit.Rezeptor.desktop \
    /app/share/rezeptor/launcher/launcher.py \
    /app/share/rezeptor/recipes/manifest.json \
    /app/runtime/winetricks/winetricks \
    /app/runtime/proton-ge/"$PROTON_GE_TAG"/files/bin/wine64 \
    /app/python/bin/python3
do
    if [ ! -e "$f" ]; then
        echo "MISSING: $f" >&2
        fail=1
    fi
done
if ! /app/python/bin/python3 -c "import PyQt6; import PyQt6.QtCore"; then
    echo "PyQt6 import check failed" >&2
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "Flatpak bundle verification OK"
