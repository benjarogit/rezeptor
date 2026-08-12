#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
if [ -f "${PROJECT_ROOT:-}/core/recipe-hooks.sh" ]; then
    source "$PROJECT_ROOT/core/recipe-hooks.sh"
elif [ -f "$RECIPE_DIR/../../core/recipe-hooks.sh" ]; then
    source "$RECIPE_DIR/../../core/recipe-hooks.sh"
else
    echo "ERROR: core/recipe-hooks.sh not found (set PROJECT_ROOT)" >&2
    exit 1
fi
recipe_hooks::load kill
recipe_hooks::_source output.sh

wine_runtime::init 2>/dev/null || true
output::section "WISO beenden"
output::progress_begin 2 "Beenden"
output::progress_tick "Prozesse"
# Virtual-Desktop-Reste (blauer Explorer) zuerst
pkill -9 -f "explorer.exe /desktop=wiso" 2>/dev/null || true
pkill -9 -f "explorer.exe.*/desktop=wiso" 2>/dev/null || true
pkill -9 -f "start.exe /exec explorer" 2>/dev/null || true
recipe_kill::run "$WINEPREFIX" "wiso2026.exe|start.exe|WISO Steuer" "WISO Steuer"
pkill -f "wiso-launch.sh" 2>/dev/null || true
pkill -f "wiso-mit-wine.sh" 2>/dev/null || true
output::progress_done "WISO beendet"
