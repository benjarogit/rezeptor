#!/usr/bin/env bash
# Reparatur: validate → MSXML, Grafik-DLLs, Fonts, Desktop-Eintrag.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
export PROJECT_ROOT RECIPE_DIR CORE_DIR

# shellcheck source=/dev/null
source "$CORE_DIR/paths.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe.sh"
recipe_export_env "$RECIPE_DIR/recipe.yml"
# shellcheck source=/dev/null
source "$CORE_DIR/output.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/wine-runtime.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-validate.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-winetricks.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/sharedFuncs.sh"

wine() { wine_runtime::wine "$@"; }
winetricks() { wine_runtime::winetricks "$@"; }

LOG_DIR="$(wine_software_logs_dir)"
mkdir -p "$LOG_DIR"
TIMESTAMP_ISO=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$LOG_DIR/Photoshop_Repair_${TIMESTAMP_ISO}.log"
export LOG_FILE

export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"

output::section "Photoshop Reparatur"

if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    output::success "Alle Prüfungen OK — nichts zu reparieren"
    exit 0
fi

wine_runtime::init || { output::error "Proton-GE init fehlgeschlagen"; exit 1; }
wine_runtime::export_env

msxml3="$WINEPREFIX/drive_c/windows/syswow64/msxml3.dll"
msxml6="$WINEPREFIX/drive_c/windows/syswow64/msxml6.dll"
if [ ! -f "$msxml3" ] || [ ! -f "$msxml6" ] \
    || ! file "$msxml3" 2>/dev/null | grep -q 'MS Windows' \
    || file "$msxml3" 2>/dev/null | grep -q 'WINE (DLL)'; then
    output::step "MSXML3/MSXML6 (Adobe-Installer)"
    wt_log="$LOG_DIR/winetricks_msxml_${TIMESTAMP_ISO}.log"
    if recipe_winetricks::run "$wt_log" -f msxml3 msxml6; then
        output::success "MSXML installiert"
    else
        output::error "MSXML fehlgeschlagen — $wt_log"
        exit 1
    fi
fi

if ! recipe_validate::graphics_dlls_present "$WINEPREFIX"; then
    output::step "Proton-GE Grafik-DLLs deployen"
    if wine_runtime::deploy_proton_graphics_dlls; then
        output::success "Grafik-DLLs deployt"
    else
        output::error "deploy_proton_graphics_dlls fehlgeschlagen"
        exit 1
    fi
fi

output::step "Fonts (corefonts, fontsmooth)"
wt_fonts="$LOG_DIR/winetricks_fonts_${TIMESTAMP_ISO}.log"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-fonts.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-guard.sh"
recipe_fonts::ensure "$wt_fonts" >> "$LOG_FILE" 2>&1 || true

output::step "Desktop-Eintrag & Icon"
if type launcher >/dev/null 2>&1; then
    export SCR_PATH="$DATA_ROOT"
    export WINE_PREFIX="$WINEPREFIX"
    launcher >> "$LOG_FILE" 2>&1 || true
fi

if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    output::success "Reparatur abgeschlossen"
    exit 0
fi
output::warning "Reparatur unvollständig — erneut Prüfen"
exit 11
