#!/usr/bin/env bash
# Trainer im gleichen Steam-Prefix wie ZA4 — runinprefix (kein Prefix-Downgrade).
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

if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    compat="/mnt/ssd2/SteamLibrary/steamapps/compatdata/${appid}"
    [ -d "$compat" ] || compat="$steam_root/steamapps/compatdata/${appid}"
fi

expected_proton=""
if type wine_runtime::resolve_compatdata_proton_script >/dev/null 2>&1; then
    expected_proton="$(wine_runtime::resolve_compatdata_proton_script "$steam_root" "$compat" 2>/dev/null || true)"
fi
if [ -n "$expected_proton" ] && [ -f "$expected_proton" ]; then
    proton="$expected_proton"
elif [ -z "$proton" ] || [ ! -f "$proton" ]; then
    if type wine_runtime::resolve_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_proton_script "$steam_root" 2>/dev/null || true)"
    fi
fi

if [ -z "$trainer" ] || [ ! -f "$trainer" ]; then
    work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
    if [ -n "$work" ] && [ -f "$work/ZA4-Trainer.exe" ]; then
        trainer="$work/ZA4-Trainer.exe"
    elif [ -f "$compat/pfx/drive_c/users/steamuser/Documents/ZA4-Trainer/ZA4-Trainer.exe" ]; then
        trainer="$compat/pfx/drive_c/users/steamuser/Documents/ZA4-Trainer/ZA4-Trainer.exe"
    fi
fi

# Wrapper nur wenn Proton passt und runinprefix nutzt (alter "run"+Rezeptor-GE-Wrapper startet nicht)
if [ -n "$script" ] && [ -x "$script" ]; then
    wrapper_proton="$(grep -m1 '^PROTON=' "$script" 2>/dev/null | sed 's/^PROTON=//' || true)"
    if grep -q 'runinprefix' "$script" 2>/dev/null \
        && { [ -z "$expected_proton" ] || [ ! -f "$expected_proton" ] || [ "$wrapper_proton" = "$expected_proton" ]; }; then
        recipe_notify::starting
        exec "$script" "$@"
    fi
fi

[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
    "Proton-GE fehlt — Steam GE-Proton (Spiel-Prefix) oder Rezeptor-Runtime installieren"
[ -n "$trainer" ] && [ -f "$trainer" ] || recipe_hooks::die \
    "Trainer-EXE fehlt — bitte installieren (ZA4-Trainer.exe wählen)"
[ -n "$compat" ] && [ -d "$compat" ] || recipe_hooks::die \
    "Steam compatdata für AppID $appid fehlt — Spiel einmal mit Proton starten"

if ! pgrep -f 'za4_(vulkan|dx12)\.exe' >/dev/null 2>&1; then
    echo "Hinweis: ZA4 scheint nicht zu laufen — erst Spiel in Steam starten (Borderless Window), dann Trainer."
else
    echo "Hinweis: ZA4 läuft. Grafikmodus Borderless Window empfohlen (nicht exklusives Vollbild)."
fi

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_DATA_PATH="$compat"
unset PROTON_ENABLE_WAYLAND || true

recipe_notify::starting
# runinprefix: gleicher Prefix/Wineserver wie das laufende Spiel — kein Downgrade via "run"
exec "$proton" runinprefix "$trainer" "$@"
