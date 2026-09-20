#!/usr/bin/env bash
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
source "$RECIPE_DIR/helpers.sh"

_guaranteed="$(recipe_get "$RECIPE_YML" version_guaranteed 2>/dev/null || true)"
export WINEPREFIX="${DATA_ROOT}/prefix"
failures=0

output::progress_begin 6 "Prüfen"

output::progress_tick "Prefix & Arbeitsordner"
if ! recipe_hooks::validate_prefix; then
    failures=$((failures + 1))
fi
if ! recipe_hooks::validate_work_root WORK_ROOT; then
    failures=$((failures + 1))
fi

output::progress_tick "EXE"
WORK_ROOT="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
GAME_DIR="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
EXE="$(prototype::find_exe "${GAME_DIR:-${WORK_ROOT:-}}" 2>/dev/null || true)"
if [ -n "$EXE" ] && [ -f "$EXE" ]; then
    recipe_validate::ok "EXE: $(basename "$EXE")"
else
    recipe_validate::fail "Keine prototypef.exe im Arbeitsordner"
    failures=$((failures + 1))
fi

output::progress_tick "Spieldateien"
if [ -n "$EXE" ] && [ -f "$(dirname "$EXE")/prototypeenginef.dll" ]; then
    recipe_validate::ok "Engine: prototypeenginef.dll"
else
    recipe_validate::fail "prototypeenginef.dll fehlt neben der EXE"
    failures=$((failures + 1))
fi
if [ -n "$EXE" ] && [ -f "$(dirname "$EXE")/art.rcf" ]; then
    recipe_validate::ok "Daten: art.rcf"
else
    recipe_validate::warn "art.rcf fehlt — Quelle unvollständig?"
fi

output::progress_tick "DX9"
if recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/syswow64/d3d9.dll" 2>/dev/null \
    || [ -f "$WINEPREFIX/drive_c/windows/syswow64/d3d9.dll" ]; then
    recipe_validate::ok "D3D9: DLL im Prefix"
else
    recipe_validate::fail "D3D9 fehlt im Prefix — Reparieren"
    failures=$((failures + 1))
fi

output::progress_tick "Mod-Bundle"
if prototype::mod_bundle_on; then
    if [ -n "$EXE" ] && prototype::bundle_critical_ok "$(dirname "$EXE")"; then
        recipe_validate::ok "Mod-Bundle $(prototype::bundle_version) (Sprache=$(prototype::language_id), Skin=$(prototype::skin_id), Parkour=$(prototype::parkour_on && echo on || echo off), PS3=$(prototype::ps3_buttons_on && echo on || echo off), Save100=$(prototype::save_100_on && echo on || echo off), Sprint-Fix)"
    else
        recipe_validate::fail "Mod-Bundle fehlt, veraltet oder unvollständig — Reparieren"
        failures=$((failures + 1))
    fi
    if [ -f "${WINEPREFIX}/dxvk.conf" ] && grep -q 'dxvk.numCompilerThreads' "${WINEPREFIX}/dxvk.conf"; then
        recipe_validate::ok "DXVK: 32-Bit-dxvk.conf (wenige Compiler-Threads)"
    else
        recipe_validate::fail "DXVK-dxvk.conf fehlt — Reparieren (sonst SURFACE_LOST/OOM nach Continue)"
        failures=$((failures + 1))
    fi
else
    recipe_validate::ok "Mod-Bundle aus (Medizin)"
fi

output::progress_tick "Host"
if prototype::pulse32_ok; then
    recipe_validate::ok "Audio: 32-Bit Pulse (libpulse) vorhanden"
else
    recipe_validate::warn "32-Bit Pulse fehlt (/usr/lib32/libpulse.so.0) — Paket lib32-libpulse. winepulse kann c0000135 loggen."
fi
if [ -n "$EXE" ]; then
    if prototype::laa_set "$EXE"; then
        recipe_validate::ok "EXE: LARGE_ADDRESS_AWARE"
    else
        recipe_validate::warn "EXE ohne LARGE_ADDRESS_AWARE — Reparieren setzt das Flag"
    fi
fi

recipe_validate::app_link

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
