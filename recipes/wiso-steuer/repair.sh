#!/usr/bin/env bash
# Reparatur: validate → nur fehlende Komponenten nachziehen (kein Voll-Install).

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
source "$CORE_DIR/recipe-validate.sh"
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
LOG_FILE="$LOG_DIR/WISO_Repair_${TIMESTAMP_ISO}.log"
ERROR_LOG="$LOG_DIR/WISO_Repair_${TIMESTAMP_ISO}_errors.log"
export LOG_FILE ERROR_LOG LOG_DIR

log_err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >> "$ERROR_LOG"; }

export WINEPREFIX="$DATA_ROOT/prefix"
export WINEARCH=win64

# Portable-Root aus env, portable.env oder FIX-Pfad ableiten
_wiso_portable=""
if [ -f "$DATA_ROOT/portable.env" ]; then
    _wiso_portable="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT || true)"
    if [ -z "$_wiso_portable" ] || [ ! -d "$_wiso_portable" ]; then
        _fix="$(env_file_get "$DATA_ROOT/portable.env" WISO_FIX_ROOT || true)"
        if [ -n "$_fix" ]; then
            _cand="$(dirname "$_fix")"
            case "$(basename "$_cand")" in
                Steuersoftware*) _cand="$(dirname "$_cand")" ;;
            esac
            if [ -d "$_cand" ]; then
                env_file_set "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT "$_cand"
                _wiso_portable="$_cand"
                output::info "Portable-Root wiederhergestellt: $_cand"
            fi
        fi
    fi
fi
if [ -n "${WISO_PORTABLE_ROOT:-}" ] && [ -d "${WISO_PORTABLE_ROOT}" ] \
    && { [ -z "$_wiso_portable" ] || [ ! -d "$_wiso_portable" ]; }; then
    env_file_set "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT "$WISO_PORTABLE_ROOT"
    _wiso_portable="$WISO_PORTABLE_ROOT"
fi

output::section "WISO Reparatur"

_validate_ok=0
if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    _validate_ok=1
    output::info "Prefix OK — synchronisiere Launcher und wined3d"
else
    output::info "Abweichungen gefunden — behebe fehlende Komponenten"
fi

wine_runtime::init || { log_err "Proton-GE init failed"; exit 1; }
wine_runtime::export_env

mkdir -p "$DATA_ROOT/bin"
cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$DATA_ROOT/bin/wiso-launch.sh"
chmod +x "$DATA_ROOT/bin/wiso-launch.sh"

output::step "Wine-Grafik (wined3d statt DXVK für Qt/WebEngine)"
if recipe_wiso::restore_wined3d_prefix >> "$LOG_FILE" 2>&1; then
    output::success "wined3d wiederhergestellt (DXVK für WISO deaktiviert)"
else
    log_err "wined3d-Wiederherstellung fehlgeschlagen"
fi
recipe_wiso::ensure_graphics_x11 "$WINE" >> "$LOG_FILE" 2>&1 || true

if [ "$_validate_ok" -eq 1 ]; then
    if [ -n "$_wiso_portable" ] && [ -d "$_wiso_portable" ]; then
        _sw_dir="$(recipe_wiso::software_dir "$_wiso_portable" || true)"
        if [ -n "$_sw_dir" ] && recipe_wiso::qnetwork_disabled "$_sw_dir"; then
            output::success "Qt-Startfix aktiv (Linux-Internet unverändert)"
        fi
        cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$_wiso_portable/wiso-mit-wine.sh" 2>/dev/null || true
        chmod +x "$_wiso_portable/wiso-mit-wine.sh" 2>/dev/null || true
    fi
    output::success "Reparatur abgeschlossen — Launcher und Grafik aktualisiert"
    exit 0
fi

if ! recipe_validate::prefix_initialized "$WINEPREFIX"; then
    output::error "Prefix fehlt — bitte Installieren (nicht Reparieren)"
    exit 1
fi

output::step "Prefix prüfen"
recipe_prefix::ensure "$WINEPREFIX" || { log_err "Prefix nicht bereit"; exit 1; }
recipe_winetricks::stabilize_prefix
output::success "Prefix bereit"

wow64="$WINEPREFIX/drive_c/windows/syswow64"
fixed=0

_wt_if_missing() {
    local check_path="$1"
    local wt_log="$2"
    shift 2
    if [ -f "$check_path" ] && recipe_validate::native_pe "$check_path" 2>/dev/null; then
        return 0
    fi
    if [ -f "$check_path" ] && recipe_validate::dll_exists "$check_path"; then
        return 0
    fi
    output::step "winetricks: $*"
    if recipe_winetricks::run "$wt_log" "$@"; then
        output::success "$* installiert"
        fixed=1
        return 0
    fi
    log_err "winetricks $* fehlgeschlagen — $wt_log"
    return 1
}

_wt_ok=0
_font_n=$(find "$WINEPREFIX/drive_c/windows/Fonts" -maxdepth 1 -type f 2>/dev/null | wc -l)
if [ "$_font_n" -lt 5 ]; then
    output::step "Schriften (corefonts, tahoma)"
    wt_fonts="$LOG_DIR/winetricks_fonts_${TIMESTAMP_ISO}.log"
    if recipe_winetricks::run "$wt_fonts" corefonts tahoma; then
        output::success "Schriften installiert"
        fixed=1
    else
        log_err "Schriften fehlgeschlagen — $wt_fonts"
        _wt_ok=1
    fi
fi

if ! recipe_validate::vcrun_dll_ok "$wow64/msvcp140.dll" \
    && ! recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
    output::step "Visual C++ Runtime (Microsoft-Installer)"
    if recipe_vcrun::ensure "$LOG_DIR/winetricks_vcrun_${TIMESTAMP_ISO}.log"; then
        output::success "vcrun2019 installiert"
        fixed=1
    else
        log_err "vcrun2019 fehlgeschlagen"
        _wt_ok=1
    fi
fi

for pkg in corefonts d3dcompiler_47 gdiplus; do
    dll="$wow64/${pkg}.dll"
    [ "$pkg" = "corefonts" ] && continue
    if ! recipe_validate::dll_exists "$dll"; then
        _wt_if_missing "$dll" "$LOG_DIR/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$pkg" || _wt_ok=1
    fi
done

if ! recipe_validate::windows_version "$WINEPREFIX" "win10"; then
    output::step "Windows 10 (Registry)"
    if recipe_win10::ensure; then
        output::success "win10 gesetzt"
        fixed=1
    else
        log_err "win10 Registry fehlgeschlagen"
        _wt_ok=1
    fi
fi

if ! recipe_dotnet::installed; then
    output::step "Wine-Mono / .NET 4.8 (dotnet48)"
    if recipe_dotnet::ensure "$LOG_DIR/winetricks_dotnet48_${TIMESTAMP_ISO}.log"; then
        output::success "dotnet48 installiert"
        fixed=1
    else
        log_err "dotnet48 fehlgeschlagen — $LOG_DIR/winetricks_dotnet48_${TIMESTAMP_ISO}.log"
        _wt_ok=1
    fi
fi

if [ ! -x "$DATA_ROOT/bin/wiso-launch.sh" ]; then
    output::step "Launcher-Skript wiederherstellen"
    mkdir -p "$DATA_ROOT/bin"
    cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$DATA_ROOT/bin/wiso-launch.sh"
    chmod +x "$DATA_ROOT/bin/wiso-launch.sh"
    output::success "wiso-launch.sh"
    fixed=1
else
    cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$DATA_ROOT/bin/wiso-launch.sh"
    chmod +x "$DATA_ROOT/bin/wiso-launch.sh"
fi

if [ -n "$_wiso_portable" ] && [ -d "$_wiso_portable" ]; then
    _sw_dir="$(recipe_wiso::software_dir "$_wiso_portable" || true)"
    if [ -n "$_sw_dir" ]; then
        if recipe_wiso::qnetwork_disabled "$_sw_dir"; then
            output::success "Qt-Startfix bereits aktiv (Linux-Internet unverändert)"
        elif recipe_wiso::disable_qnetworklistmanager "$_sw_dir"; then
            output::step "Qt-Startfix (qnetworklistmanager.dll)"
            output::success "Qt-Plugin deaktiviert — WLAN/LAN bleibt aktiv"
            fixed=1
        else
            output::step "Qt-Startfix (qnetworklistmanager.dll)"
            log_err "qnetworklistmanager.dll nicht umbenennbar — $_sw_dir/networkinformation/"
            _wt_ok=1
        fi
        cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$_wiso_portable/wiso-mit-wine.sh" 2>/dev/null || true
        chmod +x "$_wiso_portable/wiso-mit-wine.sh" 2>/dev/null || true
    fi
fi

wine reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /t REG_SZ /d x11 /f >> "$LOG_FILE" 2>&1 || true
recipe_wiso::ensure_graphics_x11 wine >> "$LOG_FILE" 2>&1 || true
wine reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothing /t REG_DWORD /d 2 /f >> "$LOG_FILE" 2>&1 || true

if [ "$_wt_ok" -ne 0 ]; then
    output::error "Reparatur unvollständig — Logs: $LOG_DIR"
    exit 11
fi

if bash "$RECIPE_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
    output::success "Reparatur abgeschlossen — alle Prüfungen OK"
    exit 0
fi

if [ "$fixed" -eq 1 ]; then
    output::warning "Teilweise repariert — erneut Prüfen"
    exit 11
fi
output::error "Reparatur fehlgeschlagen"
exit 1
