#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

output::progress_begin 2 "Reparatur"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    exit 0
fi

output::step "Launcher erneut prüfen"
script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
if [ -n "$script" ] && [ -f "$script" ]; then
    chmod +x "$script" || true
fi
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig — Installieren erneut ausführen"
exit 1
