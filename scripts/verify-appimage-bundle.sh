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
# cwd on the FUSE mount is read-only — AppRun must leave it (HOME/TMP).
if grep -qE 'cd "\$PROJECT_ROOT"|cd "\$HERE"' "$ROOT/AppRun"; then
    echo "FAIL: AppRun still cds into the AppImage mount (read-only cwd)" >&2
    fail=1
fi
if ! grep -q 'cd "\${HOME' "$ROOT/AppRun"; then
    echo "FAIL: AppRun must cd to HOME/TMP before launching GUI" >&2
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

# Catch qfluentwidgets writing ./config on a read-only cwd (real AppImage FUSE).
# chmod 555 ≈ Errno 30 on FUSE for this purpose: mkdir("config") must not run.
ro_cwd="$WORKDIR/ro-cwd"
mkdir -p "$ro_cwd"
chmod 555 "$ro_cwd"
LAUNCHER_ROOT="$ROOT/usr/share/rezeptor/launcher"
if [ ! -d "$LAUNCHER_ROOT" ]; then
    LAUNCHER_ROOT="$ROOT/usr/share/photoshopCClinux/launcher"
fi
if [ -d "$LAUNCHER_ROOT" ]; then
    # HOME/XDG under workdir so optional config/cache stays writable.
    # Also freeze the launcher tree (like FUSE) — catches writes next to __file__.
    smoke_home="$WORKDIR/smoke-home"
    mkdir -p "$smoke_home/.config" "$smoke_home/.cache"
    chmod -R a-w "$LAUNCHER_ROOT" 2>/dev/null || true
    if ! (
        cd "$ro_cwd" || exit 1
        HOME="$smoke_home" \
        XDG_CONFIG_HOME="$smoke_home/.config" \
        XDG_CACHE_HOME="$smoke_home/.cache" \
        PYTHONDONTWRITEBYTECODE=1 \
        QT_QPA_PLATFORM=offscreen \
        PYTHONPATH="$LAUNCHER_ROOT${PYTHONPATH:+:$PYTHONPATH}" \
        "$BUNDLED_PY" - <<'PY'
import os
import sys
from pathlib import Path
from PyQt6.QtWidgets import QApplication

app = QApplication(sys.argv)
import ui_fluent
import ui_icons

# Must not raise OSError (read-only cwd / AppImage mount)
host = ui_fluent.apply_rezeptor_theme()
assert isinstance(host, str) and host
assert not Path("config").exists(), "fluent wrote ./config into read-only cwd"

# Generated UI assets must land in XDG cache, never under the RO launcher tree
chev = ui_icons.ensure_chevron_png("down")
assert chev.is_file(), "chevron png missing"
cache = Path(os.environ["XDG_CACHE_HOME"]).resolve()
assert cache in chev.resolve().parents, f"chevron not under XDG_CACHE_HOME: {chev}"
print("apply_rezeptor_theme + ensure_chevron_png OK on read-only launcher/cwd")
PY
    ); then
        echo "FAIL: RO AppImage smoke crashed (theme/config or assets/ui write)" >&2
        echo "       (Errno 30 / read-only filesystem on FUSE mount)" >&2
        fail=1
    else
        echo "Fluent theme + chevron cache survive read-only AppImage simulation"
    fi
    chmod -R u+w "$LAUNCHER_ROOT" 2>/dev/null || true
    chmod 755 "$ro_cwd"
else
    echo "WARN: launcher tree missing in AppDir — skipped RO theme smoke" >&2
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "AppImage bundle verification OK"
