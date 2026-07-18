#!/usr/bin/env sh
# WISO Steuer portable — Proton-GE, Buhl ReadMe: Patch.exe → start.exe → wiso2026.exe

: "${WINEPREFIX:=$HOME/.local/share/wine-software/wiso-steuer/prefix}"
# Kanonischer Prefix — Test-Prefixe (prefix-fresh, prefix-test) ignorieren
_canonical="$HOME/.local/share/wine-software/wiso-steuer/prefix"
if [ -z "${WISO_ALLOW_ALT_PREFIX:-}" ] && [ "$WINEPREFIX" != "$_canonical" ]; then
    case "$WINEPREFIX" in
        *wiso-steuer/prefix-*|*wiso-steuer/prefix-fresh|*wiso-steuer/prefix-test)
            echo "Hinweis: $WINEPREFIX wird ignoriert — nutze $_canonical" >&2
            WINEPREFIX="$_canonical"
            ;;
    esac
fi
export WINEPREFIX WINEARCH=win64

if [ "$WINEPREFIX" = "$HOME/.wine" ]; then
    echo "Falscher Prefix (~/.wine). Bitte über Rezeptor oder wiso-steuer.desktop starten." >&2
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

export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---disable-gpu --disable-software-rasterizer --no-sandbox}"
export FREETYPE_PROPERTIES="${FREETYPE_PROPERTIES:-truetype:interpreter-version=35,lcdfilter:default}"
# Qt-Custom-Titlebar unter Wine: keine High-DPI-Autoskalierung
export QT_AUTO_SCREEN_SCALE_FACTOR="${QT_AUTO_SCREEN_SCALE_FACTOR:-0}"
export QT_ENABLE_HIGHDPI_SCALING="${QT_ENABLE_HIGHDPI_SCALING:-0}"
export QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-1}"
_dpi="${WISO_FORCE_DPI:-${WINE_LOGPIXELS:-96}}"
export QT_FONT_DPI="${QT_FONT_DPI:-$_dpi}"

_wine_cmd="${WINE:-wine}"
if ! command -v "$_wine_cmd" >/dev/null 2>&1; then
    echo "Wine nicht verfügbar — Rezeptor → Reparieren." >&2
    exit 1
fi

_wreg() {
    WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}mscoree=d" \
        "$_wine_cmd" reg "$@"
}

# Alte Virtual-Desktop-Reste (blauer Explorer) hart beenden — kein VD mehr als Default
pkill -9 -f "explorer.exe /desktop=wiso" 2>/dev/null || true
pkill -9 -f "explorer.exe.*/desktop=wiso" 2>/dev/null || true
_wreg delete "HKCU\\Software\\Wine\\Explorer" /v Desktop /f >/dev/null 2>&1 || true
_wreg delete "HKCU\\Software\\Wine\\Explorer\\Desktops" /v wiso /f >/dev/null 2>&1 || true
_wreg delete "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /f >/dev/null 2>&1 || true

if [ -z "${WISO_SKIP_DPI_REG:-}" ]; then
    _wreg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$_dpi" /f >/dev/null 2>&1 || true
fi

# Doppel-Chrome vermeiden: WISO zeichnet eigene Titlebar (Qt).
# Wine-WM-Dekoration aus → nur Qt-Chrome. Opt-out: WISO_DECORATED=1
if [ -z "${WISO_DECORATED:-}" ]; then
    _wreg add "HKCU\\Software\\Wine\\X11 Driver" /v Decorated /t REG_SZ /d N /f >/dev/null 2>&1 || true
else
    _wreg add "HKCU\\Software\\Wine\\X11 Driver" /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
fi
_wreg add "HKCU\\Software\\Wine\\X11 Driver" /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true

# Optional: alter Virtual-Desktop nur wenn explizit gesetzt (nicht empfohlen)
_wiso_vdesktop=""
if [ -n "${WISO_VIRTUAL_DESKTOP:-}" ] && [ -z "${WISO_NO_VIRTUAL_DESKTOP:-}" ]; then
    _wiso_vdesktop="$WISO_VIRTUAL_DESKTOP"
    _wreg add "HKCU\\Software\\Wine\\Explorer" /v Desktop /d wiso /f >/dev/null 2>&1
    _wreg add "HKCU\\Software\\Wine\\Explorer\\Desktops" /v wiso /d "$_wiso_vdesktop" /f >/dev/null 2>&1
    echo "WISO: Virtual Desktop ${_wiso_vdesktop} (explizit). Abschalten: unset WISO_VIRTUAL_DESKTOP" >&2
fi

# Einheitlich wie recipe_notify::starting: Titel = App-Name, Body = Start-Hinweis.
if command -v notify-send >/dev/null 2>&1; then
    _notify_icon="wiso-steuer-wine"
    _png="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/48x48/apps/wiso-steuer-wine.png"
    if [ -f "$_png" ]; then
        _notify_icon="$_png"
    elif [ -f "$ROOT_DIR/wisoakt.ico" ]; then
        _notify_icon="$ROOT_DIR/wisoakt.ico"
    else
        _found="$(find "$ROOT_DIR" -maxdepth 3 -name 'wisoakt.ico' -type f 2>/dev/null | head -1 || true)"
        [ -n "$_found" ] && _notify_icon="$_found"
    fi
    notify-send -a "WISO Steuer" -i "$_notify_icon" \
        "WISO Steuer" \
        "Wird gestartet…" \
        2>/dev/null || true
fi

# Nach Start: maximiertes Fenster → Fenster-Modus (Maximize bricht Qt-Titlebar unter Wine).
# Braucht xdotool oder wmctrl. Opt-out: WISO_ALLOW_MAXIMIZE=1
_wiso_unmaximize_bg() {
    [ -n "${WISO_ALLOW_MAXIMIZE:-}" ] && return 0
    command -v xdotool >/dev/null 2>&1 || command -v wmctrl >/dev/null 2>&1 || return 0
    (
        i=0
        while [ "$i" -lt 40 ]; do
            i=$((i + 1))
            sleep 0.5
            if command -v wmctrl >/dev/null 2>&1; then
                if wmctrl -l 2>/dev/null | grep -qi 'WISO Steuer'; then
                    wmctrl -r 'WISO Steuer' -b remove,maximized_vert,maximized_horz 2>/dev/null || true
                    wmctrl -r 'WISO Steuer' -e 0,48,48,1600,900 2>/dev/null || true
                    break
                fi
            fi
            if command -v xdotool >/dev/null 2>&1; then
                wid="$(xdotool search --name 'WISO Steuer' 2>/dev/null | tail -1)"
                [ -n "$wid" ] || continue
                xdotool windowactivate --sync "$wid" 2>/dev/null || true
                xdotool windowsize "$wid" 1600 900 2>/dev/null || true
                xdotool windowmove "$wid" 48 48 2>/dev/null || true
                break
            fi
        done
    ) >/dev/null 2>&1 &
}

_wiso_run() {
    _exe="$1"
    shift
    _wiso_unmaximize_bg
    if [ -n "$_wiso_vdesktop" ]; then
        exec "$_wine_cmd" explorer "/desktop=wiso,${_wiso_vdesktop}" "$_exe" "$@"
    else
        exec "$_wine_cmd" "$_exe" "$@"
    fi
}

MAIN_EXE=""
for _cand in "$ROOT_DIR/start.exe" "$ROOT_DIR/Start.exe"; do
    if [ -f "$_cand" ]; then
        MAIN_EXE="$_cand"
        break
    fi
done

if [ -n "$MAIN_EXE" ]; then
    cd "$ROOT_DIR" || exit 1
    export WISO_SHOW_WINE_GUI=1
    _wiso_run "./$(basename "$MAIN_EXE")" "$@"
fi

cd "$_sw_dir" || exit 1
MAIN_EXE="${WISO_MAIN_EXE:-wiso2026.exe}"
if [ ! -f "$MAIN_EXE" ]; then
    _cand=$(find . -maxdepth 1 -name 'wiso*.exe' -type f 2>/dev/null | head -1 || true)
    if [ -n "$_cand" ]; then
        MAIN_EXE="${_cand#./}"
    else
        echo "start.exe und wiso*.exe nicht gefunden unter $ROOT_DIR" >&2
        exit 1
    fi
fi

export WISO_SHOW_WINE_GUI=1
_wiso_run "$MAIN_EXE" "$@"
