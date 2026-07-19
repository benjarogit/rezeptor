#!/usr/bin/env bash
# Read-only: EXE + Online-Fix + Spacewar (wenn FakeAppId=480).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/wine-runtime.sh"

GAME_EXE="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo Game.exe)"
GAME_EXE="${GAME_EXE##*/}"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 0)"
FAKE_APPID="$(recipe_get "$RECIPE_YML" steam_fake_appid 2>/dev/null || echo 480)"
WIN64_REL="$(recipe_get "$RECIPE_YML" steam_fix_win64_rel 2>/dev/null || echo Binaries/Win64)"

failures=0
output::progress_begin 6 "Prüfen"

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
    recipe_validate::warn "Spacewar (480) fehlt — steam://install/480 vor dem Start"
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

output::progress_tick "Proton (compatdata)"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
expected_proton=""
if [ -n "$compat" ] && [ -d "$compat" ] && type wine_runtime::resolve_compatdata_proton_script >/dev/null 2>&1; then
    expected_proton="$(wine_runtime::resolve_compatdata_proton_script "$steam_root" "$compat" 2>/dev/null || true)"
fi
if [ -n "$script" ] && [ -x "$script" ] && [ -n "$expected_proton" ] && [ -f "$expected_proton" ]; then
    wrapper_proton="$(grep -m1 '^PROTON=' "$script" 2>/dev/null | sed 's/^PROTON=//' || true)"
    if [ -n "$wrapper_proton" ] && [ "$wrapper_proton" = "$expected_proton" ]; then
        recipe_validate::ok "Proton: $(basename "$(dirname "$expected_proton")")"
    elif [ -n "$wrapper_proton" ]; then
        recipe_validate::fail "Launch-Wrapper Proton veraltet ($(basename "$(dirname "$wrapper_proton")") → $(basename "$(dirname "$expected_proton")")) — Reparieren"
        failures=$((failures + 1))
    else
        recipe_validate::warn "Launch-Wrapper ohne PROTON-Zeile — Reparieren"
    fi
elif [ -n "$expected_proton" ] && [ -f "$expected_proton" ]; then
    recipe_validate::warn "Launch-Wrapper fehlt — Proton wäre $(basename "$(dirname "$expected_proton")")"
fi

output::progress_done "Validate"
[ "$failures" -eq 0 ] || exit 1
