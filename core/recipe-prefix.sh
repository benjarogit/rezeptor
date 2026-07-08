#!/usr/bin/env bash
# Prefix-Erstellung für Rezepte — Mono still vor wineboot (kein Wine-Mono-Dialog).

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

recipe_prefix::ensure() {
    local prefix="${1:?prefix}"
    local old_overrides="${WINEDLLOVERRIDES:-}"

    mkdir -p "$(dirname "$prefix")"
    export WINEPREFIX="$prefix"

    if type recipe_dotnet::_stage_mono_msi >/dev/null 2>&1; then
        recipe_dotnet::_stage_mono_msi || true
    fi

    if [ ! -f "$prefix/user.reg" ]; then
        export WINEDLLOVERRIDES="${old_overrides:+${old_overrides};}mscoree=d;mshtml=d"
        wineboot -i >> "${LOG_FILE:-/dev/null}" 2>&1 || {
            export WINEDLLOVERRIDES="$old_overrides"
            return 1
        }
        recipe_prefix::wait_ready "$prefix" 120 || true
        wine_runtime::wineserver -w 2>/dev/null || true
        export WINEDLLOVERRIDES="$old_overrides"
        if type recipe_dotnet::prefix_bootstrap >/dev/null 2>&1; then
            recipe_dotnet::prefix_bootstrap "${LOG_DIR:-/tmp}/wine_mono_prefix.log" || true
        elif type recipe_dotnet::install_wine_mono >/dev/null 2>&1; then
            recipe_dotnet::install_wine_mono "${LOG_DIR:-/tmp}/wine_mono_prefix.log" || true
        fi
    else
        if type recipe_dotnet::installed >/dev/null 2>&1 && ! recipe_dotnet::installed; then
            if type recipe_dotnet::prefix_bootstrap >/dev/null 2>&1; then
                recipe_dotnet::prefix_bootstrap "${LOG_DIR:-/tmp}/wine_mono_prefix.log" || true
            fi
        fi
        export WINEDLLOVERRIDES="${old_overrides:+${old_overrides};}mscoree=d"
        wine wineboot -u >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        export WINEDLLOVERRIDES="$old_overrides"
        wine_runtime::wineserver -w 2>/dev/null || true
    fi
    return 0
}
