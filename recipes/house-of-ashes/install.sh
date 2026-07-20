#!/usr/bin/env bash
# House of Ashes — Spielordner verknüpfen (kein Kopieren), Fix prüfen, Proton-Wrapper.
# Verteilt keine Spieldateien und keine Fix-Downloads (BYOS).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_hooks::log_setup "HouseOfAshes_Install"

GAME_EXE="HouseOfAshes.exe"
REAL_APPID="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 1281590)"
FAKE_APPID="480"
WIN64_REL="SMG025/Binaries/Win64"
STEAM_API_REL="Engine/Binaries/ThirdParty/Steamworks/Steamv147/Win64/steam_api64.dll"
REQUIRED_WIN64=(OnlineFix64.dll OnlineFix.ini winmm.dll StubDRM64.dll dlllist.txt)
WINEDLL_OVERRIDES='OnlineFix64=n;SteamOverlay64=n;winmm=n,b;dnet=n;steam_api64=n;winhttp=n,b'

# Spacewar (AppID 480) = Fake Steam-Titel für den Online-Fix. Nicht optional.
hoa_spacewar_present() {
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
    # Extra libraries under /mnt
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

output::section "House of Ashes — Einrichtung"
output::progress 5 "Einrichtung (kein Spiel-Kopieren)"
output::info "Nur prüfen + Launch-Wrapper — Spiel bleibt im Steam-/Spielordner"
output::info "Start später NUR über Rezeptor (kein neuer Steam-Bibliothekseintrag)"
output::progress 10 "Spielordner prüfen"
output::info "Quelle: $src"

[ -f "$src/$GAME_EXE" ] || recipe_hooks::die \
    "$GAME_EXE fehlt in: $src"

output::progress 20 "Steam / Spacewar (480)"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
if [ ! -d "$steam_root" ]; then
    recipe_hooks::die "Steam-Ordner nicht gefunden (~/.local/share/Steam). Steam installieren und anmelden."
fi
if hoa_spacewar_present "$steam_root"; then
    output::success "Spacewar (AppID 480) in Steam gefunden"
else
    output::warning "Spacewar (AppID 480) fehlt — Online-Fix meldet sich als Spacewar"
    output::info "Steam-Installationsdialog wird geöffnet — warte bis Spacewar fertig ist…"
    if command -v steam >/dev/null 2>&1; then
        steam steam://install/480 >/dev/null 2>&1 &
    elif [ -x "$steam_root/steam.sh" ]; then
        "$steam_root/steam.sh" steam://install/480 >/dev/null 2>&1 &
    else
        output::warning "Steam-CLI nicht gefunden — manuell: Bibliothek → Tools → Spacewar"
    fi
    # Bis 10 Min pollen — nicht „fertig“ melden während Steam noch lädt.
    _sw_ok=0
    for _i in $(seq 1 120); do
        if hoa_spacewar_present "$steam_root"; then
            output::success "Spacewar (AppID 480) installiert"
            _sw_ok=1
            break
        fi
        if [ $((_i % 6)) -eq 1 ]; then
            output::info "Warte auf Spacewar… (${_i}/120, je ~5s) — in Steam bestätigen falls nötig"
        fi
        sleep 5
    done
    if [ "$_sw_ok" -eq 0 ]; then
        recipe_hooks::die \
            "Spacewar (480) nicht rechtzeitig fertig — in Steam installieren, dann erneut Installieren/Reparieren"
    fi
fi

output::progress 30 "Online-Fix prüfen"
win64="$src/$WIN64_REL"
fail=0
[ -d "$win64" ] || {
    output::error "Ordner fehlt: $WIN64_REL"
    fail=1
}
if [ -d "$win64" ]; then
    for f in "${REQUIRED_WIN64[@]}"; do
        if [ -f "$win64/$f" ]; then
            output::success "$WIN64_REL/$f"
        else
            output::error "Fehlt: $WIN64_REL/$f"
            fail=1
        fi
    done
    if [ -f "$win64/OnlineFix.ini" ]; then
        if grep -qE "FakeAppId=${FAKE_APPID}" "$win64/OnlineFix.ini" \
            && grep -qE "RealAppId=${REAL_APPID}" "$win64/OnlineFix.ini"; then
            output::success "OnlineFix.ini AppIDs ($FAKE_APPID / $REAL_APPID)"
        else
            output::error "OnlineFix.ini: erwartet FakeAppId=${FAKE_APPID} und RealAppId=${REAL_APPID}"
            fail=1
        fi
    fi
fi
if [ -f "$src/$STEAM_API_REL" ]; then
    output::success "steam_api64.dll"
else
    output::error "Fehlt: $STEAM_API_REL"
    fail=1
fi
[ "$fail" -eq 0 ] || recipe_hooks::die \
    "Online-Fix unvollständig — Stack TDPAHOA_Fix_Repair_Steam_Generic selbst in den Spielordner legen (Rezeptor verteilt keinen Fix)"

output::progress 55 "Steam / Proton suchen"
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

output::progress 75 "Launch-Wrapper"
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

recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
if type recipe_notify::recipe >/dev/null 2>&1; then
    recipe_notify::recipe "Einrichtung fertig — Starten möglich" "Spielordner verknüpft (kein Kopieren)"
elif type recipe_notify::send >/dev/null 2>&1; then
    notify_title="$(recipe_get "$RECIPE_YML" notify_title 2>/dev/null || true)"
    [ -n "$notify_title" ] || notify_title="$(recipe_get "$RECIPE_YML" name)"
    recipe_notify::send "$notify_title" "Einrichtung fertig — Starten möglich" "Spielordner verknüpft (kein Kopieren)"
fi

output::progress 100 "Einrichtung fertig"
if [ -z "$compat" ]; then
    output::warning "compatdata AppID $REAL_APPID fehlt — Spiel einmal mit Proton starten, dann Reparieren"
fi
output::success "Einrichtung OK (Sekunden normal — kein Spiel-Download/Kopieren): $src"
recipe_hooks::emit_log_paths
