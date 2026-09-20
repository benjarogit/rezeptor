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
recipe_hooks::load launch
# shellcheck source=/dev/null
source "$RECIPE_DIR/helpers.sh"

recipe_hooks::runtime_init || exit 1

WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
GAME_DIR="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
if [ -z "$GAME_DIR" ] || [ ! -d "$GAME_DIR" ]; then
    GAME_DIR="$(prototype::game_dir "${WORK_ROOT:-}" 2>/dev/null || true)"
fi
EXE="$(prototype::find_exe "${GAME_DIR:-${WORK_ROOT:-}}" 2>/dev/null || true)"
[ -n "$EXE" ] && [ -f "$EXE" ] || recipe_hooks::die "Nicht installiert — prototypef.exe fehlt (Quelle auf Prototype-Ordner zeigen)"

# DXVK d3d11/dxgi via shared deploy; prefix d3d9 stays DXVK.
wine_runtime::deploy_proton_graphics_dlls || true
prototype::deploy_d3d9 || true
prototype::write_dxvk_conf || true
prototype::apply_mod_bundle "$(dirname "$EXE")" || true
prototype::ensure_laa "$EXE" || true
prototype::apply_registry "$(dirname "$EXE")" || true
prototype::apply_system_opt || true

export RECIPE_WINE_SHOW_GUI=1
export SteamAppId="${SteamAppId:-10150}"
export SteamGameId="${SteamGameId:-10150}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9,dxgi,d3d11,d3d10core=n}"

if type output::info >/dev/null 2>&1; then
    output::info "Prototype lang=$(prototype::language_id) FE=$(prototype::lang_fe) skin=$(prototype::skin_id) GPU=$(prototype::gpu_vendor) DXVK_FRAME_RATE=${DXVK_FRAME_RATE:-off}"
fi

cd "$(dirname "$EXE")" || exit 1
exec wine "./$(basename "$EXE")" "$@"
