#!/usr/bin/env bash
# Einmal GenP / Cure aus dem m0nkrus-Pack unter Proton starten (GUI, manuell Cure).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair
recipe_hooks::_source recipe-photoshop-pack.sh

recipe_hooks::log_setup "Photoshop_GenP"
export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"

output::section "GenP / Cure (Pack)"
wine_runtime::init || { output::error "Proton-GE init fehlgeschlagen"; exit 1; }
wine_runtime::export_env
recipe_photoshop_pack::run_genp || exit 11
recipe_hooks::emit_log_paths
exit 0
