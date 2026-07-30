#!/usr/bin/env bash
# Halo Campaign Evolved — nach Setup EXE im Prefix finden und WORK_ROOT setzen.
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_halo_campaign_evolved::find_game_exe() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local f
    [ -d "$prefix/drive_c" ] || return 1
    # Bekannte Namen zuerst
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
    return 0
}
