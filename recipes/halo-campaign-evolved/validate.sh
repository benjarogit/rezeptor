#!/usr/bin/env bash
# Halo Campaign Evolved — Validate
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
if [ -f "${PROJECT_ROOT:-}/core/recipe-hooks.sh" ]; then
    source "$PROJECT_ROOT/core/recipe-hooks.sh"
elif [ -f "$RECIPE_DIR/../../core/recipe-hooks.sh" ]; then
    source "$RECIPE_DIR/../../core/recipe-hooks.sh"
else
    echo "ERROR: core/recipe-hooks.sh not found (set PROJECT_ROOT)" >&2
    exit 1
fi
recipe_hooks::load validate

# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh"

export WINEPREFIX="${DATA_ROOT}/prefix"
failures=0

output::progress_begin 7 "Prüfen"

output::progress_tick "Prefix"
if ! recipe_hooks::validate_prefix; then
    failures=$((failures + 1))
fi

output::progress_tick "D3D12"
# Wine liefert d3d12core nur als Stub; ohne vkd3d-proton startet die Unreal-Engine
# nicht („Your GPU or driver isn't supported“). Reparieren zieht die DLL nach.
if recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/system32/d3d12core.dll"; then
    recipe_validate::ok "D3D12: vkd3d-proton aktiv"
else
    recipe_validate::fail "D3D12: vkd3d-proton fehlt im Prefix"
    failures=$((failures + 1))
fi

output::progress_tick "Spiel-EXE"
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
GAME_EXE="$(recipe_hooks::state_get GAME_EXE 2>/dev/null || true)"
EXE=""
if [ -n "$GAME_EXE" ] && [ -f "$GAME_EXE" ]; then
    EXE="$GAME_EXE"
elif [ -n "$WORK_ROOT" ]; then
    EXE="$(recipe_hooks::find_exe "$WORK_ROOT" 2>/dev/null || true)"
fi
if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    EXE="$(recipe_halo_campaign_evolved::find_game_exe 2>/dev/null || true)"
fi
if [ -n "$EXE" ] && [ -f "$EXE" ]; then
    recipe_validate::ok "EXE: $(basename "$EXE")"
else
    recipe_validate::fail "Halo-EXE fehlt im Prefix"
    failures=$((failures + 1))
fi

output::progress_tick "Steam-Stack"
if [ -n "$EXE" ] && [ -f "$EXE" ]; then
    exe_dir="$(dirname "$EXE")"
    root="$(recipe_halo_campaign_evolved::game_root_from_exe_dir "$exe_dir" || true)"
    steam_dir="$(recipe_halo_campaign_evolved::steamworks_dir "$root" || true)"
    if [ -n "$steam_dir" ] && [ -f "$steam_dir/steam_api64.dll" ] \
        && [ -f "$steam_dir/RUNE64.dll" ] \
        && [ -f "$steam_dir/steam_emu.ini" ] \
        && grep -qE '^Offline=1' "$steam_dir/steam_emu.ini" \
        && grep -qE '^LoadDll=RUNE64.dll' "$steam_dir/steam_emu.ini"; then
        recipe_validate::ok "RUNE: Offline=1 + LoadDll + RUNE64"
    else
        recipe_validate::fail "RUNE/ElAmigos unvollständig (steam_emu Offline / RUNE64)"
        failures=$((failures + 1))
    fi
else
    recipe_validate::fail "Steam-Stack: keine EXE zum Prüfen"
    failures=$((failures + 1))
fi

output::progress_tick "MSVC-Runtime"
# libHttpClient uses the constexpr std::mutex of MSVC toolset 14.40+ (zero-initialised,
# no _Mtx_init_in_situ). msvcp140 14.29 derefs a vtable pointer that was never created.
crt="$(recipe_halo_campaign_evolved::pe_file_version \
    "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll" 2>/dev/null || true)"
if recipe_halo_campaign_evolved::crt_version_ok "$crt"; then
    recipe_validate::ok "MSVC-Runtime $crt (libHttpClient braucht 14.40+)"
else
    recipe_validate::fail "MSVC-Runtime ${crt:-fehlt} zu alt — Reparieren (14.40+ nötig)"
    failures=$((failures + 1))
fi

output::progress_tick "libHttpClient"
if [ -n "$EXE" ] && [ -f "$EXE" ]; then
    http="$(dirname "$EXE")/libHttpClient.Win32.dll"
    sz="$(stat -c%s "$http" 2>/dev/null || echo 0)"
    # Original ~250 KB; the old 25 KB stub never completes XAsync callbacks (spinner)
    if [ "$sz" -gt 200000 ]; then
        recipe_validate::ok "libHttpClient: Original aktiv"
    else
        recipe_validate::fail "libHttpClient: Stub aktiv statt Original — Reparieren"
        failures=$((failures + 1))
    fi
fi

output::progress_tick "Updates"
recipe_hooks::_source recipe-updates.sh 2>/dev/null || true
if type recipe_updates::status >/dev/null 2>&1; then
    recipe_updates::status
fi

recipe_validate::app_link

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
