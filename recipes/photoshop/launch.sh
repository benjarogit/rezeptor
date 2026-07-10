#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"

export PROJECT_ROOT RECIPE_DIR CORE_DIR
export DATA_ROOT="${DATA_ROOT:-${SCR_PATH:-}}"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"
export WINE_PREFIX="${WINE_PREFIX:-${DATA_ROOT}/prefix}"

# shellcheck source=/dev/null
source "$CORE_DIR/recipe-hooks.sh"
recipe_hooks::load launch

recipe_photoshop::launch "$@"
