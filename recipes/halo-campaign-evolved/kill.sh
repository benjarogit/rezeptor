#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill

_glob="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo "*.exe")"
_pattern="${_glob##*/}"
_pattern="${_pattern%.exe}.exe"

wine_runtime::init 2>/dev/null || true
output::section "${RECIPE_NAME} beenden"
output::progress_begin 1 "Beenden"
recipe_kill::run "$WINEPREFIX" "$_pattern" "$RECIPE_NAME"
output::progress_done "${RECIPE_NAME} beendet"
