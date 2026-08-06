#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate

_guaranteed="$(recipe_get "$RECIPE_YML" version_guaranteed 2>/dev/null || true)"
export WINEPREFIX="${DATA_ROOT}/prefix"
failures=0

output::progress_begin 3 "Prüfen"

output::progress_tick "Prefix & Arbeitsordner"
if ! recipe_hooks::validate_prefix; then
    failures=$((failures + 1))
fi
if ! recipe_hooks::validate_work_root WORK_ROOT; then
    failures=$((failures + 1))
fi

output::progress_tick "EXE"
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -n "$WORK_ROOT" ] && EXE="$(recipe_hooks::find_exe "$WORK_ROOT" 2>/dev/null || true)" && [ -n "$EXE" ]; then
    recipe_validate::ok "EXE: $(basename "$EXE")"
else
    recipe_validate::fail "Keine EXE im Arbeitsordner"
    failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
