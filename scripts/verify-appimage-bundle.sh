#!/usr/bin/env bash
# Prove AppImage ships a self-contained Python + PyQt6 (no host interpreter fallback).
set -eu

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 rezeptor-<version>-x86_64.AppImage" >&2
    exit 1
fi

APPIMAGE="$(readlink -f "$1")"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
export APPIMAGE_EXTRACT_AND_RUN=1
"$APPIMAGE" --appimage-extract >/dev/null
ROOT="$WORKDIR/squashfs-root"

fail=0
check() {
    if ! "$@"; then
        echo "FAIL: $*" >&2
        fail=1
    fi
}

BUNDLED_PY="$ROOT/python/bin/python3"

check test -x "$BUNDLED_PY"

bundled_py="$(readlink -f "$BUNDLED_PY")"
case "$bundled_py" in
    "$ROOT"/*) echo "bundled python: $bundled_py" ;;
    *)
        echo "FAIL: bundled python escapes AppDir: $bundled_py" >&2
        fail=1
        ;;
esac

prefix="$("$BUNDLED_PY" -c 'import sys; print(sys.prefix)')"
case "$prefix" in
    "$ROOT"/*) echo "python prefix in bundle: $prefix" ;;
    *)
        echo "FAIL: python prefix not in AppDir: $prefix" >&2
        fail=1
        ;;
esac

if ! "$BUNDLED_PY" -c 'import sys; raise SystemExit(1 if sys.prefix.startswith("/install") or sys.base_prefix.startswith("/install") else 0)'; then
    echo "FAIL: python prefix still hardcoded to /install (broken venv copy?)" >&2
    fail=1
fi

check test ! -e "$ROOT/venv/bin/python"

check "$BUNDLED_PY" -c "import PyQt6; import PyQt6.QtCore"
pyqt_path="$("$BUNDLED_PY" -c 'import PyQt6; print(PyQt6.__file__)')"
case "$pyqt_path" in
    "$ROOT"/*) echo "PyQt6 from bundle: $pyqt_path" ;;
    *)
        echo "FAIL: PyQt6 not from AppDir: $pyqt_path" >&2
        fail=1
        ;;
esac

if grep -qE 'elif python3 -c "import PyQt6"|export PYTHON="python3"' "$ROOT/AppRun"; then
    echo "FAIL: AppRun still falls back to host python3" >&2
    fail=1
fi
if grep -q 'venv/bin/python' "$ROOT/AppRun"; then
    echo "FAIL: AppRun still points at broken venv python" >&2
    fail=1
fi

fakebin="$WORKDIR/fakebin"
mkdir -p "$fakebin"
cat > "$fakebin/python3" <<'EOF'
#!/usr/bin/env bash
echo "host python3 was invoked" >&2
exit 99
EOF
chmod +x "$fakebin/python3"

if ! PATH="$fakebin:$PATH" "$BUNDLED_PY" -c "import PyQt6" >/dev/null; then
    echo "FAIL: bundled python import with host decoy on PATH" >&2
    fail=1
else
    echo "Bundled python works with host python3 decoy on PATH"
fi

reloc="$WORKDIR/reloc-test"
cp -a "$ROOT" "$reloc"
if ! "$reloc/python/bin/python3" -c "import PyQt6.QtCore" >/dev/null; then
    echo "FAIL: bundled python broken after directory relocation" >&2
    fail=1
else
    echo "Bundled python survives relocation"
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "AppImage bundle verification OK"
