#!/usr/bin/env bash
# Halo Campaign Evolved — Launch
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch

recipe_hooks::runtime_init || exit 1

EXE="$(recipe_hooks::state_get GAME_EXE 2>/dev/null || true)"
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"

if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    # shellcheck source=/dev/null
    source "$CORE_DIR/recipe-halo-campaign-evolved.sh"
    EXE="$(recipe_halo_campaign_evolved::find_game_exe || true)"
fi
if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    if [ -n "$WORK_ROOT" ] && [ -d "$WORK_ROOT" ]; then
        EXE="$(recipe_hooks::find_exe "$WORK_ROOT" || true)"
    fi
fi
[ -n "$EXE" ] && [ -f "$EXE" ] || recipe_hooks::die "Nicht installiert — Halo-EXE fehlt (Setup / Update prüfen)"

cd "$(dirname "$EXE")" || exit 1
exec wine "./$(basename "$EXE")" "$@"
