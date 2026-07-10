#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate
recipe_hooks::_source recipe-dotnet.sh

_guaranteed="$(recipe_get "$RECIPE_YML" version_guaranteed 2>/dev/null || true)"
export WINEPREFIX="$DATA_ROOT/prefix"
failures=0

output::progress_begin 4 "Prüfen"

WISO_PORTABLE_ROOT=""
if [ -f "$DATA_ROOT/portable.env" ]; then
    WISO_PORTABLE_ROOT="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT || true)"
fi

output::progress_tick "Portable & Prefix"
if [ -n "$WISO_PORTABLE_ROOT" ] && [ -d "$WISO_PORTABLE_ROOT" ]; then
    recipe_validate::ok "Portable: $WISO_PORTABLE_ROOT"
    _wiso_ver="$(recipe_validate::wiso_portable_version "$WISO_PORTABLE_ROOT" || true)"
    if [ -z "$_wiso_ver" ] && [ -f "$DATA_ROOT/portable.env" ]; then
        _wiso_ver="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_VERSION || true)"
    fi
    recipe_validate::version_guaranteed_check "$_guaranteed" "$_wiso_ver" "WISO-Version"
    if _start="$(recipe_wiso::portable_start_exe "$WISO_PORTABLE_ROOT" 2>/dev/null || true)" \
        && [ -n "$_start" ]; then
        recipe_validate::ok "start.exe (Portable-Launcher)"
    else
        recipe_validate::warn "start.exe fehlt — Fallback wiso2026.exe"
    fi
else
    recipe_validate::fail "Portable fehlt (portable.env / WISO_PORTABLE_ROOT)"
    failures=$((failures + 1))
fi

if recipe_validate::prefix_initialized "$WINEPREFIX"; then
    recipe_validate::ok "Wine-Prefix ($WINEPREFIX)"
else
    recipe_validate::fail "Wine-Prefix fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "Runtime (vcrun, gdiplus, win10, Mono)"
wow64="$WINEPREFIX/drive_c/windows/syswow64"
if recipe_validate::vcrun_dll_ok "$wow64/msvcp140.dll" \
    || recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
    recipe_validate::ok "vcrun2019 (msvcp140.dll)"
else
    recipe_validate::fail "vcrun2019 fehlt — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::native_pe "$wow64/gdiplus.dll" \
    || recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/system32/gdiplus.dll"; then
    recipe_validate::ok "Native gdiplus"
else
    recipe_validate::fail "Native gdiplus fehlt — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::windows_version "$WINEPREFIX" "win10"; then
    recipe_validate::ok "Windows-Version win10"
else
    recipe_validate::fail "win10 nicht gesetzt — Reparieren"
    failures=$((failures + 1))
fi

if recipe_dotnet::installed; then
    recipe_validate::ok "Wine-Mono / .NET"
else
    recipe_validate::fail "Wine-Mono fehlt — Reparieren"
    failures=$((failures + 1))
fi

if [ -x "$DATA_ROOT/bin/wiso-launch.sh" ]; then
    recipe_validate::ok "Launcher-Skript"
else
    recipe_validate::fail "wiso-launch.sh fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "Qt-Fix & Schriften"
if [ -n "$WISO_PORTABLE_ROOT" ] && [ -d "$WISO_PORTABLE_ROOT" ]; then
    _sw_dir="$(recipe_wiso::software_dir "$WISO_PORTABLE_ROOT" || true)"
    if [ -n "$_sw_dir" ] && recipe_wiso::qnetwork_disabled "$_sw_dir"; then
        recipe_validate::ok "Wine-Startfix (qnetworklistmanager)"
    elif [ -n "$_sw_dir" ] && [ -f "$_sw_dir/networkinformation/qnetworklistmanager.dll" ]; then
        recipe_validate::fail "Wine-Startfix fehlt — Reparieren (qnetworklistmanager.dll)"
        failures=$((failures + 1))
    fi
fi

_font_n=$(find "$WINEPREFIX/drive_c/windows/Fonts" -maxdepth 1 -type f 2>/dev/null | wc -l)
if [ "$_font_n" -ge 5 ]; then
    recipe_validate::ok "Windows-Schriften ($_font_n)"
else
    recipe_validate::fail "Schriften fehlen (corefonts) — Reparieren"
    failures=$((failures + 1))
fi

# Tahoma = Fallback wenn Calibri fehlt (recipe_fonts::registry).
if find "$WINEPREFIX/drive_c/windows/Fonts" -maxdepth 1 -iname 'tahoma*.ttf' 2>/dev/null | grep -q .; then
    recipe_validate::ok "Tahoma (Segoe-Fallback)"
else
    recipe_validate::fail "Tahoma fehlt (Segoe-Fallback) — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::font_smoothing_ok "$WINEPREFIX"; then
    recipe_validate::ok "ClearType / FontSmoothing (fontsmooth=rgb)"
else
    recipe_validate::fail "FontSmoothing fehlt (pixelige Schrift) — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::segoe_ui_ok "$WINEPREFIX"; then
    recipe_validate::ok "Segoe UI → Calibri/Tahoma (Wine Font Replacements)"
else
    recipe_validate::fail "Segoe UI noch Times New Roman — Reparieren (unleserliche Schrift)"
    failures=$((failures + 1))
fi

# Calibri bevorzugt (klarere UI); Tahoma als Fallback reicht für segoe_ui_ok.
if find "$WINEPREFIX/drive_c/windows/Fonts" -maxdepth 1 -iname 'calibri*.ttf' 2>/dev/null | grep -q .; then
    recipe_validate::ok "Calibri (UI-Schrift)"
else
    recipe_validate::warn "Calibri fehlt — Segoe fällt auf Tahoma zurück"
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
