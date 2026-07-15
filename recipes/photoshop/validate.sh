#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate
recipe_hooks::_source sharedFuncs.sh
# Prefs-Helfer (Legacy-Neu-Dialog / MachinePrefs) liegen im Install-Modul
recipe_hooks::_source recipe-photoshop-install.sh

_guaranteed="$(recipe_get "$RECIPE_YML" version_guaranteed 2>/dev/null || true)"
export WINEPREFIX="${DATA_ROOT}/prefix"
failures=0

output::progress_begin 4 "Prüfen"

output::progress_tick "Prefix & Runtime"
if recipe_validate::prefix_initialized "$WINEPREFIX"; then
    recipe_validate::ok "Wine-Prefix initialisiert ($WINEPREFIX)"
else
    recipe_validate::fail "Wine-Prefix fehlt oder leer ($WINEPREFIX)"
    failures=$((failures + 1))
fi

if recipe_validate::graphics_dlls_present "$WINEPREFIX"; then
    recipe_validate::ok "Grafik-DLLs (vkd3d/DXVK im Prefix)"
else
    recipe_validate::fail "Grafik-DLLs fehlen — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::windows_version "$WINEPREFIX" "win10"; then
    recipe_validate::ok "Windows-Version win10"
else
    recipe_validate::fail "win10 nicht gesetzt — Reparieren"
    failures=$((failures + 1))
fi

wow64="$WINEPREFIX/drive_c/windows/syswow64"
if recipe_validate::vcrun_dll_ok "$wow64/msvcp140.dll" \
    || recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
    recipe_validate::ok "Visual C++ Runtime (msvcp140.dll)"
else
    recipe_validate::fail "Visual C++ Runtime fehlt — Reparieren"
    failures=$((failures + 1))
fi

output::progress_tick "Komponenten (MSXML, Schriften, gdiplus)"
msxml3="$wow64/msxml3.dll"
msxml6="$wow64/msxml6.dll"
if recipe_validate::msxml_is_native "$msxml3"; then
    recipe_validate::ok "Native MSXML3"
else
    recipe_validate::fail "MSXML3 fehlt oder nicht nativ — Reparieren"
    failures=$((failures + 1))
fi
if recipe_validate::msxml_is_native "$msxml6"; then
    recipe_validate::ok "Native MSXML6"
else
    recipe_validate::fail "MSXML6 fehlt oder nicht nativ — Reparieren"
    failures=$((failures + 1))
fi

_font_n="$(find "$WINEPREFIX/drive_c/windows/Fonts" -maxdepth 1 -type f 2>/dev/null | wc -l)"
if [ "$_font_n" -ge 5 ]; then
    recipe_validate::ok "Windows-Schriften ($_font_n)"
else
    recipe_validate::fail "Schriften fehlen (corefonts) — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::font_smoothing_ok "$WINEPREFIX"; then
    recipe_validate::ok "ClearType / FontSmoothing (fontsmooth=rgb)"
else
    recipe_validate::fail "FontSmoothing fehlt (pixelige Schrift) — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::native_pe "$wow64/gdiplus.dll"; then
    recipe_validate::ok "Native gdiplus (Neu-Dokument/Export)"
else
    recipe_validate::fail "Native gdiplus fehlt — Reparieren (Neu erstellen)"
    failures=$((failures + 1))
fi

output::progress_tick "Photoshop.exe & Prefs"
if exe="$(photoshop::find_exe "$WINEPREFIX" 2>/dev/null || true)" && [ -n "$exe" ]; then
    recipe_validate::ok "Photoshop.exe: $exe"
    _ps_ver="$(recipe_validate::photoshop_app_version "$exe" || true)"
    recipe_validate::version_guaranteed_check "$_guaranteed" "$_ps_ver" "Photoshop-Version"

    # Proton-GE: Photoshop läuft als Windows-User "steamuser".
    users_dir="$WINEPREFIX/drive_c/users"
    [ -d "$users_dir/steamuser" ] && users_dir="$users_dir/steamuser"
    settings_dir="$(find "$users_dir" -maxdepth 6 -type d -name 'Adobe Photoshop 2021 Settings' 2>/dev/null | head -1)"
    psuc=""
    [ -n "$settings_dir" ] && psuc="$settings_dir/PSUserConfig.txt"
    # GPU aus = Neu/Text stabil (isatsam Known Issue + live). ToolTips aus = Plugins/Text-Tool.
    if [ -n "$psuc" ] && [ -f "$psuc" ] && grep -q 'GPUForce 0' "$psuc" 2>/dev/null; then
        recipe_validate::ok "GPU-Konfiguration (PSUserConfig.txt: GPUForce 0)"
    elif [ -n "$psuc" ] && [ -f "$psuc" ] && grep -qE '^GPUForce[[:space:]]+1' "$psuc" 2>/dev/null; then
        _gp="$(cat "${DATA_ROOT}/gpu-profile.active" 2>/dev/null | tr -d '[:space:]' || true)"
        recipe_validate::warn "GPU-Experiment aktiv (${_gp:-unbekannt}) — bei Fail: scripts/photoshop-gpu-profile.sh stable"
    else
        recipe_validate::fail "GPU-Konfiguration fehlt (PSUserConfig.txt) — Reparieren"
        failures=$((failures + 1))
    fi
    if [ -f "${DATA_ROOT}/gpu-profile.active" ]; then
        _gp="$(tr -d '[:space:]' <"${DATA_ROOT}/gpu-profile.active" 2>/dev/null || true)"
        case "$_gp" in
            stable|dxvk_ui_only|"")
                recipe_validate::ok "GPU-Profil: ${_gp:-stable}"
                ;;
            *)
                recipe_validate::warn "GPU-Profil Experiment: $_gp (Default wäre stable)"
                ;;
        esac
    fi
    if [ -n "$psuc" ] && [ -f "$psuc" ] && grep -qE '^WarnRunningScripts[[:space:]]+0' "$psuc" 2>/dev/null; then
        recipe_validate::ok "Skript-Warnung aus (WarnRunningScripts 0)"
    elif [ -n "$psuc" ] && [ -f "$psuc" ]; then
        recipe_validate::warn "WarnRunningScripts fehlt — Reparieren (Skript-Dialog beim Start)"
    fi

    ui_prefs=""
    machine_prefs=""
    [ -n "$settings_dir" ] && ui_prefs="$settings_dir/UIPrefs.psp"
    [ -n "$settings_dir" ] && machine_prefs="$settings_dir/MachinePrefs.psp"
    # PS überschreibt Prefs beim ersten Start — einmal sanft nachziehen (sonst Dauer-„Teilweise“).
    if [ -f "$ui_prefs" ] || [ -f "$machine_prefs" ]; then
        recipe_photoshop::ensure_post_install_config >/dev/null 2>&1 || true
    fi
    if [ -f "$ui_prefs" ] && recipe_photoshop::_prefs_get_bool "$ui_prefs" useClassicFileNewDialog 2>/dev/null; then
        recipe_validate::ok "Legacy-Neu-Dialog (useClassicFileNewDialog)"
    elif [ ! -f "$ui_prefs" ]; then
        recipe_validate::warn "UIPrefs.psp fehlt noch — einmal starten, dann Reparieren"
    else
        recipe_validate::fail "Legacy-Neu-Dialog aus — Reparieren (schwarze Felder / Programmfehler)"
        failures=$((failures + 1))
    fi
    # Tooltips: Template hat useRichToolTips; manchen Builds zusätzlich ToolTips.
    # Fehlender Key ≠ „aus“ vortäuschen — useRichToolTips ist die Pflichtprüfung.
    _tips_bad=0
    if [ -f "$ui_prefs" ]; then
        if recipe_photoshop::_prefs_find_bool_val "$ui_prefs" useRichToolTips >/dev/null 2>&1; then
            if recipe_photoshop::_prefs_get_bool "$ui_prefs" useRichToolTips 2>/dev/null; then
                _tips_bad=1
            fi
        else
            recipe_validate::warn "useRichToolTips fehlt in UIPrefs — Reparieren"
        fi
        if recipe_photoshop::_prefs_find_bool_val "$ui_prefs" ToolTips >/dev/null 2>&1; then
            if recipe_photoshop::_prefs_get_bool "$ui_prefs" ToolTips 2>/dev/null; then
                _tips_bad=1
            fi
        fi
    fi
    if [ -f "$ui_prefs" ] && [ "$_tips_bad" -eq 0 ]; then
        recipe_validate::ok "ToolTips aus (sonst Text-Tool/Plugins kaputt)"
    elif [ -f "$ui_prefs" ]; then
        recipe_validate::fail "ToolTips noch an — Reparieren"
        failures=$((failures + 1))
    fi
    # Text-Glatt-Script deployt (Anti-Alias „Ohne“ → Glatt).
    _ps_scripts="$(dirname "$(photoshop::find_exe "$WINEPREFIX" 2>/dev/null || true)")/Presets/Scripts"
    if [ -f "$_ps_scripts/Rezeptor-Text-Glatt.jsx" ]; then
        recipe_validate::ok "Skript Rezeptor-Text-Glatt.jsx"
    else
        recipe_validate::fail "Rezeptor-Text-Glatt.jsx fehlt — Reparieren (Text-Anti-Alias)"
        failures=$((failures + 1))
    fi
    if recipe_photoshop::startup_event_registered; then
        recipe_validate::ok "Text-Glatt Autostart (Event Start Application)"
    else
        recipe_validate::warn "Text-Glatt Autostart noch nicht registriert — einmal Starten (CLI-Fallback)"
    fi
    # Mehrthread-Composing: kein stabiler Prefs-Key in Prefs.psp/MachinePrefs (Recherche).
    recipe_validate::warn "Mehrthread-Composing: in PS manuell unter Leistung aktivieren (kein Auto-Key)"
    _gp_active="$(tr -d '[:space:]' <"${DATA_ROOT}/gpu-profile.active" 2>/dev/null || true)"
    if [ -f "$machine_prefs" ] && ! recipe_photoshop::_prefs_get_bool "$machine_prefs" openglEnabled 2>/dev/null; then
        recipe_validate::ok "OpenGL in MachinePrefs aus (sonst Programmfehler bei Neu)"
    elif [ ! -f "$machine_prefs" ]; then
        recipe_validate::warn "MachinePrefs.psp fehlt noch — einmal starten, dann Reparieren"
    elif [ "$_gp_active" = "ps_gpu_no_opencl" ] || [ "$_gp_active" = "ps_gpu_full" ]; then
        # Experiment-Profil setzt OpenGL absichtlich an — kein Installations-FAIL.
        recipe_validate::warn "OpenGL an (GPU-Experiment $_gp_active) — bei Fail: photoshop-gpu-profile.sh stable"
    else
        recipe_validate::fail "OpenGL noch an (MachinePrefs) — Reparieren"
        failures=$((failures + 1))
    fi
    if grep -qE '"Desktop"="[0-9]+x[0-9]+"' "$WINEPREFIX/user.reg" 2>/dev/null; then
        recipe_validate::warn "Virtual Desktop noch an — Reparieren (blaue Fläche)"
    else
        recipe_validate::ok "Kein Virtual Desktop"
    fi
else
    recipe_validate::fail "Photoshop.exe nicht gefunden — installieren"
    failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
