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

recipe_guard::process_matches() {
    # True if a real process cmdline matches needle, excluding shells/tools that
    # merely mention the pattern in their own argv (agent/CI false positives).
    local needle="$1"
    local pid cmdline
    for pid in /proc/[0-9]*; do
        cmdline="$(tr '\0' ' ' <"${pid}/cmdline" 2>/dev/null || true)"
        [ -n "$cmdline" ] || continue
        case "$cmdline" in
            *"${needle}"*) ;;
            *) continue ;;
        esac
        case "$cmdline" in
            */bin/bash*|*/bin/zsh*|*/usr/bin/bash*|*/usr/bin/zsh*|*python*|*cursor*|*pgrep*|*rg\ *|*grep\ *|*systemd-run*)
                continue
                ;;
        esac
        return 0
    done
    return 1
}

recipe_guard::abort_if_running() {
    local pattern="$1"
    if recipe_guard::process_matches "$pattern"; then
        echo "Läuft bereits: $pattern — keine zweite Instanz." >&2
        return 1
    fi
    return 0
}

recipe_guard::kill_stale_winetricks() {
    pkill -f 'winetricks -q win10' 2>/dev/null || true
}

recipe_guard::notify_icon() {
    # Rezept-Icon aus recipe.yml, sonst Photoshop-Fallback (Legacy).
    local project_root="${PROJECT_ROOT:-}"
    local raw="" icon=""
    if [ -n "${RECIPE_YML:-}" ] && [ -f "${RECIPE_YML}" ]; then
        raw="$(recipe_get "$RECIPE_YML" icon 2>/dev/null || true)"
        if [ -n "$raw" ]; then
            icon="${raw//\{repo\}/${project_root}}"
            icon="${icon/#\~/$HOME}"
            if [ -f "$icon" ]; then
                echo "$icon"
                return 0
            fi
        fi
    fi
    if [ -n "$project_root" ] && [ -f "$project_root/images/AdobePhotoshop-icon.png" ]; then
        echo "$project_root/images/AdobePhotoshop-icon.png"
    elif [ -n "$project_root" ] && [ -f "$project_root/images/AdobePhotoshop-icon.svg" ]; then
        echo "$project_root/images/AdobePhotoshop-icon.svg"
    else
        echo "dialog-information"
    fi
}

# Einheitliche Desktop-Benachrichtigung für alle Rezepte.
# Syntax: recipe_notify::send <app-name> <summary> [body] [icon]
# -a <app-name> ist Pflicht (sonst erbt KDE den Parent, z. B. „Cursor“).
#
# Titel-Quelle (Vorgabe):
#   1. notify_title aus recipe.yml (manuell, optional)
#   2. sonst name aus recipe.yml (Pflichtfeld — Anzeigename)
#   3. Aufrufer kann app-name trotzdem explizit setzen
# Kein Auto-Detect aus EXE-Dateinamen (unzuverlässig bei Trainern/Setups).
recipe_notify::title() {
    local t=""
    if [ -n "${RECIPE_YML:-}" ] && [ -f "${RECIPE_YML}" ]; then
        t="$(recipe_get "$RECIPE_YML" notify_title 2>/dev/null || true)"
        [ -n "$t" ] || t="$(recipe_get "$RECIPE_YML" name 2>/dev/null || true)"
    fi
    echo "${t:-${RECIPE_NAME:-Rezeptor}}"
}

recipe_notify::send() {
    local app="${1:?app name}"
    local summary="${2:?summary}"
    local body="${3:-}"
    local icon="${4:-}"
    command -v notify-send >/dev/null 2>&1 || return 0
    if [ -z "$icon" ]; then
        icon="$(recipe_guard::notify_icon 2>/dev/null || true)"
    fi
    if [ -n "$icon" ]; then
        notify-send -a "$app" -i "$icon" "$summary" "$body" 2>/dev/null || true
    else
        notify-send -a "$app" "$summary" "$body" 2>/dev/null || true
    fi
}

# Kurzform: Titel aus recipe.yml, Summary + optional Body/Icon
recipe_notify::recipe() {
    local summary="${1:?summary}"
    local body="${2:-}"
    local icon="${3:-}"
    recipe_notify::send "$(recipe_notify::title)" "$summary" "$body" "$icon"
}

# Einheitlicher Start-Hinweis für alle Rezepte (Photoshop/WISO/HOA/Trainer):
#   App + Titel = Rezeptname, Body = „Wird gestartet…“
# Optionaler Body-Text z. B. für ersten Start / längere Hinweise.
recipe_notify::starting() {
    local body="${1:-Wird gestartet…}"
    local title
    title="$(recipe_notify::title)"
    recipe_notify::send "$title" "$title" "$body"
}

# Einheitliches Layout (Photoshop/WISO/HOA/Trainer):
#   App (-a)  = Rezeptname
#   Titel     = Rezeptname  (KDE-fett)
#   Text      = Statuszeile (z. B. „Wird gestartet…“)
recipe_notify::status() {
    local body="${1:?body}"
    local icon="${2:-}"
    local title
    title="$(recipe_notify::title)"
    [ -n "$icon" ] || icon="$(recipe_guard::notify_icon 2>/dev/null || true)"
    recipe_notify::send "$title" "$title" "$body" "$icon"
}

# Start-Hinweis — alle launch.sh / Wrapper nutzen das.
recipe_notify::starting() {
    local body="${1:-Wird gestartet…}"
    recipe_notify::status "$body"
}

recipe_dpi::logpixels() {
    # Wine-DPI für UI-Layout. Qt-Apps (WISO): bei Host-DPI>96 oft Header/Sidebar-Versatz —
    # dann WINE_LOGPIXELS=96 oder WISO_FORCE_DPI=96 erzwingen.
    local dpi="${WINE_LOGPIXELS:-${WISO_FORCE_DPI:-}}"
    local log="${LOG_FILE:-${DATA_ROOT:-${SCR_PATH:-}}/dpi-runtime.log}"
    if [ -z "$dpi" ]; then
        if command -v xrdb >/dev/null 2>&1; then
            dpi="$(xrdb -query 2>/dev/null | awk '/Xft\.dpi/ {print $2; exit}')"
        fi
    fi
    if [ -z "$dpi" ] && [ -n "${QT_FONT_DPI:-}" ]; then
        dpi="$QT_FONT_DPI"
    fi
    # Ganzzahl 72–288; Default 96 (vermeidet fraktionale Qt-Skalierung unter Wine).
    case "$dpi" in
        ''|*[!0-9]*) dpi=96 ;;
    esac
    if [ "$dpi" -lt 72 ] || [ "$dpi" -gt 288 ]; then
        dpi=96
    fi
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    if wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$dpi" /f \
        >>"$log" 2>&1; then
        echo "[recipe_dpi] LogPixels=$dpi" >>"$log" 2>/dev/null || true
    else
        echo "[recipe_dpi] WARN: LogPixels=$dpi fehlgeschlagen" >>"$log" 2>/dev/null || true
    fi
}
