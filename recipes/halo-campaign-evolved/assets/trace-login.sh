#!/usr/bin/env bash
# Halo CE — Live-Login-Trace (GDB attach an laufendes Wine/Proton).
#
# Empfohlen:
#   1. bash trace-login.sh --attach
#   2. Halo in Rezeptor starten
#   3. Schritt A: Enter wenn Spielfenster da
#   4. Schritt B: Enter am TITEL („[Enter] ZUM STARTEN DRÜCKEN“)
#   5. Warten auf „Continuing.“ → dann Enter IM SPIEL
#   6. [HIT]-Zeilen lesen; beenden: Ctrl+C → quit
#
# Bekannte Fallstricke (alle hier abgefangen):
#   - kein gdb|tee (Ctrl+C landet sonst nicht bei GDB)
#   - kein continue -a (all-stop → Fehler, Spiel bleibt stehen)
#   - kein „file EXE“ vor attach (exec-file-mismatch ask)
#   - kein bt (ohne Symbole → Prompt, Spiel friert)
#   - kein IsLoggedIn-Stub-BP (Hot-Path → Freeze)
#   - kein Attach während Intro
#   - keine EXE-Änderung: das Rezept patcht die Spieldatei nicht mehr
#   - debuginfod aus, pagination aus, SIGUSR1 nostop
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch

# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh"

ATTACH_ONLY=0
TRACE_KILL=0
FULL_BPS=0

usage() {
    cat <<'EOF'
Usage: trace-login.sh [--attach] [--kill] [--full]

  --attach   Terminal wartet; Spiel startet du in Rezeptor (empfohlen)
  --kill     hängendes Halo + Wine für Halo-Prefix beenden
  --full     mehr Breakpoints

Die Spieldatei ist immer unverändert — das Rezept patcht sie nicht.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --attach) ATTACH_ONLY=1 ;;
        --kill) TRACE_KILL=1 ;;
        --full) FULL_BPS=1 ;;
        -h | --help) usage; exit 0 ;;
        *)
            echo "Unbekannt: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

trace_login::resolve_prefix() {
    local exe="${1:-}" root
    if [ -n "$exe" ] && [[ "$exe" == *"/drive_c/"* ]]; then
        printf '%s\n' "${exe%%/drive_c/*}"
        return 0
    fi
    if [ -f "${HOME}/.local/share/wine-software/halo-campaign-evolved/data_root.path" ]; then
        root="$(tr -d '\r\n' <"${HOME}/.local/share/wine-software/halo-campaign-evolved/data_root.path")"
        [ -n "$root" ] && printf '%s\n' "${root}/prefix" && return 0
    fi
    [ -n "${WINEPREFIX:-}" ] && printf '%s\n' "$WINEPREFIX" && return 0
    return 1
}

trace_login::kill_stuck() {
    local prefix="$1" ws
    # /usr/bin/… — PATH kann „pkill“ durch andere Tools ersetzen
    # Kein pkill auf trace-login.sh — sonst killt --kill sich selbst.
    echo ">>> Beende Halo/GDB/Wine (WINEPREFIX=$prefix) …"
    /usr/bin/pkill -9 -f 'gdb -q' 2>/dev/null || true
    /usr/bin/pkill -9 -f 'HaloCampaignEvolved' 2>/dev/null || true
    sleep 1
    for ws in \
        "$HOME/.local/share/wine-software/runtime/proton-ge/GE-Proton11-3/files/bin/wineserver" \
        "$HOME/.local/share/wine-software/runtime/proton-ge/GE-Proton10-28/files/bin/wineserver"; do
        [ -x "$ws" ] || continue
        WINEPREFIX="$prefix" "$ws" -k 2>/dev/null || true
    done
    sleep 1
    if /usr/bin/pgrep -f 'HaloCampaignEvolved' >/dev/null 2>&1; then
        echo "Warnung: Halo noch aktiv — /usr/bin/pkill -9 -f HaloCampaignEvolved" >&2
        return 1
    fi
    echo ">>> Fertig."
}

if [ "$TRACE_KILL" -eq 1 ]; then
    EXE="$(recipe_halo_campaign_evolved::find_game_exe || true)"
    PREFIX="$(trace_login::resolve_prefix "$EXE" || true)"
    [ -n "$PREFIX" ] || PREFIX="/mnt/ssd2/Games/Halo Evolved/prefix"
    export WINEPREFIX="$PREFIX"
    trace_login::kill_stuck "$PREFIX"
    exit $?
fi

EXE="$(recipe_halo_campaign_evolved::find_game_exe || true)"
[ -n "$EXE" ] && [ -f "$EXE" ] || {
    echo "Halo-EXE fehlt — zuerst installieren/reparieren." >&2
    exit 1
}

recipe_halo_campaign_evolved::require_steam_stopped

PREFIX="$(trace_login::resolve_prefix "$EXE" || true)"
export WINEPREFIX="${PREFIX:-${WINEPREFIX:-}}"

# --attach: kein Proton-Init nötig (Rezeptor startet das Spiel)
if [ "$ATTACH_ONLY" -eq 0 ]; then
    export PROTON_GE_TAG="GE-Proton11-3"
    export PROTON_GE_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_GE_TAG}/${PROTON_GE_TAG}.tar.gz"
    export PROTON_GE_SHA256="861c2edc8d40d051fb1e7a692deb953be52bd339c46d90f2b7dde50ddad91266"
    recipe_hooks::runtime_init || exit 1
    # runtime.lock setzt Tag auf 10 — force 11 wie launch.sh
    export PROTON_GE_TAG="GE-Proton11-3"
    export PROTON_GE_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_GE_TAG}/${PROTON_GE_TAG}.tar.gz"
    export PROTON_GE_SHA256="861c2edc8d40d051fb1e7a692deb953be52bd339c46d90f2b7dde50ddad91266"
    wine_runtime::reset 2>/dev/null || true
    wine_runtime::init || exit 1
    wine_runtime::export_env || true
    wine_runtime::deploy_proton_graphics_dlls || true

    recipe_halo_campaign_evolved::prepare_runtime "$EXE" || true
fi

export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core,dxgi,d3d11,d3d10core,steam_api64,RUNE64,libHttpClient.Win32=n;winhttp=n,b;gameinput=}"
export SteamAppId="${SteamAppId:-2806050}"
export SteamGameId="${SteamGameId:-2806050}"
export DEBUGINFOD_URLS=

LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/wine-software/logs"
mkdir -p "$LOG_DIR"
TRACE_LOG="$LOG_DIR/halo-login-trace_$(date +%Y-%m-%d_%H-%M-%S).log"
GAME_LOG="${TRACE_LOG%.log}.game.log"
GDB_CMD="$(mktemp)"

cleanup() {
    rm -f "$GDB_CMD"
}
trap cleanup EXIT

trace_login::find_pe_pid() {
    local pid maps
    for pid in $(/usr/bin/pgrep -f 'HaloCampaignEvolved' 2>/dev/null | sort -u); do
        maps="/proc/$pid/maps"
        [ -r "$maps" ] || continue
        if grep -qE '^140000000-' "$maps" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
    done
    return 1
}

# Eine Breakpoint-Zeile: printf + continue (kein define/bt — Fehler dort frieren das Spiel ein)
trace_login::bp() {
    local addr="$1" name="$2"
    cat <<EOF
break *${addr}
commands
  silent
  printf "\\n[HIT] ${name} @ %p\\n", \$pc
  continue
end

EOF
}

trace_login::write_breakpoints() {
    # VAs gelten für die unveränderte EXE (ImageBase 0x140000000).
    trace_login::bp 0x0000000146E8A2A3 Title_LoginUI_Branch_je
    trace_login::bp 0x0000000146E8A2B0 Title_IsLoggedIn_vtable
    trace_login::bp 0x0000000146E8A2C3 Title_Enter_Fail_jz
    trace_login::bp 0x0000000146E8A3C5 SignIn_UI_rcx_test
    trace_login::bp 0x0000000146E8A4D3 SignIn_XAL_Call
    trace_login::bp 0x0000000146E8A736 Title_Success_Epilog
    trace_login::bp 0x0000000146E88598 UMG_LoginWidget_Entry
    trace_login::bp 0x0000000146E2C5F0 XAL_LoginAsync_Start
    if [ "$FULL_BPS" -eq 1 ]; then
        trace_login::bp 0x0000000146E55200 BuildLoginErrorString
        trace_login::bp 0x0000000146E23820 ShowLoginErrorModal
        trace_login::bp 0x0000000146E7D839 Alpha_Switch_A
        trace_login::bp 0x0000000146E7E0A7 Alpha_Switch_B
    fi
}

{
    echo "set pagination off"
    echo "set height 0"
    echo "set width 0"
    echo "set confirm off"
    echo "set debuginfod enabled off"
    echo "set exec-file-mismatch off"
    echo "set print thread-events off"
    echo "set scheduler-locking off"
    echo "set architecture i386:x86-64"
    # all-stop (Standard): continue ohne -a. non-stop+Wine = oft kaputt.
    echo "handle SIGSEGV nostop noprint pass"
    echo "handle SIGPIPE nostop noprint pass"
    echo "handle SIGUSR1 nostop noprint pass"
    echo "handle SIGUSR2 nostop noprint pass"
    echo "set logging file $TRACE_LOG"
    echo "set logging overwrite off"
    echo "set logging redirect off"
    echo "set logging enabled on"
    echo ""
    # hook-quit: detach, damit Spiel nach quit weiterläuft
    cat <<'EOF'
define hook-quit
  detach
end
EOF
    echo ""
    trace_login::write_breakpoints
    echo 'printf "\n=== Login-Trace AKTIV ===\n"'
    echo 'printf "Jetzt IM SPIEL Enter drücken. [HIT]-Zeilen erscheinen hier.\n"'
    echo 'printf "Beenden: Ctrl+C → quit   |  Notfall: trace-login.sh --kill\n\n"'
} >"$GDB_CMD"

cd "$(dirname "$EXE")" || exit 1
EXE_BASE="$(basename "$EXE")"

{
    echo "=== Halo Login-Trace $(date -Iseconds) ==="
    echo "ATTACH_ONLY=$ATTACH_ONLY FULL_BPS=$FULL_BPS"
    echo "EXE=$EXE"
    echo "WINEPREFIX=${WINEPREFIX:-}"
    echo "WINE=${WINE:-n/a}"
    echo "GDB=$(gdb --version | head -1)"
    echo "---"
} | tee "$TRACE_LOG"

if [ "$ATTACH_ONLY" -eq 0 ]; then
    echo ""
    echo ">>> Starte Spiel (Proton ${PROTON_GE_TAG:-?}) …"
    # shellcheck disable=SC2086
    "$WINE" "./$EXE_BASE" >>"$GAME_LOG" 2>&1 &
    sleep 2
fi

echo ""
if [ "$ATTACH_ONLY" -eq 1 ]; then
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  SCHRITT A — Halo in Rezeptor starten                        ║"
    echo "║  Enter hier, sobald das SPIELFENSTER sichtbar ist.           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    read -r _
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SCHRITT B — Warten bis TITEL:                               ║"
echo "║  „HALO CAMPAIGN EVOLVED“ + „[Enter] ZUM STARTEN DRÜCKEN“     ║"
echo "║  NICHT während Xbox-Intro Enter!                             ║"
echo "║  ERST am Titel → Enter hier → GDB hängt an.                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
read -r _

TARGET_PID=""
echo ">>> Suche Halo (ImageBase 0x140000000) …"
for i in $(seq 1 90); do
    TARGET_PID="$(trace_login::find_pe_pid || true)"
    [ -n "$TARGET_PID" ] && break
    [ $((i % 10)) -eq 0 ] && echo "    … ${i}s"
    sleep 1
done

[ -n "$TARGET_PID" ] || {
    echo "Kein Halo-Prozess gefunden." >&2
    exit 1
}

echo ""
echo ">>> Attach PID $TARGET_PID"
echo ">>> Log: $TRACE_LOG"
echo ">>> Nach „Continuing.“ / „Login-Trace AKTIV“ → Enter IM SPIEL"
echo ""

# GDB im Vordergrund (kein tee!) — Ctrl+C geht an GDB
# Kein „file EXE“, kein „continue -a“
gdb -q \
    -iex 'set debuginfod enabled off' \
    -iex 'set pagination off' \
    -iex 'set height 0' \
    -iex 'set width 0' \
    -iex 'set confirm off' \
    -iex 'set exec-file-mismatch off' \
    -iex 'set print thread-events off' \
    -p "$TARGET_PID" \
    -x "$GDB_CMD" \
    -ex 'continue'

cleanup
