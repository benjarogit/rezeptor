#!/usr/bin/env bash
# Adobe Lightroom Classic starten — Proton-GE, DXVK/vkd3d, Lightroom-on-Linux-Fixes.

if ! type adobe_setup::disable_virtual_desktop >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-adobe-setup.sh"
fi

if ! type recipe_lightroom::apply_stub_files >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-lightroom-install.sh"
fi

LIGHTROOM_TITLE="Adobe Lightroom Classic"

recipe_lightroom::_locale() {
    if command -v locale >/dev/null 2>&1; then
        if locale -a 2>/dev/null | grep -qE 'de_DE\.(utf8|UTF-8)|de_DE'; then
            export LANG="${LANG:-de_DE.UTF-8}"
        elif locale -a 2>/dev/null | grep -qE 'C\.(utf8|UTF-8)'; then
            export LANG="${LANG:-C.UTF-8}"
        else
            export LANG="${LANG:-C}"
        fi
    else
        export LANG="${LANG:-C.UTF-8}"
    fi
    export LC_ALL="${LC_ALL:-$LANG}"
}

recipe_lightroom::_runtime_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"${DATA_ROOT}/lightroom-runtime.log" 2>/dev/null || true
}

recipe_lightroom::_notify() {
    local message="${1:-}" icon="${2:-}"
    if type recipe_notify::send >/dev/null 2>&1; then
        recipe_notify::send "$LIGHTROOM_TITLE" "$LIGHTROOM_TITLE" "$message" "$icon"
        return 0
    fi
    command -v notify-send >/dev/null 2>&1 || return 0
    if [ -n "$icon" ]; then
        notify-send -a "$LIGHTROOM_TITLE" -i "$icon" "$LIGHTROOM_TITLE" "$message" 2>/dev/null || true
    else
        notify-send -a "$LIGHTROOM_TITLE" "$LIGHTROOM_TITLE" "$message" 2>/dev/null || true
    fi
}

# Lightroom bricht beim Beenden ab (UnregisterApplicationRecoveryCallback) und
# lässt Prozesse mit offenen Locks zurück — der nächste Start blockiert dann.
recipe_lightroom::_clear_stale_session() {
    local pat='[\\/](Lightroom\.exe|Adobe Lightroom CEF Helper\.exe|Adobe Crash Processor\.exe)'
    pgrep -f "$pat" >/dev/null 2>&1 || return 0
    echo "⚠ Reste einer vorherigen Lightroom-Sitzung — beende…"
    recipe_lightroom::_runtime_log "Stale session — kill leftovers"
    pkill -f "$pat" 2>/dev/null || true
    sleep 1
    pkill -9 -f "$pat" 2>/dev/null || true
    if type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
    fi
    sleep 1
    return 0
}

# UI-Skalierung: „auto“ überlässt recipe_dpi die Host-DPI, sonst harter LogPixels-Wert.
recipe_lightroom::_apply_ui_scale() {
    case "${LIGHTROOM_UI_SCALE:-auto}" in
        auto | '') ;;
        *[!0-9]*) ;;
        *) export WINE_LOGPIXELS="${LIGHTROOM_UI_SCALE}" ;;
    esac
    recipe_dpi::logpixels 2>/dev/null || true
}

recipe_lightroom::_export_launch_env() {
    local d2d1_ov
    export WINE_PREFIX="${WINE_PREFIX:-${DATA_ROOT}/prefix}"
    export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"
    export WINEPREFIX="$WINE_PREFIX"
    export FREETYPE_PROPERTIES="${FREETYPE_PROPERTIES:-truetype:interpreter-version=35,lcdfilter:default}"
    export WINEDEBUG="${WINEDEBUG:--all,+err}"

    if [ -d /proc/sys/fs/epoll ] || [ -c /dev/shm ]; then
        export WINEESYNC=1
        if [ -f /proc/sys/fs/aio-max-nr ] && [ "$(uname -r | cut -d. -f1)" -ge 5 ] 2>/dev/null; then
            export WINEFSYNC=1
        fi
    fi

    # X11/Xwayland: winewayland.drv würde EDID/HDR durchreichen, bringt LrC aber
    # zum Absturz (Upstream KNOWN_ISSUES) — deshalb hart aus.
    export PROTON_ENABLE_WAYLAND=0
    unset WAYLAND_DISPLAY WAYLAND_SOCKET
    export DISPLAY="${DISPLAY:-:0}"

    # Lightroom rendert über DXVK/vkd3d — ein GL-Override stört CameraRaw/CEF.
    unset MESA_GL_VERSION_OVERRIDE || true
    export __GL_SHADER_DISK_CACHE=0
    export __GL_THREADED_OPTIMIZATIONS=1
    export __GL_YIELD="USLEEP"
    export CSMT=enabled
    export DXVK_ASYNC=0
    export DXVK_HUD=0
    export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-none}"
    export VKD3D_DEBUG="${VKD3D_DEBUG:-none}"
    export DXVK_CONFIG="${DXVK_CONFIG:-dxgi.hideNvidiaGpu = False}"
    if [ -z "${DXVK_CONFIG_FILE:-}" ] && [ -f "${WINEPREFIX}/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="${WINEPREFIX}/dxvk.conf"
    fi

    d2d1_ov="$(lr_stubs::d2d1_override)"
    export WINEDLLOVERRIDES="winewayland.drv=d;winemenubuilder.exe=d;d3d11=native,builtin;d3d10core=native,builtin;dxgi=native,builtin;d3d12=native;d3d12core=native;d2d1=${d2d1_ov};hnetcfg=native,builtin;mfplat=native;discburning=;gdiplus=native;msxml3=native,builtin"

    # Stencil-PushLayer im gepatchten d2d1 — füllt Histogramm und Miniaturraster.
    if recipe_lightroom::histogram_fix_enabled; then
        export D2D_LAYER_MASK="${D2D_LAYER_MASK:-1}"
    else
        export D2D_LAYER_MASK=0
    fi

    if recipe_lightroom::ai_masking_enabled; then
        lr_stubs::export_fakeram_preload \
            || recipe_lightroom::_runtime_log "fakeram.so fehlt — KI-Masken ohne RAM-Deckel"
    fi

    # Vom Host-GUI geerbtes D-Bus killt Wine/CEF oft mit Assertion-Abort.
    unset DBUS_SESSION_BUS_ADDRESS || true
    export NO_AT_BRIDGE=1
    export DBUS_FATAL_WARNINGS=0
}

recipe_lightroom::_validate_prefix() {
    if ! type security::validate_path >/dev/null 2>&1; then
        recipe_hooks::_source security.sh
    fi
    security::validate_path "$WINE_PREFIX" || return 1
    [ -d "$WINE_PREFIX" ] || {
        echo "FEHLER: Wine-Prefix nicht gefunden: $WINE_PREFIX" >&2
        recipe_lightroom::_notify "Wine-Prefix nicht gefunden — bitte installieren/reparieren." "dialog-error"
        return 1
    }
    return 0
}

recipe_lightroom::_prepare_prefix() {
    recipe_guard::kill_stale_winetricks 2>/dev/null || true
    if ! recipe_guard::require_mem 4096; then
        recipe_lightroom::_notify \
            "Zu wenig freier RAM — Programme schließen, dann erneut Starten." "dialog-error"
        return 1
    fi
    recipe_lightroom::_clear_stale_session
    if recipe_guard::process_matches "Lightroom.exe"; then
        recipe_lightroom::_notify "Läuft noch — zuerst Beenden, dann erneut Starten." \
            "$(recipe_guard::notify_icon 2>/dev/null || true)"
        return 1
    fi

    adobe_setup::disable_virtual_desktop
    # Nach einem Runtime-Wechsel zeigen Overrides/WinRT-Klassen wieder auf Wines
    # Builtins und version_orig.dll passt nicht mehr — vor jedem Start neu setzen.
    wine_runtime::deploy_proton_graphics_dlls \
        || recipe_lightroom::_runtime_log "FEHLER: Proton-Grafik-DLLs nicht deploybar — Reparieren"
    recipe_lightroom::apply_stub_files \
        || recipe_lightroom::_runtime_log "Warnung: Stub-Dateien unvollständig"
    recipe_lightroom::apply_registry \
        || recipe_lightroom::_runtime_log "Warnung: Registry-Fixes fehlgeschlagen"

    if ! recipe_fonts::ensure "${DATA_ROOT}/lightroom-fonts.log"; then
        recipe_lightroom::_runtime_log "Schriften fehlgeschlagen — siehe ${DATA_ROOT}/lightroom-fonts.log"
        return 1
    fi
    recipe_fonts::registry
    recipe_lightroom::_apply_ui_scale

    if ! recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/syswow64/gdiplus.dll"; then
        echo "FEHLER: Native gdiplus fehlt — Rezeptor → Reparieren." >&2
        recipe_lightroom::_notify "gdiplus fehlt — bitte Reparieren." "dialog-error"
        return 1
    fi
    return 0
}

recipe_lightroom::_wine_args() {
    local -n _out=$1
    local file abs wine_path
    _out=()
    for file in "${@:2}"; do
        [ -f "$file" ] || [ -d "$file" ] || continue
        abs="$(readlink -f "$file" 2>/dev/null || echo "$file")"
        if type wine_runtime::winepath >/dev/null 2>&1; then
            wine_path="$(wine_runtime::winepath -w "$abs" 2>/dev/null || true)"
        else
            wine_path=""
        fi
        [ -n "$wine_path" ] || wine_path="$(echo "$abs" | sed 's|^/|Z:/|' | sed 's|/|\\|g')"
        _out+=("$wine_path")
        echo "📂 Öffne Datei: $(basename "$file")"
    done
}

recipe_lightroom::launch() {
    recipe_lightroom::_locale
    recipe_hooks::_source security.sh
    recipe_hooks::_source sharedFuncs.sh
    recipe_hooks::_source recipe-fonts.sh
    recipe_hooks::_source recipe-guard.sh
    recipe_hooks::_source recipe-win10.sh
    recipe_hooks::_source recipe-winetricks.sh
    recipe_hooks::_source recipe-vcrun.sh
    recipe_hooks::_source recipe-validate.sh

    export WINE_METHOD="${WINE_METHOD:-proton-ge}"
    recipe_hooks::runtime_init || {
        recipe_hooks::die "Proton-GE nicht verfügbar — Rezeptor → Reparieren"
    }

    recipe_lightroom::_export_launch_env
    recipe_lightroom::_validate_prefix || exit 1
    recipe_lightroom::_prepare_prefix || exit 1

    local lightroom_exe runtime_desc wine_args=() exit_code wine_bin
    lightroom_exe="$(lightroom::find_exe "$WINE_PREFIX" 2>/dev/null || true)"
    [ -n "$lightroom_exe" ] || {
        recipe_lightroom::_notify "Lightroom.exe nicht gefunden — Installation prüfen." "dialog-error"
        recipe_hooks::die "Lightroom.exe nicht gefunden — installieren oder reparieren"
    }

    runtime_desc="$(wine_runtime::describe 2>/dev/null || echo "Proton-GE")"
    echo "═══════════════════════════════════════════════════════════════"
    echo "          Adobe Lightroom Classic - Linux Launcher"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Lightroom-Pfad: $lightroom_exe"
    echo "Wine-Prefix:    $WINE_PREFIX"
    echo "Wine-Version:   $runtime_desc"
    echo "GPU (D3D12):    vkd3d-proton — Voreinstellungen → Leistung"
    echo ""
    echo "Tipps: Erster Start kann 1–2 Minuten dauern; bei Problemen Reparieren."
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "🔄 Lightroom wird gestartet..."

    if type recipe_notify::starting >/dev/null 2>&1; then
        recipe_notify::starting
    else
        recipe_lightroom::_notify "Wird gestartet…" \
            "$(recipe_guard::notify_icon 2>/dev/null || true)"
    fi

    recipe_lightroom::_wine_args wine_args "$@"
    recipe_lightroom::_runtime_log "Starte Lightroom: $lightroom_exe"
    recipe_lightroom::_runtime_log "WINEDLLOVERRIDES=$WINEDLLOVERRIDES LD_PRELOAD=${LD_PRELOAD:-<unset>}"

    wine_bin="${WINE:-wine}"
    if [ -n "${WINE64:-}" ] && [ -x "${WINE64}" ]; then
        wine_bin="$WINE64"
    elif [ -x "$(dirname "${WINE:-}")/wine64" ]; then
        wine_bin="$(dirname "$WINE")/wine64"
    fi

    # set -e in launch.sh would abort here on non-zero wine and skip the exit log.
    set +e
    if [ ${#wine_args[@]} -gt 0 ]; then
        "$wine_bin" "$lightroom_exe" "${wine_args[@]}" >>"${DATA_ROOT}/lightroom-runtime.log" 2>&1
    else
        "$wine_bin" "$lightroom_exe" >>"${DATA_ROOT}/lightroom-runtime.log" 2>&1
    fi
    exit_code=$?
    set -e
    recipe_lightroom::_runtime_log "Lightroom.exe wine exit=$exit_code"

    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "⚠ Lightroom wurde mit Exit-Code $exit_code beendet"
        echo "Log: ${DATA_ROOT}/lightroom-runtime.log"
        recipe_lightroom::_notify "Start fehlgeschlagen (Exit $exit_code) — Log prüfen." "dialog-error"
    fi
    return "$exit_code"
}
