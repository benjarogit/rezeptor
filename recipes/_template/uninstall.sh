#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal
recipe_hooks::_source env-file.sh

output::progress_begin 1 "Deinstallation"
output::progress_tick "Rezept-Status"
rm -f "$(recipe_hooks::state_file)"
output::progress_done "Deinstalliert"
output::success "Deinstalliert: $DATA_ROOT (recipe.env geleert — Prefix manuell löschen: rm -rf $DATA_ROOT/prefix)"
