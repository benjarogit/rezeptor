#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill
recipe_hooks::_source recipe-guard.sh

wine_runtime::init 2>/dev/null || true
wine_runtime::export_env 2>/dev/null || true
output::section "Premiere beenden"
output::progress_begin 3 "Beenden"
output::progress_tick "Adobe Premiere Pro.exe"
recipe_kill::run "$WINEPREFIX" "Adobe Premiere Pro.exe" "Adobe Premiere Pro"
pkill -9 -f 'Adobe Premiere Pro\.exe' 2>/dev/null || true
pkill -9 -f 'crashpad_handler.exe' 2>/dev/null || true
output::progress_tick "Wine Desktop / wineserver"
recipe_kill::run "$WINEPREFIX" "explorer.exe" "Wine Desktop" 2>/dev/null || true
if type wine_runtime::wineserver >/dev/null 2>&1; then
    wine_runtime::wineserver -k 2>/dev/null || true
elif [ -n "${WINE:-}" ] && [ -n "${WINEPREFIX:-}" ]; then
    "$WINE" wineserver -k 2>/dev/null || true
fi
recipe_guard::kill_stale_winetricks 2>/dev/null || pkill -f 'winetricks -q win10' 2>/dev/null || true
output::progress_done "Premiere beendet"
