#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill
recipe_hooks::_source env-file.sh 2>/dev/null || true

output::section "ZA4 Trainer beenden"

compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 694280)"
if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    compat="/mnt/ssd2/SteamLibrary/steamapps/compatdata/${appid}"
    [ -d "$compat" ] || compat="${HOME}/.local/share/Steam/steamapps/compatdata/${appid}"
fi

# Trainer-EXE + Proton-Wrapper
pkill -f 'ZA4-Trainer\.exe' 2>/dev/null || true
pkill -f 'proton run .*/ZA4-Trainer' 2>/dev/null || true
sleep 0.5
pkill -9 -f 'ZA4-Trainer\.exe' 2>/dev/null || true

# Steam-Prefix des Spiels (nicht Rezept-DATA_ROOT)
if [ -n "$compat" ] && [ -d "$compat" ]; then
    export STEAM_COMPAT_DATA_PATH="$compat"
    export WINEPREFIX="$compat/pfx"
    if [ -x "${HOME}/.local/share/Steam/compatibilitytools.d/GE-Proton10-34/proton" ]; then
        # wineserver im compatdata beenden, falls noch da
        WINEPREFIX="$compat/pfx" wineserver -k 2>/dev/null || true
    else
        WINEPREFIX="$compat/pfx" wineserver -k 2>/dev/null || true
    fi
fi

output::success "ZA4 Trainer beendet"
