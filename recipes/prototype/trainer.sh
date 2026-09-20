#!/usr/bin/env bash
# Start the staged Locke trainer in the same Proton prefix.
# Never injected at game launch (cheat overlay often kills Present).
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

EXE=""
if [ -n "${DATA_ROOT:-}" ] && [ -f "${DATA_ROOT}/trainer/prototype.v1001.p7trn.exe" ]; then
    EXE="${DATA_ROOT}/trainer/prototype.v1001.p7trn.exe"
fi
if [ -z "$EXE" ]; then
    WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
    GAME_DIR="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
    if [ -z "$GAME_DIR" ] || [ ! -d "$GAME_DIR" ]; then
        GAME_DIR="$(prototype::game_dir "${WORK_ROOT:-}" 2>/dev/null || true)"
    fi
    if [ -n "$GAME_DIR" ] && [ -f "$GAME_DIR/rezeptor-trainer/prototype.v1001.p7trn.exe" ]; then
        EXE="$GAME_DIR/rezeptor-trainer/prototype.v1001.p7trn.exe"
    fi
fi
[ -n "$EXE" ] && [ -f "$EXE" ] || recipe_hooks::die "Trainer-EXE fehlt — Reparieren legt sie nach rezeptor-trainer/prototype.v1001.p7trn.exe"

export RECIPE_WINE_SHOW_GUI=1
export SteamAppId="${SteamAppId:-10150}"
export SteamGameId="${SteamGameId:-10150}"

if type output::info >/dev/null 2>&1; then
    output::info "Trainer: $EXE (nicht mit Prototype mitgestartet)"
fi

cd "$(dirname "$EXE")" || exit 1
exec wine "./$(basename "$EXE")" "$@"
