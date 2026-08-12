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
recipe_hooks::_source recipe-guard.sh
recipe_hooks::_source recipe-photoshop-cleanup.sh

wine_runtime::init 2>/dev/null || true
wine_runtime::export_env 2>/dev/null || true
output::section "$(msg::t ps.kill.section)"
output::progress_begin 3 "$(msg::t ps.kill.progress)"
output::progress_tick "$(msg::t ps.kill.tick)"
recipe_photoshop::graceful_shutdown
output::progress_done "$(msg::t ps.kill.done)"
