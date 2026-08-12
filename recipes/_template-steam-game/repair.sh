#!/usr/bin/env bash
# Steam-Template: validate → Launch-Wrapper/Proton-Pfade neu (kein exec install.sh).
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
recipe_hooks::load repair

GAME_EXE="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo Game.exe)"
GAME_EXE="${GAME_EXE##*/}"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 0)"
FAKE_APPID="$(recipe_get "$RECIPE_YML" steam_fake_appid 2>/dev/null || echo 480)"
WINEDLL_OVERRIDES='OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b'

steam_game_write_wrapper() {
    local src="${1:?}"
    local steam_root compat proton wrapper
    local q_steam q_compat q_proton q_exe q_dll

    [ -f "$src/$GAME_EXE" ] || recipe_hooks::die "$GAME_EXE fehlt in: $src"

    steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
    [ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

    proton=""
    if type wine_runtime::resolve_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_proton_script "$steam_root" 2>/dev/null || true)"
    fi
    if [ -z "$proton" ] || [ ! -f "$proton" ]; then
        if compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
            proton="$(ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1)"
        fi
    fi
    [ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die "Proton-GE fehlt"

    compat=""
    for lib in "$steam_root" /mnt/*/SteamLibrary "$HOME"/.local/share/Steam; do
        [ -d "$lib/steamapps/compatdata/$REAL_APPID" ] || continue
        compat="$lib/steamapps/compatdata/$REAL_APPID"
        break
    done

    wrapper="$DATA_ROOT/steam-game-run.sh"
    mkdir -p "$DATA_ROOT"
    q_steam="$(printf '%q' "$steam_root")"
    q_compat="$(printf '%q' "$compat")"
    q_proton="$(printf '%q' "$proton")"
    q_exe="$(printf '%q' "$src/$GAME_EXE")"
    q_dll="$(printf '%q' "$WINEDLL_OVERRIDES")"
    cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
APPID=$REAL_APPID
FAKE_APPID=$FAKE_APPID
STEAM_ROOT=$q_steam
COMPATDATA=$q_compat
PROTON=$q_proton
GAME_EXE=$q_exe
export WINEDLLOVERRIDES=$q_dll
export SteamAppId=\$FAKE_APPID
export SteamGameId=\$FAKE_APPID
[[ -f "\$PROTON" ]] || { echo "Proton fehlt: \$PROTON" >&2; exit 1; }
[[ -f "\$GAME_EXE" ]] || { echo "EXE fehlt: \$GAME_EXE" >&2; exit 1; }
[[ -n "\$COMPATDATA" && -d "\$COMPATDATA" ]] || {
  echo "compatdata AppID \$APPID fehlt — Spiel einmal mit Proton starten." >&2
  exit 1
}
export STEAM_COMPAT_CLIENT_INSTALL_PATH="\$STEAM_ROOT"
export STEAM_COMPAT_DATA_PATH="\$COMPATDATA"
unset PROTON_ENABLE_WAYLAND || true
cd "\$(dirname "\$GAME_EXE")"
exec "\$PROTON" run "\$GAME_EXE" "\$@"
EOF
    chmod +x "$wrapper"

    recipe_hooks::state_set SCRIPT_PATH "$wrapper"
    recipe_hooks::state_set WORK_ROOT "$src"
    recipe_hooks::state_set GAME_DIR "$src"
    recipe_hooks::state_set GAME_EXE "$src/$GAME_EXE"
    recipe_hooks::state_set STEAM_APPID "$REAL_APPID"
    recipe_hooks::state_set FAKE_STEAM_APPID "$FAKE_APPID"
    [ -n "$compat" ] && recipe_hooks::state_set COMPATDATA "$compat"
    [ -n "$proton" ] && recipe_hooks::state_set PROTON "$proton"
    if type recipe_app_link::ensure >/dev/null 2>&1; then
        recipe_app_link::ensure || true
    fi
}

output::progress_begin 3 "Reparatur"
if [ -f "$RECIPE_DIR/validate.sh" ] && bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    exit 0
fi

output::progress_tick "Spielordner / Wrapper"
game_dir="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
[ -n "$game_dir" ] || game_dir="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
    output::progress_done "Spielordner unbekannt — Installieren erneut"
    exit 1
fi

steam_game_write_wrapper "$game_dir"

if [ -f "$RECIPE_DIR/validate.sh" ] && bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig"
exit 1
