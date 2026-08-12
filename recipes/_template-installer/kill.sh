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

_glob="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo "*.exe")"
_pattern="${_glob##*/}"
_pattern="${_pattern%.exe}.exe"

wine_runtime::init 2>/dev/null || true
output::section "${RECIPE_NAME} beenden"
output::progress_begin 1 "Beenden"
recipe_kill::run "$WINEPREFIX" "$_pattern" "$RECIPE_NAME"
output::progress_done "${RECIPE_NAME} beendet"
