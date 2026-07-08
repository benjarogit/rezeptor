#!/usr/bin/env bash
# Windows 10 per Registry — kein winetricks winecfg (hängt/segfaultet unter Proton).

recipe_win10::ensure() {
    local current_ver=""
    current_ver="$(wine reg query "HKCU\\Software\\Wine" /v Version 2>/dev/null \
        | awk '/Version/{print $3}' | tr -d '\r\n' || true)"
    if [ "$current_ver" = "win10" ]; then
        return 0
    fi

    wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d win10 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || return 1
    wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
        /v CurrentVersion /t REG_SZ /d 10.0 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || return 1
    wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
        /v CurrentBuild /t REG_SZ /d 19045 /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
        /v ProductName /t REG_SZ /d "Microsoft Windows 10" /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    return 0
}
