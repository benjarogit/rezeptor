#!/usr/bin/env bash
# Prozesse eines Rezepts sauber beenden (Wine/EXE/wineserver).

recipe_kill::run() {
    local prefix="${1:?WINEPREFIX}"
    local exe_pattern="${2:-}"
    local label="${3:-Rezept}"

    echo "→ Beende $label …"

    if [ -n "$exe_pattern" ]; then
        pkill -f "$exe_pattern" 2>/dev/null || true
        sleep 1
        pkill -9 -f "$exe_pattern" 2>/dev/null || true
    fi

    if [ -d "$prefix" ]; then
        export WINEPREFIX="$prefix"
        if type wine_runtime::wineserver >/dev/null 2>&1; then
            wine_runtime::wineserver -k 2>/dev/null || true
        elif command -v wineserver >/dev/null 2>&1; then
            wineserver -k 2>/dev/null || true
        fi
    fi

    sleep 1
    if [ -n "$exe_pattern" ] && pgrep -f "$exe_pattern" >/dev/null 2>&1; then
        echo "✗ Einige Prozesse laufen noch: $exe_pattern" >&2
        return 1
    fi
    echo "✓ $label beendet"
    return 0
}
