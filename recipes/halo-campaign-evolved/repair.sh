#!/usr/bin/env bash
# Halo: Campaign Evolved — Repair
set -euo pipefail
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
recipe_hooks::log_setup "Halo_Repair"

# Proton pin: recipe.yml proton_ge_tag (GE-Proton11-3).

output::progress_begin 4 "Reparatur"
output::step "Installation prüfen"
validate_ok=0
bash "$RECIPE_DIR/validate.sh" && validate_ok=1 || true

output::section "Reparatur"
recipe_hooks::runtime_init || exit 1
if [ "$validate_ok" -eq 0 ]; then
    output::step "Winetricks / Grafik"
    recipe_hooks::install_winetricks_from_recipe || true
    wine_runtime::deploy_proton_graphics_dlls || true
fi

output::step "Spiel-EXE"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh"
recipe_halo_campaign_evolved::finalize || true

output::step "Steam-Stack / MSVC-Runtime / libHttpClient / DirectML"
EXE="$(recipe_hooks::state_get GAME_EXE 2>/dev/null || true)"
[ -n "$EXE" ] && [ -f "$EXE" ] || EXE="$(recipe_halo_campaign_evolved::find_game_exe || true)"
if [ -n "$EXE" ] && [ -f "$EXE" ]; then
    recipe_halo_campaign_evolved::prepare_runtime "$EXE" || true
fi

output::step "Erneut prüfen"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur OK"
    output::success "Reparatur OK"
    exit 0
fi
output::progress_done "Reparatur mit Restfehlern"
exit 1
