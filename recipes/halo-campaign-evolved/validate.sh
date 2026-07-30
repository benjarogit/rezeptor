#!/usr/bin/env bash
# Halo Campaign Evolved — Validate
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate

export WINEPREFIX="${DATA_ROOT}/prefix"
failures=0

output::progress_begin 4 "Prüfen"

output::progress_tick "Prefix"
if ! recipe_hooks::validate_prefix; then
    failures=$((failures + 1))
fi

output::progress_tick "Spiel-EXE"
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
GAME_EXE="$(recipe_hooks::state_get GAME_EXE 2>/dev/null || true)"
if [ -n "$GAME_EXE" ] && [ -f "$GAME_EXE" ]; then
    recipe_validate::ok "EXE: $(basename "$GAME_EXE")"
elif [ -n "$WORK_ROOT" ] && EXE="$(recipe_hooks::find_exe "$WORK_ROOT" 2>/dev/null || true)" && [ -n "$EXE" ]; then
    recipe_validate::ok "EXE: $(basename "$EXE")"
elif type recipe_halo_campaign_evolved::find_game_exe >/dev/null 2>&1 \
    && EXE="$(recipe_halo_campaign_evolved::find_game_exe 2>/dev/null || true)" && [ -n "$EXE" ]; then
    recipe_validate::ok "EXE: $(basename "$EXE")"
else
    # Modul ggf. nachladen
    # shellcheck source=/dev/null
    source "$CORE_DIR/recipe-halo-campaign-evolved.sh" 2>/dev/null || true
    if EXE="$(recipe_halo_campaign_evolved::find_game_exe 2>/dev/null || true)" && [ -n "$EXE" ]; then
        recipe_validate::ok "EXE: $(basename "$EXE")"
    else
        recipe_validate::fail "Halo-EXE fehlt im Prefix"
        failures=$((failures + 1))
    fi
fi

output::progress_tick "Updates"
recipe_hooks::_source recipe-updates.sh 2>/dev/null || true
if type recipe_updates::status >/dev/null 2>&1; then
    recipe_updates::status
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
