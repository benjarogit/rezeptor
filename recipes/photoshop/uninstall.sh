#!/usr/bin/env bash
# Rezeptor: Prefix + Desktop/Icons + Datenordner entfernen. Proton-GE (shared) bleibt.

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
recipe_hooks::load minimal

output::section "Photoshop deinstallieren"
output::progress_begin 3 "Deinstallation"

output::progress_tick "Prozesse beenden"
pkill -f "Photoshop.exe" 2>/dev/null || true
pkill -f "photoshop/launch.sh" 2>/dev/null || true
pkill -9 -f "Photoshop.exe" 2>/dev/null || true

output::progress_tick "Desktop, Icons & Daten"
recipe_hooks::purge_recipe_data

output::progress_tick "Fertig"
output::progress_done "Photoshop deinstalliert"
output::success "Photoshop Rezept entfernt (Proton-GE unter ~/.local/share/wine-software/runtime/ bleibt)"
