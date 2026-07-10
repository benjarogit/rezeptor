#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
# FIX_ROOT from CLI / env for optional_fix_root
export WISO_FIX_ROOT="${WISO_FIX_ROOT:-${RECIPE_FIX_ROOT:-${2:-}}}"
recipe_install_steps::run "$@"
