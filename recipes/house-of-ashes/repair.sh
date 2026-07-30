#!/usr/bin/env bash
# Validate → bei Fehlern Wrapper/Pfade aus GAME_DIR neu schreiben (kein Reinstall).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

GAME_EXE="HouseOfAshes.exe"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 1281590)"
FAKE_APPID="480"
WINEDLL_OVERRIDES='OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b'

output::progress_begin 3 "Reparatur"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    exit 0
fi

output::progress_tick "Spielordner / Wrapper"
game_dir="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
[ -n "$game_dir" ] || game_dir="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
    output::progress_done "Spielordner unbekannt — Installieren erneut (Ordner wählen)"
    exit 1
fi

fix_src="${RECIPE_FIX_ROOT:-}"
merge_rel="${RECIPE_FIX_MERGE_PATH:-SMG025/Binaries/Win64}"
if [ -n "$fix_src" ] && [ -d "$fix_src" ]; then
    # shellcheck source=/dev/null
    source "$RECIPE_DIR/../../core/recipe-online-fix.sh"
    recipe_online_fix::merge "$game_dir" "$fix_src" "$merge_rel" || true
fi

# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-house-of-ashes.sh"
if ! hoa::write_launch_wrapper "$game_dir"; then
    output::progress_done "Reparatur fehlgeschlagen"
    exit 1
fi

if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig — Fix-Dateien prüfen"
exit 1
