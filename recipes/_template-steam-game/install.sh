#!/usr/bin/env bash
# Steam-Spiel — Ordner verknüpfen (kein Kopieren), Fix prüfen, Proton-Wrapper.
# Verteilt keine Spieldateien und keine Fix-Downloads (BYOS). Nur Proton-GE.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_hooks::log_setup "SteamGame_Install"

GAME_EXE="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo Game.exe)"
GAME_EXE="${GAME_EXE##*/}"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 0)"
FAKE_APPID="$(recipe_get "$RECIPE_YML" steam_fake_appid 2>/dev/null || echo 480)"
WIN64_REL="$(recipe_get "$RECIPE_YML" steam_fix_win64_rel 2>/dev/null || echo Binaries/Win64)"
STEAM_API_REL="$(recipe_get "$RECIPE_YML" steam_api_rel 2>/dev/null || true)"
WINEDLL_OVERRIDES='OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b'

spacewar_present() {
    local steam_root="${1:-}"
    local lib p
    for lib in "$steam_root" "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
        [ -d "$lib" ] || continue
        [ -f "$lib/steamapps/appmanifest_480.acf" ] && return 0
        [ -d "$lib/steamapps/common/Spacewar" ] && return 0
        if [ -f "$lib/steamapps/libraryfolders.vdf" ]; then
            while IFS= read -r p; do
                [ -f "$p/steamapps/appmanifest_480.acf" ] && return 0
                [ -d "$p/steamapps/common/Spacewar" ] && return 0
            done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$lib/steamapps/libraryfolders.vdf" \
                | sed -E 's/.*"([^"]+)"/\1/' || true)
        fi
    done
    for p in /mnt/*/SteamLibrary /mnt/*/*/SteamLibrary; do
        [ -f "$p/steamapps/appmanifest_480.acf" ] && return 0
        [ -d "$p/steamapps/common/Spacewar" ] && return 0
    done 2>/dev/null || true
    return 1
}

src="${RECIPE_SOURCE_ROOT:-}"
[ -n "$src" ] && [ -d "$src" ] || recipe_hooks::die \
    "Bitte den Spielordner mit $GAME_EXE im Install-Dialog wählen"
src="$(cd "$src" && pwd)"

output::section "Steam-Spiel — Einrichtung"
output::progress 5 "Einrichtung (kein Spiel-Kopieren)"
output::info "Nur prüfen + Launch-Wrapper — Spiel bleibt im Steam-/Spielordner"
output::progress 10 "Spielordner prüfen"
[ -f "$src/$GAME_EXE" ] || recipe_hooks::die "$GAME_EXE fehlt in: $src"

output::progress 20 "Steam / Spacewar ($FAKE_APPID)"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
[ -d "$steam_root" ] || recipe_hooks::die "Steam-Ordner nicht gefunden"
if [ "$FAKE_APPID" = "480" ]; then
    if spacewar_present "$steam_root"; then
        output::success "Spacewar (480) gefunden"
    else
        output::info "Spacewar (480) fehlt — Steam-Install öffnen, warte bis fertig…"
        if command -v steam >/dev/null 2>&1; then
            steam steam://install/480 >/dev/null 2>&1 &
        elif [ -x "$steam_root/steam.sh" ]; then
            "$steam_root/steam.sh" steam://install/480 >/dev/null 2>&1 &
        fi
        _sw_ok=0
        for _i in $(seq 1 120); do
            if spacewar_present "$steam_root"; then
                output::success "Spacewar (480) installiert"
                _sw_ok=1
                break
            fi
            [ $((_i % 6)) -eq 1 ] && output::info "Warte auf Spacewar… (${_i}/120)"
            sleep 5
        done
        [ "$_sw_ok" -eq 1 ] || recipe_hooks::die \
            "Spacewar (480) nicht fertig — steam://install/480, dann erneut"
    fi
fi

output::progress 30 "Online-Fix prüfen"
win64="$src/$WIN64_REL"
[ -d "$win64" ] || recipe_hooks::die "Fix-Ordner fehlt: $WIN64_REL"
fail=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$win64/$f" ]; then
        output::success "$WIN64_REL/$f"
    else
        output::error "Fehlt: $WIN64_REL/$f"
        fail=1
    fi
done < <(recipe_get "$RECIPE_YML" steam_fix_required 2>/dev/null | tr ',[]"' '    ' | xargs -n1 2>/dev/null || true)
# Fallback wenn Liste leer: Mindestanforderung
if [ -z "$(ls -A "$win64" 2>/dev/null || true)" ]; then
    fail=1
fi
if [ -f "$win64/OnlineFix.ini" ]; then
    if grep -qE "FakeAppId=${FAKE_APPID}" "$win64/OnlineFix.ini" \
        && grep -qE "RealAppId=${REAL_APPID}" "$win64/OnlineFix.ini"; then
        output::success "OnlineFix.ini AppIDs"
    else
        output::error "OnlineFix.ini: FakeAppId=${FAKE_APPID} / RealAppId=${REAL_APPID} erwartet"
        fail=1
    fi
fi
if [ -n "$STEAM_API_REL" ] && [ ! -f "$src/$STEAM_API_REL" ]; then
    output::error "Fehlt: $STEAM_API_REL"
    fail=1
fi
[ "$fail" -eq 0 ] || recipe_hooks::die "Online-Fix unvollständig (BYOS — Rezeptor liefert keinen Fix)"

output::progress 55 "Proton suchen"
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

output::progress 75 "Launch-Wrapper"
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

output::progress 100 "Einrichtung fertig"
[ -n "$compat" ] || output::warning "compatdata fehlt — Spiel einmal mit Proton starten, dann Reparieren"
output::success "Einrichtung OK: $src"
recipe_hooks::emit_log_paths
