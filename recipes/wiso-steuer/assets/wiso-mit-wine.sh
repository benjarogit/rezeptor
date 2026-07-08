#!/usr/bin/env sh
# WISO Steuer portable — System-Wine, angelehnt an wiso-steuer-portable-linux.
# Kein DXVK: nur wine + wiso20xx.exe im Rezeptor-Prefix.

: "${WINEPREFIX:=$HOME/.local/share/wine-software/wiso-steuer/prefix}"
export WINEPREFIX WINEARCH=win64

if [ "$WINEPREFIX" = "$HOME/.wine" ]; then
    echo "Falscher Prefix (~/.wine). Bitte über Rezeptor starten, nicht wine/winecfg direkt." >&2
    exit 1
fi

if [ -n "${WISO_PORTABLE_ROOT:-}" ] && [ -d "$WISO_PORTABLE_ROOT" ]; then
    ROOT_DIR="$WISO_PORTABLE_ROOT"
else
    ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

SOFTWARE_DIR="${WISO_STEUER_SOFTWARE_DIR:-Steuersoftware 2026}"
if [ ! -d "$ROOT_DIR/$SOFTWARE_DIR" ]; then
    _alt="$(ls -d "$ROOT_DIR"/Steuersoftware* 2>/dev/null | head -1 || true)"
    if [ -n "$_alt" ] && [ -d "$_alt" ]; then
        SOFTWARE_DIR="${_alt##*/}"
    else
        echo "Cannot find Steuersoftware* under $ROOT_DIR." >&2
        exit 1
    fi
fi

_sw_dir="$ROOT_DIR/$SOFTWARE_DIR"
_net_dll="$_sw_dir/networkinformation/qnetworklistmanager.dll"
_net_bak="$_sw_dir/networkinformation/qnetworklistmanager.dll.bak"
if [ -f "$_net_dll" ] && [ ! -f "$_net_bak" ]; then
    mv -f "$_net_dll" "$_net_bak" 2>/dev/null || true
fi

if [ -z "$WISO_KEEP_WAYLAND" ]; then
    DISPLAY="${DISPLAY:-:0}"
    export DISPLAY
    unset WAYLAND_DISPLAY
fi

_wine_cmd="${WINE:-wine}"
if ! command -v "$_wine_cmd" >/dev/null 2>&1; then
    echo "Wine nicht verfügbar — Rezeptor → Reparieren." >&2
    exit 1
fi

_wreg() {
    WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}mscoree=d" \
        "$_wine_cmd" reg "$@"
}

if [ -n "$WISO_VIRTUAL_DESKTOP" ]; then
    _wreg add "HKCU\\Software\\Wine\\Explorer" /v Desktop /d Default /f >/dev/null 2>&1
    _wreg add "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /d "$WISO_VIRTUAL_DESKTOP" /f >/dev/null 2>&1
elif [ -z "${WISO_NO_CLEAR_VDESKTOP:-}" ]; then
    _wreg delete "HKCU\\Software\\Wine\\Explorer" /v Desktop /f >/dev/null 2>&1 || true
    _wreg delete "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /f >/dev/null 2>&1 || true
fi

cd "$_sw_dir" || exit 1

MAIN_EXE="${WISO_MAIN_EXE:-wiso2026.exe}"
if [ ! -f "$MAIN_EXE" ]; then
    _cand=$(find . -maxdepth 1 -name 'wiso*.exe' -type f 2>/dev/null | head -1 || true)
    if [ -n "$_cand" ]; then
        MAIN_EXE="${_cand#./}"
    else
        echo "Main executable not found." >&2
        exit 1
    fi
fi

exec "$_wine_cmd" "$MAIN_EXE" "$@"
