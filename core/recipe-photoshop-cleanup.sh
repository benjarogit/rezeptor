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
# "…Photoshop…" (issue #10 follow-up). Prefer _NET_WM_PID related to Photoshop.exe
# in this prefix; WM_CLASS is a fallback (Proton/Wine class strings vary).
recipe_photoshop::_wm_class_is_photoshop() {
    local wclass="${1,,}"
    case "$wclass" in
        *photoshop.exe*|photoshop.exe|photoshop.exe.*) return 0 ;;
        # Some Wine/Proton builds omit ".exe" or use instance.Class pairs.
        photoshop.photoshop|*.photoshop|photoshop|photoshop.*) return 0 ;;
    esac
    return 1
}

# PIDs of real Photoshop.exe in this recipe prefix (one per line).
recipe_photoshop::_photoshop_pids() {
    local prefix pid cmd argv0 base
    prefix="$(recipe_photoshop::_prefix)"
    [ -n "$prefix" ] || return 0
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
            printf '%s\n' "$pid"
            continue
        fi
        case "$cmd" in
            *[/\\]Photoshop.exe*|*[/\\]photoshop.exe*) printf '%s\n' "$pid" ;;
        esac
    done
}

# Wine often sets _NET_WM_PID to a parent/child of Photoshop.exe, not the .exe PID.
recipe_photoshop::_related_pids() {
    local pid ppid child
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        printf '%s\n' "$pid"
        if [ -r "/proc/${pid}/stat" ]; then
            # /proc/pid/stat: pid (comm) state ppid …
            ppid="$(awk '{print $4}' "/proc/${pid}/stat" 2>/dev/null || true)"
            case "$ppid" in
                ''|0|1) ;;
                *) printf '%s\n' "$ppid" ;;
            esac
        fi
        for child in $(pgrep -P "$pid" 2>/dev/null || true); do
            printf '%s\n' "$child"
        done
    done
}

recipe_photoshop::_wm_window_pid() {
    local id="${1:?}"
    local raw
    command -v xprop >/dev/null 2>&1 || return 1
    raw="$(xprop -id "$id" _NET_WM_PID 2>/dev/null | awk -F'= *' '{print $2}' | tr -d '[:space:]')"
    case "$raw" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$raw"
}

recipe_photoshop::_pid_list_has() {
    local needle="${1:?}"
    local list="${2:-}"
    local p
    [ -n "$list" ] || return 1
    while IFS= read -r p; do
        [ "$p" = "$needle" ] && return 0
    done <<EOF
$list
EOF
    return 1
}

# WM-managed Photoshop windows of this prefix (window ids, one per line).
# Only the window manager list is used: xdotool search --pid also returns Wine's
# hidden message windows, which makes "window still open" unreliable.
recipe_photoshop::_photoshop_window_ids() {
    local id desk wclass wpid pids prefix
    command -v wmctrl >/dev/null 2>&1 || return 0
    prefix="$(recipe_photoshop::_prefix)"
    pids="$(recipe_photoshop::_photoshop_pids | recipe_photoshop::_related_pids | sort -u)"

    # wmctrl -lx columns: id desktop WM_CLASS host title…
    # Do not use IFS= here — we need default whitespace field splitting.
    while read -r id desk wclass _; do
        [ -n "$id" ] || continue
        wpid="$(recipe_photoshop::_wm_window_pid "$id" 2>/dev/null || true)"
        if [ -n "$wpid" ] && [ -n "$pids" ]; then
            if recipe_photoshop::_pid_list_has "$wpid" "$pids"; then
                printf '%s\n' "$id"
                continue
            fi
            # Same Wine prefix + Photoshop class: PID may be another wine helper.
            if [ -n "$prefix" ] \
                && recipe_photoshop::_pid_in_prefix "$wpid" "$prefix" \
                && recipe_photoshop::_wm_class_is_photoshop "$wclass"; then
                printf '%s\n' "$id"
            fi
            continue
        fi
        # No usable PID list / _NET_WM_PID: class fallback (still never by title).
        if recipe_photoshop::_wm_class_is_photoshop "$wclass"; then
            printf '%s\n' "$id"
        fi
    done < <(wmctrl -lx 2>/dev/null || true)
    return 0
}

# Ask the WM to close Photoshop windows: _NET_CLOSE_WINDOW is what clicking ✕
# does, so Photoshop runs its own quit path and writes prefs/recents.
# Never `xdotool windowclose`: that destroys the X window without telling
# Photoshop, which then keeps running windowless and never saves (#10).
recipe_photoshop::_wm_close_photoshop() {
    local id
    command -v wmctrl >/dev/null 2>&1 || return 0
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        wmctrl -ic "$id" 2>/dev/null || true
    done <<EOF
$(recipe_photoshop::_photoshop_window_ids)
EOF
    return 0
}

# True while a Photoshop window for this prefix is still mapped.
recipe_photoshop::_photoshop_windows_open() {
    [ -n "$(recipe_photoshop::_photoshop_window_ids)" ]
}

recipe_photoshop::_wait_windows_gone() {
    local max_s="${1:-8}"
    local i=0
    while recipe_photoshop::_photoshop_windows_open; do
        i=$((i + 1))
        if [ "$i" -ge "$max_s" ]; then
            return 1
        fi
        sleep 1
    done
    return 0
}

# Soft keyboard quit on Photoshop windows belonging to our prefix.
recipe_photoshop::_wm_alt_f4_photoshop() {
    local id
    command -v xdotool >/dev/null 2>&1 || return 0
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        xdotool windowactivate --sync "$id" 2>/dev/null || true
        xdotool key --window "$id" --clearmodifiers alt+F4 2>/dev/null || true
    done <<EOF
$(recipe_photoshop::_photoshop_window_ids)
EOF
    return 0
}

# Windows taskkill /F is hard kill. Soft taskkill without /F often leaves Wine
# showing "Not responding" while the UI still paints (issue #10 video) — avoid it.
recipe_photoshop::_wine_taskkill() {
    local force="${1:-0}"
    local prefix
    prefix="$(recipe_photoshop::_prefix)"
    [ -n "$prefix" ] && [ -d "$prefix" ] || return 1
    export WINEPREFIX="$prefix"
    type wine_runtime::wine >/dev/null 2>&1 || return 1
    # Only hard kill is used from request_photoshop_exit.
    if [ "$force" = "1" ]; then
        wine_runtime::wine taskkill.exe /F /IM Photoshop.exe >/dev/null 2>&1 || true
        wine_runtime::wine taskkill.exe /F /IM photoshop.exe >/dev/null 2>&1 || true
    fi
    return 0
}

recipe_photoshop::_force_photoshop_exit() {
    type output::info >/dev/null 2>&1 && output::info "$(msg::t ps.exit.force)" || true
    recipe_photoshop::_wine_taskkill 1
    if recipe_photoshop::wait_photoshop_gone 8; then
        return 0
    fi
    recipe_photoshop::_pkill_pat '[\\/]Photoshop\.exe|[\\/]photoshop\.exe' TERM
    if recipe_photoshop::wait_photoshop_gone 5; then
        return 0
    fi
    recipe_photoshop::_pkill_pat '[\\/]Photoshop\.exe|[\\/]photoshop\.exe' 9
    recipe_photoshop::wait_photoshop_gone 5 || true
    return 0
}

# Window is gone: Photoshop writes prefs/recents while it shuts down, so give it
# time. But never wait forever — a stuck Photoshop.exe blocks the whole teardown,
# helpers stay in RAM and the next launch crashes during init (issue #10).
recipe_photoshop::_await_exit_or_force() {
    type output::info >/dev/null 2>&1 && output::info "$(msg::t ps.exit.window_closed)" || true
    if recipe_photoshop::wait_photoshop_gone "${PHOTOSHOP_EXIT_WAIT_S:-45}"; then
        return 0
    fi
    recipe_photoshop::_force_photoshop_exit
}

# Ask Photoshop to exit like File→Exit / window close; escalate only if needed.
# Do NOT SIGTERM first — that causes prefs/recents "amnesia" (issue #10).
# Do NOT soft-taskkill — that triggers Wine "Not responding" with a live UI.
recipe_photoshop::request_photoshop_exit() {
    local attempt
    if ! recipe_photoshop::photoshop_running; then
        return 0
    fi
    type output::step >/dev/null 2>&1 && output::step "$(msg::t ps.exit.soft)" || true

    # Host WM close retries (same mechanism as clicking the window ✕).
    for attempt in 1 2 3; do
        recipe_photoshop::_wm_close_photoshop
        if recipe_photoshop::_wait_windows_gone 6; then
            recipe_photoshop::_await_exit_or_force
            return 0
        fi
        if recipe_photoshop::wait_photoshop_gone 2; then
            return 0
        fi
        type output::progress_tick >/dev/null 2>&1 \
            && output::progress_tick "$(msg::t ps.exit.soft)" \
            || true
    done

    recipe_photoshop::_wm_alt_f4_photoshop
    if recipe_photoshop::_wait_windows_gone 10; then
        recipe_photoshop::_await_exit_or_force
        return 0
    fi
    if recipe_photoshop::wait_photoshop_gone 8; then
        return 0
    fi

    # Window still mapped after WM close + Alt+F4 — last resort only.
    recipe_photoshop::_force_photoshop_exit
    return 0
}

# Adobe helpers that outlive Photoshop.exe (pgrep -f patterns, prefix-scoped).
RECIPE_PHOTOSHOP_HELPERS=(
    'Adobe Spaces Helper'
    'CEPHtmlEngine'
    '[Aa]dobe[Ii][Pp][Cc][Bb]roker'
    'CCLibrary'
    'CCXProcess'
    'Adobe Crash Processor'
    'Adobe Desktop Service'
    'AdobeNotificationClient'
    'CoreSync'
    'wmain26\.dll'
    'explorer\.exe.*/desktop'
)

# Kill leftover Adobe/Wine helpers in THIS prefix only. Ends with wineserver -k for that prefix.
recipe_photoshop::cleanup_orphans() {
    local prefix pat
    prefix="$(recipe_photoshop::_prefix)"
    type output::step >/dev/null 2>&1 && output::step "$(msg::t ps.cleanup.helpers)" || true

    if [ -z "$prefix" ] || [ ! -d "$prefix" ]; then
        type output::warn >/dev/null 2>&1 && output::warn "$(msg::t ps.cleanup.no_prefix)" || true
        return 0
    fi

    # Soft first
    for pat in "${RECIPE_PHOTOSHOP_HELPERS[@]}"; do
        recipe_photoshop::_pkill_pat "$pat"
    done
    sleep 0.8
    # Hard leftover
    for pat in "${RECIPE_PHOTOSHOP_HELPERS[@]}"; do
        recipe_photoshop::_pkill_pat "$pat" 9
    done
    # Only if Photoshop in this prefix is really gone.
    if recipe_photoshop::photoshop_running; then
        type output::warn >/dev/null 2>&1 \
            && output::warn "$(msg::t ps.cleanup.still_running)" \
            || true
        return 0
    fi
    # Photoshop.exe has exited and prefs are flushed by now, so ending the
    # session server is safe and is the only reliable way to clear helpers that
    # are not in the list above (CCLibrary & co left PS crashing on next start).
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
    sleep "${PHOTOSHOP_EXIT_FLUSH_S:-8}"
    recipe_photoshop::cleanup_orphans
}
