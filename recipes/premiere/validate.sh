#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate
recipe_hooks::_source sharedFuncs.sh
recipe_hooks::_source recipe-adobe-setup.sh
recipe_hooks::_source recipe-nvidia-libs.sh

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
msxml3_64="$WINEPREFIX/drive_c/windows/system32/msxml3.dll"
if recipe_validate::msxml_is_native "$msxml3"; then
    recipe_validate::ok "Native MSXML3 (syswow64)"
else
    recipe_validate::fail "MSXML3 fehlt oder nicht nativ — Reparieren"
    failures=$((failures + 1))
fi
if recipe_validate::msxml_is_native "$msxml3_64"; then
    recipe_validate::ok "Native MSXML3 (system32 / x64)"
else
    recipe_validate::fail "MSXML3 x64 (system32) fehlt — Reparieren"
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
    recipe_validate::ok "Native gdiplus"
else
    recipe_validate::fail "Native gdiplus fehlt — Reparieren"
    failures=$((failures + 1))
fi

output::progress_tick "Premiere.exe"
if exe="$(premiere::find_exe "$WINEPREFIX" 2>/dev/null || true)" && [ -n "$exe" ]; then
    recipe_validate::ok "Adobe Premiere Pro.exe: $exe"
    _pr_ver="$(recipe_validate::premiere_app_version "$exe" || true)"
    recipe_validate::version_guaranteed_check "$_guaranteed" "$_pr_ver" "Premiere-Version"

    _exe_dir="$(dirname "$exe")"
    if [ -f "$_exe_dir/icuin.dll" ] && [ -f "$_exe_dir/icuuc.dll" ]; then
        recipe_validate::ok "ICU-DLLs (icuin/icuuc)"
    elif compgen -G "$_exe_dir/icuin[0-9]*.dll" >/dev/null 2>&1 \
        || compgen -G "$_exe_dir/icuuc[0-9]*.dll" >/dev/null 2>&1; then
        recipe_validate::warn "ICU-Duplikate fehlen — Reparieren (icuin*/icuuc* → icuin/icuuc.dll)"
    else
        recipe_validate::ok "ICU-DLLs (keine Version-DLLs im Baum)"
    fi

    if grep -qE '"Desktop"="[0-9]+x[0-9]+"' "$WINEPREFIX/user.reg" 2>/dev/null; then
        recipe_validate::warn "Virtual Desktop noch an — Reparieren (blaue Fläche)"
    else
        recipe_validate::ok "Kein Virtual Desktop"
    fi
else
    recipe_validate::fail "Adobe Premiere Pro.exe nicht gefunden — installieren"
    failures=$((failures + 1))
fi

if recipe_nvidia_libs::installed "$WINEPREFIX"; then
    recipe_validate::ok "GPU: nvidia-libs (CUDA/NVAPI — NVIDIA-Pfad)"
elif recipe_nvidia_libs::host_has_nvidia && recipe_nvidia_libs::wanted; then
    recipe_validate::warn "GPU: nvidia-libs fehlen — Reparieren (CUDA auf NVIDIA)"
elif recipe_nvidia_libs::host_has_nvidia; then
    recipe_validate::ok "GPU: NVIDIA, nvidia-libs abgeschaltet (PREMIERE_NVIDIA_LIBS=0)"
else
    recipe_validate::ok "GPU: kein NVIDIA — AMD/Intel ohne CUDA (erwartet)"
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
