#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

output::progress_begin 3 "Reparatur"
output::step "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    output::success "Validate OK — nichts zu reparieren"
    exit 0
fi

output::section "Reparatur"
recipe_hooks::runtime_init || exit 1
output::step "Winetricks aus recipe.yml"
recipe_hooks::install_winetricks_from_recipe || exit 11
output::progress_done "Reparatur abgeschlossen"
output::success "Reparatur abgeschlossen"
exit 0
