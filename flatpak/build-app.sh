#!/usr/bin/env bash
# Bundle Rezeptor into /app (Python + PyQt6 + Proton-GE + recipes). Called from flatpak-builder.
set -eu

ROOT="${FLATPAK_BUILDER_BUILDDIR:?missing FLATPAK_BUILDER_BUILDDIR}"
SHARE="/app/share/rezeptor"

# shellcheck source=/dev/null
source "$ROOT/core/runtime.lock"

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
install -Dm644 "$ROOT/flatpak/io.github.benjarogit.Rezeptor.metainfo.xml" \
    /app/share/metainfo/io.github.benjarogit.Rezeptor.metainfo.xml

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
        curl -fsSL "$PROTON_GE_URL" -o "$cache/${PROTON_GE_TAG}.tar.gz"
    fi
    if [ -n "${PROTON_GE_SHA256:-}" ]; then
        echo "${PROTON_GE_SHA256}  $cache/${PROTON_GE_TAG}.tar.gz" | sha256sum -c -
    fi
    tar -xzf "$cache/${PROTON_GE_TAG}.tar.gz" -C /app/runtime/proton-ge
    if [ -d "/app/runtime/proton-ge/files/bin" ] && [ ! -d "/app/runtime/proton-ge/$PROTON_GE_TAG/files/bin" ]; then
        mkdir -p "/app/runtime/proton-ge/.tmp"
        mv "/app/runtime/proton-ge"/* "/app/runtime/proton-ge/.tmp/" 2>/dev/null || true
        mkdir -p "/app/runtime/proton-ge/$PROTON_GE_TAG"
        mv "/app/runtime/proton-ge/.tmp"/* "/app/runtime/proton-ge/$PROTON_GE_TAG/"
        rmdir "/app/runtime/proton-ge/.tmp" 2>/dev/null || true
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

echo "Creating Flatpak venv with PyQt6 + Fluent Widgets..."
rm -rf /app/venv
/app/python/bin/python3 -m venv --copies /app/venv
/app/venv/bin/pip install -q --upgrade pip
/app/venv/bin/pip install -q PyQt6 "PyQt6-Fluent-Widgets"

venv_py="$(readlink -f /app/venv/bin/python)"
case "$venv_py" in
    /app/*) ;;
    *)
        echo "Flatpak venv python escapes /app: $venv_py" >&2
        exit 1
        ;;
esac
if ! /app/venv/bin/python -c \
    "import importlib.metadata as m; m.version('PyQt6'); m.version('PyQt6-Fluent-Widgets')"; then
    echo "Flatpak venv missing PyQt6 packages" >&2
    exit 1
fi
if ! /app/venv/bin/python -c "import PyQt6" 2>/dev/null; then
    echo "Flatpak venv cannot import PyQt6" >&2
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
    /app/venv/bin/python \
    /app/python/bin/python3
do
    if [ ! -e "$f" ]; then
        echo "MISSING: $f" >&2
        fail=1
    fi
done
if ! /app/venv/bin/python -c "import PyQt6; import PyQt6.QtCore"; then
    echo "PyQt6 import check failed" >&2
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "Flatpak bundle verification OK"
