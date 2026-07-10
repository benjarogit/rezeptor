#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch

recipe_hooks::runtime_init || exit 1

WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -z "$WORK_ROOT" ] || [ ! -d "$WORK_ROOT" ]; then
    recipe_hooks::die "Nicht installiert — WORK_ROOT fehlt in recipe.env"
fi

EXE="$(recipe_hooks::find_exe "$WORK_ROOT")"
[ -n "$EXE" ] || recipe_hooks::die "Keine EXE unter $WORK_ROOT (exe_glob in recipe.yml prüfen)"

cd "$(dirname "$EXE")" || exit 1
exec wine "./$(basename "$EXE")" "$@"
