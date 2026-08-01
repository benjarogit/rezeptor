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
output::progress_tick "Photoshop + Adobe-Helfer"
recipe_kill::run "$WINEPREFIX" "Photoshop.exe" "Adobe Photoshop"
# Broker-Cmdline enthält Photoshop.exe — separat hart beenden (Orphan nach Absturz/Weiß).
pkill -f '[Aa]dobe[Ii][Pp][Cc][Bb]roker' 2>/dev/null || true
recipe_kill::run "$WINEPREFIX" "AdobeIPCBroker.exe" "Adobe IPC Broker" 2>/dev/null || true
recipe_kill::run "$WINEPREFIX" "wmain26.dll" "Photoshop (Wine)"
# Virtual Desktop = explorer.exe /desktop — sonst bleibt die blaue Fläche hängen.
output::progress_tick "Wine Desktop / wineserver"
recipe_kill::run "$WINEPREFIX" "explorer.exe.*/desktop=" "Wine Desktop" 2>/dev/null || true
pkill -f 'explorer\.exe.*/desktop' 2>/dev/null || true
if [ -n "${WINEPREFIX:-}" ] && type wine_runtime::wineserver >/dev/null 2>&1; then
    wine_runtime::wineserver -k 2>/dev/null || true
elif [ -n "${WINE:-}" ] && [ -n "${WINEPREFIX:-}" ]; then
    "$WINE" wineserver -k 2>/dev/null || true
fi
pkill -9 -f 'explorer\.exe.*/desktop' 2>/dev/null || true
pkill -9 -f '[Aa]dobe[Ii][Pp][Cc][Bb]roker' 2>/dev/null || true
pkill -9 -f 'Photoshop\.exe' 2>/dev/null || true
recipe_guard::kill_stale_winetricks 2>/dev/null || pkill -f 'winetricks -q win10' 2>/dev/null || true
output::progress_done "Photoshop beendet"
