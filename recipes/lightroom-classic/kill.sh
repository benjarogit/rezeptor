#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
if [ -f "${PROJECT_ROOT:-}/core/recipe-hooks.sh" ]; then
    source "$PROJECT_ROOT/core/recipe-hooks.sh"
elif [ -f "$RECIPE_DIR/../../core/recipe-hooks.sh" ]; then
    source "$RECIPE_DIR/../../core/recipe-hooks.sh"
else
    echo "ERROR: core/recipe-hooks.sh not found (set PROJECT_ROOT)" >&2
    exit 1
fi
recipe_hooks::load kill
recipe_hooks::_source recipe-guard.sh

wine_runtime::init 2>/dev/null || true
wine_runtime::export_env 2>/dev/null || true
output::section "Lightroom Classic beenden"
output::progress_begin 3 "Beenden"
output::progress_tick "Lightroom.exe"
recipe_kill::run "$WINEPREFIX" "Lightroom.exe" "Adobe Lightroom Classic"
# Adobe-Hintergrundprozesse halten Locks und blockieren sonst den nächsten Start.
pkill -9 -f 'Lightroom\.exe' 2>/dev/null || true
pkill -9 -f 'Adobe Lightroom CEF Helper\.exe' 2>/dev/null || true
pkill -9 -f 'Adobe Crash Processor\.exe' 2>/dev/null || true
pkill -9 -f 'CRLogTransport\.exe' 2>/dev/null || true
output::progress_tick "Wine Desktop / wineserver"
recipe_kill::run "$WINEPREFIX" "explorer.exe" "Wine Desktop" 2>/dev/null || true
if type wine_runtime::wineserver >/dev/null 2>&1; then
    wine_runtime::wineserver -k 2>/dev/null || true
elif [ -n "${WINE:-}" ] && [ -n "${WINEPREFIX:-}" ]; then
    "$WINE" wineserver -k 2>/dev/null || true
fi
recipe_guard::kill_stale_winetricks 2>/dev/null || true
output::progress_done "Lightroom beendet"
