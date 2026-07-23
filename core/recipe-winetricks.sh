#!/usr/bin/env bash
# Einheitlicher winetricks-Lauf für Rezepte (Proton-GE, kein Subshell-Rauschen).

WINETRICKS_WINEBOOT_WATCHDOG_SEC=60
WINETRICKS_DEFAULT_TIMEOUT_SEC=600
WINETRICKS_HEAVY_TIMEOUT_SEC=900
# wineserver -w nach Adobe/explorer-/desktop kann ewig warten — hart begrenzen.
WINETRICKS_WINESERVER_WAIT_SEC=45

recipe_winetricks::prepare() {
    wine_runtime::init || return 1
    wine_runtime::export_env
    wine_runtime::cache_dir >/dev/null
    export WINEDEBUG="${WINEDEBUG:--all}"
    # Geerbtes Session-D-Bus → oft Assertion-Abort in wine/regedit, dann hängt wineserver -w.
    unset DBUS_SESSION_BUS_ADDRESS || true
    export NO_AT_BRIDGE=1
    export DBUS_FATAL_WARNINGS=0
}

# Wartet auf Prefix-Idle; bei Timeout Prefix hart beenden (kein Endlos-Hang).
recipe_winetricks::wineserver_wait() {
    local sec="${1:-${WINETRICKS_WINESERVER_WAIT_SEC}}"
    local wpid="" i=0
    wine_runtime::wineserver -w 2>/dev/null &
    wpid=$!
    while kill -0 "$wpid" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge "$sec" ]; then
            kill -TERM "$wpid" 2>/dev/null || true
            wine_runtime::wineserver -k 2>/dev/null || true
            wait "$wpid" 2>/dev/null || true
            return 0
        fi
        sleep 1
    done
    wait "$wpid" 2>/dev/null || true
    return 0
}

recipe_winetricks::stabilize_prefix() {
    local old_overrides="${WINEDLLOVERRIDES:-}"
    local boot_pid=""
    if type recipe_dotnet::installed >/dev/null 2>&1 && ! recipe_dotnet::installed; then
        export WINEDLLOVERRIDES="${old_overrides:+${old_overrides};}mscoree=d;mshtml=d"
    fi
    # wineboot -u kann bei hängendem wineserver ewig blockieren — Timeout + Kill.
    wine wineboot -u >> "${LOG_FILE:-/dev/null}" 2>&1 &
    boot_pid=$!
    (
        sleep "$WINETRICKS_WINEBOOT_WATCHDOG_SEC"
        if kill -0 "$boot_pid" 2>/dev/null; then
            kill -TERM "$boot_pid" 2>/dev/null || true
            wine_runtime::wineserver -k 2>/dev/null || true
        fi
    ) &
    wait "$boot_pid" 2>/dev/null || true
    export WINEDLLOVERRIDES="$old_overrides"
    recipe_winetricks::wineserver_wait
    sleep 1
}

recipe_winetricks::_pkg_satisfied() {
    local pkg="$1"
    local wow64="${WINEPREFIX:-}/drive_c/windows/syswow64"
    local fonts="${WINEPREFIX:-}/drive_c/windows/Fonts"
    case "$pkg" in
        gdiplus|gdiplus_winxp)
            # Native MS-GDI+ (nicht Wine-Builtin) — gdiplus_winxp-Download ist tot.
            type recipe_validate::native_pe >/dev/null 2>&1 \
                && recipe_validate::native_pe "$wow64/gdiplus.dll"
            ;;
        d3dcompiler_47) [ -f "$wow64/d3dcompiler_47.dll" ] ;;
        corefonts)
            [ "$(find "$fonts" -maxdepth 1 -type f 2>/dev/null | wc -l)" -ge 5 ]
            ;;
        *) return 1 ;;
    esac
}

# Nur bei SIGSEGV (139): einmal Proton/Wine-Neustart. Kein Retry bei normalen Fehlern.
recipe_winetricks::_invoke() {
    # winetricks muss Proton-GE nutzen (WINE=…), nicht System-Wine.
    # Kein recipe_wine_silent::run — xvfb/offscreen um winetricks → SIGSEGV unter Proton.
    # wine()/wineboot()-Wrapper unsetten — winetricks ruft „wine“ intern auf.
    (
        unset -f wine wineboot 2>/dev/null || true
        wine_runtime::export_env || return 1
        wine_runtime::winetricks "$@"
    )
}

# Vordergrund + timeout(1) auf externes bash -c (nicht Hintergrundjob).
# Hintergrund + Watchdog unter Proton → oft SIGSEGV (139) obwohl plain winetricks OK ist.
recipe_winetricks::_invoke_with_timeout() {
    local log_file="$1" wt_timeout="$2"
    shift 2
    local root="${PROJECT_ROOT:-}"
    if [ -z "$root" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
        root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
    [ -n "$root" ] || root="$(pwd)"

    if command -v timeout >/dev/null 2>&1 && [ "$wt_timeout" -gt 0 ]; then
        # shellcheck disable=SC2086
        timeout --signal=TERM --kill-after=15 "$wt_timeout" \
            env WINEPREFIX="${WINEPREFIX:?}" WINE="${WINE:?}" \
                PROJECT_ROOT="$root" CORE_DIR="${CORE_DIR:-$root/core}" \
            bash -c '
                set -eu
                source "$CORE_DIR/wine-runtime.sh"
                unset -f wine wineboot 2>/dev/null || true
                wine_runtime::init || exit 1
                wine_runtime::export_env || exit 1
                wine_runtime::winetricks "$@"
            ' _ "$@" >> "$log_file" 2>&1
        return $?
    fi

    recipe_winetricks::_invoke "$@" >> "$log_file" 2>&1
}

recipe_winetricks::run() {
    local log_file="$1"
    shift
    local rc attempt wt_timeout=${WINETRICKS_DEFAULT_TIMEOUT_SEC}

    # Font-Pakete laden/extrahieren oft >5 Min — 300s killt mitten im Lauf (falsch als Fail).
    case "$*" in
        *corefonts*|*allfonts*|*calibri*|*tahoma*|*dotnet48*|*vcrun*)
            wt_timeout=${WINETRICKS_HEAVY_TIMEOUT_SEC}
            ;;
    esac

    if [ "$#" -eq 1 ] && recipe_winetricks::_pkg_satisfied "$1"; then
        type output::success >/dev/null 2>&1 && output::success "$1 (bereits im Prefix)"
        return 0
    fi

    recipe_winetricks::prepare || return 1
    recipe_winetricks::stabilize_prefix
    if type recipe_dotnet::installed >/dev/null 2>&1 && ! recipe_dotnet::installed; then
        type recipe_hooks::hint_wine_popup >/dev/null 2>&1 && recipe_hooks::hint_wine_popup
    fi
    rc=1
    for attempt in 1 2; do
        if [ "$attempt" -eq 2 ]; then
            [ "$rc" -eq 139 ] || break
            output::warning "winetricks $* — Wine-Neustart nach Absturz (einmalig)"
            wine_runtime::wineserver -k 2>/dev/null || true
            sleep 2
            wine wineboot -u >> "${LOG_FILE:-/dev/null}" 2>&1 || true
            recipe_winetricks::wineserver_wait
            sleep 2
        fi
        set +e
        recipe_winetricks::_invoke_with_timeout "$log_file" "$wt_timeout" -q "$@"
        rc=$?
        set -e
        [ "$rc" -eq 0 ] && break
        if [ "$#" -eq 1 ] && recipe_winetricks::_pkg_satisfied "$1"; then
            rc=0
            break
        fi
    done
    return "$rc"
}
