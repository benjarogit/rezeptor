#!/usr/bin/env bash
# Nur Rezeptor-State + Wrapper — Steam-Spiel und Online-Fix bleiben unangetastet.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal

output::section "House of Ashes — Deinstallation (Rezeptor)"
output::progress_begin 3 "Deinstallation"
output::info "Entfernt nur den Rezeptor-Eintrag. Steam-Spiel, Fix und Spacewar bleiben."

output::progress_tick "Prozesse"
pkill -f "HouseOfAshes.exe" 2>/dev/null || true
pkill -f "house-of-ashes-run.sh" 2>/dev/null || true

output::progress_tick "Wrapper"
script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
[ -n "$script" ] && [ -f "$script" ] && rm -f "$script" || true
rm -f "${DATA_ROOT:-}/house-of-ashes-run.sh" 2>/dev/null || true

output::progress_tick "Desktop & Rezeptor-Daten"
recipe_hooks::purge_recipe_data

output::progress_done "Deinstalliert"
output::success "Rezeptor-Eintrag weg — House of Ashes / Fix / Spacewar in Steam unverändert"
