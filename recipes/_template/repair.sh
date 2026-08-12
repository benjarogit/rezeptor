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
recipe_hooks::load repair

output::progress_begin 3 "Reparatur"
output::step "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh" >>"${LOG_FILE:-/dev/null}" 2>&1; then
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
