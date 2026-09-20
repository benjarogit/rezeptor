#!/usr/bin/env bash
# Standard-Install: deklarative install_steps aus recipe.yml
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
recipe_hooks::load install
# shellcheck source=/dev/null
source "$RECIPE_DIR/helpers.sh"
recipe_install_steps::run "$@"
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

recipe_hooks::runtime_init || exit 1
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
GAME_DIR="$(prototype::game_dir "${WORK_ROOT:-}" 2>/dev/null || true)"
if [ -n "$GAME_DIR" ]; then
    recipe_hooks::state_set WORK_ROOT "$GAME_DIR" || true
    recipe_hooks::state_set GAME_DIR "$GAME_DIR" || true
    prototype::deploy_d3d9 || true
    prototype::write_dxvk_conf || true
    prototype::apply_registry "$GAME_DIR" || true
    prototype::apply_mod_bundle "$GAME_DIR" || true
    EXE="$(prototype::find_exe "$GAME_DIR" 2>/dev/null || true)"
    [ -n "$EXE" ] && prototype::ensure_laa "$EXE" || true
fi
exit 0
