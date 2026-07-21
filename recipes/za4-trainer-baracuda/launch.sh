#!/usr/bin/env bash
# Baracuda/CE-Trainer: in den laufenden Steam-Prefix (runinprefix), nicht als
# eigener wineserver — sonst startet er oft nur einmal.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch
recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
recipe_hooks::_source env-file.sh 2>/dev/null || true

trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
proton="$(recipe_hooks::state_get PROTON 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 694280)"

steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

# compatdata / Proton immer frisch auflösen (Wrapper-Pfade werden schnell stale)
if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    for lib in "$steam_root" /mnt/*/SteamLibrary "$HOME"/.local/share/Steam; do
        [ -d "$lib/steamapps/compatdata/$appid" ] || continue
        compat="$lib/steamapps/compatdata/$appid"
        break
    done
fi
if [ -z "$compat" ] || [ ! -d "$compat" ]; then
    if [ -f "$steam_root/steamapps/libraryfolders.vdf" ]; then
        while IFS= read -r p; do
            [ -d "$p/steamapps/compatdata/$appid" ] || continue
            compat="$p/steamapps/compatdata/$appid"
            break
        done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$steam_root/steamapps/libraryfolders.vdf" \
            | sed -E 's/.*"([^"]+)"/\1/' || true)
    fi
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
    work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
    if [ -n "$work" ] && [ -f "$work/ZA4-Trainer-Baracuda.exe" ]; then
        trainer="$work/ZA4-Trainer-Baracuda.exe"
    fi
fi

[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
    "Proton-GE fehlt — Rezeptor-Runtime oder Steam GE-Proton installieren"
[ -n "$trainer" ] && [ -f "$trainer" ] || recipe_hooks::die \
    "Trainer-EXE fehlt — bitte installieren (Baracuda-.exe wählen)"
[ -n "$compat" ] && [ -d "$compat" ] || recipe_hooks::die \
    "Steam compatdata für AppID $appid fehlt — Spiel einmal mit Proton starten"

# Alte CE-/Trainer-Reste wegräumen (ohne wineserver -k am Spiel-Prefix!)
pkill -f 'ZA4-Trainer-Baracuda\.exe' 2>/dev/null || true
pkill -f '[Cc]heat[Ee]ngine' 2>/dev/null || true
pkill -f 'CET_TRAINER' 2>/dev/null || true
sleep 0.3

game_running=0
if pgrep -f 'za4_(vulkan|dx12)\.exe' >/dev/null 2>&1; then
    game_running=1
fi
if [ "$game_running" -ne 1 ]; then
    output::warning "ZA4 läuft nicht — Baracuda braucht das laufende Spiel (Borderless empfohlen)."
    recipe_hooks::die "Bitte zuerst Zombie Army 4 starten, dann den Trainer erneut starten"
fi

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_DATA_PATH="$compat"
unset PROTON_ENABLE_WAYLAND || true

# State aktualisieren (Reparatur / nächster Start)
recipe_hooks::state_set TRAINER_EXE "$trainer"
recipe_hooks::state_set COMPATDATA "$compat"
recipe_hooks::state_set PROTON "$proton"
recipe_hooks::state_set STEAM_APPID "$appid"

recipe_notify::starting
# runinprefix = gleicher wineserver wie das Spiel (CE-Injection)
exec "$proton" runinprefix "$trainer" "$@"
