#!/usr/bin/env bash
# Halo Campaign Evolved — nach Setup EXE im Prefix finden und WORK_ROOT setzen.
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_halo_campaign_evolved::find_game_exe() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local f preferred
    [ -d "$prefix/drive_c" ] || return 1
    # Bevorzugter /DIR=-Pfad aus Silent-Install
    preferred="$prefix/drive_c/Games/HaloCampaignEvolved/HaloCampaignEvolved.exe"
    if [ -f "$preferred" ]; then
        echo "$preferred"
        return 0
    fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            setup.exe|Setup.exe|unins*.exe|vcredist*.exe|dxwebsetup.exe) continue ;;
        esac
        echo "$f"
        return 0
    done < <(
        find "$prefix/drive_c" -type f \( \
            -iname 'HaloCampaignEvolved.exe' -o \
            -iname '*Halo*Campaign*Evolved*.exe' -o \
            -iname 'MCC-Win64-Shipping.exe' \
        \) 2>/dev/null | head -5
    )
    return 1
}

# Mögliche Nick-/Sprach-Configs im Spielordner (ElAmigos / Spiel).
recipe_halo_campaign_evolved::find_player_configs() {
    local dir="$1" f
    [ -d "$dir" ] || return 1
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        echo "$f"
    done < <(
        find "$dir" -maxdepth 3 -type f \( \
            -iname '*player*.ini' -o -iname '*player*.cfg' -o \
            -iname '*user*.ini' -o -iname '*user*.cfg' -o \
            -iname '*nick*.ini' -o -iname '*nick*.cfg' -o \
            -iname '*lang*.ini' -o -iname '*lang*.cfg' -o \
            -iname '*language*' -o -iname 'settings.ini' -o \
            -iname 'config.ini' -o -iname 'options.ini' \
        \) 2>/dev/null | head -20
    )
}

recipe_halo_campaign_evolved::offer_player_config() {
    local dir="$1"
    local configs="" f count=0
    [ -d "$dir" ] || return 0

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        configs="${configs}${configs:+|}${f}"
        count=$((count + 1))
        output::info "Config: $(basename "$f") — $(dirname "$f")"
    done < <(recipe_halo_campaign_evolved::find_player_configs "$dir" || true)

    if [ "$count" -gt 0 ]; then
        recipe_hooks::state_set PLAYER_CONFIG_PATHS "$configs"
        output::info "Nickname/Spielsprache: passende Dateien gefunden — siehe Post-Install-Hinweis"
    else
        recipe_hooks::state_set PLAYER_CONFIG_PATHS ""
        output::info "Nickname/Spielsprache: nach dem ersten Start ggf. im Spielordner einstellen"
    fi

    # Tag für Launcher-Post-Dialog (Fluent/Info nach Install-Erfolg)
    type output::_gui_emit >/dev/null 2>&1 \
        && output::_gui_emit info "POST_CONFIG:$dir" \
        || true
    return 0
}

recipe_halo_campaign_evolved::finalize() {
    local exe dir
    output::progress 92 "Spielordner ermitteln"
    exe="$(recipe_halo_campaign_evolved::find_game_exe || true)"
    if [ -z "$exe" ]; then
        output::info "Spiel-EXE noch nicht gefunden — nach manuellem Setup → Reparieren"
        # Keep installer work root if any; launch will fail until finalize succeeds
        return 0
    fi
    dir="$(cd "$(dirname "$exe")" && pwd)"
    recipe_hooks::state_set WORK_ROOT "$dir"
    recipe_hooks::state_set GAME_EXE "$exe"
    recipe_hooks::state_set GAME_DIR "$dir"
    output::success "Spiel: $(basename "$exe")"
    output::info "Pfad: $dir"
    output::progress 96 "Spieler-Einstellungen"
    recipe_halo_campaign_evolved::offer_player_config "$dir" || true
    return 0
}
