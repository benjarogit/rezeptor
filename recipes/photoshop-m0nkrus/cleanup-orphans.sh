#!/usr/bin/env bash
# After Photoshop.exe exits via its own window close: flush wait + orphan cleanup (issue #10).
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

# Short beat: Photoshop has already exited, so prefs are written by now.
sleep "${PHOTOSHOP_EXIT_FLUSH_S:-2}"

if recipe_photoshop::photoshop_running; then
    exit 0
fi

output::section "$(msg::t ps.cleanup.section)"
output::progress_begin 2 "$(msg::t ps.cleanup.progress)"
recipe_photoshop::cleanup_orphans
output::progress_done "$(msg::t ps.cleanup.done)"
