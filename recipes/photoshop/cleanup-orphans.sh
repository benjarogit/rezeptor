#!/usr/bin/env bash
# After Photoshop.exe exits via its own window close: flush wait + orphan cleanup (issue #10).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill
recipe_hooks::_source recipe-guard.sh
recipe_hooks::_source recipe-photoshop-cleanup.sh

wine_runtime::init 2>/dev/null || true
wine_runtime::export_env 2>/dev/null || true

# Let QuitEndFlag / prefs finish writing before wineserver -k.
sleep "${PHOTOSHOP_EXIT_FLUSH_S:-2}"

if recipe_photoshop::photoshop_running; then
    # Raced a relaunch; do not tear down a new session.
    exit 0
fi

output::section "$(msg::t ps.cleanup.section)"
output::progress_begin 2 "$(msg::t ps.cleanup.progress)"
recipe_photoshop::cleanup_orphans
output::progress_done "$(msg::t ps.cleanup.done)"
