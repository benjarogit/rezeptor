#!/usr/bin/env bash
# Halo Campaign Evolved — Repair (validate → EXE-Pfade nachziehen, kein Reinstall)
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

output::progress_begin 4 "Reparatur"
output::step "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    output::success "Validate OK — nichts zu reparieren"
    exit 0
fi

output::section "Reparatur"
recipe_hooks::runtime_init || exit 1
output::step "Winetricks / Grafik"
recipe_hooks::install_winetricks_from_recipe || true
wine_runtime::deploy_proton_graphics_dlls || true

output::step "Spiel-EXE neu verknüpfen"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh"
recipe_halo_campaign_evolved::finalize || true

if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur abgeschlossen"
    output::success "Reparatur abgeschlossen"
    exit 0
fi
output::progress_done "Reparatur unvollständig"
exit 11
