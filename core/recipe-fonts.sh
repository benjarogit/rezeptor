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
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothing /t REG_DWORD /d 2 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingType /t REG_DWORD /d 2 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingGamma /t REG_DWORD /d 2200 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingOrientation /t REG_DWORD /d 1 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingContrast /t REG_DWORD /d 106 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Wine\\Fonts" /v FontSmoothing /t REG_DWORD /d 2 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Wine\\X11 Driver" /v ClientAreaWithStandardDecorations /t REG_DWORD /d 1 /f \
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
            recipe_winetricks::run "$log_file" tahoma fontsmooth=rgb || true
        fi
        if ! find "${WINEPREFIX}/drive_c/windows/Fonts" -maxdepth 1 -iname 'calibri*.ttf' 2>/dev/null | grep -q .; then
            recipe_winetricks::run "$log_file" calibri || true
        fi
    fi

    if type output::progress >/dev/null 2>&1; then
        output::progress 55 "ClearType-Registry"
    fi
    recipe_fonts::registry
    return 0
}
