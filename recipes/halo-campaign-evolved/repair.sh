#!/usr/bin/env bash
# Halo: Campaign Evolved — Repair
set -euo pipefail
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair
recipe_hooks::log_setup "Halo_Repair"

# Halo braucht Proton-GE 11 (DXCore) — global bleibt 10 für Photoshop.
export PROTON_GE_TAG="${PROTON_GE_TAG:-GE-Proton11-3}"
export PROTON_GE_URL="${PROTON_GE_URL:-https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_GE_TAG}/${PROTON_GE_TAG}.tar.gz}"
export PROTON_GE_SHA256="${PROTON_GE_SHA256:-861c2edc8d40d051fb1e7a692deb953be52bd339c46d90f2b7dde50ddad91266}"

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
