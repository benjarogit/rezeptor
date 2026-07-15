#!/usr/bin/env bash
# Start über Proton-GE + OnlineFix-DLL-Overrides (SteamAppId=Fake).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch
recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
recipe_hooks::_source env-file.sh 2>/dev/null || true

script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
game_exe="$(recipe_hooks::state_get GAME_EXE 2>/dev/null || true)"
game_dir="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
[ -n "$game_dir" ] || game_dir="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
proton="$(recipe_hooks::state_get PROTON 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
fake_id="$(recipe_hooks::state_get FAKE_STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 0)"
[ -n "$fake_id" ] || fake_id="$(recipe_get "$RECIPE_YML" steam_fake_appid 2>/dev/null || echo 480)"
exe_name="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo Game.exe)"
exe_name="${exe_name##*/}"

steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    compat="$steam_root/steamapps/compatdata/${appid}"
fi
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    if type wine_runtime::resolve_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_proton_script "$steam_root" 2>/dev/null || true)"
    fi
fi
if [ -z "$game_exe" ] || [ ! -f "$game_exe" ]; then
    if [ -n "$game_dir" ] && [ -f "$game_dir/$exe_name" ]; then
        game_exe="$game_dir/$exe_name"
    fi
fi

if [ -n "$script" ] && [ -x "$script" ]; then
    exec "$script" "$@"
fi

[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die "Proton-GE fehlt"
[ -n "$game_exe" ] && [ -f "$game_exe" ] || recipe_hooks::die "$exe_name fehlt — Installieren"
[ -n "$compat" ] && [ -d "$compat" ] || recipe_hooks::die "compatdata AppID $appid fehlt"

export WINEDLLOVERRIDES="OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b"
export SteamAppId="$fake_id"
export SteamGameId="$fake_id"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_DATA_PATH="$compat"
unset PROTON_ENABLE_WAYLAND || true
cd "$(dirname "$game_exe")"
exec "$proton" run "$game_exe" "$@"
