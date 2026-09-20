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
recipe_hooks::load repair
# shellcheck source=/dev/null
source "$RECIPE_DIR/helpers.sh"

output::progress_begin 3 "Reparatur"
output::step "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh" >>"${LOG_FILE:-/dev/null}" 2>&1; then
    output::progress_done "Validate OK — nichts zu reparieren"
    output::success "Validate OK — nichts zu reparieren"
    exit 0
fi

output::section "Reparatur"
recipe_hooks::runtime_init || exit 1
output::step "Winetricks aus recipe.yml"
recipe_hooks::install_winetricks_from_recipe || exit 11
wine_runtime::deploy_proton_graphics_dlls || true
prototype::deploy_d3d9 || true
prototype::write_dxvk_conf || true
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
GAME_DIR="$(prototype::game_dir "${WORK_ROOT:-}" 2>/dev/null || true)"
if [ -n "$GAME_DIR" ]; then
    prototype::apply_registry "$GAME_DIR" || true
    prototype::apply_mod_bundle "$GAME_DIR" || true
    EXE="$(prototype::find_exe "$GAME_DIR" 2>/dev/null || true)"
    [ -n "$EXE" ] && prototype::ensure_laa "$EXE" || true
fi

output::progress_done "Reparatur abgeschlossen"
output::success "Reparatur abgeschlossen"
exit 0
