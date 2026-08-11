#!/usr/bin/env bash
# Photoshop session teardown: graceful exit + orphan Adobe helpers (issue #10).
# Shared by kill.sh and cleanup-orphans.sh (natural window close).
# User-facing strings: msg::t (RECIPE_UI_LANG=de|en).
#
# Safety: only touch processes whose /proc/<pid>/environ has WINEPREFIX=<this prefix>.
# wineserver -k is also scoped by WINEPREFIX (other prefixes keep their server).

recipe_photoshop::_prefix() {
    printf '%s' "${WINEPREFIX:-${WINE_PREFIX:-}}"
}

# True if pid belongs to this recipe's Wine prefix.
recipe_photoshop::_pid_in_prefix() {
    local pid="${1:?}" prefix="${2:?}"
    local envf="/proc/${pid}/environ"
    [ -r "$envf" ] || return 1
    # Exact WINEPREFIX=… entry (null-separated environ).
    tr '\0' '\n' <"$envf" 2>/dev/null | grep -Fxq "WINEPREFIX=${prefix}"
}

# Kill processes matching pat only if they run under our WINEPREFIX.
recipe_photoshop::_pkill_pat() {
    local pat="${1:?}"
    local sig="${2:-}"
    local prefix pid cmd
    prefix="$(recipe_photoshop::_prefix)"
    if [ -z "$prefix" ] || [ ! -d "$prefix" ]; then
        return 0
    fi
    for pid in $(pgrep -f "$pat" 2>/dev/null || true); do
        [ -d "/proc/$pid" ] || continue
        recipe_photoshop::_pid_in_prefix "$pid" "$prefix" || continue
        if [ -n "$sig" ]; then
            kill "-${sig}" "$pid" 2>/dev/null || true
        else
            kill "$pid" 2>/dev/null || true
        fi
    done
}

# True while a real Photoshop.exe exists in THIS prefix (not IPC broker; not other prefixes).
recipe_photoshop::photoshop_running() {
    local prefix pid cmd argv0 base
    prefix="$(recipe_photoshop::_prefix)"
    [ -n "$prefix" ] || return 1
    for pid in $(pgrep -f '[Pp]hotoshop\.exe' 2>/dev/null || true); do
        [ -d "/proc/$pid" ] || continue
        recipe_photoshop::_pid_in_prefix "$pid" "$prefix" || continue
        cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
        case "${cmd,,}" in
            *adobeipcbroker*) continue ;;
        esac
        argv0="$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | head -1 || true)"
        base="${argv0##*/}"
        base="${base,,}"
        if [ "$base" = "photoshop.exe" ]; then
            return 0
        fi
        case "$cmd" in
            *[/\\]Photoshop.exe*|*[/\\]photoshop.exe*) return 0 ;;
        esac
    done
    return 1
}

recipe_photoshop::wait_photoshop_gone() {
    local max_s="${1:-15}"
    local i=0
    while recipe_photoshop::photoshop_running; do
        i=$((i + 1))
        if [ "$i" -ge "$max_s" ]; then
            return 1
        fi
        sleep 1
    done
    return 0
}

# Close Photoshop windows via the host WM (same path as clicking the window ✕).
# IMPORTANT: never wmctrl -c by title substring — that closes browser tabs titled
# "…Photoshop…" (issue #10 follow-up). Match WM_CLASS only (StartupWMClass=Photoshop.exe).
recipe_photoshop::_wm_class_is_photoshop() {
    local wclass="${1,,}"
    case "$wclass" in
        *photoshop.exe*|photoshop.exe|photoshop.exe.*) return 0 ;;
    esac
    return 1
}

recipe_photoshop::_wm_close_photoshop() {
    command -v wmctrl >/dev/null 2>&1 || return 0
    local id desk wclass
    # wmctrl -lx columns: id desktop WM_CLASS host title…
    # Do not use IFS= here — we need default whitespace field splitting.
    while read -r id desk wclass _; do
        [ -n "$id" ] || continue
        recipe_photoshop::_wm_class_is_photoshop "$wclass" || continue
        wmctrl -ic "$id" 2>/dev/null || true
    done < <(wmctrl -lx 2>/dev/null || true)
}

# Windows taskkill without /F sends WM_CLOSE (prefs/recents can flush). /F is hard kill.
recipe_photoshop::_wine_taskkill() {
    local force="${1:-0}"
    local prefix
    prefix="$(recipe_photoshop::_prefix)"
    [ -n "$prefix" ] && [ -d "$prefix" ] || return 1
    export WINEPREFIX="$prefix"
    type wine_runtime::wine >/dev/null 2>&1 || return 1
    if [ "$force" = "1" ]; then
        wine_runtime::wine taskkill.exe /F /IM Photoshop.exe >/dev/null 2>&1 || true
        wine_runtime::wine taskkill.exe /F /IM photoshop.exe >/dev/null 2>&1 || true
    else
        wine_runtime::wine taskkill.exe /IM Photoshop.exe >/dev/null 2>&1 || true
        wine_runtime::wine taskkill.exe /IM photoshop.exe >/dev/null 2>&1 || true
    fi
    return 0
}

# Ask Photoshop to exit like File→Exit / window close; escalate only if needed.
# Do NOT SIGTERM first — that causes prefs/recents "amnesia" (issue #10).
recipe_photoshop::request_photoshop_exit() {
    if ! recipe_photoshop::photoshop_running; then
        return 0
    fi
    type output::step >/dev/null 2>&1 && output::step "$(msg::t ps.exit.soft)" || true

    recipe_photoshop::_wm_close_photoshop
    if recipe_photoshop::wait_photoshop_gone 8; then
        return 0
    fi

    recipe_photoshop::_wine_taskkill 0
    if recipe_photoshop::wait_photoshop_gone 20; then
        return 0
    fi

    type output::info >/dev/null 2>&1 && output::info "$(msg::t ps.exit.force)" || true
    recipe_photoshop::_wine_taskkill 1
    if recipe_photoshop::wait_photoshop_gone 8; then
        return 0
    fi

    # Last resort: Unix signals (may skip prefs flush — only if still stuck).
    recipe_photoshop::_pkill_pat '[\\/]Photoshop\.exe|[\\/]photoshop\.exe' TERM
    if recipe_photoshop::wait_photoshop_gone 5; then
        return 0
    fi
    recipe_photoshop::_pkill_pat '[\\/]Photoshop\.exe|[\\/]photoshop\.exe' 9
    recipe_photoshop::wait_photoshop_gone 5 || true
    return 0
}

# Kill leftover Adobe/Wine helpers in THIS prefix only. Ends with wineserver -k for that prefix.
recipe_photoshop::cleanup_orphans() {
    local prefix
    prefix="$(recipe_photoshop::_prefix)"
    type output::step >/dev/null 2>&1 && output::step "$(msg::t ps.cleanup.helpers)" || true

    if [ -z "$prefix" ] || [ ! -d "$prefix" ]; then
        type output::warn >/dev/null 2>&1 && output::warn "$(msg::t ps.cleanup.no_prefix)" || true
        return 0
    fi

    # Soft first
    recipe_photoshop::_pkill_pat 'Adobe Spaces Helper'
    recipe_photoshop::_pkill_pat 'CEPHtmlEngine'
    recipe_photoshop::_pkill_pat '[Aa]dobe[Ii][Pp][Cc][Bb]roker'
    recipe_photoshop::_pkill_pat 'CCXProcess'
    recipe_photoshop::_pkill_pat 'Adobe Crash Processor'
    recipe_photoshop::_pkill_pat 'Adobe Desktop Service'
    recipe_photoshop::_pkill_pat 'CoreSync'
    recipe_photoshop::_pkill_pat 'wmain26\.dll'
    recipe_photoshop::_pkill_pat 'explorer\.exe.*/desktop'
    sleep 0.8
    # Hard leftover
    recipe_photoshop::_pkill_pat 'Adobe Spaces Helper' 9
    recipe_photoshop::_pkill_pat 'CEPHtmlEngine' 9
    recipe_photoshop::_pkill_pat '[Aa]dobe[Ii][Pp][Cc][Bb]roker' 9
    recipe_photoshop::_pkill_pat 'CCXProcess' 9
    recipe_photoshop::_pkill_pat 'Adobe Crash Processor' 9
    recipe_photoshop::_pkill_pat 'wmain26\.dll' 9
    recipe_photoshop::_pkill_pat 'explorer\.exe.*/desktop' 9
    # Only if Photoshop in this prefix is really gone.
    if recipe_photoshop::photoshop_running; then
        type output::warn >/dev/null 2>&1 \
            && output::warn "$(msg::t ps.cleanup.still_running)" \
            || true
        return 0
    fi
    export WINEPREFIX="$prefix"
    type output::step >/dev/null 2>&1 && output::step "$(msg::t ps.cleanup.wineserver)" || true
    # Scoped: Wine only signals the server for this WINEPREFIX.
    if type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
    elif [ -n "${WINE:-}" ]; then
        "$WINE" wineserver -k 2>/dev/null || true
    elif command -v wineserver >/dev/null 2>&1; then
        wineserver -k 2>/dev/null || true
    fi
    if type recipe_guard::kill_stale_winetricks >/dev/null 2>&1; then
        recipe_guard::kill_stale_winetricks 2>/dev/null || true
    fi
    return 0
}

# Full Quit from Rezeptor: soft PS exit → orphans → wineserver.
recipe_photoshop::graceful_shutdown() {
    recipe_photoshop::request_photoshop_exit
    # Extra beat after process exit so prefs/recents finish flushing to disk.
    sleep "${PHOTOSHOP_EXIT_FLUSH_S:-3}"
    recipe_photoshop::cleanup_orphans
}
