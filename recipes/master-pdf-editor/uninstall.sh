#!/usr/bin/env bash
# Vollständige Deinstallation: Desktop + DATA_ROOT + kanonischer data_root.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal

output::section "Master PDF Editor deinstallieren"
output::progress_begin 2 "Deinstallation"

output::progress_tick "Prozesse"
pkill -f "MasterPDFEditor.exe" 2>/dev/null || true
pkill -9 -f "MasterPDFEditor.exe" 2>/dev/null || true

output::progress_tick "Desktop & Rezeptor-Daten"
recipe_hooks::purge_recipe_data

output::progress_done "Deinstalliert"
output::success "Master PDF Editor entfernt (Proton-GE unter runtime/ bleibt)"
