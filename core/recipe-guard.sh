#!/usr/bin/env bash
# Start-Schutz: RAM, Doppel-Instanz, Notify-Icon.

recipe_guard::mem_available_mb() {
    awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0
}

recipe_guard::require_mem() {
    local min_mb="${1:-4096}"
    local avail
    avail="$(recipe_guard::mem_available_mb)"
    if [ "$avail" -gt 0 ] && [ "$avail" -lt "$min_mb" ]; then
        echo "Zu wenig freier RAM (${avail} MB verfügbar, mindestens ${min_mb} MB nötig)." >&2
        echo "Schließe andere Apps oder beende hängende Wine-Prozesse (winetricks/wineserver)." >&2
        return 1
    fi
    return 0
}

recipe_guard::abort_if_running() {
    local pattern="$1"
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        echo "Läuft bereits: $pattern — keine zweite Instanz." >&2
        return 1
    fi
    return 0
}

recipe_guard::kill_stale_winetricks() {
    pkill -f 'winetricks -q win10' 2>/dev/null || true
}

recipe_guard::notify_icon() {
    local scr_path="${SCR_PATH:-${DATA_ROOT:-}}"
    local project_root="${PROJECT_ROOT:-}"
    if [ -n "$scr_path" ] && [ -f "$scr_path/launcher/AdobePhotoshop-icon.png" ]; then
        echo "$scr_path/launcher/AdobePhotoshop-icon.png"
    elif [ -n "$project_root" ] && [ -f "$project_root/images/AdobePhotoshop-icon.png" ]; then
        echo "$project_root/images/AdobePhotoshop-icon.png"
    elif [ -n "$project_root" ] && [ -f "$project_root/images/AdobePhotoshop-icon.svg" ]; then
        echo "$project_root/images/AdobePhotoshop-icon.svg"
    else
        echo "photoshop"
    fi
}

recipe_dpi::logpixels() {
    local dpi="${WINE_LOGPIXELS:-}"
    if [ -z "$dpi" ]; then
        if command -v xrdb >/dev/null 2>&1; then
            dpi="$(xrdb -query 2>/dev/null | awk '/Xft\.dpi/ {print $2; exit}')"
        fi
    fi
    if [ -z "$dpi" ] && [ -n "${QT_FONT_DPI:-}" ]; then
        dpi="$QT_FONT_DPI"
    fi
    if [ -z "$dpi" ]; then
        dpi=96
    fi
    wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$dpi" /f \
        >> "${LOG_FILE:-${SCR_PATH:-}/photoshop-runtime.log}" 2>&1 || true
}
