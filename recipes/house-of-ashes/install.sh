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

output::progress 25 "Online-Fix (optional)"
fix_src="${RECIPE_FIX_ROOT:-}"
merge_rel="${RECIPE_FIX_MERGE_PATH:-$WIN64_REL}"
if [ -n "$fix_src" ] && [ -d "$fix_src" ]; then
    # shellcheck source=/dev/null
    source "$RECIPE_DIR/../../core/recipe-online-fix.sh"
    recipe_online_fix::merge "$src" "$fix_src" "$merge_rel" || recipe_hooks::die \
        "Online-Fix konnte nicht kopiert werden: $fix_src"
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
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-house-of-ashes.sh"
hoa::write_launch_wrapper "$src"

recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
if type recipe_notify::recipe >/dev/null 2>&1; then
    recipe_notify::recipe "Einrichtung fertig — Starten möglich" "Spielordner verknüpft (kein Kopieren)"
elif type recipe_notify::send >/dev/null 2>&1; then
    notify_title="$(recipe_get "$RECIPE_YML" notify_title 2>/dev/null || true)"
    [ -n "$notify_title" ] || notify_title="$(recipe_get "$RECIPE_YML" name)"
    recipe_notify::send "$notify_title" "Einrichtung fertig — Starten möglich" "Spielordner verknüpft (kein Kopieren)"
fi

output::progress 100 "Einrichtung fertig"
output::success "Einrichtung OK (Sekunden normal — kein Spiel-Download/Kopieren): $src"
recipe_hooks::emit_log_paths
