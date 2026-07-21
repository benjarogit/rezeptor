#!/usr/bin/env bash
# Baracuda/CE: MUSS denselben Steam-Proton nutzen wie das laufende ZA4
# und per "runinprefix" in dessen Prefix. Rezeptor-GE (wine-software/runtime)
# erzeugt eine fremde Session → Trainer startet nicht / stirbt sofort.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch
recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
recipe_hooks::_source env-file.sh 2>/dev/null || true

APPID_DEFAULT=694280

# Steam-Proton aus laufendem ZA4-Prozess (zuverlässigste Quelle).
za4_baracuda::proton_from_running_game() {
    local line=""
    line="$(pgrep -af 'compatibilitytools\.d/GE-Proton[^/]+/proton' 2>/dev/null \
        | grep -E 'ZombieArmy4|za4\.exe|za4_vulkan|za4_dx12|AppId=694280' \
        | head -1 || true)"
    [ -n "$line" ] || return 1
    if [[ "$line" =~ (/(home|mnt)/[^[:space:]]+/compatibilitytools\.d/GE-Proton[^/]+/proton) ]]; then
        [ -f "${BASH_REMATCH[1]}" ] || return 1
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Neuestes Steam GE-Proton (nie Rezeptor wine-software/runtime zuerst).
za4_baracuda::proton_steam_latest() {
    local steam_root="$1" p=""
    [ -d "$steam_root" ] || return 1
    if compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
        p="$(ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1)"
        [ -n "$p" ] && [ -f "$p" ] || return 1
        echo "$p"
        return 0
    fi
    return 1
}

trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo "$APPID_DEFAULT")"

steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

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

# Proton: 1) laufendes Spiel  2) Steam GE  3) gespeicherter Steam-Pfad (kein Rezeptor-GE)
proton=""
proton="$(za4_baracuda::proton_from_running_game 2>/dev/null || true)"
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    proton="$(za4_baracuda::proton_steam_latest "$steam_root" 2>/dev/null || true)"
fi
if [ -z "$proton" ] || [ ! -f "$proton" ]; then
    stored="$(recipe_hooks::state_get PROTON 2>/dev/null || true)"
    case "$stored" in
        */wine-software/runtime/*)
            stored=""
            ;;
    esac
    if [ -n "$stored" ] && [ -f "$stored" ]; then
        proton="$stored"
    fi
fi

if [ -z "$trainer" ] || [ ! -f "$trainer" ]; then
    work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
    if [ -n "$work" ] && [ -f "$work/ZA4-Trainer-Baracuda.exe" ]; then
        trainer="$work/ZA4-Trainer-Baracuda.exe"
    fi
fi

[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
    "Steam GE-Proton fehlt — in Steam unter Kompatibilität GE-Proton installieren"
[ -n "$trainer" ] && [ -f "$trainer" ] || recipe_hooks::die \
    "Trainer-EXE fehlt — bitte installieren (Baracuda-.exe wählen)"
[ -n "$compat" ] && [ -d "$compat" ] || recipe_hooks::die \
    "Steam compatdata für AppID $appid fehlt — Spiel einmal mit Proton starten"

game_running=0
if pgrep -f 'za4_(vulkan|dx12)\.exe' >/dev/null 2>&1; then
    game_running=1
fi
if [ "$game_running" -ne 1 ]; then
    recipe_hooks::die "Zombie Army 4 läuft nicht — zuerst das Spiel starten (Borderless), dann Trainer"
fi

# State + Wrapper auf korrekten Steam-Proton schreiben (Reparatur ohne Reinstall)
recipe_hooks::state_set SCRIPT_PATH ""
recipe_hooks::state_set TRAINER_EXE "$trainer"
recipe_hooks::state_set COMPATDATA "$compat"
recipe_hooks::state_set PROTON "$proton"
recipe_hooks::state_set STEAM_APPID "$appid"

wrapper="$DATA_ROOT/za4-trainer-baracuda-run.sh"
q_steam="$(printf '%q' "$steam_root")"
q_compat="$(printf '%q' "$compat")"
q_proton="$(printf '%q' "$proton")"
q_trainer="$(printf '%q' "$trainer")"
cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
STEAM_ROOT=$q_steam
COMPATDATA=$q_compat
PROTON=$q_proton
TRAINER=$q_trainer
if [[ ! -f "\$PROTON" || ! -f "\$TRAINER" || ! -d "\$COMPATDATA" ]]; then
  echo "Baracuda-Launcher: Pfade ungültig — in Rezeptor erneut Starten/Reparieren." >&2
  exit 1
fi
if ! pgrep -f 'za4_(vulkan|dx12)\\.exe' >/dev/null 2>&1; then
  echo "ZA4 läuft nicht — zuerst das Spiel starten." >&2
  exit 1
fi
export STEAM_COMPAT_CLIENT_INSTALL_PATH="\$STEAM_ROOT"
export STEAM_COMPAT_DATA_PATH="\$COMPATDATA"
unset PROTON_ENABLE_WAYLAND || true
exec "\$PROTON" runinprefix "\$TRAINER"
EOF
chmod +x "$wrapper"
recipe_hooks::state_set SCRIPT_PATH "$wrapper"

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_DATA_PATH="$compat"
unset PROTON_ENABLE_WAYLAND || true

output::info "Proton: $proton (runinprefix)"
recipe_notify::starting
exec "$proton" runinprefix "$trainer" "$@"
