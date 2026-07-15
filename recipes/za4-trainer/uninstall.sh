#!/usr/bin/env bash
# Nur Rezeptor-State + Wrapper — Steam-Spiel bleibt.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal

output::section "ZA4 Trainer — Deinstallation"
output::progress_begin 3 "Deinstallation"

output::progress_tick "Prozesse"
pkill -f "ZA4-Trainer.exe" 2>/dev/null || true
pkill -f "za4-trainer-run.sh" 2>/dev/null || true

output::progress_tick "Desktop & Trainer-Kopie"
# Trainer-EXE im WORK_ROOT vor dem Wipe löschen (liegt oft unter DATA_ROOT)
work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
[ -n "$script" ] && [ -f "$script" ] && rm -f "$script" || true
[ -n "$trainer" ] && [ -f "$trainer" ] && rm -f "$trainer" || true
[ -n "$work" ] && [ -f "$work/ZA4-Trainer.exe" ] && rm -f "$work/ZA4-Trainer.exe" || true

output::progress_tick "Rezeptor-Daten"
recipe_hooks::purge_recipe_data

output::progress_done "Deinstalliert"
output::success "ZA4 Trainer entfernt (Steam-Spiel unverändert)"
