#!/usr/bin/env bash
# Reparatur: validate → Sync (Fonts/Grafik/Lightroom-Fixes) auch bei grün;
# sonst zusätzlich fehlende Prefix-Komponenten nachziehen.

set -eu
(set -o pipefail 2>/dev/null) || true

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
# Log so früh wie möglich, damit die GUI bei Exit≠0 immer eine Datei hat.
recipe_hooks::init_dirs
recipe_hooks::_source paths.sh
recipe_hooks::_source recipe.sh
recipe_export_env "$RECIPE_YML"
recipe_hooks::log_setup "Lightroom_Repair"
recipe_hooks::load repair
recipe_hooks::_source sharedFuncs.sh
recipe_hooks::_source recipe-fonts.sh
recipe_hooks::_source recipe-adobe-setup.sh
recipe_hooks::_source recipe-lightroom-install.sh

export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"

output::section "Lightroom Classic Reparatur"
output::progress_begin 6 "Reparatur"

_validate_ok=0
output::progress_tick "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh" >>"$LOG_FILE" 2>&1; then
    _validate_ok=1
    output::info "Prüfungen OK — synchronisiere Schriften, Grafik & Lightroom-Fixes"
else
    output::info "Abweichungen gefunden — behebe fehlende Komponenten"
fi

wine_runtime::init || {
    output::error "Proton-GE init fehlgeschlagen"
    exit 1
}
wine_runtime::export_env

output::progress_tick "Schriften & ClearType"
output::step "Schriften & ClearType (corefonts, fontsmooth)"
wt_fonts="$LOG_DIR/winetricks_fonts_${TIMESTAMP_ISO}.log"
if recipe_fonts::ensure "$wt_fonts" >>"$LOG_FILE" 2>&1; then
    recipe_fonts::registry >>"$LOG_FILE" 2>&1 || true
    output::success "Schriften & ClearType"
else
    output::error "Schriften fehlgeschlagen — $wt_fonts"
    exit 1
fi

output::progress_tick "Grafik-DLLs (DXVK + vkd3d D3D12)"
output::step "Proton-GE Grafik-DLLs + Registry"
adobe_setup::kill_all_wineservers
if wine_runtime::deploy_proton_graphics_dlls; then
    output::success "Grafik-DLLs"
elif recipe_validate::graphics_dlls_present "$WINEPREFIX"; then
    output::warning "Grafik-DLL-Deploy fehlgeschlagen — vorhandene DLLs bleiben (Prefix OK)"
else
    output::error "deploy_proton_graphics_dlls fehlgeschlagen"
    exit 1
fi

output::progress_tick "Lightroom-Fixes (Stubs, Registry)"
output::step "Lightroom-on-Linux-Fixes"
if recipe_lightroom::apply_stub_files >>"$LOG_FILE" 2>&1; then
    output::success "Stubs & Case-Aliase"
else
    output::error "Stub-Dateien fehlgeschlagen — $LOG_FILE"
    exit 1
fi
recipe_lightroom::apply_registry >>"$LOG_FILE" 2>&1 || {
    output::error "Registry-Fixes fehlgeschlagen — $LOG_FILE"
    exit 1
}
adobe_setup::disable_virtual_desktop >>"$LOG_FILE" 2>&1 || true

output::progress_tick "Desktop"
output::step "Desktop-Eintrag & Icon (falls bereits angelegt)"
export SCR_PATH="$DATA_ROOT"
recipe_hooks::_source recipe-desktop.sh
recipe_desktop::refresh_if_present >>"$LOG_FILE" 2>&1 || true

if [ "$_validate_ok" -eq 1 ]; then
    output::progress_tick "Erneut prüfen"
    if bash "$RECIPE_DIR/validate.sh" >>"$LOG_FILE" 2>&1; then
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
    output::step "Windows 11 (Adobe-OS-Prüfung)"
    if recipe_win10::ensure win11; then
        output::success "Windows-Version gesetzt"
    else
        output::error "Windows-Version fehlgeschlagen"
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

_lr_exe="$(lightroom::find_exe "$WINEPREFIX" 2>/dev/null || true)"
if [ -n "$_lr_exe" ] && [ -f "$_lr_exe" ]; then
    recipe_hooks::state_set WORK_ROOT "$(cd "$(dirname "$_lr_exe")" && pwd)"
fi
if type recipe_app_link::ensure >/dev/null 2>&1; then
    recipe_app_link::ensure || true
fi

output::progress_tick "Erneut prüfen"
if bash "$RECIPE_DIR/validate.sh" >>"$LOG_FILE" 2>&1; then
    output::progress_done "Reparatur abgeschlossen — alle Prüfungen OK"
    output::success "Reparatur abgeschlossen — alle Prüfungen OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig"
output::warning "Reparatur unvollständig — erneut Prüfen"
exit 11
