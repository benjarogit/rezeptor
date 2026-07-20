#!/usr/bin/env bash
# Startet den Trainer wie ~/Downloads/za4-trainer.sh — über Proton + Steam compatdata.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch
recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
recipe_hooks::_source env-file.sh 2>/dev/null || true

script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
proton="$(recipe_hooks::state_get PROTON 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 694280)"

steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

# Fallback: wie Referenzskript (Documents im compatdata)
if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    compat="/mnt/ssd2/SteamLibrary/steamapps/compatdata/${appid}"
    [ -d "$compat" ] || compat="$steam_root/steamapps/compatdata/${appid}"
fi
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    if type wine_runtime::resolve_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_proton_script "$steam_root" 2>/dev/null || true)"
    fi
fi
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    if compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
        proton="$(ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1)"
    fi
fi
if [ -z "$trainer" ] || [ ! -f "$trainer" ]; then
    # Install-Ziel oder klassischer Documents-Pfad
    work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
    if [ -n "$work" ] && [ -f "$work/ZA4-Trainer.exe" ]; then
        trainer="$work/ZA4-Trainer.exe"
    elif [ -f "$compat/pfx/drive_c/users/steamuser/Documents/ZA4-Trainer/ZA4-Trainer.exe" ]; then
        trainer="$compat/pfx/drive_c/users/steamuser/Documents/ZA4-Trainer/ZA4-Trainer.exe"
    fi
fi

# Bevorzugt den bei Install geschriebenen Wrapper (identisch zur Referenz-Logik)
if [ -n "$script" ] && [ -x "$script" ]; then
    recipe_notify::starting
    exec "$script" "$@"
fi

[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
    "Proton-GE fehlt — Rezeptor-Runtime oder Steam GE-Proton installieren"
[ -n "$trainer" ] && [ -f "$trainer" ] || recipe_hooks::die \
    "Trainer-EXE fehlt — bitte installieren (ZA4-Trainer.exe wählen)"
[ -n "$compat" ] && [ -d "$compat" ] || recipe_hooks::die \
    "Steam compatdata für AppID $appid fehlt — Spiel einmal mit Proton starten"

if ! pgrep -f 'za4_(vulkan|dx12)\.exe' >/dev/null 2>&1; then
    echo "Hinweis: ZA4 scheint nicht zu laufen. Trainer erst NACH dem Spielstart ausführen."
fi

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_DATA_PATH="$compat"
unset PROTON_ENABLE_WAYLAND || true

recipe_notify::starting
exec "$proton" run "$trainer" "$@"
