#!/usr/bin/env bash
# Einheitlicher winetricks-Lauf für Rezepte (Proton-GE, kein Subshell-Rauschen).

recipe_winetricks::prepare() {
    wine_runtime::init || return 1
    wine_runtime::export_env
    wine_runtime::cache_dir >/dev/null
    export WINEDEBUG="${WINEDEBUG:--all}"
}

recipe_winetricks::stabilize_prefix() {
    local old_overrides="${WINEDLLOVERRIDES:-}"
    if type recipe_dotnet::installed >/dev/null 2>&1 && ! recipe_dotnet::installed; then
        export WINEDLLOVERRIDES="${old_overrides:+${old_overrides};}mscoree=d;mshtml=d"
    fi
    wine wineboot -u >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    export WINEDLLOVERRIDES="$old_overrides"
    wine_runtime::wineserver -w 2>/dev/null || true
    sleep 2
}

# Nur bei SIGSEGV (139): einmal Proton neu starten. Kein Retry bei normalen Fehlern.
recipe_winetricks::run() {
    local log_file="$1"
    shift
    local rc attempt

    recipe_winetricks::prepare || return 1
    recipe_winetricks::stabilize_prefix
    rc=1
    for attempt in 1 2; do
        if [ "$attempt" -eq 2 ]; then
            [ "$rc" -eq 139 ] || break
            output::warning "winetricks $* — Proton-Neustart nach Absturz (einmalig)"
            wine_runtime::wineserver -k 2>/dev/null || true
            sleep 2
            wine wineboot -u >> "${LOG_FILE:-/dev/null}" 2>&1 || true
            wine_runtime::wineserver -w 2>/dev/null || true
            sleep 2
        fi
        set +e
        winetricks -q "$@" >> "$log_file" 2>&1
        rc=$?
        set -e
        [ "$rc" -eq 0 ] && break
    done
    return "$rc"
}
