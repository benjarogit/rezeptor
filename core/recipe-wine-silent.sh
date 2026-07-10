#!/usr/bin/env bash
# Optionale headless Wine-Session (nur mit RECIPE_WINE_SILENT=1).
# Standard: Wine läuft normal — Dialoge sind erlaubt; Hinweise über output::user_action.

_RECIPE_WINE_SILENT_ACTIVE=0
_RECIPE_WINE_SILENT_SAVED_DISPLAY=""
_RECIPE_WINE_SILENT_SAVED_WAYLAND=""
_RECIPE_WINE_SILENT_SAVED_XAUTH=""
_RECIPE_WINE_SILENT_SAVED_QT=""

recipe_wine_silent::wants_gui() {
    [ -n "${RECIPE_WINE_SHOW_GUI:-}" ] || [ -n "${WISO_SHOW_WINE_GUI:-}" ]
}

recipe_wine_silent::session_active() {
    [ "${RECIPE_WINE_SILENT:-}" = "1" ] || [ "$_RECIPE_WINE_SILENT_ACTIVE" -eq 1 ]
}

recipe_wine_silent::session_begin() {
    recipe_wine_silent::wants_gui && return 0
    [ "$_RECIPE_WINE_SILENT_ACTIVE" -eq 1 ] && return 0
    [ "${RECIPE_WINE_SILENT:-}" = "1" ] || return 0

    _RECIPE_WINE_SILENT_SAVED_DISPLAY="${DISPLAY-}"
    _RECIPE_WINE_SILENT_SAVED_WAYLAND="${WAYLAND_DISPLAY-}"
    _RECIPE_WINE_SILENT_SAVED_XAUTH="${XAUTHORITY-}"
    _RECIPE_WINE_SILENT_SAVED_QT="${QT_QPA_PLATFORM-}"
    unset DISPLAY WAYLAND_DISPLAY XAUTHORITY 2>/dev/null || true
    export QT_QPA_PLATFORM=offscreen
    export WINEDEBUG="${WINEDEBUG:--all}"
    _RECIPE_WINE_SILENT_ACTIVE=1
}

recipe_wine_silent::session_end() {
    [ "$_RECIPE_WINE_SILENT_ACTIVE" -eq 1 ] || return 0
    if [ -n "$_RECIPE_WINE_SILENT_SAVED_DISPLAY" ]; then
        export DISPLAY="$_RECIPE_WINE_SILENT_SAVED_DISPLAY"
    else
        unset DISPLAY 2>/dev/null || true
    fi
    if [ -n "$_RECIPE_WINE_SILENT_SAVED_WAYLAND" ]; then
        export WAYLAND_DISPLAY="$_RECIPE_WINE_SILENT_SAVED_WAYLAND"
    else
        unset WAYLAND_DISPLAY 2>/dev/null || true
    fi
    if [ -n "$_RECIPE_WINE_SILENT_SAVED_XAUTH" ]; then
        export XAUTHORITY="$_RECIPE_WINE_SILENT_SAVED_XAUTH"
    else
        unset XAUTHORITY 2>/dev/null || true
    fi
    if [ -n "$_RECIPE_WINE_SILENT_SAVED_QT" ]; then
        export QT_QPA_PLATFORM="$_RECIPE_WINE_SILENT_SAVED_QT"
    else
        unset QT_QPA_PLATFORM 2>/dev/null || true
    fi
    _RECIPE_WINE_SILENT_ACTIVE=0
}

recipe_wine_silent::run() {
    if recipe_wine_silent::wants_gui || ! recipe_wine_silent::session_active; then
        "$@"
        return $?
    fi

    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a "$@"
        return $?
    fi

    local saved_d="${DISPLAY-}" saved_w="${WAYLAND_DISPLAY-}" saved_x="${XAUTHORITY-}" saved_qt="${QT_QPA_PLATFORM-}"
    unset DISPLAY WAYLAND_DISPLAY XAUTHORITY 2>/dev/null || true
    export QT_QPA_PLATFORM=offscreen
    "$@"
    local rc=$?
    if [ -n "$saved_d" ]; then export DISPLAY="$saved_d"; else unset DISPLAY 2>/dev/null || true; fi
    if [ -n "$saved_w" ]; then export WAYLAND_DISPLAY="$saved_w"; else unset WAYLAND_DISPLAY 2>/dev/null || true; fi
    if [ -n "$saved_x" ]; then export XAUTHORITY="$saved_x"; else unset XAUTHORITY 2>/dev/null || true; fi
    if [ -n "$saved_qt" ]; then export QT_QPA_PLATFORM="$saved_qt"; else unset QT_QPA_PLATFORM 2>/dev/null || true; fi
    return "$rc"
}
