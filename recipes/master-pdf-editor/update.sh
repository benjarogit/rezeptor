#!/usr/bin/env bash
# Post-Install-Updates (fix_kind != none). Geordnete Pakete via recipe_updates::apply_all.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load update

recipe_hooks::log_setup "${RECIPE_ID:-app}_Update"
recipe_hooks::runtime_init || exit 1

# Alias: GUI setzt RECIPE_UPDATE_ROOT und/oder RECIPE_FIX_ROOT
if [ -z "${RECIPE_UPDATE_ROOT:-}" ] && [ -n "${RECIPE_FIX_ROOT:-}" ]; then
    export RECIPE_UPDATE_ROOT="$RECIPE_FIX_ROOT"
fi

output::section "Updates"
output::progress 10 "Updates suchen"
recipe_updates::apply_all "${LOG_FILE:-/dev/null}" wine || {
    recipe_hooks::emit_log_paths
    exit 11
}
recipe_updates::status
output::progress 100 "Fertig"
recipe_hooks::emit_log_paths
output::success "Updates angewandt"
exit 0
