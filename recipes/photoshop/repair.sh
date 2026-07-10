#!/usr/bin/env bash
# Reparatur: validate → Sync (Fonts/Grafik/Post-Install) auch bei grün; sonst fehlende Komponenten.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair
recipe_hooks::_source sharedFuncs.sh
recipe_hooks::_source recipe-fonts.sh

recipe_hooks::log_setup "Photoshop_Repair"

export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"

output::section "Photoshop Reparatur"
output::progress_begin 6 "Reparatur"

_validate_ok=0
output::progress_tick "Installation prüfen"
if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    _validate_ok=1
    output::info "Prüfungen OK — synchronisiere Fonts, Grafik, Post-Install"
else
    output::info "Abweichungen gefunden — behebe fehlende Komponenten"
fi

wine_runtime::init || { output::error "Proton-GE init fehlgeschlagen"; exit 1; }
wine_runtime::export_env

# --- Sync-Pfad (immer, auch bei grünem Validate) ---
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
    recipe_photoshop::_apply_graphics_registry >> "$LOG_FILE" 2>&1 || {
        output::error "_apply_graphics_registry fehlgeschlagen — $LOG_FILE"
        exit 1
    }
    output::success "Grafik-DLLs & Registry"
else
    output::error "deploy_proton_graphics_dlls fehlgeschlagen"
    exit 1
fi

output::progress_tick "Post-Install & Desktop"
if _ps_exe="$(photoshop::find_exe "$WINEPREFIX" 2>/dev/null)" && [ -n "$_ps_exe" ]; then
    output::step "Photoshop-Konfiguration (GPU aus, Tooltips, Text-Glatt, ScriptingSupport)"
    if recipe_photoshop::ensure_post_install_config >> "$LOG_FILE" 2>&1; then
        output::success "Post-Install-Konfiguration angewendet"
    else
        output::error "Post-Install-Konfiguration fehlgeschlagen — $LOG_FILE"
        exit 1
    fi
fi

output::step "Desktop-Eintrag & Icon"
export SCR_PATH="$DATA_ROOT"
export WINE_PREFIX="$WINEPREFIX"
recipe_photoshop::install_desktop >> "$LOG_FILE" 2>&1 || true

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

# --- Fix-Pfad (nur wenn Validate vorher fehlgeschlagen) ---
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
    wt_log="$LOG_DIR/winetricks_msxml_${TIMESTAMP_ISO}.log"
    if recipe_winetricks::run "$wt_log" -f msxml3 msxml6; then
        output::success "MSXML installiert"
    else
        output::error "MSXML fehlgeschlagen — $wt_log"
        exit 1
    fi
fi

if ! recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/syswow64/gdiplus.dll"; then
    if recipe_photoshop::ensure_gdiplus; then
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
