#!/usr/bin/env bash
# Read-only: EXE + Online-Fix + Spacewar (wenn FakeAppId=480).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate

GAME_EXE="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo Game.exe)"
GAME_EXE="${GAME_EXE##*/}"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 0)"
FAKE_APPID="$(recipe_get "$RECIPE_YML" steam_fake_appid 2>/dev/null || echo 480)"
WIN64_REL="$(recipe_get "$RECIPE_YML" steam_fix_win64_rel 2>/dev/null || echo Binaries/Win64)"

failures=0
output::progress_begin 5 "Prüfen"

spacewar_ok() {
    local steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
    [ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
    local lib p
    for lib in "$steam_root" "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
        [ -d "$lib" ] || continue
        [ -f "$lib/steamapps/appmanifest_480.acf" ] && return 0
        [ -d "$lib/steamapps/common/Spacewar" ] && return 0
    done
    return 1
}

game_dir="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
[ -n "$game_dir" ] || game_dir="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"

output::progress_tick "Spacewar / FakeAppId"
if [ "$FAKE_APPID" != "480" ] || spacewar_ok; then
    recipe_validate::ok "FakeAppId $FAKE_APPID / Spacewar"
else
    recipe_validate::fail "Spacewar (480) fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "Spielordner"
if [ -n "$game_dir" ] && [ -d "$game_dir" ]; then
    recipe_validate::ok "Spielordner: $game_dir"
else
    recipe_validate::fail "Spielordner fehlt — Installieren"
    failures=$((failures + 1))
    game_dir=""
fi

output::progress_tick "EXE"
if [ -n "$game_dir" ] && [ -f "$game_dir/$GAME_EXE" ]; then
    recipe_validate::ok "$GAME_EXE"
else
    recipe_validate::fail "$GAME_EXE fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "Online-Fix"
if [ -n "$game_dir" ] && [ -d "$game_dir/$WIN64_REL" ]; then
    recipe_validate::ok "$WIN64_REL"
else
    recipe_validate::fail "Fix-Ordner fehlt: $WIN64_REL"
    failures=$((failures + 1))
fi

output::progress_tick "Wrapper"
script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
if [ -n "$script" ] && [ -x "$script" ]; then
    recipe_validate::ok "Launch-Wrapper"
else
    recipe_validate::warn "Wrapper fehlt — Installieren/Reparieren"
fi

output::progress_done "Validate"
[ "$failures" -eq 0 ] || exit 1
