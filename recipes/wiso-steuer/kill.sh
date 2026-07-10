#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
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
