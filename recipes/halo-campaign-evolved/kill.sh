#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill

_glob="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo "*.exe")"
_pattern="${_glob##*/}"
_pattern="${_pattern%.exe}.exe"

wine_runtime::init 2>/dev/null || true
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh" 2>/dev/null || true
output::section "${RECIPE_NAME} beenden"
output::progress_begin 1 "Beenden"
# Co-launched BYOS trainer (same prefix) — stop by basename if present
if type recipe_halo_campaign_evolved::find_trainer_exe >/dev/null 2>&1; then
    _tr="$(recipe_halo_campaign_evolved::find_trainer_exe 2>/dev/null || true)"
    if [ -n "$_tr" ]; then
        pkill -f "$(basename "$_tr")" 2>/dev/null || true
    fi
fi
recipe_kill::run "$WINEPREFIX" "$_pattern" "$RECIPE_NAME"
output::progress_done "${RECIPE_NAME} beendet"
