#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill
recipe_hooks::_source env-file.sh

export SCR_PATH="$DATA_ROOT"

output::section "WISO deinstallieren"
output::progress_begin 3 "Deinstallation"

output::progress_tick "Prozesse beenden"
pkill -f "wiso.*${DATA_ROOT}" 2>/dev/null || true
pkill -f "wiso-launch.sh" 2>/dev/null || true
pkill -f "wiso-mit-wine.sh" 2>/dev/null || true

output::progress_tick "Prefix & Launcher"
[ -d "$DATA_ROOT/prefix" ] && rm -rf "$DATA_ROOT/prefix"
rm -f "$DATA_ROOT/portable.env" "$DATA_ROOT/bin/wiso-launch.sh"

output::progress_done "WISO deinstalliert"
output::success "WISO Rezept entfernt (Portable-Ordner bleibt unberührt)"
