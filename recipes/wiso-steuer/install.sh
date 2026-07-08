#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
export PROJECT_ROOT RECIPE_DIR CORE_DIR

# shellcheck source=/dev/null
source "$CORE_DIR/paths.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe.sh"
recipe_export_env "$RECIPE_DIR/recipe.yml"
# shellcheck source=/dev/null
source "$CORE_DIR/security.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$CORE_DIR/env-file.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/output.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/wine-runtime.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-prefix.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-winetricks.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-win10.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-dotnet.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-wiso.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-vcrun.sh"

wine() { wine_runtime::wine "$@"; }
winetricks() { wine_runtime::winetricks "$@"; }
wineboot() { wine_runtime::wineboot "$@"; }

LOG_DIR="$(wine_software_logs_dir)"
mkdir -p "$LOG_DIR"
TIMESTAMP_ISO=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$LOG_DIR/WISO_Install_${TIMESTAMP_ISO}.log"
ERROR_LOG="$LOG_DIR/WISO_Install_${TIMESTAMP_ISO}_errors.log"
export LOG_FILE ERROR_LOG LOG_DIR

log_err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >> "$ERROR_LOG"; }

export WINEPREFIX="$DATA_ROOT/prefix"
export WINEARCH=win64

PORTABLE_ROOT="${WISO_PORTABLE_ROOT:-${RECIPE_SOURCE_ROOT:-${1:-}}}"
FIX_ROOT="${WISO_FIX_ROOT:-${RECIPE_FIX_ROOT:-${2:-}}}"
if [ -z "$PORTABLE_ROOT" ] && [ -n "${RECIPE_EXTRACT_DIR:-}" ]; then
    PORTABLE_ROOT="$RECIPE_EXTRACT_DIR"
fi

if [ -z "$PORTABLE_ROOT" ]; then
    log_err "WISO_PORTABLE_ROOT fehlt — im Launcher Portable-Ordner wählen"
    exit 1
fi
if [ ! -d "$PORTABLE_ROOT" ]; then
    log_err "Kein Verzeichnis: $PORTABLE_ROOT"
    exit 1
fi
PORTABLE_ROOT="$(cd "$PORTABLE_ROOT" && pwd)"

case "$(basename "$PORTABLE_ROOT")" in
    Steuersoftware*)
        output::info "Portable-Root korrigiert: $(dirname "$PORTABLE_ROOT")"
        PORTABLE_ROOT="$(cd "$(dirname "$PORTABLE_ROOT")" && pwd)"
        ;;
esac

if type security::validate_path >/dev/null 2>&1; then
    security::validate_path "$PORTABLE_ROOT" || exit 1
fi

_sw=""
if [ -d "$PORTABLE_ROOT/Steuersoftware 2026" ]; then
    _sw="Steuersoftware 2026"
else
    _sw="$(find "$PORTABLE_ROOT" -maxdepth 1 -type d -name 'Steuersoftware*' 2>/dev/null | head -1)"
    _sw="${_sw##*/}"
fi
_exe="$(find "$PORTABLE_ROOT" -maxdepth 3 -name 'wiso*.exe' -type f 2>/dev/null | head -1 || true)"
if [ -z "$_sw" ] && [ -z "$_exe" ]; then
    log_err "Kein Steuersoftware* Ordner und keine wiso*.exe unter $PORTABLE_ROOT"
    exit 1
fi

output::section "WISO Steuer Installation"
output::progress 5 "Installation vorbereiten"
output::info "Portable: $PORTABLE_ROOT"
[ -n "$_sw" ] && output::info "Software-Ordner: $_sw"
[ -n "$_exe" ] && output::info "EXE: $_exe"

wiso_apply_fix() {
    local fix="$1"
    [ -n "$fix" ] || return 0
    if [ ! -e "$fix" ]; then
        log_err "Fix-Pfad existiert nicht: $fix"
        return 1
    fi
    if [ -f "$fix" ] && [[ "${fix,,}" == *.exe ]]; then
        output::step "Fix-Installer: $(basename "$fix")"
        env_file_set "$DATA_ROOT/portable.env" WISO_FIX_ROOT "$fix"
        if wine "$fix" /S >> "$LOG_FILE" 2>&1 || wine "$fix" >> "$LOG_FILE" 2>&1; then
            output::success "Fix-Installer ausgeführt"
            return 0
        fi
        log_err "Fix-Installer fehlgeschlagen: $fix"
        return 1
    fi
    if [ -d "$fix" ]; then
        output::info "Fix-Ordner: $fix"
        env_file_set "$DATA_ROOT/portable.env" WISO_FIX_ROOT "$fix"
        local ran=0 f
        shopt -s nullglob
        for f in "$fix"/*.exe "$fix"/*/*.exe; do
            [ -f "$f" ] || continue
            ran=1
            output::step "Fix: $(basename "$f")"
            wine "$f" /S >> "$LOG_FILE" 2>&1 || wine "$f" >> "$LOG_FILE" 2>&1 || true
        done
        shopt -u nullglob
        if [ "$ran" -eq 0 ]; then
            log_err "Keine .exe im Fix-Ordner: $fix"
            return 1
        fi
        output::success "Fix-Ordner verarbeitet"
        return 0
    fi
    log_err "Fix muss .exe-Datei oder Ordner sein: $fix"
    return 1
}

_WISO_FIX_ROOT=""
[ -n "$FIX_ROOT" ] && _WISO_FIX_ROOT="$FIX_ROOT"

output::step "Proton-GE initialisieren"
output::progress 10 "Proton-GE"
wine_runtime::init || { log_err "Proton-GE init failed"; exit 1; }
wine_runtime::export_env
output::success "Proton-GE bereit"

output::step "Wine-Prefix erstellen"
output::progress 18 "Wine-Prefix"
mkdir -p "$(dirname "$WINEPREFIX")" "$DATA_ROOT/bin"
recipe_prefix::ensure "$WINEPREFIX" || { log_err "Prefix fehlgeschlagen"; exit 1; }
output::success "Prefix bereit"

mkdir -p "$DATA_ROOT/bin"
cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$DATA_ROOT/bin/wiso-launch.sh"
chmod +x "$DATA_ROOT/bin/wiso-launch.sh"
env_file_set "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT "$PORTABLE_ROOT"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-validate.sh"
_wiso_ver="$(recipe_validate::wiso_portable_version "$PORTABLE_ROOT" || true)"
[ -n "$_wiso_ver" ] && env_file_set "$DATA_ROOT/portable.env" WISO_PORTABLE_VERSION "$_wiso_ver"
cp -f "$DATA_ROOT/bin/wiso-launch.sh" "$PORTABLE_ROOT/wiso-mit-wine.sh" 2>/dev/null || true
chmod +x "$PORTABLE_ROOT/wiso-mit-wine.sh" 2>/dev/null || true

_wt_ok=0
_sw_dir="$(recipe_wiso::software_dir "$PORTABLE_ROOT" || true)"
if [ -n "$_sw_dir" ]; then
    if recipe_wiso::qnetwork_disabled "$_sw_dir"; then
        output::success "Qt-Startfix bereits aktiv (Linux-Internet unverändert)"
    elif recipe_wiso::disable_qnetworklistmanager "$_sw_dir"; then
        output::step "Qt-Startfix (qnetworklistmanager.dll)"
        output::progress 28 "Qt-Startfix"
        output::success "Qt-Plugin deaktiviert — WLAN/LAN bleibt aktiv"
    else
        output::step "Qt-Startfix (qnetworklistmanager.dll)"
        output::progress 28 "Qt-Startfix"
        log_err "Konnte qnetworklistmanager.dll nicht umbenennen — $_sw_dir/networkinformation/"
        _wt_ok=1
    fi
fi

recipe_winetricks::stabilize_prefix

_wt_run() {
    local label="$1" wt_log="$2" pct="${3:-0}"
    shift 3
    [ "$pct" -gt 0 ] && output::progress "$pct" "$label"
    output::step "$label"
    if recipe_winetricks::run "$wt_log" "$@"; then
        output::success "$*"
        return 0
    fi
    log_err "winetricks $* fehlgeschlagen — $wt_log"
    tail -30 "$wt_log" >> "$ERROR_LOG" 2>/dev/null || true
    _wt_ok=1
    return 1
}

output::step "Visual C++ Runtime (vcrun2019)"
output::progress 38 "Visual C++ Runtime"
if recipe_vcrun::ensure "$LOG_DIR/winetricks_vcrun_${TIMESTAMP_ISO}.log"; then
    output::success "vcrun2019"
else
    log_err "vcrun2019 fehlgeschlagen — Microsoft-Installer"
    _wt_ok=1
fi

output::step "Wine-Mono / .NET 4.8 (dotnet48)"
output::progress 52 ".NET / Wine-Mono"
if recipe_dotnet::ensure "$LOG_DIR/winetricks_dotnet48_${TIMESTAMP_ISO}.log"; then
    output::success "dotnet48"
else
    log_err "dotnet48 fehlgeschlagen — $LOG_DIR/winetricks_dotnet48_${TIMESTAMP_ISO}.log"
    _wt_ok=1
fi

for pkg in corefonts d3dcompiler_47 gdiplus; do
    case "$pkg" in
        corefonts) _pct=62 ;;
        d3dcompiler_47) _pct=72 ;;
        gdiplus) _pct=82 ;;
        *) _pct=70 ;;
    esac
    _wt_run "winetricks: $pkg" \
        "$LOG_DIR/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$_pct" "$pkg" || true
done

output::step "Windows 10 (Registry)"
output::progress 88 "Windows 10"
if recipe_win10::ensure; then
    output::success "win10 gesetzt"
else
    log_err "win10 Registry fehlgeschlagen"
    _wt_ok=1
fi

if [ -n "$_WISO_FIX_ROOT" ]; then
    wiso_apply_fix "$_WISO_FIX_ROOT" || _wt_ok=1
fi

wine reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /t REG_SZ /d x11 /f >> "$LOG_FILE" 2>&1 || true
wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothing /t REG_DWORD /d 2 /f >> "$LOG_FILE" 2>&1 || true

if [ "$_wt_ok" -ne 0 ]; then
    output::error "Winetricks teilweise fehlgeschlagen — Launcher → Reparieren"
    echo "RECIPE_LOG_FILE=$LOG_FILE"
    echo "RECIPE_ERROR_LOG=$ERROR_LOG"
    exit 11
fi

output::success "WISO Rezept installiert"
output::progress 100 "Installation abgeschlossen"
echo "RECIPE_LOG_FILE=$LOG_FILE"
echo "RECIPE_ERROR_LOG=$ERROR_LOG"
output::info "Start über Launcher → Starten"
