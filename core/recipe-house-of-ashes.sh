#!/usr/bin/env bash
# House of Ashes — Launch-Wrapper / Proton / State (von install + repair genutzt).
# Erwartet: DATA_ROOT, RECIPE_YML, recipe_hooks::*, wine_runtime (optional).
# Parameter: $1 = Spielordner (absolut).

hoa::write_launch_wrapper() {
    local src="${1:?game dir}"
    local steam_root compat proton wrapper
    local q_steam q_compat q_proton q_exe q_dll
    local GAME_EXE="${GAME_EXE:-HouseOfAshes.exe}"
    local REAL_APPID="${REAL_APPID:-1281590}"
    local FAKE_APPID="${FAKE_APPID:-480}"
    local WINEDLL_OVERRIDES="${WINEDLL_OVERRIDES:-OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b}"

    [ -n "$src" ] && [ -d "$src" ] || return 1
    [ -f "$src/$GAME_EXE" ] || recipe_hooks::die "$GAME_EXE fehlt in: $src"

    steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
    [ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

    compat=""
    for lib in "$steam_root" /mnt/*/SteamLibrary "$HOME"/.local/share/Steam; do
        [ -d "$lib/steamapps/compatdata/$REAL_APPID" ] || continue
        compat="$lib/steamapps/compatdata/$REAL_APPID"
        break
    done
    if [ -z "$compat" ] && [ -f "$steam_root/steamapps/libraryfolders.vdf" ]; then
        while IFS= read -r p; do
            [ -d "$p/steamapps/compatdata/$REAL_APPID" ] || continue
            compat="$p/steamapps/compatdata/$REAL_APPID"
            break
        done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$steam_root/steamapps/libraryfolders.vdf" \
            | sed -E 's/.*"([^"]+)"/\1/' || true)
    fi

    proton=""
    if type wine_runtime::resolve_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_proton_script "$steam_root" 2>/dev/null || true)"
    fi
    if [ -z "$proton" ] || [ ! -f "$proton" ]; then
        if compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
            proton="$(ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1)"
        elif compgen -G "$steam_root/steamapps/common/Proton"*/proton >/dev/null 2>&1; then
            proton="$(ls -1d "$steam_root/steamapps/common"/Proton*/proton 2>/dev/null | sort -V | tail -1)"
        fi
    fi
    [ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
        "Proton-GE fehlt — Rezeptor-Runtime oder Steam GE-Proton installieren"

    wrapper="$DATA_ROOT/house-of-ashes-run.sh"
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
if [[ ! -f "\$PROTON" ]]; then
  echo "Proton nicht gefunden: \$PROTON" >&2
  exit 1
fi
if [[ ! -f "\$GAME_EXE" ]]; then
  echo "Spiel-EXE fehlt: \$GAME_EXE" >&2
  exit 1
fi
if [[ -z "\$COMPATDATA" || ! -d "\$COMPATDATA" ]]; then
  echo "Steam compatdata für AppID \$APPID fehlt — Spiel einmal unter Proton starten." >&2
  exit 1
fi
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

    if [ -z "$compat" ]; then
        output::warning "compatdata AppID $REAL_APPID fehlt — Spiel einmal mit Proton starten, dann Reparieren"
    fi
}
