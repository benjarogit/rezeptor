#!/usr/bin/env bash
# Halo: Campaign Evolved — Launch
set -euo pipefail
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
recipe_hooks::load launch

# Proton pin: recipe.yml proton_ge_tag (GE-Proton11-3); URL/SHA from runtime.lock ALT.
recipe_hooks::runtime_init || exit 1

EXE="$(recipe_hooks::state_get GAME_EXE 2>/dev/null || true)"
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"

# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh"

if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    EXE="$(recipe_halo_campaign_evolved::find_game_exe || true)"
fi
if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    recipe_hooks::die "Nicht installiert — Halo-EXE fehlt (Setup / Update prüfen)"
fi
[ -n "$EXE" ] && [ -f "$EXE" ] || recipe_hooks::die "Nicht installiert — Halo-EXE fehlt (Setup / Update prüfen)"

# Steam Non-Steam / library launch needs the Steam client (RUNE tip still applies).
if recipe_halo_campaign_evolved::steam_proton_wanted; then
    export HALO_ALLOW_STEAM=1
fi
recipe_halo_campaign_evolved::require_steam_stopped

# D3D12/DXVK + libvkd3d-utils (Proton-11-DXCore braucht wined3d/utils)
wine_runtime::deploy_proton_graphics_dlls || true
# RUNE-Pfad, MSVC-Runtime, libHttpClient, DirectML-Off — auch nach Updates erneut
recipe_halo_campaign_evolved::prepare_runtime "$EXE" || true

# Ohne Override: Wine-Builtins statt DXVK/vkd3d-proton → „GPU not supported“.
# steam_api64/RUNE64 native erzwingen (House-of-Ashes-Muster).
# gameinput=: Stub liefert Nullzeiger; lieber ganz weglassen.
# House-of-Ashes-Muster: Crack-DLLs native + winhttp native/builtin (Xbox-HTTP-Pfad).
# CRT native: libHttpClient needs the release's msvcp140 14.40+ (constexpr std::mutex);
# Wine's builtin would win over the installed native one and crash in _Mtx_lock.
HALO_CRT_OVERRIDE="msvcp140,msvcp140_1,msvcp140_2,msvcp140_atomic_wait,msvcp140_codecvt_ids,vcruntime140,vcruntime140_1,concrt140=n,b"
# dwmapi/version: UE4SS / Third-Person proxy when those mods are deployed
HALO_PROXY_OVERRIDE=""
[ -f "$(dirname "$EXE")/dwmapi.dll" ] && HALO_PROXY_OVERRIDE="${HALO_PROXY_OVERRIDE:+$HALO_PROXY_OVERRIDE,}dwmapi"
[ -f "$(dirname "$EXE")/version.dll" ] && HALO_PROXY_OVERRIDE="${HALO_PROXY_OVERRIDE:+$HALO_PROXY_OVERRIDE,}version"
HALO_PROXY_PART=""
[ -n "$HALO_PROXY_OVERRIDE" ] && HALO_PROXY_PART=";${HALO_PROXY_OVERRIDE}=n,b"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core,dxgi,d3d11,d3d10core,steam_api64,RUNE64,libHttpClient.Win32=n;${HALO_CRT_OVERRIDE}${HALO_PROXY_PART};winhttp=n,b;gameinput=}"
# RUNE/ElAmigos AppId (wie House-of-Ashes SteamAppId)
export SteamAppId="${SteamAppId:-2806050}"
export SteamGameId="${SteamGameId:-2806050}"
# XAL (Microsoft GDK) would spawn XALApp.exe for sign-in — missing / broken under
# Proton (endless spinner or failed sign-in). Always SteamDeck=1 so XAL signs in
# inside the game process (Proton issue 8814 / Gears of War: Reloaded). Not a
# Medizin toggle — required for this recipe under Proton-GE.
export SteamDeck=1

# Remember host DISPLAY before low-latency winewayland unsets it (gamescope needs it).
export HALO_HOST_DISPLAY="${DISPLAY:-}"

# Overlays off + NVIDIA shader cache + PowerMizer (host). Always — not Medizin.
recipe_halo_campaign_evolved::apply_host_perf || true

# Game must show a real window. RECIPE_WINE_SILENT=1 would otherwise wrap wine
# in xvfb/offscreen via recipe_wine_silent::run — kills winewayland + adds lag.
export RECIPE_WINE_SHOW_GUI=1

# Win64-EXE (Community: Meteorite/Binaries/Win64 — nicht Desktop-Shortcut).
# Optional BYOS trainer in the same prefix (Medizin → Trainer mitstarten).
# Without a co-process we can exec; with trainer we must wait on the game PID.
if recipe_halo_campaign_evolved::trainer_launch_enabled; then
    recipe_halo_campaign_evolved::run_game "$EXE" "$@" &
    _halo_game_pid=$!
    recipe_halo_campaign_evolved::spawn_trainer_after_delay || true
    wait "$_halo_game_pid"
    _rc=$?
    # Best-effort: stop trainer when the game exits (same wineserver is fine either way).
    _tr="$(recipe_halo_campaign_evolved::find_trainer_exe 2>/dev/null || true)"
    if [ -n "$_tr" ]; then
        pkill -f "$(basename "$_tr")" 2>/dev/null || true
    fi
    exit "$_rc"
fi

recipe_halo_campaign_evolved::run_game "$EXE" "$@"
