#!/usr/bin/env bash
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
recipe_hooks::load validate
recipe_hooks::_source sharedFuncs.sh
recipe_hooks::_source recipe-adobe-setup.sh
recipe_hooks::_source recipe-lightroom-stubs.sh

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

sys32="$WINEPREFIX/drive_c/windows/system32"
if [ -f "$sys32/d3d12.dll" ] && [ -f "$sys32/d3d12core.dll" ]; then
    recipe_validate::ok "D3D12 (vkd3d-proton) — GPU in Voreinstellungen → Leistung"
else
    recipe_validate::fail "D3D12 fehlt — Reparieren (ohne GPU nur CPU-Entwickeln)"
    failures=$((failures + 1))
fi

if recipe_validate::windows_version "$WINEPREFIX" "win10"; then
    recipe_validate::ok "Windows-Version 10.0 (win11-Build für Adobe-Installer)"
else
    recipe_validate::fail "Windows-Version nicht gesetzt — Reparieren"
    failures=$((failures + 1))
fi

wow64="$WINEPREFIX/drive_c/windows/syswow64"
if recipe_validate::vcrun_dll_ok "$wow64/msvcp140.dll" \
    || recipe_validate::vcrun_dll_ok "$sys32/msvcp140.dll"; then
    recipe_validate::ok "Visual C++ Runtime (msvcp140.dll)"
else
    recipe_validate::fail "Visual C++ Runtime fehlt — Reparieren"
    failures=$((failures + 1))
fi

output::progress_tick "Komponenten (MSXML, Schriften, gdiplus)"
if recipe_validate::msxml_is_native "$wow64/msxml3.dll"; then
    recipe_validate::ok "Native MSXML3"
else
    recipe_validate::fail "MSXML3 fehlt oder nicht nativ — Reparieren"
    failures=$((failures + 1))
fi
if recipe_validate::msxml_is_native "$wow64/msxml6.dll"; then
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
    recipe_validate::ok "Native gdiplus"
else
    recipe_validate::fail "Native gdiplus fehlt — Reparieren"
    failures=$((failures + 1))
fi

output::progress_tick "Lightroom-Fixes"
# d2d1: ohne die gepatchte DLL bricht der Start an CreateD2DDeviceResources ab.
if recipe_validate::native_pe "$sys32/d2d1.dll"; then
    recipe_validate::ok "Gepatchtes d2d1 (ColorManagement + Histogramm)"
else
    recipe_validate::fail "d2d1-Patch fehlt — Reparieren (sonst Startabbruch 0x88990028)"
    failures=$((failures + 1))
fi
if recipe_validate::native_pe "$sys32/hnetcfg.dll"; then
    recipe_validate::ok "hnetcfg-Stub (Firewall-COM-Probe)"
else
    recipe_validate::fail "hnetcfg-Stub fehlt — Reparieren"
    failures=$((failures + 1))
fi
if recipe_validate::native_pe "$sys32/mfplat.dll"; then
    recipe_validate::ok "Gepatchtes mfplat (MFCreateSampleCopierMFT)"
else
    recipe_validate::warn "mfplat nicht gepatcht — Reparieren, falls Medien-Funktionen fehlen"
fi
if recipe_validate::native_pe "$sys32/winrt_inmemstream.dll"; then
    recipe_validate::ok "WinRT-Streams (KI-Masken)"
else
    recipe_validate::warn "winrt_inmemstream fehlt — KI-Masken bleiben ohne Wirkung (Reparieren)"
fi

output::progress_tick "Lightroom.exe"
if exe="$(lightroom::find_exe "$WINEPREFIX" 2>/dev/null || true)" && [ -n "$exe" ]; then
    recipe_validate::ok "Lightroom.exe: $exe"
    _lr_ver="$(recipe_validate::lightroom_app_version "$exe" || true)"
    recipe_validate::version_guaranteed_check "$_guaranteed" "$_lr_ver" "Lightroom-Version"

    _exe_dir="$(dirname "$exe")"
    if [ -f "$_exe_dir/version.dll" ] && [ -f "$_exe_dir/version_orig.dll" ]; then
        recipe_validate::ok "Dialog-Fix (version-Proxy neben Lightroom.exe)"
    else
        recipe_validate::warn "version-Proxy fehlt — Exportieren/Einstellungen kopieren ggf. leer (Reparieren)"
    fi
    if [ -f "$_exe_dir/AdobeGrowthSDK.dll" ]; then
        recipe_validate::warn "AdobeGrowthSDK aktiv — Reparieren (SetThreadpoolTimerEx bricht den Start ab)"
    else
        recipe_validate::ok "AdobeGrowthSDK deaktiviert"
    fi

    if grep -qE '"Desktop"="[0-9]+x[0-9]+"' "$WINEPREFIX/user.reg" 2>/dev/null; then
        recipe_validate::warn "Virtual Desktop noch an — Reparieren"
    else
        recipe_validate::ok "Kein Virtual Desktop"
    fi
else
    recipe_validate::fail "Lightroom.exe nicht gefunden — installieren"
    failures=$((failures + 1))
fi

if [ -z "$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)" ]; then
    _lr_exe="$(lightroom::find_exe "$WINEPREFIX" 2>/dev/null || true)"
    if [ -n "$_lr_exe" ] && [ -f "$_lr_exe" ]; then
        recipe_hooks::state_set WORK_ROOT "$(cd "$(dirname "$_lr_exe")" && pwd)"
    fi
fi
recipe_validate::app_link

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
