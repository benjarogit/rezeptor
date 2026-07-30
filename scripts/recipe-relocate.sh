#!/usr/bin/env bash
# CLI: Installationsziel eines Rezepts umziehen.
# Usage: recipe-relocate.sh <recipe_dir>
# Env: RECIPE_RELOCATE_TO (Pflicht), optional RECIPE_RELOCATE_PORTABLE_TO
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="${1:-${RECIPE_DIR:-}}"
if [ -z "$RECIPE_DIR" ]; then
    echo "ERROR: recipe_dir fehlt (Argument oder RECIPE_DIR)" >&2
    exit 2
fi
RECIPE_DIR="$(cd "$RECIPE_DIR" && pwd)"

if [ -z "${RECIPE_RELOCATE_TO:-}" ]; then
    echo "ERROR: RECIPE_RELOCATE_TO setzen" >&2
    exit 2
fi

if [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/core/recipe-hooks.sh" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/core/recipe-hooks.sh"
else
    # shellcheck source=/dev/null
    source "$RECIPE_DIR/../../core/recipe-hooks.sh"
fi
recipe_hooks::load minimal
recipe_hooks::_source output.sh
recipe_hooks::_source env-file.sh
recipe_hooks::_source recipe-desktop.sh
recipe_hooks::_source recipe-relocate.sh

recipe_relocate::move
