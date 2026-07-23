#!/usr/bin/env bash
# Reparatur: validate → Sync (Fonts/Grafik) auch bei grün; sonst fehlende Komponenten.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair
recipe_hooks::_source sharedFuncs.sh
recipe_hooks::_source recipe-fonts.sh
recipe_hooks::_source recipe-adobe-setup.sh

recipe_hooks::log_setup "Premiere_Repair"

export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"

output::section "Premiere Reparatur"
output::progress_begin 6 "Reparatur"

_validate_ok=0
output::progress_tick "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    _validate_ok=1
    output::info "Prüfungen OK — synchronisiere Fonts & Grafik"
else
    output::info "Abweichungen gefunden — behebe fehlende Komponenten"
fi

wine_runtime::init || { output::error "Proton-GE init fehlgeschlagen"; exit 1; }
wine_runtime::export_env

output::progress_tick "Schriften & ClearType"
output::step "Schriften & ClearType (corefonts, fontsmooth)"
wt_fonts="$LOG_DIR/winetricks_fonts_${TIMESTAMP_ISO}.log"
if recipe_fonts::ensure "$wt_fonts" >> "$LOG_FILE" 2>&1; then
    recipe_fonts::registry >> "$LOG_FILE" 2>&1 || true
    output::success "Schriften & ClearType"
else
    output::error "Schriften fehlgeschlagen — $wt_fonts"
    exit 1
fi

output::progress_tick "Grafik-DLLs"
output::step "Proton-GE Grafik-DLLs (DXVK) + Registry"
if wine_runtime::deploy_proton_graphics_dlls; then
    adobe_setup::apply_graphics_registry >> "$LOG_FILE" 2>&1 || {
        output::error "apply_graphics_registry fehlgeschlagen — $LOG_FILE"
        exit 1
    }
    output::success "Grafik-DLLs & Registry"
else
    output::error "deploy_proton_graphics_dlls fehlgeschlagen"
    exit 1
fi

recipe_hooks::_source recipe-nvidia-libs.sh
if recipe_nvidia_libs::wanted; then
    output::step "nvidia-libs (CUDA/NVAPI)"
    if recipe_nvidia_libs::ensure >> "$LOG_FILE" 2>&1; then
        output::success "nvidia-libs"
    else
        output::warning "nvidia-libs optional fehlgeschlagen — ohne CUDA weiter"
    fi
fi

adobe_setup::disable_virtual_desktop >> "$LOG_FILE" 2>&1 || true

recipe_hooks::_source recipe-premiere-install.sh
recipe_premiere::disable_crash_reporters >> "$LOG_FILE" 2>&1 || true
recipe_premiere::fix_icu_dlls >> "$LOG_FILE" 2>&1 || true
recipe_premiere::apply_ui_workarounds >> "$LOG_FILE" 2>&1 || true

output::progress_tick "Desktop"
output::step "Desktop-Eintrag & Icon (falls bereits angelegt)"
export SCR_PATH="$DATA_ROOT"
export WINE_PREFIX="$WINEPREFIX"
recipe_hooks::_source recipe-desktop.sh
recipe_desktop::refresh_if_present >> "$LOG_FILE" 2>&1 || true

if [ "$_validate_ok" -eq 1 ]; then
    output::progress_tick "Erneut prüfen"
    if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
        output::progress_done "Sync abgeschlossen — alle Prüfungen OK"
        output::success "Sync abgeschlossen — alle Prüfungen OK"
        exit 0
    fi
    output::progress_done "Sync unvollständig"
    output::warning "Sync unvollständig — erneut Prüfen"
    exit 11
fi

output::progress_tick "Fehlende Komponenten"
if ! recipe_validate::windows_version "$WINEPREFIX" "win10"; then
    output::step "Windows 10 (Registry)"
    if recipe_win10::ensure; then
        output::success "win10 gesetzt"
    else
        output::error "win10 Registry fehlgeschlagen"
        exit 1
    fi
fi

if ! recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/syswow64/msvcp140.dll" \
    && ! recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
    output::step "Visual C++ Runtime (Microsoft)"
    if recipe_vcrun::ensure "$LOG_DIR/vcrun_${TIMESTAMP_ISO}.log"; then
        output::success "Visual C++ Runtime installiert"
    else
        output::error "Visual C++ Runtime fehlgeschlagen"
        exit 1
    fi
fi

msxml3="$WINEPREFIX/drive_c/windows/syswow64/msxml3.dll"
msxml6="$WINEPREFIX/drive_c/windows/syswow64/msxml6.dll"
if ! recipe_validate::msxml_is_native "$msxml3" || ! recipe_validate::msxml_is_native "$msxml6"; then
    output::step "MSXML3/MSXML6 (Adobe-Installer)"
    if adobe_setup::ensure_native_msxml; then
        output::success "MSXML installiert"
    else
        output::error "MSXML fehlgeschlagen"
        exit 1
    fi
fi

if ! recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/syswow64/gdiplus.dll"; then
    if adobe_setup::ensure_gdiplus; then
        output::success "Native gdiplus installiert"
    else
        output::error "gdiplus fehlgeschlagen — siehe $LOG_DIR"
        exit 1
    fi
fi

output::progress_tick "Erneut prüfen"
if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    output::progress_done "Reparatur abgeschlossen — alle Prüfungen OK"
    output::success "Reparatur abgeschlossen — alle Prüfungen OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig"
output::warning "Reparatur unvollständig — erneut Prüfen"
exit 11
