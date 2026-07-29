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
output::section "Photoshop beenden"
output::progress_begin 3 "Beenden"
output::progress_tick "Photoshop.exe"
recipe_kill::run "$WINEPREFIX" "Photoshop.exe" "Adobe Photoshop"
recipe_kill::run "$WINEPREFIX" "wmain26.dll" "Photoshop (Wine)"
# Virtual Desktop = explorer.exe /desktop — sonst bleibt die blaue Fläche hängen.
output::progress_tick "Wine Desktop / wineserver"
recipe_kill::run "$WINEPREFIX" "explorer.exe" "Wine Desktop" 2>/dev/null || true
if [ -n "${WINE:-}" ] && [ -n "${WINEPREFIX:-}" ]; then
    "$WINE" wineserver -k 2>/dev/null || true
fi
recipe_guard::kill_stale_winetricks 2>/dev/null || pkill -f 'winetricks -q win10' 2>/dev/null || true
output::progress_done "Photoshop beendet"
