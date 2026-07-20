#!/usr/bin/env bash
# Read-only: EXE + Online-Fix-Stack.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate

GAME_EXE="HouseOfAshes.exe"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 1281590)"
FAKE_APPID="480"
WIN64_REL="SMG025/Binaries/Win64"
STEAM_API_REL="Engine/Binaries/ThirdParty/Steamworks/Steamv147/Win64/steam_api64.dll"
REQUIRED_WIN64=(OnlineFix64.dll OnlineFix.ini winmm.dll StubDRM64.dll dlllist.txt)
FLT_CONFLICT_FILES=(flt.ini steamclient64.dll)

failures=0
output::progress_begin 7 "Prüfen"

# Spacewar (480) — Fake-AppID des Online-Fix
hoa_spacewar_ok() {
    local steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
    [ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
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

game_dir="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
[ -n "$game_dir" ] || game_dir="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"

output::progress_tick "Steam / Spacewar (480)"
if hoa_spacewar_ok; then
    recipe_validate::ok "Spacewar (AppID 480) in Steam"
else
    # Warnung statt Fail: Einrichtung/Wrapper OK; Start braucht 480.
    recipe_validate::warn "Spacewar (480) fehlt — steam://install/480, dann Starten"
fi

output::progress_tick "Spielordner"
if [ -n "$game_dir" ] && [ -d "$game_dir" ]; then
    recipe_validate::ok "Spielordner: $game_dir"
else
    recipe_validate::fail "Spielordner fehlt — bitte Installieren (Ordner wählen)"
    failures=$((failures + 1))
    game_dir=""
fi

output::progress_tick "HouseOfAshes.exe"
if [ -n "$game_dir" ] && [ -f "$game_dir/$GAME_EXE" ]; then
    recipe_validate::ok "$GAME_EXE"
else
    recipe_validate::fail "$GAME_EXE fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "Online-Fix Dateien"
win64=""
if [ -n "$game_dir" ]; then
    win64="$game_dir/$WIN64_REL"
fi
if [ -n "$win64" ] && [ -d "$win64" ]; then
    missing=0
    for f in "${REQUIRED_WIN64[@]}"; do
        if [ -f "$win64/$f" ]; then
            recipe_validate::ok "$WIN64_REL/$f"
        else
            recipe_validate::fail "Fehlt: $WIN64_REL/$f"
            missing=1
            failures=$((failures + 1))
        fi
    done
    [ "$missing" -eq 0 ] || true
else
    recipe_validate::fail "Ordner fehlt: $WIN64_REL — Fix (TDPAHOA_Fix_Repair_Steam_Generic) selbst einlegen"
    failures=$((failures + 1))
fi

output::progress_tick "OnlineFix.ini AppIDs"
if [ -n "$win64" ] && [ -f "$win64/OnlineFix.ini" ]; then
    if grep -qE "FakeAppId=${FAKE_APPID}" "$win64/OnlineFix.ini" \
        && grep -qE "RealAppId=${REAL_APPID}" "$win64/OnlineFix.ini"; then
        recipe_validate::ok "FakeAppId=$FAKE_APPID RealAppId=$REAL_APPID"
    else
        recipe_validate::fail "OnlineFix.ini AppIDs falsch (erwartet Fake=$FAKE_APPID Real=$REAL_APPID)"
        failures=$((failures + 1))
    fi
else
    recipe_validate::fail "OnlineFix.ini fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "steam_api64.dll"
if [ -n "$game_dir" ] && [ -f "$game_dir/$STEAM_API_REL" ]; then
    recipe_validate::ok "steam_api64.dll"
else
    recipe_validate::fail "Fehlt: $STEAM_API_REL"
    failures=$((failures + 1))
fi

# Konflikte / Hinweise (kein Hard-Fail)
if [ -n "$win64" ] && [ -d "$win64" ]; then
    for f in "${FLT_CONFLICT_FILES[@]}"; do
        if [ -f "$win64/$f" ]; then
            recipe_validate::warn "Möglicher Konflikt: $WIN64_REL/$f"
        fi
    done
fi
if [ -n "$game_dir" ] && [ -f "$game_dir/steam_appid.txt" ]; then
    recipe_validate::warn "steam_appid.txt im Spielordner — kann den Fix stören"
fi

output::progress_tick "Launch-Wrapper / Proton"
script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
if [ -n "$script" ] && [ -x "$script" ]; then
    recipe_validate::ok "Wrapper: $script"
else
    recipe_validate::fail "Launch-Wrapper fehlt — Installieren / Reparieren"
    failures=$((failures + 1))
fi

compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
if [ -n "$compat" ] && [ -d "$compat" ]; then
    recipe_validate::ok "compatdata: $compat"
elif [ -d "$HOME/.local/share/Steam/steamapps/compatdata/$REAL_APPID" ]; then
    recipe_validate::warn "compatdata unter Standard-Steam — Wrapper ggf. neu installieren"
else
    recipe_validate::warn "compatdata AppID $REAL_APPID nicht gefunden — Spiel einmal unter Proton starten"
fi

if [ "$failures" -eq 0 ]; then
    # Version für GUI-Badge (getestet & garantiert) — stack aus recipe.yml
    _guaranteed="$(recipe_get "$RECIPE_YML" version_guaranteed 2>/dev/null || true)"
    if [ -n "$_guaranteed" ]; then
        recipe_validate::ok "Version: ${_guaranteed} (getestet & garantiert)"
    fi
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
