#!/usr/bin/env bash
# Prove Flatpak build ships self-contained Python + PyQt6 (no host interpreter fallback).
set -eu

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 flatpak/build-flatpak" >&2
    exit 1
fi

BUILD_DIR="$(readlink -f "$1")"
MANIFEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/flatpak/io.github.benjarogit.Rezeptor.yml"

fail=0
check() {
    if ! "$@"; then
        echo "FAIL: $*" >&2
        fail=1
    fi
}

check flatpak-builder --run "$BUILD_DIR" "$MANIFEST" test -x /app/venv/bin/python
check flatpak-builder --run "$BUILD_DIR" "$MANIFEST" test -x /app/python/bin/python3

venv_py="$(flatpak-builder --run "$BUILD_DIR" "$MANIFEST" readlink -f /app/venv/bin/python)"
case "$venv_py" in
    /app/*) echo "venv python is bundled: $venv_py" ;;
    *)
        echo "FAIL: venv python escapes /app: $venv_py" >&2
        fail=1
        ;;
esac

check flatpak-builder --run "$BUILD_DIR" "$MANIFEST" /app/venv/bin/python -c "import PyQt6; import PyQt6.QtCore"
pyqt_path="$(flatpak-builder --run "$BUILD_DIR" "$MANIFEST" /app/venv/bin/python -c 'import PyQt6; print(PyQt6.__file__)')"
case "$pyqt_path" in
    /app/*) echo "PyQt6 from bundle: $pyqt_path" ;;
    *)
        echo "FAIL: PyQt6 not from /app: $pyqt_path" >&2
        fail=1
        ;;
esac

check flatpak-builder --run "$BUILD_DIR" "$MANIFEST" test -x "/app/runtime/proton-ge/GE-Proton10-28/files/bin/wine64"
check flatpak-builder --run "$BUILD_DIR" "$MANIFEST" test -x /app/runtime/winetricks/winetricks
check flatpak-builder --run "$BUILD_DIR" "$MANIFEST" test -f /app/share/rezeptor/recipes/manifest.json

if ! flatpak-builder --run "$BUILD_DIR" "$MANIFEST" bash -c 'grep -q usr/share/rezeptor /app/bin/rezeptor-launch 2>/dev/null || grep -q share/rezeptor /app/bin/rezeptor-launch'; then
    echo "FAIL: rezeptor-launch missing PROJECT_ROOT" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "Flatpak bundle verification OK"
