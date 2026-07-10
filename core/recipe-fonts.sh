#!/usr/bin/env bash
# Windows-Schriften + ClearType — Adobe UI braucht echte Fonts (nicht Times-Fallback).

recipe_fonts::count() {
    local prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    find "$prefix/drive_c/windows/Fonts" -maxdepth 1 -type f 2>/dev/null | wc -l
}

recipe_fonts::registry() {
    wine reg delete "HKCU\\Control Panel\\Desktop" /v FontSmoothing /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    # FontSmoothing MUSS REG_SZ sein (Windows-Konvention, winetricks fontsmooth ebenso) —
    # als REG_DWORD liest Wine den Wert nicht und Antialiasing bleibt AUS (pixelige Schrift).
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothing /t REG_SZ /d 2 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingType /t REG_DWORD /d 2 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingGamma /t REG_DWORD /d 1400 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingOrientation /t REG_DWORD /d 1 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    # Windows-Default ~1400 — 106 war falsch und macht Text dünn/grau (WISO/Qt).
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingContrast /t REG_DWORD /d 1400 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Wine\\Fonts" /v FontSmoothing /t REG_DWORD /d 2 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Wine\\X11 Driver" /v ClientAreaWithStandardDecorations /t REG_DWORD /d 1 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    # Qt/Win-Apps fordern "Segoe UI" — Calibri liest sich klarer als Tahoma für UI-Text.
    local _ui_font="Calibri" _ui_bold="Calibri Bold"
    if ! find "${WINEPREFIX:-}/drive_c/windows/Fonts" -maxdepth 1 -iname 'calibri*.ttf' 2>/dev/null | grep -q .; then
        _ui_font="Tahoma"
        _ui_bold="Tahoma Bold"
    fi
    local _segoe_key
    for _segoe_key in \
        "HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" \
        "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" \
        "HKLM\\Software\\Wow6432Node\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes"; do
        wine reg add "$_segoe_key" /v "Segoe UI" /t REG_SZ /d "$_ui_font" /f \
            >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        wine reg add "$_segoe_key" /v "Segoe UI Semibold" /t REG_SZ /d "$_ui_bold" /f \
            >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        wine reg add "$_segoe_key" /v "Segoe UI Bold" /t REG_SZ /d "$_ui_bold" /f \
            >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        wine reg add "$_segoe_key" /v "Segoe UI Light" /t REG_SZ /d "$_ui_font" /f \
            >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        wine reg add "$_segoe_key" /v "Segoe UI Semilight" /t REG_SZ /d "$_ui_font" /f \
            >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    done
    # Wine-eigene Font-Replacements (gewinnen oft über FontSubstitutes!) —
    # Default: Segoe UI → Times New Roman → unleserliche Qt/WISO-UI.
    local _rep="HKCU\\Software\\Wine\\Fonts\\Replacements"
    wine reg add "$_rep" /v "Segoe UI" /t REG_SZ /d "$_ui_font" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "Segoe UI Semibold" /t REG_SZ /d "$_ui_bold" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "Segoe UI Bold" /t REG_SZ /d "$_ui_bold" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "Segoe UI Light" /t REG_SZ /d "$_ui_font" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "Segoe UI Semilight" /t REG_SZ /d "$_ui_font" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "Verdana" /t REG_SZ /d "$_ui_font" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "MS Shell Dlg" /t REG_SZ /d "$_ui_font" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "$_rep" /v "MS Shell Dlg 2" /t REG_SZ /d "$_ui_font" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
}

recipe_fonts::ensure() {
    local log_file="${1:-${LOG_DIR:-/tmp}/winetricks_fonts.log}"
    local n need=0

    recipe_winetricks::prepare || return 1

    if type recipe_dpi::logpixels >/dev/null 2>&1; then
        recipe_dpi::logpixels
    else
        wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d 96 /f \
            >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    fi

    n="$(recipe_fonts::count)"
    if [ "$n" -lt 8 ]; then
        need=1
        if type output::step >/dev/null 2>&1; then
            output::step "Schriften (corefonts, tahoma, calibri, fontsmooth=rgb)"
        fi
        if type output::progress >/dev/null 2>&1; then
            output::progress 40 "Schriften installieren"
        fi
        recipe_winetricks::run "$log_file" corefonts tahoma calibri fontsmooth=rgb || return 1
    fi

    if [ "$need" -eq 0 ]; then
        if ! find "${WINEPREFIX}/drive_c/windows/Fonts" -maxdepth 1 -iname 'tahoma*.ttf' 2>/dev/null | grep -q .; then
            recipe_winetricks::run "$log_file" tahoma fontsmooth=rgb || return 1
        fi
        if ! find "${WINEPREFIX}/drive_c/windows/Fonts" -maxdepth 1 -iname 'calibri*.ttf' 2>/dev/null | grep -q .; then
            recipe_winetricks::run "$log_file" calibri || return 1
        fi
    fi

    if type output::progress >/dev/null 2>&1; then
        output::progress 55 "ClearType-Registry"
    fi
    # recipe_validate ist optional (Launch-Profil lädt es nicht immer).
    if type recipe_validate::font_smoothing_ok >/dev/null 2>&1; then
        if ! recipe_validate::font_smoothing_ok "${WINEPREFIX:-}"; then
            recipe_winetricks::run "$log_file" fontsmooth=rgb || return 1
        fi
    fi
    recipe_fonts::registry
    return 0
}
