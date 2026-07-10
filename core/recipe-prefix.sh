#!/usr/bin/env bash
# Prefix-Erstellung für Rezepte — Mono per MSI; Wine-Dialoge mit generischem User-Hinweis
# (welches Wine-Fenster genau erscheint, lässt sich nicht zuverlässig vorhersagen —
# darum ein Hinweis, der beide bekannten Dialoge abdeckt statt einen falschen zu zeigen).

recipe_prefix::wait_ready() {
    local prefix="$1" max="${2:-120}" i=0
    while [ "$i" -lt "$max" ]; do
        if [ -f "$prefix/user.reg" ] && [ -s "$prefix/user.reg" ]; then
            return 0
        fi
        sleep 0.5
        i=$((i + 1))
    done
    return 1
}

recipe_prefix::_bootstrap_overrides() {
    local old="${WINEDLLOVERRIDES:-}"
    echo "${old:+${old};}mscoree=d;mshtml=d;winemenubuilder.exe=d"
}

recipe_prefix::_disable_wine_desktop() {
    wine reg add "HKCU\\Software\\Wine\\Explorer\\Desktop" /v Enable /t REG_SZ /d N /f \
        >> "${LOG_FILE:-/dev/null}" 2>&1 || true
}

recipe_prefix::_mono_missing() {
    type recipe_dotnet::installed >/dev/null 2>&1 || return 0
    recipe_dotnet::installed && return 1
    return 0
}

recipe_prefix::ensure() {
    local prefix="${1:?prefix}"
    local old_overrides="${WINEDLLOVERRIDES:-}"

    mkdir -p "$(dirname "$prefix")"
    export WINEPREFIX="$prefix"
    export WINEDEBUG="${WINEDEBUG:--all}"

    if type recipe_dotnet::_stage_mono_msi >/dev/null 2>&1; then
        recipe_dotnet::_stage_mono_msi || true
    fi

    type recipe_hooks::hint_wine_popup >/dev/null 2>&1 && recipe_hooks::hint_wine_popup

    if [ ! -f "$prefix/user.reg" ]; then
        export WINEDLLOVERRIDES="$(recipe_prefix::_bootstrap_overrides)"
        wineboot -i >> "${LOG_FILE:-/dev/null}" 2>&1 || {
            export WINEDLLOVERRIDES="$old_overrides"
            return 1
        }
        recipe_prefix::wait_ready "$prefix" 120 || true
        wine_runtime::wineserver -w 2>/dev/null || true
        if recipe_prefix::_mono_missing; then
            if type recipe_dotnet::prefix_bootstrap >/dev/null 2>&1; then
                recipe_dotnet::prefix_bootstrap "${LOG_DIR:-/tmp}/wine_mono_prefix.log" || true
            elif type recipe_dotnet::install_wine_mono >/dev/null 2>&1; then
                recipe_dotnet::install_wine_mono "${LOG_DIR:-/tmp}/wine_mono_prefix.log" || true
            fi
        fi
        export WINEDLLOVERRIDES="$old_overrides"
        recipe_prefix::_disable_wine_desktop
    else
        if recipe_prefix::_mono_missing && type recipe_dotnet::prefix_bootstrap >/dev/null 2>&1; then
            recipe_dotnet::prefix_bootstrap "${LOG_DIR:-/tmp}/wine_mono_prefix.log" || true
        fi
        export WINEDLLOVERRIDES="$(recipe_prefix::_bootstrap_overrides)"
        wine wineboot -u >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        export WINEDLLOVERRIDES="$old_overrides"
        wine_runtime::wineserver -w 2>/dev/null || true
    fi
    return 0
}
