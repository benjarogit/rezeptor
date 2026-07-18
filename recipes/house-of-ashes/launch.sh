#!/usr/bin/env bash
# Start über Proton + OnlineFix-DLL-Overrides (SteamAppId=480).
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
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 1281590)"
[ -n "$fake_id" ] || fake_id="480"

steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

# Spacewar (FakeAppId) — ohne 480 startet der Online-Fix nicht zuverlässig.
hoa_spacewar_ok() {
    local lib p
    for lib in "$steam_root" "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
        [ -d "$lib" ] || continue
        [ -f "$lib/steamapps/appmanifest_480.acf" ] && return 0
        [ -d "$lib/steamapps/common/Spacewar" ] && return 0
        if [ -f "$lib/steamapps/libraryfolders.vdf" ]; then
            while IFS= read -r p; do
                [ -f "$p/steamapps/appmanifest_480.acf" ] && return 0
                [ -d "$p/steamapps/common/Spacewar" ] && return 0
            done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$lib/steamapps/libraryfolders.vdf" \
                | sed -E 's/.*"([^"]+)"/\1/' || true)
        fi
    done
    for p in /mnt/*/SteamLibrary /mnt/*/*/SteamLibrary; do
        [ -f "$p/steamapps/appmanifest_480.acf" ] && return 0
        [ -d "$p/steamapps/common/Spacewar" ] && return 0
    done 2>/dev/null || true
    return 1
}
if [ "$fake_id" = "480" ] && ! hoa_spacewar_ok; then
    if command -v steam >/dev/null 2>&1; then
        steam steam://install/480 >/dev/null 2>&1 &
    elif [ -x "$steam_root/steam.sh" ]; then
        "$steam_root/steam.sh" steam://install/480 >/dev/null 2>&1 &
    fi
    recipe_hooks::die \
        "Spacewar (480) fehlt — in Steam installieren (steam://install/480), dann erneut Starten"
fi

if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    compat="$steam_root/steamapps/compatdata/${appid}"
fi
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    if type wine_runtime::resolve_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_proton_script "$steam_root" 2>/dev/null || true)"
    fi
fi
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    if compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
        proton="$(ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1)"
    fi
fi
if [ -z "$game_exe" ] || [ ! -f "$game_exe" ]; then
    if [ -n "$game_dir" ] && [ -f "$game_dir/HouseOfAshes.exe" ]; then
        game_exe="$game_dir/HouseOfAshes.exe"
    fi
fi

if [ -n "$script" ] && [ -x "$script" ]; then
    recipe_notify::starting
    exec "$script" "$@"
fi

[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
    "Proton-GE fehlt — Rezeptor-Runtime oder Steam GE-Proton installieren"
[ -n "$game_exe" ] && [ -f "$game_exe" ] || recipe_hooks::die \
    "HouseOfAshes.exe fehlt — bitte Installieren (Spielordner wählen)"
[ -n "$compat" ] && [ -d "$compat" ] || recipe_hooks::die \
    "Steam compatdata für AppID $appid fehlt — Spiel einmal unter Proton starten"

export WINEDLLOVERRIDES="OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b"
export SteamAppId="$fake_id"
export SteamGameId="$fake_id"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_DATA_PATH="$compat"
unset PROTON_ENABLE_WAYLAND || true

recipe_notify::starting
cd "$(dirname "$game_exe")"
exec "$proton" run "$game_exe" "$@"
