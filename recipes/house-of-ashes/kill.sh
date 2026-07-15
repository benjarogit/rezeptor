#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill
recipe_hooks::_source env-file.sh 2>/dev/null || true

output::section "House of Ashes beenden"

compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 1281590)"
if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    compat="${HOME}/.local/share/Steam/steamapps/compatdata/${appid}"
fi

pkill -f 'HouseOfAshes\.exe' 2>/dev/null || true
pkill -f 'proton run .*/HouseOfAshes' 2>/dev/null || true
sleep 0.5
pkill -9 -f 'HouseOfAshes\.exe' 2>/dev/null || true

if [ -n "$compat" ] && [ -d "$compat" ]; then
    export STEAM_COMPAT_DATA_PATH="$compat"
    export WINEPREFIX="$compat/pfx"
    WINEPREFIX="$compat/pfx" wineserver -k 2>/dev/null || true
fi

output::success "House of Ashes beendet"
