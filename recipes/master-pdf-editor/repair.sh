#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

output::progress_begin 5 "Reparatur"
output::step "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    output::success "Validate OK — nichts zu reparieren"
    exit 0
fi

output::section "Reparatur"
recipe_hooks::runtime_init || exit 1
export WINEPREFIX="${DATA_ROOT}/prefix"
export WINE_PREFIX="$WINEPREFIX"
recipe_hooks::log_setup "${RECIPE_ID:-master-pdf-editor}_repair"

output::step "Visual C++ / Schriften"
recipe_hooks::_source recipe-vcrun.sh
recipe_vcrun::ensure "${LOG_DIR}/repair_vcrun_${TIMESTAMP_ISO}.log" || exit 11
recipe_winetricks::run "${LOG_DIR}/repair_corefonts_${TIMESTAMP_ISO}.log" corefonts || true
recipe_winetricks::run "${LOG_DIR}/repair_fontsmooth_${TIMESTAMP_ISO}.log" fontsmooth=rgb || true
recipe_win10::ensure || true

recipe_hooks::_source recipe-master-pdf-editor.sh 2>/dev/null || true
if type recipe_master_pdf_editor::finalize >/dev/null 2>&1; then
    output::step "Arbeitsordner / BYOS-Fix"
    recipe_master_pdf_editor::finalize || true
fi

output::step "Erneut prüfen"
if ! bash "$RECIPE_DIR/validate.sh"; then
    output::error "Reparatur unvollständig — ggf. erneut Installieren (Pack mit MSI)"
    exit 1
fi

output::progress_done "Reparatur abgeschlossen"
output::success "Reparatur abgeschlossen"
exit 0
