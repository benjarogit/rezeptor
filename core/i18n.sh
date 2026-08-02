#!/usr/bin/env bash
# Rezeptor — minimale Shell-i18n (RECIPE_UI_LANG=de|en).
# Phase 1: Core-Schritte. Rezept-eigene Strings folgen später derselben API.
#
# Usage: msg::t KEY [printf-args...]
# Fallback: en → key name if missing.

msg::_lang() {
    local code="${RECIPE_UI_LANG:-${LANG:-}}"
    code="${code%%.*}"
    code="${code%%_*}"
    code="$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')"
    case "$code" in
        de*) echo de ;;
        *) echo en ;;
    esac
}

msg::_lookup() {
    local key="$1"
    local lang
    lang="$(msg::_lang)"
    case "$lang:$key" in
        de:step.wine_init) echo "Wine initialisieren" ;;
        en:step.wine_init) echo "Initializing Wine" ;;
        de:step.wine_prefix) echo "Wine-Prefix" ;;
        en:step.wine_prefix) echo "Wine prefix" ;;
        de:ok.prefix_ready) echo "Prefix bereit" ;;
        en:ok.prefix_ready) echo "Prefix ready" ;;
        de:ok.wine_ready) echo "Wine bereit" ;;
        en:ok.wine_ready) echo "Wine ready" ;;
        de:step.win10_registry) echo "Windows 10 (Registry)" ;;
        en:step.win10_registry) echo "Windows 10 (registry)" ;;
        de:ok.win10) echo "win10" ;;
        en:ok.win10) echo "win10" ;;
        de:step.installer) echo "Installer: %s" ;;
        en:step.installer) echo "Installer: %s" ;;
        de:ok.installer_done) echo "Installer ausgeführt" ;;
        en:ok.installer_done) echo "Installer finished" ;;
        de:err.installer_missing) echo "Installer fehlt: %s" ;;
        en:err.installer_missing) echo "Installer missing: %s" ;;
        de:step.winetricks) echo "winetricks: %s" ;;
        en:step.winetricks) echo "winetricks: %s" ;;
        de:err.winetricks_failed) echo "winetricks %s fehlgeschlagen" ;;
        en:err.winetricks_failed) echo "winetricks %s failed" ;;
        de:err.win10_failed) echo "win10 Registry fehlgeschlagen" ;;
        en:err.win10_failed) echo "win10 registry failed" ;;
        de:step.proton_init) echo "Proton-GE initialisieren" ;;
        en:step.proton_init) echo "Initializing Proton-GE" ;;
        *)
            # Missing key: try English, else echo key
            if [ "$lang" != en ]; then
                RECIPE_UI_LANG=en msg::_lookup "$key"
            else
                echo "$key"
            fi
            ;;
    esac
}

# Translate KEY; remaining args are printf format arguments.
msg::t() {
    local key="${1:-}"
    shift || true
    local fmt
    fmt="$(msg::_lookup "$key")"
    if [ "$#" -gt 0 ]; then
        # shellcheck disable=SC2059
        printf "$fmt" "$@"
    else
        printf '%s' "$fmt"
    fi
}
