#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux Installer - Installation Script
#
# Description:
#   Handles the complete installation process of Adobe Photoshop CC on Linux
#   including Wine configuration, dependency installation, registry tweaks,
#   and performance optimizations for stable operation.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
#
# Based on:     photoshopCClinux by Gictorbit
#               https://github.com/Gictorbit/photoshopCClinux
################################################################################

# CRITICAL: Enable robust error handling
set -eu
(set -o pipefail 2>/dev/null) || true

# CRITICAL: Trap for CTRL+C (INT) and other signals - MUST be set at the very beginning
# Also needed in subprocesses (winetricks, wine, etc.)
cleanup_on_interrupt() {
    # Initialize i18n if not already done
    if [ -z "${LANG_CODE:-}" ]; then
        if [ -f "${SCRIPT_DIR:-}/i18n.sh" ]; then
            source "${SCRIPT_DIR}/i18n.sh" 2>/dev/null || true
        fi
    fi
    
    local cancelled_msg
    if [ "$LANG_CODE" = "de" ]; then
        cancelled_msg="$(i18n::get "installation_cancelled_user" 2>/dev/null || echo "Installation abgebrochen durch Benutzer (STRG+C)")"
    else
        cancelled_msg="$(i18n::get "installation_cancelled_user" 2>/dev/null || echo "Installation cancelled by user (CTRL+C)")"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "$cancelled_msg"
    echo "═══════════════════════════════════════════════════════════════"
    # Log error if LOG_FILE is available
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $cancelled_msg" >> "${LOG_FILE}"
    fi
    exit 130
}
trap cleanup_on_interrupt INT TERM HUP

# Locale/UTF-8 for DE/EN (with check for existing locale)
# CRITICAL: Check if locale exists (Alpine often only has C.UTF-8)
if command -v locale >/dev/null 2>&1; then
    # Fix grep warnings: Use -F for fixed strings or escape properly
    if locale -a 2>/dev/null | grep -qF "de_DE.utf8" || locale -a 2>/dev/null | grep -qF "de_DE.UTF-8" || locale -a 2>/dev/null | grep -qF "de_DE"; then
        export LANG="${LANG:-de_DE.UTF-8}"
    elif locale -a 2>/dev/null | grep -qF "C.utf8" || locale -a 2>/dev/null | grep -qF "C.UTF-8"; then
        export LANG="${LANG:-C.UTF-8}"
    else
        export LANG="${LANG:-C}"
    fi
else
    # Fallback if locale not available
    export LANG="${LANG:-C.UTF-8}"
fi
export LC_ALL="${LC_ALL:-$LANG}"

# ============================================================================
# @function init_environment
# @description Initialize all environment variables in a centralized location
# @return 0 on success, 1 on error
# ============================================================================
init_environment() {
    RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
    CORE_DIR="$PROJECT_ROOT/core"
    export PROJECT_ROOT RECIPE_DIR CORE_DIR

    # shellcheck source=/dev/null
    source "$CORE_DIR/paths.sh"
    # shellcheck source=/dev/null
    source "$CORE_DIR/recipe.sh"
    recipe_export_env "$RECIPE_DIR/recipe.yml"

    SCRIPT_DIR="$CORE_DIR"
    export SCRIPT_DIR

    if [[ ":$PATH:" == *":.:"* ]] || [[ "$PATH" == .:* ]] || [[ "$PATH" == *:. ]]; then
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
    fi

    LOG_DIR="$(wine_software_logs_dir)"
    mkdir -p "$LOG_DIR"
    
    # Log rotation: Keep only the 10 most recent log files, delete older ones
    if [ -d "$LOG_DIR" ]; then
        # Delete compressed logs older than 7 days
        find "$LOG_DIR" -name "*.log.gz" -type f -mtime +7 -delete 2>/dev/null || true
        
        # Cache find results for performance (avoid multiple find calls on same directory)
        local log_files=($(find "$LOG_DIR" -name "*.log" -type f 2>/dev/null))
        local log_count=${#log_files[@]}
        
        if [ "$log_count" -gt 10 ]; then
            # Portable sorting: Use find -printf (GNU) or ls -t (BSD/macOS)
            if find "$LOG_DIR" -name "*.log" -type f -printf '%T@ %p\n' >/dev/null 2>&1; then
                # GNU find (Linux) - use -printf for modification time
                find "$LOG_DIR" -name "*.log" -type f -printf '%T@ %p\n' | sort -rn | tail -n +11 | cut -d' ' -f2- | xargs -r rm -f 2>/dev/null || {
                    if type log_warning >/dev/null 2>&1; then
                        log_warning "Failed to remove old log files (non-critical)"
                    fi
                }
            else
                # BSD/macOS fallback: Use ls -t (sort by modification time)
                # Use shopt nullglob to prevent glob errors when no files match
                local old_nullglob
                shopt -q nullglob && old_nullglob=1 || old_nullglob=0
                shopt -s nullglob
                local log_files_glob=("$LOG_DIR"/*.log)
                shopt -u nullglob
                if [ "$old_nullglob" = "1" ]; then
                    shopt -s nullglob
                fi
                
                if [ ${#log_files_glob[@]} -gt 0 ]; then
                    ls -t "${log_files_glob[@]}" 2>/dev/null | tail -n +11 | xargs -r rm -f 2>/dev/null || {
                        if type log_warning >/dev/null 2>&1; then
                            log_warning "Failed to remove old log files (non-critical)"
                        fi
                    }
                fi
            fi
        fi
        
        # Compress logs older than 3 days (before deletion) to save space
        if command -v gzip >/dev/null 2>&1; then
            find "$LOG_DIR" -name "*.log" -type f -mtime +3 ! -name "*.log.gz" -exec gzip {} \; 2>/dev/null || {
                if type log_warning >/dev/null 2>&1; then
                    log_warning "Failed to compress old log files (non-critical, gzip may not be available)"
                fi
            }
        fi
        
        # Delete logs older than 7 days (portable - mtime works on all systems)
        find "$LOG_DIR" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    fi
    
    # Generate timestamp for structured logging
    # Format: YYYY-MM-DD_HH-MM-SS for better sorting
    TIMESTAMP_ISO=$(date +%Y-%m-%d_%H-%M-%S)
    TIMESTAMP=$(date +%d.%m.%y\ %H:%M\ Uhr)  # Keep old format for compatibility
    
    # Structured log files
    LOG_FILE="$LOG_DIR/Installation_${TIMESTAMP_ISO}.log"
    WARNING_LOG="$LOG_DIR/Installation_${TIMESTAMP_ISO}_warnings.log"
    ERROR_LOG="$LOG_DIR/Installation_${TIMESTAMP_ISO}_errors.log"
    DEBUG_LOG="$LOG_DIR/Installation_${TIMESTAMP_ISO}_debug.log"
    WINE_LOG="$LOG_DIR/wine_${TIMESTAMP_ISO}.log"
    
    # Initialize log files with headers
    # Initialize i18n if not already done
    if [ -z "${LANG_CODE:-}" ]; then
        if [ -f "${SCRIPT_DIR:-}/i18n.sh" ]; then
            source "${SCRIPT_DIR}/i18n.sh" 2>/dev/null || true
        fi
    fi
    
    local log_header_inst log_header_warn log_header_err log_header_wine
    log_header_inst="$(i18n::get "log_header_installation" 2>/dev/null || echo "Photoshop CC Linux Installation Log")"
    log_header_warn="$(i18n::get "log_header_warnings" 2>/dev/null || echo "Installation Warnings Log")"
    log_header_err="$(i18n::get "log_header_errors" 2>/dev/null || echo "Installation Errors Log")"
    log_header_wine="$(i18n::get "log_header_wine" 2>/dev/null || echo "Wine Process Log")"
    
    echo "═══════════════════════════════════════════════════════════════" > "$LOG_FILE"
    echo "            $log_header_inst" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "Log file: $LOG_FILE" >> "$LOG_FILE"
    echo "Error log: $ERROR_LOG" >> "$LOG_FILE"
    echo "Debug log: $DEBUG_LOG" >> "$LOG_FILE"
    echo "Launcher session: ${LAUNCHER_SESSION_ID:-—}" >> "$LOG_FILE"
    echo "Launcher GUI: ${LAUNCHER_GUI:-0}" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo "═══════════════════════════════════════════════════════════════" > "$WARNING_LOG"
    echo "            $log_header_warn" >> "$WARNING_LOG"
    echo "═══════════════════════════════════════════════════════════════" >> "$WARNING_LOG"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$WARNING_LOG"
    echo "" >> "$WARNING_LOG"
    
    echo "═══════════════════════════════════════════════════════════════" > "$ERROR_LOG"
    echo "            $log_header_err" >> "$ERROR_LOG"
    echo "═══════════════════════════════════════════════════════════════" >> "$ERROR_LOG"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$ERROR_LOG"
    echo "" >> "$ERROR_LOG"
    
    echo "═══════════════════════════════════════════════════════════════" > "$WINE_LOG"
    echo "            $log_header_wine" >> "$WINE_LOG"
    echo "═══════════════════════════════════════════════════════════════" >> "$WINE_LOG"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$WINE_LOG"
    echo "" >> "$WINE_LOG"
    
    # Export all logging variables for sharedFuncs.sh
    export LOG_FILE
    export WARNING_LOG
    export ERROR_LOG
    export LOG_DIR
    export TIMESTAMP
    export TIMESTAMP_ISO
    export DEBUG_LOG
    export WINE_LOG
}

# Initialize environment first
init_environment

# Source i18n module for internationalization
source "$SCRIPT_DIR/i18n.sh"

# Source security module for validation and sanitization
source "$SCRIPT_DIR/security.sh"

# Source checkpoint module for rollback support
source "$SCRIPT_DIR/checkpoint.sh"

# Source update module for version checking
source "$SCRIPT_DIR/update.sh"

# Source shared functions after environment is initialized
source "$SCRIPT_DIR/sharedFuncs.sh"
source "$SCRIPT_DIR/wine-runtime.sh"

# Runtime-aware wine/winetricks wrappers (Proton-GE or system fallback)
wine() {
    wine_runtime::wine "$@"
}
winetricks() {
    wine_runtime::winetricks "$@"
}
wineserver() {
    wine_runtime::wineserver "$@"
}
wineboot() {
    wine_runtime::wineboot "$@"
}

# Resolve the active wine binary (Proton-GE path, not shell function name "wine")
photoshop_setup::wine_binary() {
    wine_runtime::export_env 2>/dev/null || true
    if [ -n "${WINE_RUNTIME_BIN:-}" ] && [ -x "${WINE_RUNTIME_BIN}" ]; then
        echo "$WINE_RUNTIME_BIN"
    elif [ -n "${WINE:-}" ] && [ -x "${WINE}" ]; then
        echo "$WINE"
    else
        type -P wine 2>/dev/null || echo "wine"
    fi
}

# Proton-GE has no files/bin/winecfg — must run via wine winecfg, never system /usr/bin/winecfg
photoshop_setup::run_winecfg() {
    local wb="$1"
    local cfg=""
    cfg="$(type -P winecfg 2>/dev/null || true)"
    if [ -n "$cfg" ] && [ "$(dirname "$cfg")" = "$(dirname "$wb")" ]; then
        "$cfg" "${@:2}"
    else
        "$wb" winecfg "${@:2}"
    fi
}

photoshop_setup::kill_all_wineservers() {
    wine_runtime::wineserver -k 2>/dev/null || true
    if command -v wineserver >/dev/null 2>&1; then
        wineserver -k 2>/dev/null || true
    fi
    pkill -9 wineserver 2>/dev/null || true
}

# Fast Windows 10 version set via registry (avoids winetricks winecfg + wineserver -w hang)
photoshop_setup::ensure_win10() {
    local current_ver=""
    current_ver="$(wine reg query "HKCU\\Software\\Wine" /v Version 2>/dev/null \
        | awk '/Version/{print $3}' | tr -d '\r\n' || true)"
    if [ "$current_ver" = "win10" ]; then
        log_debug "Windows version already win10 (registry)"
        return 0
    fi

    photoshop_setup::kill_all_wineservers
    wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d win10 /f >> "$LOG_FILE" 2>&1 \
        || return 1
    wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion /t REG_SZ /d 10.0 /f >> "$LOG_FILE" 2>&1 \
        || return 1
    wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuild /t REG_SZ /d 19045 /f >> "$LOG_FILE" 2>&1 \
        || true
    wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v ProductName /t REG_SZ /d "Microsoft Windows 10" /f >> "$LOG_FILE" 2>&1 \
        || true
    log_debug "Windows version set to win10 via registry"
    return 0
}

photoshop_setup::prefix_is_initialized() {
    [ -f "${WINE_PREFIX}/user.reg" ] && [ -s "${WINE_PREFIX}/user.reg" ]
}

photoshop_setup::wine_runtime_ready() {
    photoshop_setup::prefix_is_initialized || return 1
    photoshop_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll" \
        && photoshop_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll"
}

photoshop_setup::init_prefix_silent() {
    local wine_binary="$1"
    local wineboot_timeout="${2:-30}"
    local wait_timeout="${3:-30}"

    photoshop_setup::kill_all_wineservers
    mkdir -p "$WINE_PREFIX" || return 1
    export WINEARCH=win64
    export WINEDEBUG=-all,+err

    local wineboot_ok=false
    if command -v timeout >/dev/null 2>&1; then
        timeout "$wineboot_timeout" "$wine_binary" wineboot -i >> "$LOG_FILE" 2>&1 && wineboot_ok=true
    else
        "$wine_binary" wineboot -i >> "$LOG_FILE" 2>&1 && wineboot_ok=true
    fi
    if [ "$wineboot_ok" = false ]; then
        "$wine_binary" wineboot -u >> "$LOG_FILE" 2>&1 || true
    fi

    wait::for_wine_prefix "$WINE_PREFIX" "$wait_timeout" 0.5 || true
    photoshop_setup::ensure_win10 >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktop" /v "Enable" /t REG_SZ /d "N" /f >> "$LOG_FILE" 2>&1 || true
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-};winemenubuilder.exe=d"
    wine_runtime::deploy_proton_graphics_dlls >> "$LOG_FILE" 2>&1 || true

    [ -f "$WINE_PREFIX/user.reg" ]
}

photoshop_setup::ie8_present() {
    local prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    [ -f "$prefix/drive_c/Program Files/Internet Explorer/iexplore.exe" ] \
        || [ -f "$prefix/drive_c/Program Files (x86)/Internet Explorer/iexplore.exe" ]
}

# Runtime overrides (launch.sh) — full native IE stack + DXVK
photoshop_setup::export_ie_dll_overrides() {
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;d3d11=native,builtin;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin"
}

# Adobe Set-up.exe: native MSXML + IE stack (GUI needs CommBridge localhost — use --silent=1 on Wine)
photoshop_setup::export_adobe_installer_dll_overrides() {
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;msxml3=native,builtin;msxml6=native,builtin;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin"
    log_debug "WINEDLLOVERRIDES (Adobe-Installer) gesetzt"
}

photoshop_setup::msxml_is_native() {
    local dll="$1"
    [ -f "$dll" ] && file "$dll" 2>/dev/null | grep -q 'MS Windows' && ! file "$dll" 2>/dev/null | grep -q 'WINE (DLL)'
}

photoshop_setup::ensure_native_msxml() {
    local msxml3="${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll"
    local msxml6="${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll"
    if photoshop_setup::msxml_is_native "$msxml3" && photoshop_setup::msxml_is_native "$msxml6"; then
        log_debug "Native MSXML3/MSXML6 vorhanden"
        return 0
    fi
    export WINEPREFIX="${WINEPREFIX:-$WINE_PREFIX}"
    export WINEARCH="${WINEARCH:-win64}"
    photoshop_setup::kill_all_wineservers
    sleep 1

    log_debug "Native MSXML fehlt — winetricks -f msxml3 msxml6 (Proton-GE)"
    if [ "$LANG_CODE" = "de" ]; then
        output::step "Installiere native MSXML3/MSXML6 (Adobe-Installer)..."
    else
        output::step "Installing native MSXML3/MSXML6 (Adobe installer)..."
    fi

    local wt_log="${LOG_DIR}/winetricks_msxml_${TIMESTAMP_ISO:-$(date +%Y-%m-%d_%H-%M-%S)}.log"
    local wt_rc=0
    if command -v timeout >/dev/null 2>&1; then
        timeout 600 winetricks -q -f msxml3 msxml6 >> "$wt_log" 2>&1 || wt_rc=$?
    else
        winetricks -q -f msxml3 msxml6 >> "$wt_log" 2>&1 || wt_rc=$?
    fi
    if [ "$wt_rc" -ne 0 ]; then
        log_error "winetricks msxml3/msxml6 fehlgeschlagen (exit $wt_rc) — Log: $wt_log"
        tail -40 "$wt_log" >> "${ERROR_LOG:-$LOG_FILE}" 2>/dev/null || true
    fi

    wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v msxml3 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v msxml6 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine regsvr32 /S C:\\windows\\syswow64\\msxml3.dll >> "$LOG_FILE" 2>&1 || true
    wine regsvr32 /S C:\\windows\\syswow64\\msxml6.dll >> "$LOG_FILE" 2>&1 || true

    if photoshop_setup::msxml_is_native "$msxml3" && photoshop_setup::msxml_is_native "$msxml6"; then
        output::success "Native MSXML3/MSXML6 installiert"
        return 0
    fi

    if [ -f "$msxml3" ]; then
        file "$msxml3" >> "${ERROR_LOG:-$LOG_FILE}" 2>&1 || true
    fi
    if [ -f "$msxml6" ]; then
        file "$msxml6" >> "${ERROR_LOG:-$LOG_FILE}" 2>&1 || true
    fi
    log_error "Native MSXML3/MSXML6 konnte nicht installiert werden"
    output::error "MSXML-Installation fehlgeschlagen — Adobe-Installer bricht ohne native MSXML ab"
    return 1
}

photoshop_setup::apply_adobe_network_registry() {
    wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings" /v AutoDetect /t REG_DWORD /d 0 /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKLM\\System\\CurrentControlSet\\Services\\NlaSvc\\Parameters\\Internet" /v EnableActiveProbing /t REG_DWORD /d 1 /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKLM\\System\\CurrentControlSet\\Services\\NlaSvc\\Parameters\\Internet" /v ActiveDnsProbeHost /t REG_SZ /d "dns.msftncsi.com" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKLM\\System\\CurrentControlSet\\Services\\NlaSvc\\Parameters\\Internet" /v ActiveWebProbeHost /t REG_SZ /d "www.msftncsi.com" /f >> "$LOG_FILE" 2>&1 || true
    log_debug "Adobe-Netzwerk-Registry (WPAD aus, NLA an) gesetzt"
}

photoshop_setup::fix_installer_case_symlinks() {
    local base="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -d "$base/products" ] || return 0
    if [ -f "$base/products/Driver.xml" ] && [ ! -e "$base/products/driver.xml" ]; then
        ln -sf Driver.xml "$base/products/driver.xml"
    fi
    if [ -f "$base/resources/Config.xml" ] && [ ! -e "$base/resources/config.xml" ]; then
        ln -sf Config.xml "$base/resources/config.xml"
    fi
    log_debug "Installer Case-Symlinks (driver.xml, config.xml) gesetzt"
}

photoshop_setup::deploy_installer_to_c_drive() {
    local src="$1"
    local dest="${WINEPREFIX}/drive_c/AdobeSetup"
    if [ -z "$src" ] || [ ! -f "$src/Set-up.exe" ]; then
        log_error "deploy_installer_to_c_drive: Set-up.exe missing in $src"
        return 1
    fi
    log_debug "Deploy Adobe installer nach C:\\AdobeSetup (von $src)"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    photoshop_setup::fix_installer_case_symlinks
    export ADOBE_INSTALLER_DIR="$dest"
    return 0
}

photoshop_setup::resolve_setup_exe() {
    if [ -n "${ADOBE_INSTALLER_DIR:-}" ] && [ -f "${ADOBE_INSTALLER_DIR}/Set-up.exe" ]; then
        echo "${ADOBE_INSTALLER_DIR}/Set-up.exe"
        return 0
    fi
    if [ -f "${WINEPREFIX}/drive_c/AdobeSetup/Set-up.exe" ]; then
        echo "${WINEPREFIX}/drive_c/AdobeSetup/Set-up.exe"
        return 0
    fi
    if [ -f "${RESOURCES_PATH}/photoshop/Set-up.exe" ]; then
        echo "${RESOURCES_PATH}/photoshop/Set-up.exe"
        return 0
    fi
    return 1
}

photoshop_setup::reregister_ie8_dlls() {
    local dll="" dir="C:\\windows\\syswow64"
    for dll in mshtml.dll jscript.dll vbscript.dll urlmon.dll wininet.dll ieframe.dll shdocvw.dll; do
        wine regsvr32 /S "${dir}\\${dll}" >> "$LOG_FILE" 2>&1 || true
    done
    log_debug "IE8 DLLs neu registriert (syswow64, 32-bit Adobe-Installer)"
}

photoshop_setup::prepare_adobe_installer_env() {
    photoshop_setup::disable_virtual_desktop
    photoshop_setup::kill_all_wineservers
    sleep 1
    photoshop_setup::ensure_native_msxml || true
    photoshop_setup::apply_adobe_network_registry
    photoshop_setup::export_adobe_installer_dll_overrides
    photoshop_setup::ensure_win10 >> "$LOG_FILE" 2>&1 || true
    photoshop_setup::reregister_ie8_dlls
}

photoshop_setup::disable_virtual_desktop() {
    wine reg delete "HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver" /v Desktop /f >> "$LOG_FILE" 2>&1 \
        || wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver" /v Desktop /t REG_SZ /d "" /f >> "$LOG_FILE" 2>&1 \
        || true
    log_debug "Virtual Desktop deaktiviert für Adobe-Installer"
}

photoshop_setup::enable_virtual_desktop() {
    local resolution="${1:-${PHOTOSHOP_VIRTUAL_DESKTOP_RES:-1920x1080}}"
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver" /v Desktop /t REG_SZ /d "$resolution" /f >> "$LOG_FILE" 2>&1 || true
    log_debug "Virtual Desktop reaktiviert ($resolution)"
}

source "$SCRIPT_DIR/output.sh"
source "$SCRIPT_DIR/system.sh"

# Setup comprehensive logging - ALL output will be logged
# This function sets up automatic logging of all stdout/stderr
setup_comprehensive_logging() {
    log_debug "Comprehensive logging enabled - all output will be automatically logged"
}
debug_log() {
    local location="$1"
    local message="$2"
    local data="$3"
    local hypothesis_id="${4:-}"
    local timestamp=$(date +%s%3N 2>/dev/null || date +%s000)
    local session_id="debug-session-$(date +%s)"
    local run_id="${RUN_ID:-run1}"
    local log_entry="{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"${session_id}\",\"runId\":\"${run_id}\",\"hypothesisId\":\"${hypothesis_id}\"}"
    echo "$log_entry" >> "$DEBUG_LOG" 2>/dev/null || {
        # Debug log write failure is non-critical, but log it if warning function exists
        if type warning >/dev/null 2>&1; then
            warning "Failed to write to debug log: $DEBUG_LOG" 2>/dev/null || true
        fi
    }
    # Silent during installation - only log to file, don't output to stderr
    # Uncomment the line below if you need live debugging:
    # echo "[DEBUG] $log_entry" >&2
}

# Agent debug log function removed - production code should not contain AI debug logs
# Use debug_log() instead if debugging is needed

# ANSI Color codes (compatible with setup.sh)
# Check if terminal supports colors
if [ -t 1 ] && [ "$TERM" != "dumb" ]; then
    C_RESET="\033[0m"
    C_CYAN="\033[0;36;1m"
    C_MAGENTA="\033[0;35;1m"
    C_BLUE="\033[0;34;1m"
    C_YELLOW="\033[0;33;1m"
    C_WHITE="\033[0;37;1m"
    C_GREEN="\033[0;32;1m"
    C_GRAY="\033[0;37m"
    C_RED="\033[1;31m"
else
    # No colors for dumb terminals
    C_RESET=""
    C_CYAN=""
    C_MAGENTA=""
    C_BLUE=""
    C_YELLOW=""
    C_WHITE=""
    C_GREEN=""
    C_GRAY=""
    C_RED=""
fi

# Spinner function for long-running processes
spinner() {
    local pid=$1
    local message="${2:-}"
    
    # In quiet/GUI mode: wait silently (no TTY spinner garbage)
    if [ "${QUIET:-0}" = "1" ] || [ "${LAUNCHER_GUI:-0}" = "1" ]; then
        if [ -n "$message" ] && [ "${LAUNCHER_GUI:-0}" = "1" ]; then
            printf '@step:%s\n' "$message"
        fi
        wait "$pid" 2>/dev/null || true
        return 0
    fi
    
    local spinstr='|/-\'
    local temp
    
    # Show message if provided
    if [ -n "$message" ]; then
        echo -ne "${C_YELLOW}$message${C_RESET} "
    fi
    
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        temp=${spinstr#?}
        printf "${C_CYAN}[%c]${C_RESET}" "$spinstr"
        local old_IFS="${IFS:-}"
        IFS=
        spinstr=$temp${spinstr%"$temp"}
        IFS="$old_IFS"
        sleep 0.1
        printf "\b\b\b"
    done
    printf "   \b\b\b"
    echo ""
}

# Run command with spinner in background
run_with_spinner() {
    local message="$1"
    shift
    local cmd="$*"
    
    # CRITICAL: Export environment variables before running command
    # This ensures winetricks uses the correct Wine binary and WINEPREFIX
    # CRITICAL: Use arrays instead of eval for security
    # Build environment variables array
    local env_array=()
    if [ -n "${WINEPREFIX:-}" ]; then
        env_array+=("WINEPREFIX=$WINEPREFIX")
    fi
    if [ -n "${WINEARCH:-}" ]; then
        env_array+=("WINEARCH=$WINEARCH")
    fi
    # REMOVED: Proton GE environment variables
    
    # CRITICAL: Validate command before execution if security::safe_eval available
    if type security::safe_eval >/dev/null 2>&1; then
        if ! security::safe_eval "$cmd" "wine" "winetricks"; then
            log_error "Unsafe command detected: $cmd"
            return 1
        fi
    fi
    
    # Run command in background with environment variables and capture PID
    # Use env command with array instead of eval
    if [ ${#env_array[@]} -gt 0 ]; then
        env "${env_array[@]}" bash -c "$cmd" >> "$LOG_FILE" 2>&1 &
    else
        bash -c "$cmd" >> "$LOG_FILE" 2>&1 &
    fi
    local pid=$!
    
    # In quiet mode, just wait without spinner
    if [ "${QUIET:-0}" = "1" ]; then
        log::debug "Running: $message"
        wait $pid
        return $?
    fi
    
    # Show spinner while command runs
    spinner $pid "$message"
    
    # Wait for command to finish and get exit code
    wait $pid
    return $?
}

# ============================================================================
# @function run_with_spinner_and_retry
# @description Run command with spinner and retry mechanism
# @param $1 Message to display
# @param $2 Command to execute
# @param $3 Optional: Max retries (default: 2)
# @param $4 Optional: Retry delay in seconds (default: 5)
# @return 0 on success, 1 if all retries failed
# ============================================================================
run_with_spinner_and_retry() {
    local message="$1"
    local cmd="$2"
    local max_retries="${3:-2}"
    local retry_delay="${4:-5}"
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        if run_with_spinner "$message" "$cmd"; then
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            log::debug "Command failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s: $cmd"
            sleep "$retry_delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    log::warning "Command failed after $max_retries attempts: $cmd"
    return 1
}

# ============================================================================
# Unified Logging System with Namespace Pattern
# ============================================================================
# @namespace log
# @description Unified logging system with consistent interface
# All log functions follow the pattern: log::<level> "message"
# ============================================================================

# ============================================================================
# @function log::success
# @description Log success message (green, shown to user)
# @param $* Success message(s)
# @param $1 Optional: Category (INSTALL, WINE, SYSTEM, CONFIG)
# @return 0 (always succeeds)
# ============================================================================
log::success() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local category="ERFOLG"
    local message="$*"
    if [[ "${1:-}" =~ ^[A-Z_]+$ ]] && [ $# -gt 1 ]; then
        category="$1"
        shift
        message="$*"
    fi
    local log_category="ERFOLG"
    if [ "$LANG_CODE" = "en" ]; then
        log_category="SUCCESS"
    fi
    echo "[$timestamp] [$log_category] $message" >> "$LOG_FILE"
    
    # In quiet mode, only log to file, don't output to console
    if [ "${QUIET:-0}" = "1" ]; then
        return 0
    fi
    
    # Display to user
    echo -e "${C_GREEN}✓ $message${C_RESET}"
}

# ============================================================================
# @function log::info
# @description Log info message (cyan, shown to user)
# @param $* Info message(s)
# @param $1 Optional: Category (INSTALL, WINE, SYSTEM, CONFIG)
# @return 0 (always succeeds)
# ============================================================================
log::info() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local category="${1:-INFO}"
    shift
    local message="$*"

    # Check if first argument is a category (uppercase, no spaces)
    if [[ ! "$category" =~ ^[A-Z_]+$ ]] || [ "$category" = "INFO" ]; then
        # First arg is not a category, use it as part of message
        message="$category $*"
        category="INFO"
    fi

    # Write to main log (always)
    echo "[$timestamp] [INFO] [$category] $message" >> "$LOG_FILE"
    
    # In quiet mode, only log to file, don't output to console
    if [ "${QUIET:-0}" = "1" ]; then
        return 0
    fi
    
    # Display to user
    echo -e "${C_CYAN}ℹ $message${C_RESET}"
}

# ============================================================================
# @function log::installation
# @description Log installation-specific message
# @param $* Message(s)
# @param $1 Optional: Category (INSTALL, WINE, SYSTEM, CONFIG)
# @return 0 (always succeeds)
# ============================================================================
log::installation() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local category="${1:-INSTALL}"
    shift
    local message="$*"
    
    # Check if first argument is a category
    if [[ ! "$category" =~ ^[A-Z_]+$ ]] || [ "$category" = "INSTALL" ]; then
        message="$category $*"
        category="INSTALL"
    fi
    
    # Write to main log and installation log
    echo "[$timestamp] [INFO] [$category] $message" >> "$LOG_FILE"
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] [$category] $message" >> "$LOG_FILE"
    fi
}

# ============================================================================
# @function log::wine
# @description Log Wine-specific message
# @param $* Message(s)
# @return 0 (always succeeds)
# ============================================================================
log::wine() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"
    
    # Write to main log and wine log
    echo "[$timestamp] [INFO] [WINE] $message" >> "$LOG_FILE"
    if [ -n "${WINE_LOG:-}" ] && [ -f "${WINE_LOG:-}" ]; then
        echo "[$timestamp] $message" >> "$WINE_LOG"
    fi
}

# ============================================================================
# @function log::warning
# @description Log warning message (yellow, shown to user, also to warning log)
# @param $* Warning message(s)
# @param $1 Optional: Category (INSTALL, WINE, SYSTEM, CONFIG)
# @return 0 (always succeeds)
# ============================================================================
log::warning() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local category="${1:-WARNING}"
    shift
    local message="$*"
    
    # Check if first argument is a category (uppercase, no spaces)
    if [[ ! "$category" =~ ^[A-Z_]+$ ]] || [ "$category" = "WARNING" ]; then
        # First arg is not a category, use it as part of message
        message="$category $*"
        category="WARNING"
    fi
    
    # Write to main log
    echo "[$timestamp] [WARNING] [$category] $message" >> "$LOG_FILE"
    
    # Write to warning log
    if [ -n "${WARNING_LOG:-}" ] && [ -f "${WARNING_LOG:-}" ]; then
        echo "[$timestamp] [$category] $message" >> "$WARNING_LOG"
    fi
    
    # In quiet mode, only log to file, don't output to console
    if [ "${QUIET:-0}" = "1" ]; then
        return 0
    fi
    
    # Display to user
    echo -e "${C_YELLOW}⚠ WARNING: $message${C_RESET}"
}

# ============================================================================
# @function log::error
# @description Log error message (red, shown to user, also to error log)
# @param $* Error message(s)
# @return 0 (always succeeds, does not exit)
# ============================================================================
log::error() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
    echo "[$timestamp] ERROR: $message" >> "$ERROR_LOG"
    echo -e "${C_RED}ERROR: $message${C_RESET}"
}

# ============================================================================
# @function log::debug
# @description Log debug message (only to log file, not shown to user)
# @param $* Debug message(s)
# @return 0 (always succeeds)
# ============================================================================
log::debug() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"
    
    # Always log to file
    echo "[$timestamp] DEBUG: $message" >> "$LOG_FILE"
    
    # Only show on console in verbose mode (and not in quiet mode)
    if [ "${VERBOSE:-0}" = "1" ] && [ "${QUIET:-0}" != "1" ]; then
        echo -e "${C_GRAY}[DEBUG]${C_RESET} $message"
    fi
}

# ============================================================================
# @function log::prompt
# @description Log user prompt (shown to user and logged)
# @param $* Prompt message(s)
# @return 0 (always succeeds)
# ============================================================================
log::prompt() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"
    # Only log to file, don't output to console (prevents double prompt display)
    # The prompt itself is shown via read -p in the calling function
    echo "[$timestamp] PROMPT: $message" >> "$LOG_FILE" 2>/dev/null || {
        # Log write failure is non-critical, but log it if warning function exists
        if type warning >/dev/null 2>&1; then
            warning "Failed to write prompt to log file: $LOG_FILE" 2>/dev/null || true
        fi
    }
}

# ============================================================================
# @function log::input
# @description Log user input (logged only)
# @param $* Input message(s)
# @return 0 (always succeeds)
# ============================================================================
log::input() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"
    # CRITICAL: Only log to file, don't output to console (security: prevents password/input exposure)
    echo "[$timestamp] USER_INPUT: $message" >> "$LOG_FILE" 2>/dev/null || {
        # Log write failure is non-critical, but log it if warning function exists
        if type warning >/dev/null 2>&1; then
            warning "Failed to write user input to log file: $LOG_FILE" 2>/dev/null || true
        fi
    }
}

# ============================================================================
# DEPRECATED: Legacy logging functions for backward compatibility
# These will be removed in a future version. Use log::* functions instead.
# ============================================================================
log() {
    log::success "$@"
}

log_error() {
    log::error "$@"
}

log_warning() {
    log::warning "$@"
}

log_info() {
    log::info "$@"
}

log_debug() {
    log::debug "$@"
}

log_prompt() {
    log::prompt "$@"
}

log_input() {
    log::input "$@"
}

# Wrapper for read that logs input
read_with_log() {
    local prompt="$1"
    local var_name="$2"
    # CRITICAL: Reset IFS after read
    local old_IFS="${IFS:-}"
    log_prompt "$prompt"
    # shellcheck disable=SC2162,SC2086
    IFS= read -r -p "$prompt" ${var_name?}
    log_input "${!var_name}"
    # CRITICAL: Reset IFS
    IFS="$old_IFS"
}

# Note: All echo statements should also call log() for comprehensive logging
# This ensures everything is logged to the log file

log_command() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cmd_args="$*"
    echo "[$timestamp] EXEC: $cmd_args" >> "$LOG_FILE"
    local output
    output=$("$@" 2>&1)
    local exit_code=$?
    if [ -n "$output" ]; then
        echo "$output" | while IFS= read -r line; do
            echo "[$timestamp] OUTPUT: $line" >> "$LOG_FILE"
        done
    fi
    return $exit_code
}

# Log all environment variables relevant to Wine/Proton
log_environment() {
    log_debug "=== Environment Variables ==="
    log_debug "PATH: $PATH"
    log_debug "WINEPREFIX: ${WINEPREFIX:-not set}"
    log_debug "WINEARCH: ${WINEARCH:-not set}"
    # REMOVED: Proton GE environment variables
    log_debug "SCR_PATH: ${SCR_PATH:-not set}"
    log_debug "WINE_PREFIX: ${WINE_PREFIX:-not set}"
    log_debug "RESOURCES_PATH: ${RESOURCES_PATH:-not set}"
    log_debug "CACHE_PATH: ${CACHE_PATH:-not set}"
    log_debug "LANG: ${LANG:-not set}"
    log_debug "LANG_CODE: ${LANG_CODE:-not set}"
    log_debug "=== End Environment Variables ==="
}

# Log system information (with timeout protection to prevent hanging)
log_system_info() {
    log_debug "=== System Information ==="
    log_debug "OS: $(uname -a 2>&1)"
    
    local distro=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'unknown')
    log_debug "Distribution: $distro"
    
    # Wine version (Proton-GE)
    local wine_ver="unknown"
    if wine_runtime::init 2>/dev/null; then
        wine_ver="$(wine_runtime::describe 2>/dev/null || echo "Proton-GE")"
        if [ -n "${WINE_RUNTIME_BIN:-}" ] && [ -x "${WINE_RUNTIME_BIN}" ]; then
            wine_ver="$wine_ver ($("$WINE_RUNTIME_BIN" --version 2>/dev/null | head -1))"
        fi
    fi
    log_debug "Wine runtime: $wine_ver"
    
    # Winetricks version - this can hang, so we use a safer approach
    log_debug "Winetricks: checking..."
    if command -v winetricks &>/dev/null; then
        # Try to get version quickly, but don't wait forever
        if command -v timeout &>/dev/null; then
            local winetricks_ver=$(timeout 1 winetricks --version 2>&1 | head -1 || echo 'timeout')
        else
            # Fallback: just check if it exists
            local winetricks_ver="installed (version check skipped)"
        fi
    else
        local winetricks_ver="not found"
    fi
    log_debug "Winetricks: $winetricks_ver"
    
    # REMOVED: Proton GE check - Proton GE support removed
    
    log_debug "Active wine binary: $(photoshop_setup::wine_binary 2>/dev/null || echo unknown)"
    log_debug "=== End System Information ==="
}

# Detect system language
LANG_CODE="${LANG:0:2}"
if [ "$LANG_CODE" != "de" ]; then
    LANG_CODE="en"
fi

# Detect system distribution for recommendations
detect_system() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "${ID:-unknown}"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# REMOVED: Proton GE support removed - check_proton_ge_installable() function removed

# Detect available Wine runtimes (default install: Proton-GE only)
detect_all_wine_versions() {
    local options=()
    local descriptions=()
    local paths=()
    local index=1
    local recommended_index=1

    wine_runtime::_load_lock 2>/dev/null || true

    # Default path: Proton-GE only — no system wine in install menu
    if [ "${WINE_METHOD:-proton-ge}" = "proton-ge" ]; then
        if wine_runtime::ensure_proton_ge 2>/dev/null; then
            local ge_desc
            ge_desc="$(wine_runtime::describe 2>/dev/null || echo "Proton-GE ${PROTON_GE_TAG:-}")"
            options+=("1")
            descriptions+=("Proton-GE: $ge_desc ⭐ $(i18n::get "recommended" 2>/dev/null || echo "recommended")")
            paths+=("proton-ge")
            WINE_RECOMMENDED=1
            WINE_OPTIONS=("${options[@]}")
            WINE_DESCRIPTIONS=("${descriptions[@]}")
            WINE_PATHS=("${paths[@]}")
            return 1
        fi
        WINE_OPTIONS=()
        WINE_DESCRIPTIONS=()
        WINE_PATHS=()
        return 0
    fi

    local system
    system=$(detect_system)

    if wine_runtime::ensure_proton_ge 2>/dev/null; then
        local ge_desc
        ge_desc="$(wine_runtime::describe 2>/dev/null || echo "Proton-GE ${PROTON_GE_TAG:-}")"
        options+=("$index")
        descriptions+=("Proton-GE: $ge_desc ⭐ $(i18n::get "recommended" 2>/dev/null || echo "recommended")")
        paths+=("proton-ge")
        recommended_index=$index
        ((index++))
    fi

    # Priority 2: Wine Staging
    # Wine 10.x WOW64-Modus ist experimentell und verursacht bei Photoshop häufig Rendering-Glitches
    # Wine 9.x ist stabiler und wird für Photoshop 2021 empfohlen
    if command -v wine-staging &> /dev/null; then
        local version=$(wine-staging --version 2>/dev/null | head -1 || echo "unknown")
        local wine_major_version=$(echo "$version" | grep -oE "wine-[0-9]+" | grep -oE "[0-9]+" | head -1 || echo "0")
        
        options+=("$index")
        if [ "$wine_major_version" -ge 9 ] && [ "$wine_major_version" -lt 10 ]; then
            # Wine 9.x - empfohlen für Photoshop 2021
            local recommended_text=$(i18n::get "recommended")
            descriptions+=("Wine Staging: $version ⭐ $recommended_text (stabiler für Photoshop 2021)")
            recommended_index=$index  # Wine 9.x als empfohlen setzen
        else
            local alternative_text=$(i18n::get "wine_staging_alternative")
            descriptions+=("Wine Staging: $version ($alternative_text)")
        fi
        paths+=("wine-staging")
        ((index++))
    fi
    
    # Priority 3: Standard Wine (Warnung bei Wine 10.x, nicht bei 11.0+)
    if command -v wine &> /dev/null; then
        local version=$(wine --version 2>/dev/null | head -1 || echo "unknown")
        local wine_major_version=$(echo "$version" | grep -oE "wine-[0-9]+" | grep -oE "[0-9]+" | head -1 || echo "0")
        
        options+=("$index")
        local fallback_text=$(i18n::get "fallback")
        if [ "$wine_major_version" -eq 10 ]; then
            # Wine 10.x - Warnung hinzufügen (WoW64 experimentell)
            descriptions+=("Standard Wine: $version ($fallback_text) ⚠ Wine 10.x kann Probleme verursachen - Wine 9.x oder 11.0+ empfohlen")
        elif [ "$wine_major_version" -ge 11 ]; then
            # Wine 11.0+ - WoW64 vollständig unterstützt, keine Warnung
            descriptions+=("Standard Wine: $version ($fallback_text)")
        else
            descriptions+=("Standard Wine: $version ($fallback_text)")
        fi
        paths+=("wine")
        ((index++))
    fi
    
    # Store recommended index
    WINE_RECOMMENDED=$recommended_index
    
    # Return via global arrays (bash limitation)
    WINE_OPTIONS=("${options[@]}")
    WINE_DESCRIPTIONS=("${descriptions[@]}")
    WINE_PATHS=("${paths[@]}")
    
    return ${#options[@]}
}

# ============================================================================
# @function handle_wine_method_parameter
# @description Handle WINE_METHOD command line parameter (--wine-standard)
# @return Selected option index (1-based) if found, empty string if not set or not found
# ============================================================================
handle_wine_method_parameter() {
    # Check if WINE_METHOD is set via command line parameter (skip interactive menu)
    # CRITICAL: Export WINE_METHOD so it's available in all scopes
    export WINE_METHOD="${WINE_METHOD:-}"
    if [ -z "$WINE_METHOD" ]; then
        echo ""  # No parameter set
        return 1
    fi
    
    # CRITICAL: Redirect all log output to stderr to prevent it from being captured
    # This function returns only the index via stdout
    log "Wine-Methode wurde per Parameter gesetzt: $WINE_METHOD" >&2
    log_debug "Wine-Methode Parameter: $WINE_METHOD" >&2
    debug_log "PhotoshopSetup.sh:484" "WINE_METHOD set via parameter" "{\"WINE_METHOD\":\"${WINE_METHOD}\"}" "H1"
    
    # Show info output to user about Wine method being used
    if type output::info >/dev/null 2>&1; then
        output::info "Using Wine method from parameter: $WINE_METHOD" >&2
    else
        log "Using Wine method from parameter: $WINE_METHOD" >&2
    fi
    
    local skip_text=$(i18n::get "skipping_interactive_selection")
    local wine_method_display
    case "$WINE_METHOD" in
        proton-ge) wine_method_display="$(i18n::get "proton_ge" 2>/dev/null || echo "Proton-GE")" ;;
        wine-staging) wine_method_display="Wine Staging" ;;
        *) wine_method_display="$(i18n::get "wine_standard" 2>/dev/null || echo "Wine Standard")" ;;
    esac
    log "$skip_text: $wine_method_display" >&2
    
    # Find the matching option index
    # CRITICAL: We need to return the option NUMBER from WINE_OPTIONS, not the array index
    local found=0
    local selected_option=""
    for i in "${!WINE_PATHS[@]}"; do
        local path="${WINE_PATHS[$i]}"
        if [ "$WINE_METHOD" = "wine" ] && { [ "$path" = "wine" ] || [ "$path" = "wine-staging" ]; }; then
            selected_option="${WINE_OPTIONS[$i]}"
            found=1
            log_debug "Wine gefunden bei Array-Index $i, Option-Nummer: $selected_option" >&2
            break
        fi
        if [ "$WINE_METHOD" = "proton-ge" ] && [ "$path" = "proton-ge" ]; then
            selected_option="${WINE_OPTIONS[$i]}"
            found=1
            log_debug "Proton-GE gefunden bei Array-Index $i, Option-Nummer: $selected_option" >&2
            break
        fi
    done
    
    if [ $found -eq 0 ]; then
        log_error "Angeforderte Wine-Methode '$WINE_METHOD' nicht gefunden!" >&2
        local error_msg=$(i18n::get "wine_method_not_found")
        error "$(printf "$error_msg" "$WINE_METHOD")" >&2
        echo ""  # Not found, fall through to interactive menu
        return 1
    else
        # Use the found selection and skip menu
        log "Verwende automatisch ausgewählte Option: $selected_option" >&2
        echo "$selected_option"  # Return option number from WINE_OPTIONS (ONLY this goes to stdout)
        return 0  # Successfully handled
    fi
}

# ============================================================================
# REMOVED: Proton GE support functions removed
# Functions removed: check_proton_ge_availability(), find_proton_ge_path(), validate_and_configure_proton_ge()
# REMOVED: Proton GE installation functions removed
# Functions removed: install_proton_ge_auto(), prompt_install_proton_ge(), install_proton_ge_interactive()
# ============================================================================

# Handle the case when only one Wine option is available
# Returns: selection number or empty string
# Show interactive menu for Wine selection
# Returns: selected option number via echo
show_wine_selection_menu() {
    echo ""
    
    # Step 1: Check if Wine is installed
    if [ "$LANG_CODE" = "de" ]; then
        log "$(i18n::get "step_check_wine_short")"
    else
        log "$(i18n::get "step_check_wine_short_en")"
    fi
    echo ""
    if ! command -v wine &> /dev/null; then
        if [ "$LANG_CODE" = "de" ]; then
            log "$(i18n::get "wine_missing_install")"
            log "$(i18n::get "wine_needed_components")"
        else
            log "$(i18n::get "wine_missing_install_en")"
            log "$(i18n::get "wine_needed_components_en")"
        fi
        echo ""
        if command -v pacman &> /dev/null; then
            log_command sudo pacman -S wine
        else
            if [ "$LANG_CODE" = "de" ]; then
                log "$(i18n::get "install_wine_manually_short")"
                log_prompt "$(i18n::get "press_enter_wine_installed")"
                IFS= read -r -p "$(i18n::get "press_enter_wine_installed")" wait_wine
            else
                log "$(i18n::get "install_wine_manually_short_en")"
                log_prompt "$(i18n::get "press_enter_wine_installed_en")"
                IFS= read -r -p "$(i18n::get "press_enter_wine_installed_en")" wait_wine
            fi
            log_input "$wait_wine"
        fi
        echo ""
    else
        if [ "$LANG_CODE" = "de" ]; then
            log "$(i18n::get "wine_already_installed_short")"
        else
            log "$(i18n::get "wine_already_installed_short_en")"
        fi
        echo ""
    fi
    
    # Step 2: Install Proton GE
    if [ "$LANG_CODE" = "de" ]; then
        log "$(i18n::get "step_install_proton_short")"
        log "$(i18n::get "proton_install_takes_time_short")"
    else
        log "$(i18n::get "step_install_proton_short_en")"
        log "$(i18n::get "proton_install_takes_time_short_en")"
    fi
    echo ""
    
    local install_success=0
    local proton_ge_install_path=""
    
    # OPTION 1: Try AUR package (Arch-based)
    if command -v yay &> /dev/null || command -v paru &> /dev/null; then
        local aur_helper=""
        if command -v yay &> /dev/null; then
            aur_helper="yay"
        else
            aur_helper="paru"
        fi
        
        log "  → Versuche Installation über AUR ($aur_helper)..."
        log_command $aur_helper -S --noconfirm proton-ge-custom-bin
        if [ $? -eq 0 ]; then
            local proton_ge_path=$(pacman -Ql proton-ge-custom-bin 2>/dev/null | grep "files/bin/wine$" | head -1 | awk '{print $2}' | xargs dirname | xargs dirname | xargs dirname)
            if [ -n "$proton_ge_path" ] && [ -d "$proton_ge_path" ]; then
                if [[ "$proton_ge_path" =~ steam ]]; then
                    log "⚠ AUR-Paket installiert in Steam-Verzeichnis - überspringe"
                    log "   → Installiere Proton GE manuell system-weit..."
                    install_success=0
                else
                    log "✓ Proton GE system-weit installiert: $proton_ge_path"
                    echo "$(i18n::get "proton_ge_installed_systemwide")"
                    install_success=1
                    proton_ge_install_path="$proton_ge_path"
                fi
            fi
        fi
    fi
    
    # OPTION 2: Manual installation (universal for all Linux distributions)
    if [ $install_success -eq 0 ]; then
        log "  → Installiere Proton GE manuell system-weit..."
        echo "$(i18n::get "proton_ge_manual_installing")"
        
        local install_base=""
        if [ -w "/usr/local/share" ]; then
            install_base="/usr/local/share/proton-ge"
        elif [ -w "$HOME/.local/share" ]; then
            install_base="$HOME/.local/share/proton-ge"
        else
            install_base="$HOME/.proton-ge"
        fi
        
        log "  → Installationspfad: $install_base"
        
        mkdir -p "$install_base" 2>/dev/null || {
            log_error "Konnte Installationsverzeichnis nicht erstellen: $install_base"
            install_success=0
        }
        
        if [ -d "$install_base" ]; then
            log "  → Lade neueste Proton GE Version herunter..."
            echo "$(i18n::get "proton_ge_downloading")"
            
            local latest_version=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
            
            if [ -z "$latest_version" ]; then
                latest_version="GE-Proton10-28"  # Fallback version (updated 2025-01-09)
                log "  ⚠ Konnte neueste Version nicht ermitteln, verwende Fallback: $latest_version"
            else
                log "  → Neueste Version gefunden: $latest_version"
            fi
            
            local download_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${latest_version}/${latest_version}.tar.gz"
            local download_file="$install_base/${latest_version}.tar.gz"
            
            # URL validation
            local download_ok=0
            if [[ "$download_url" =~ ^https:// ]] && [[ "$download_url" =~ ^https://(www\.)?github\.com ]]; then
                log "  → Download von: $download_url"
                echo "$(i18n::get "proton_ge_download_running")"
                
                if command -v wget &> /dev/null; then
                    wget -q --show-progress -O "$download_file" "$download_url" 2>&1 | tee -a "$LOG_FILE"
                    if [ $? -eq 0 ] && [ -f "$download_file" ]; then
                        download_ok=1
                    else
                        log_error "Download fehlgeschlagen"
                    fi
                elif command -v curl &> /dev/null; then
                    curl -L --progress-bar -o "$download_file" "$download_url" 2>&1 | tee -a "$LOG_FILE"
                    if [ $? -eq 0 ] && [ -f "$download_file" ]; then
                        download_ok=1
                    else
                        log_error "Download fehlgeschlagen"
                    fi
                else
                    log_error "wget oder curl nicht gefunden - Download nicht möglich"
                fi
            else
                log_error "Ungültige Download-URL: $download_url"
            fi
            
            if [ $download_ok -eq 1 ] && [ -f "$download_file" ]; then
                log "  → Entpacke Proton GE..."
                echo "$(i18n::get "proton_ge_extracting")"
                tar -xzf "$download_file" -C "$install_base" 2>&1 | tee -a "$LOG_FILE"
                if [ $? -eq 0 ]; then
                    local extracted_dir="$install_base/${latest_version}"
                    if [ -d "$extracted_dir" ] && [ -f "$extracted_dir/files/bin/wine" ]; then
                        log "✓ Proton GE manuell installiert: $extracted_dir"
                        echo "$(i18n::get "proton_ge_installed_systemwide")"
                        install_success=1
                        proton_ge_install_path="$extracted_dir"
                        
                        if [ -d "$install_base" ]; then
                            ln -sfn "$extracted_dir" "$install_base/current" 2>/dev/null || {
                                # Symlink creation failure is non-critical, but log it if warning function exists
                                if type warning >/dev/null 2>&1; then
                                    warning "Failed to create symlink: $install_base/current" 2>/dev/null || true
                                fi
                            }
                        fi
                    else
                        log_error "Installation unvollständig - wine-Binary nicht gefunden"
                        install_success=0
                    fi
                else
                    log_error "Entpacken fehlgeschlagen"
                    install_success=0
                fi
                
                rm -f "$download_file" 2>/dev/null || true
            else
                install_success=0
            fi
        fi
    fi
    
    # Handle installation result
    if [ $install_success -eq 0 ]; then
        log "⚠ Automatische Installation fehlgeschlagen"
        echo ""
        echo "$(i18n::get "proton_ge_install_failed")"
        echo ""
        echo "$(i18n::get "you_can_install_proton_ge_manually")"
        echo "  1. https://github.com/GloriousEggroll/proton-ge-custom/releases"
        echo "  2. Oder: erneut starten — Setup lädt Proton nach:"
        echo "     $(wine_software_runtime_dir 2>/dev/null || echo '~/.local/share/wine-software/runtime/proton-ge')"
        echo ""
        echo "  Proton-GE ist Pflicht. System-Wine wird nicht unterstützt."
        log_error "Proton-GE Installation fehlgeschlagen — Abbruch"
        error "$(i18n::get "proton_ge_not_found" 2>/dev/null || echo "Proton-GE not available")"
        return 1
    fi
    
    # Success - re-detect versions
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "$(i18n::get "proton_ge_install_success")"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "$(i18n::get "options_available")"
    echo "$(i18n::get "can_choose_proton_wine")"
    echo ""
    echo "$(i18n::get "searching_versions")"
    echo ""
    
    detect_all_wine_versions
    
    return 0  # Success
}

# Handle the case when only one Wine option is available
# Returns: selection number or empty string
# Show interactive menu for Wine selection
# Returns: selected option number via echo
show_wine_selection_menu() {
    local system="$1"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "           $(i18n::get "select_wine_version")"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Show system detection
    echo "$(i18n::get "system_detected" "$system")"
    # REMOVED: Proton GE recommendations - only Wine Standard/Staging supported
    echo ""
    
    # Display options
    for i in "${!WINE_OPTIONS[@]}"; do
        local opt_num="${WINE_OPTIONS[$i]}"
        local desc="${WINE_DESCRIPTIONS[$i]}"
        echo "  [$opt_num] $desc"
    done
    
    echo ""
    
    # Get user selection with recommended default
    local default_choice=$WINE_RECOMMENDED
    local valid_options=$(IFS=,; echo "${WINE_OPTIONS[*]}")
    local selection=""
    
    while true; do
        IFS= read -r -p "$(i18n::get "choose_option_wine" "$valid_options" "$default_choice") " selection
        
        # Default to recommended option
        if [ -z "$selection" ]; then
            selection=$default_choice
        fi
        
        # Validate selection - check if it exists in WINE_OPTIONS array
        local is_valid=0
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            for opt in "${WINE_OPTIONS[@]}"; do
                if [ "$opt" = "$selection" ]; then
                    is_valid=1
                    break
                fi
            done
        fi
        
        if [ $is_valid -eq 1 ]; then
            break
        else
            echo "$(i18n::get "invalid_selection" "$valid_options")"
        fi
    done
    
    echo "$selection"
}

# Find index of selected Wine option
# Returns: index via echo, -1 if not found
find_selected_wine_index() {
    local selection="$1"
    local selected_index=-1
    
    for i in "${!WINE_OPTIONS[@]}"; do
        if [ "${WINE_OPTIONS[$i]}" = "$selection" ]; then
            selected_index=$i
            break
        fi
    done
    echo "$selected_index"
}

# Configure Wine environment based on selected path
configure_selected_wine() {
    local selected_path="$1"
    local selected_desc="$2"

    log "Ausgewählte Version: $selected_desc"
    log "Pfad: $selected_path"

    if [ "$selected_path" = "proton-ge" ]; then
        export WINE_METHOD="proton-ge"
        wine_runtime::reset
        if ! wine_runtime::init; then
            error "$(i18n::get "proton_ge_not_found" 2>/dev/null || echo "Proton-GE not found")"
            return 1
        fi
        wine_runtime::export_env
        log "✓ Proton-GE konfiguriert"
        return 0
    fi

    export PROTON_PATH=""
    if [ "$selected_path" = "wine-staging" ]; then
        export WINE_RUNTIME_PREFER_SYSTEM=1
        WINE_METHOD="wine"
    else
        export WINE_RUNTIME_PREFER_SYSTEM=1
    fi
    wine_runtime::init 2>/dev/null || true
    wine_runtime::export_env 2>/dev/null || export WINE="$(command -v "$selected_path" 2>/dev/null || command -v wine)"
    log "✓ Wine konfiguriert"
}

handle_single_wine_option() {
    local system="$1"
    local selection="${WINE_OPTIONS[0]:-1}"
    
    # Skip prompt if WINE_METHOD is already set
    if [ -n "$WINE_METHOD" ]; then
        log_debug "WINE_METHOD bereits gesetzt ($WINE_METHOD)"
        debug_log "PhotoshopSetup.sh:527" "WINE_METHOD check - skipping prompt" "{\"WINE_METHOD\":\"${WINE_METHOD}\",\"count\":1}" "H1"
        echo "$selection"
        return 0
    fi
    
    # REMOVED: Proton GE support - only Wine Standard/Staging supported
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "           Installation mit Wine"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Verwende: ${WINE_DESCRIPTIONS[0]}"
    echo ""
    selection="${WINE_OPTIONS[0]:-1}"
    
    echo "$selection"
    return 0
}

# Verify Photoshop.exe exists in the Wine prefix after Adobe installer
validate_photoshop_installation() {
    local exe_path=""
    exe_path="$(photoshop::find_exe "$WINE_PREFIX" 2>/dev/null || true)"
    if [ -n "$exe_path" ] && [ -f "$exe_path" ]; then
        log_debug "validate_photoshop_installation: OK $exe_path"
        return 0
    fi
    log_error "validate_photoshop_installation: Photoshop.exe not found in prefix $WINE_PREFIX"
    return 1
}

# Interactive selection of Wine version
select_wine_version() {
    log_debug "=== select_wine_version() gestartet ==="
    local count=0
    local system=$(detect_system)
    log_debug "System erkannt: $system"
    local selection=""  # Declare at function start
    
    log_debug "Rufe detect_all_wine_versions() auf..."
    detect_all_wine_versions || true
    count=${#WINE_OPTIONS[@]}
    log_debug "detect_all_wine_versions: $count Option(en)"
    
    if [ $count -eq 0 ]; then
        log_error "Keine Wine/Proton-Version gefunden!"
        error "$(i18n::get "no_wine_found")"
        return 1
    fi
    
    # Handle command line parameter (--wine-standard)
    local param_selection
    param_selection=$(handle_wine_method_parameter)
    if [ -n "$param_selection" ]; then
        selection="$param_selection"
        # Parameter was handled successfully, selection is set
        # Continue to setup_wine_environment with the selected option
        # No menu needed - skip to configuration
    fi
    
    # REMOVED: Proton GE check - only Wine Standard/Staging supported
    
    # If only one option available, use it automatically (no menu)
    # BUT: Skip if selection is already set via command line parameter
    if [ $count -eq 1 ] && [ -z "$selection" ]; then
        local single_selection
        single_selection=$(handle_single_wine_option "$system")
        if [ $? -ne 0 ]; then
            return 1  # User cancelled
        fi
        selection="$single_selection"
        
        # If selection is empty, jump to menu
        if [ -z "$selection" ]; then
            # Re-detect to get updated count
            detect_all_wine_versions || true
            count=${#WINE_OPTIONS[@]}
        fi
    fi
    
    # If count > 1 AND selection is empty, show menu
    # If selection is already set (after auto-install), skip menu
    if [ $count -gt 1 ] && [ -z "$selection" ]; then
        selection=$(show_wine_selection_menu "$system")
    fi
    
    # Find selected option index
    local selected_index
    log_debug "DEBUG: selection='$selection'"
    log_debug "DEBUG: WINE_OPTIONS=(${WINE_OPTIONS[*]})"
    log_debug "DEBUG: WINE_PATHS=(${WINE_PATHS[*]})"
    selected_index=$(find_selected_wine_index "$selection")
    log_debug "DEBUG: selected_index=$selected_index"
    
    if [ "$selected_index" = "-1" ]; then
        log_error "DEBUG: Selection '$selection' not found in WINE_OPTIONS=(${WINE_OPTIONS[*]})"
        error "$(i18n::get "selection_not_found")"
        return 1
    fi
    
    # Setup selected version
    local selected_path="${WINE_PATHS[$selected_index]}"
    local selected_desc="${WINE_DESCRIPTIONS[$selected_index]}"
    
    # Configure environment based on selection
    configure_selected_wine "$selected_path" "$selected_desc"
    
    return 0
}

# Setup Wine environment (wrapper for compatibility)
setup_wine_environment() {
    select_wine_version
}

# Localized messages - now using i18n::get instead of MSG_* variables

# NOTE: main() function is defined later in the file (line ~2005)
# This placeholder was removed to avoid duplicate function definitions

# Setup Wine environment (wrapper for compatibility)
setup_wine_environment() {
    select_wine_version
}

# Localized messages - now using i18n::get instead of MSG_* variables

# Detect Photoshop version from installer files or directory structure
# Uses multiple methods: pev/peres tool, directory structure, or file metadata
detect_photoshop_version() {
    local installer_dir="${PHOTOSHOP_INSTALLER_DIR:-$PROJECT_ROOT/photoshop}"
    local version=""
    local setup_exe="$installer_dir/Set-up.exe"
    local codex_version=""
    local major_ver=""

    if [ ! -f "$setup_exe" ]; then
        if resolved="$(photoshop::resolve_installer_dir "$PROJECT_ROOT" 2>/dev/null)"; then
            installer_dir="$resolved"
            setup_exe="$installer_dir/Set-up.exe"
        fi
    fi

    if [ ! -f "$setup_exe" ]; then
        log_debug "detect_photoshop_version: Set-up.exe not found, default 2021 (best-effort)"
        echo "2021"
        return 0
    fi

    # METHOD 1: PHSP Application.json (Adobe offline installers)
    log_debug "detect_photoshop_version: METHOD 1 - PHSP Application.json"
    for app_json in "$installer_dir"/products/PHSP/*/Application.json; do
        [ -f "$app_json" ] || continue
        codex_version=$(grep -oE '"CodexVersion"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+"' "$app_json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -z "$codex_version" ]; then
            codex_version=$(grep -oE '<CodexVersion>[0-9]+\.[0-9]+</CodexVersion>' "$app_json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        fi
        if [ -n "$codex_version" ]; then
            major_ver=$(echo "$codex_version" | cut -d. -f1)
            if [ "$major_ver" -ge 23 ]; then
                version="2022"
            elif [ "$major_ver" -ge 22 ]; then
                version="2021"
            elif [ "$major_ver" -ge 20 ]; then
                version="CC 2019"
            fi
            log_debug "detect_photoshop_version: METHOD 1 PHSP CodexVersion=$codex_version -> $version"
            break
        fi
    done

    # METHOD 2: Any Driver.xml under products/
    if [ -z "$version" ]; then
        log_debug "detect_photoshop_version: METHOD 2 - Driver.xml scan"
        local driver_file=""
        for driver_file in "$installer_dir"/products/Driver.xml "$installer_dir"/products/*/Driver.xml; do
            [ -f "$driver_file" ] || continue
            local name_line
            name_line=$(grep -iE "<Name>.*Photoshop.*</Name>" "$driver_file" 2>/dev/null | head -1)
            if echo "$name_line" | grep -qiE "2022"; then
                version="2022"
            elif echo "$name_line" | grep -qiE "2021"; then
                version="2021"
            elif echo "$name_line" | grep -qiE "CC 2019|2019"; then
                version="CC 2019"
            fi
            if [ -z "$version" ]; then
                codex_version=$(grep -iE "<CodexVersion>|<BaseVersion>" "$driver_file" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1)
                if [ -n "$codex_version" ]; then
                    major_ver=$(echo "$codex_version" | cut -d. -f1)
                    if [ "$major_ver" -ge 23 ]; then
                        version="2022"
                    elif [ "$major_ver" -ge 22 ]; then
                        version="2021"
                    elif [ "$major_ver" -ge 20 ]; then
                        version="CC 2019"
                    fi
                fi
            fi
            [ -n "$version" ] && break
        done
    fi

    # METHOD 3: Legacy root Driver.xml
    if [ -z "$version" ] && [ -f "$installer_dir/products/Driver.xml" ]; then
        log_debug "detect_photoshop_version: checking Driver.xml"
        local name_line=$(grep -iE "<Name>.*Photoshop.*</Name>" "$installer_dir/products/Driver.xml" 2>/dev/null | head -1)
        log_debug "detect_photoshop_version: found Name line: $name_line"
        if [ -n "$name_line" ]; then
            if echo "$name_line" | grep -qiE "2022"; then
                version="2022"
                log_debug "detect_photoshop_version: METHOD 1 detected 2022 from Driver.xml Name"
            elif echo "$name_line" | grep -qiE "2021"; then
                version="2021"
                log_debug "detect_photoshop_version: METHOD 1 detected 2021 from Driver.xml Name"
            elif echo "$name_line" | grep -qiE "CC 2019|2019"; then
                version="CC 2019"
                log_debug "detect_photoshop_version: METHOD 1 detected CC 2019 from Driver.xml Name"
            fi
        fi
        # Also check CodexVersion/BaseVersion (22.0 = 2021, 23.0 = 2022, 20.x = CC 2019)
        if [ -z "$version" ]; then
            local codex_version=$(grep -iE "<CodexVersion>|<BaseVersion>" "$installer_dir/products/Driver.xml" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1)
            log_debug "detect_photoshop_version: found CodexVersion/BaseVersion: $codex_version"
            if [ -n "$codex_version" ]; then
                local major_ver=$(echo "$codex_version" | cut -d. -f1)
                if [ "$major_ver" -ge 23 ]; then
                    version="2022"
                    log_debug "detect_photoshop_version: METHOD 1 detected 2022 from CodexVersion $codex_version"
                elif [ "$major_ver" -ge 22 ]; then
                    version="2021"
                    log_debug "detect_photoshop_version: METHOD 1 detected 2021 from CodexVersion $codex_version"
                elif [ "$major_ver" -ge 20 ]; then
                    version="CC 2019"
                    log_debug "detect_photoshop_version: METHOD 1 detected CC 2019 from CodexVersion $codex_version"
                fi
            fi
        fi
    fi
    
    # METHOD 2: Try to extract version from EXE using multiple tools
    # Based on: https://askubuntu.com/questions/23454/how-to-view-a-pe-exe-dll-file-version-information
    # and https://superuser.com/questions/1159092/getting-info-about-windows-executables-on-a-linux-system
    if [ -z "$version" ]; then
        # Try peres first (lightweight)
        if command -v peres >/dev/null 2>&1; then
            local exe_version=$(peres -v "$setup_exe" 2>/dev/null | awk '{print $3}' | head -1)
            log_debug "detect_photoshop_version: peres found version: $exe_version"
            if [ -n "$exe_version" ] && [[ "$exe_version" =~ ^[0-9] ]]; then
                local major_version=$(echo "$exe_version" | cut -d. -f1)
                log_debug "detect_photoshop_version: major_version=$major_version"
                if [ "$major_version" -ge 23 ]; then
                    version="2022"
                elif [ "$major_version" -ge 22 ]; then
                    version="2021"
                elif [ "$major_version" -ge 20 ]; then
                    version="CC 2019"
                fi
                log_debug "detect_photoshop_version: METHOD 2 (peres) detected: $version"
            fi
        # Try ExifTool (more comprehensive, shows Product Version)
        # See: https://superuser.com/questions/1159092/getting-info-about-windows-executables-on-a-linux-system
        elif command -v exiftool >/dev/null 2>&1; then
            log_debug "detect_photoshop_version: trying ExifTool"
            local product_version=$(exiftool "$setup_exe" 2>/dev/null | grep -iE "Product Version|File Version" | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
            log_debug "detect_photoshop_version: ExifTool found version: $product_version"
            if [ -n "$product_version" ]; then
                local major_version=$(echo "$product_version" | cut -d. -f1)
                if [ "$major_version" -ge 23 ]; then
                    version="2022"
                elif [ "$major_version" -ge 22 ]; then
                    version="2021"
                elif [ "$major_version" -ge 20 ]; then
                    version="CC 2019"
                fi
                log_debug "detect_photoshop_version: METHOD 2 (ExifTool) detected: $version"
            fi
        # Try pev as fallback
        elif command -v pev >/dev/null 2>&1; then
            log_debug "detect_photoshop_version: trying pev"
            local exe_version=$(pev "$setup_exe" 2>/dev/null | grep -iE "version" | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
            log_debug "detect_photoshop_version: pev found version: $exe_version"
            if [ -n "$exe_version" ]; then
                local major_version=$(echo "$exe_version" | cut -d. -f1)
                if [ "$major_version" -ge 23 ]; then
                    version="2022"
                elif [ "$major_version" -ge 22 ]; then
                    version="2021"
                elif [ "$major_version" -ge 20 ]; then
                    version="CC 2019"
                fi
                log_debug "detect_photoshop_version: METHOD 2 (pev) detected: $version"
            fi
        else
            log_debug "detect_photoshop_version: peres/ExifTool/pev not found, trying other methods"
        fi
    fi
    
    # METHOD 3: Check directory structure in installer
    if [ -z "$version" ]; then
        log_debug "detect_photoshop_version: METHOD 3 - checking directory structure"
        # Check for version-specific directories in root
        for dir in "$installer_dir"/Adobe\ Photoshop*; do
            if [ -d "$dir" ]; then
                local dirname=$(basename "$dir")
                log_debug "detect_photoshop_version: found directory: $dirname"
                if [[ "$dirname" =~ "2022" ]]; then
                    version="2022"
                    log_debug "detect_photoshop_version: METHOD 3 detected 2022 from directory"
                    break
                elif [[ "$dirname" =~ "2021" ]]; then
                    version="2021"
                    log_debug "detect_photoshop_version: METHOD 3 detected 2021 from directory"
                    break
                elif [[ "$dirname" =~ "CC 2019" ]] || [[ "$dirname" =~ "2019" ]]; then
                    if [ -z "$version" ]; then
                        version="CC 2019"
                        log_debug "detect_photoshop_version: METHOD 3 detected CC 2019 from directory"
                    fi
                    break
                fi
            fi
        done
        
        # Also check in packages and products subdirectories
        if [ -z "$version" ] || [ "$version" = "CC 2019" ]; then
            for subdir in "$installer_dir/packages" "$installer_dir/products"; do
                if [ -d "$subdir" ]; then
                    for dir in "$subdir"/*; do
                        if [ -d "$dir" ]; then
                            local dirname=$(basename "$dir")
                            log_debug "detect_photoshop_version: found subdirectory: $dirname"
                            if [[ "$dirname" =~ 2022 ]] || [[ "$dirname" =~ 23\. ]]; then
                                version="2022"
                                log_debug "detect_photoshop_version: METHOD 3 detected 2022 from subdirectory"
                                break 2
                            elif [[ "$dirname" =~ 2021 ]] || [[ "$dirname" =~ 22\. ]]; then
                                version="2021"
                                log_debug "detect_photoshop_version: METHOD 3 detected 2021 from subdirectory"
                                break 2
                            elif [[ "$dirname" =~ "CC 2019" ]] || [[ "$dirname" =~ 2019 ]] || [[ "$dirname" =~ 20\. ]]; then
                                if [ -z "$version" ]; then
                                    version="CC 2019"
                                    log_debug "detect_photoshop_version: METHOD 3 detected CC 2019 from subdirectory"
                                fi
                            fi
                        fi
                    done
                fi
            done
        fi
    fi
    
    # METHOD 4: Try to extract version from strings in EXE (fallback)
    if [ -z "$version" ] || [ "$version" = "CC 2019" ]; then
        if command -v strings >/dev/null 2>&1; then
            log_debug "detect_photoshop_version: METHOD 3 - checking strings in EXE"
            # Try multiple patterns to find version
            local version_string=$(strings "$setup_exe" 2>/dev/null | grep -iE "(photoshop|adobe).*(202[12]|22\.|23\.|20\.|CC 2019|2019)" | head -5)
            log_debug "detect_photoshop_version: found version strings: $version_string"
            if [ -n "$version_string" ]; then
                # Check for 2022 first (most specific)
                if echo "$version_string" | grep -qiE "2022|23\."; then
                    version="2022"
                    log_debug "detect_photoshop_version: METHOD 3 detected 2022"
                # Check for 2021 (v22.x)
                elif echo "$version_string" | grep -qiE "2021|22\."; then
                    version="2021"
                    log_debug "detect_photoshop_version: METHOD 3 detected 2021"
                # Check for CC 2019 (v20.x)
                elif echo "$version_string" | grep -qiE "CC 2019|2019|20\."; then
                    if [ -z "$version" ]; then
                        version="CC 2019"
                        log_debug "detect_photoshop_version: METHOD 3 detected CC 2019"
                    fi
                fi
            fi
        fi
    fi
    
    # METHOD 5: Check for version in any files in installer directory
    if [ -z "$version" ] || [ "$version" = "CC 2019" ]; then
        log_debug "detect_photoshop_version: METHOD 5 - checking files in installer directory"
        for file in "$installer_dir"/*; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                if [[ "$filename" =~ "2022" ]]; then
                    version="2022"
                    log_debug "detect_photoshop_version: METHOD 5 detected 2022 from file: $filename"
                    break
                elif [[ "$filename" =~ "2021" ]]; then
                    version="2021"
                    log_debug "detect_photoshop_version: METHOD 5 detected 2021 from file: $filename"
                    break
                fi
            fi
        done
    fi
    
    # Fallback: PHSP package present => CC 2021 best-effort
    if [ -z "$version" ]; then
        if [ -d "$installer_dir/products/PHSP" ]; then
            version="2021"
            log_debug "detect_photoshop_version: PHSP present, default 2021 (best-effort)"
        else
            version="2021"
            log_debug "detect_photoshop_version: No version detected, default 2021 (best-effort, guaranteed v22.0.0.35 only)"
        fi
    fi

    if [ "$version" = "2021" ] && [ "$codex_version" != "22.0.0.35" ]; then
        log_debug "detect_photoshop_version: non-guaranteed v22.x build (best-effort)"
    fi

    log_debug "detect_photoshop_version: FINAL RESULT: $version"
    echo "$version"
}

# Get Photoshop installation path based on version
get_photoshop_install_path() {
    local version="${1:-CC 2019}"
    local wine_prefix="${WINE_PREFIX:-$SCR_PATH/prefix}"
    local user="${USER:-$(id -un)}"
    
    # Convert version to path format
    if [[ "$version" =~ "CC 2019" ]]; then
        echo "$wine_prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2019"
    elif [[ "$version" =~ "2021" ]]; then
        echo "$wine_prefix/drive_c/Program Files/Adobe/Adobe Photoshop 2021"
    elif [[ "$version" =~ "2022" ]]; then
        echo "$wine_prefix/drive_c/Program Files/Adobe/Adobe Photoshop 2022"
    else
        # Fallback to CC 2019 path
        echo "$wine_prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2019"
    fi
}

# Get Photoshop preferences path based on version
get_photoshop_prefs_path() {
    local version="${1:-CC 2019}"
    local wine_prefix="${WINE_PREFIX:-$SCR_PATH/prefix}"
    local user="${USER:-$(id -un)}"
    
    # Convert version to preferences path format
    if [[ "$version" =~ "CC 2019" ]]; then
        echo "$wine_prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop CC 2019"
    elif [[ "$version" =~ "2021" ]]; then
        echo "$wine_prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop 2021"
    elif [[ "$version" =~ "2022" ]]; then
        echo "$wine_prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop 2022"
    else
        # Fallback to CC 2019 path
        echo "$wine_prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop CC 2019"
    fi
}

function main() {
    # CRITICAL: Trap for CTRL+C (INT) and other signals
    # Use cleanup_on_interrupt() function for consistent i18n support
    trap 'cleanup_on_interrupt' INT TERM HUP
    
    # Check for updates in background (non-blocking)
    # Use type instead of command -v for namespace functions (::)
    if type update::check_async >/dev/null 2>&1; then
        update::check_async
    fi
    
    # Enable comprehensive logging - ALL output will be logged automatically
    setup_comprehensive_logging
    
    # CRITICAL: Set PS_VERSION early, before it's used
    # Will be set again later in install_photoshopSE(), but needed here for main()
    PS_VERSION=$(detect_photoshop_version)
    PS_INSTALL_PATH=$(get_photoshop_install_path "$PS_VERSION")
    PS_PREFS_PATH=$(get_photoshop_prefs_path "$PS_VERSION")
    
    # Start logging immediately with comprehensive system info
    # Write header to log file (not to console)
    echo "" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ═══════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Photoshop Installation gestartet: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log-Datei: $LOG_FILE" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error-Log: $ERROR_LOG" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Debug-Log: $DEBUG_LOG" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ═══════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Show system information (modern, beautiful display)
    if type system::get_info >/dev/null 2>&1; then
        output::section "System Information"
        output::info "$(system::get_info)"
        echo ""
    fi
    
    # Show installation header (modern style)
    output::section "Photoshop CC Linux Installation"
    
    # Show log paths in clean format (just filename, not full path)
    if [ "${DEBUG:-0}" = "1" ]; then
        output::log_path "Log file" "$LOG_FILE"
        output::log_path "Debug log" "$DEBUG_LOG"
    echo ""
    fi
    
    # Log comprehensive system information (to file only)
    log_system_info
    echo "" >> "$LOG_FILE"
    
    log_debug "=== Script Initialization ==="
    log_debug "SCRIPT_DIR: $SCRIPT_DIR"
    log_debug "PROJECT_ROOT: $PROJECT_ROOT"
    log_debug "LOG_DIR: $LOG_DIR"
    log_debug "LOG_FILE: $LOG_FILE"
    log_debug "ERROR_LOG: $ERROR_LOG"
    log_debug "=== End Script Initialization ==="
    echo "" >> "$LOG_FILE"
    
    # Create directories (silent, only log)
    mkdir -p $SCR_PATH
    log_debug "SCR_PATH erstellt: $SCR_PATH"
    mkdir -p $CACHE_PATH
    log_debug "CACHE_PATH erstellt: $CACHE_PATH"
    echo "" >> "$LOG_FILE"
    
    setup_log "================| script executed |================"
    log_debug "setup_log aufgerufen"

    # System checks (compact display)
    output::step "$(i18n::get "checking_system_requirements")"
    output::substep "$(i18n::get "system_architecture")"
    is64 >/dev/null 2>&1 || true
    log_debug "is64 Prüfung abgeschlossen"

    # Package checks (compact display)
    output::substep "$(i18n::get "required_packages")"
    # Wine / Proton runtime (always Proton-GE unless --wine-standard)
    if wine_runtime::init 2>/dev/null; then
        log_debug "Runtime: $(wine_runtime::describe 2>/dev/null || echo Proton-GE)"
    else
        log_error "Proton-GE Runtime nicht verfügbar"
        error "$(i18n::get "proton_ge_not_found" 2>/dev/null || echo "Proton-GE not found")"
        exit 1
    fi
    package_installed md5sum >/dev/null 2>&1 || package_installed md5sum
    # Do not invoke winetricks here (may load Proton wine and crash on some systems)
    if command -v winetricks >/dev/null 2>&1 \
        || [ -x "${SCR_PATH:-}/runtime/winetricks/winetricks" ] \
        || { [ -n "${APPDIR:-}" ] && [ -x "${APPDIR}/runtime/winetricks/winetricks" ]; }; then
        log_debug "winetricks: available"
    else
        package_installed winetricks >/dev/null 2>&1 || package_installed winetricks
    fi
    wine_runtime::cache_dir >/dev/null 2>&1 || true
    echo "" >> "$LOG_FILE"

    # Setup Wine environment (GUI: direkt Proton-GE, kein interaktives Menü)
    if [ "${LAUNCHER_GUI:-0}" = "1" ] && [ "${WINE_METHOD:-}" = "proton-ge" ]; then
        output::step "$(i18n::get "wine_proton_selection")"
        wine_runtime::reset
        if ! wine_runtime::init; then
            error "$(i18n::get "proton_ge_not_found" 2>/dev/null || echo "Proton-GE not found")"
            exit 1
        fi
        wine_runtime::export_env
        output::success "$(i18n::get "using_proton_ge" 2>/dev/null || echo "Proton-GE bereit")"
    else
        output::step "$(i18n::get "wine_proton_selection")"
        log_debug "Rufe setup_wine_environment() auf..."
        if ! setup_wine_environment; then
            log_error "setup_wine_environment() fehlgeschlagen!"
            error "$(i18n::get "wine_not_found")"
            exit 1
        fi
        log_debug "setup_wine_environment() erfolgreich abgeschlossen"
        if [ "${WINE_METHOD:-}" = "proton-ge" ]; then
            show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}$(i18n::get "using_proton_ge" 2>/dev/null || echo "→ Using Proton-GE...")${C_RESET}"
        else
            show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}$(i18n::get "using_standard_wine")${C_RESET}"
        fi
        log "Wine aktiviert"
    fi

    RESOURCES_PATH="$SCR_PATH/resources"
    WINE_PREFIX="$SCR_PATH/prefix"
    
    # CRITICAL: Kill ALL Wine processes before starting installation
    # This prevents conflicts, version mismatches, and ensures clean installation
    output::step "$(i18n::get "terminating_wine_processes")"
    if [ "$LANG_CODE" = "de" ]; then
        output::substep "Beende alle laufenden Wine/Photoshop Prozesse..."
    else
        output::substep "Terminating all running Wine/Photoshop processes..."
    fi
    
    # Kill Photoshop processes
    pkill -f "Photoshop.exe" 2>/dev/null && log_debug "Photoshop Prozesse beendet" || log_debug "Keine Photoshop Prozesse gefunden"
    
    # Kill all wineserver instances (Proton + system — prevent version mismatch)
    photoshop_setup::kill_all_wineservers
    wait::for_process "$(pgrep wineserver 2>/dev/null || echo "")" 5 0.2 2>/dev/null || true
    log_debug "Wine Server beendet"
    
    # Kill any remaining wine processes for this prefix
    if [ -d "$WINE_PREFIX" ]; then
        export WINEPREFIX="$WINE_PREFIX"
        photoshop_setup::kill_all_wineservers
        pkill -f "wine.*Photoshop" 2>/dev/null || true
        unset WINEPREFIX
        log_debug "Wine Prozesse für Prefix beendet"
    fi
    
    # Kill any other wine processes
    pkill -f "wine.*${SCR_PATH}" 2>/dev/null || true
    sleep 1
    
    if [ "$LANG_CODE" = "de" ]; then
        output::success "Alle Wine-Prozesse beendet"
    else
        output::success "All Wine processes terminated"
    fi
    echo ""
    
    # Wine-Prefix: wiederverwenden wenn möglich (Rezept-spezifisch, kein winecfg)
    export WINEARCH=win64
    debug_log "PhotoshopSetup.sh:1958" "WINEARCH set before export_var" "{\"WINEARCH\":\"${WINEARCH}\",\"WINE_PREFIX\":\"${WINE_PREFIX}\"}" "H2"
    
    #export necessary variable for wine
    export_var
    
    # Ensure we use Proton-GE wine binary (command -v wine returns the shell function name)
    wine_runtime::export_env 2>/dev/null || true
    local wine_binary
    wine_binary="$(photoshop_setup::wine_binary)"
    log_debug "Verwende Wine-Binary: $wine_binary"
    
    output::step "$(i18n::get "configuring_wine_prefix")"
    if photoshop_setup::prefix_is_initialized; then
        if [ "$LANG_CODE" = "de" ]; then
            output::info "Bestehendes Rezept-Prefix erkannt — überspringe Neu-Erstellung"
        else
            output::info "Existing recipe prefix detected — skipping recreation"
        fi
        export WINEPREFIX="$WINE_PREFIX"
        photoshop_setup::ensure_win10 >> "$LOG_FILE" 2>&1 || true
        wine_runtime::deploy_proton_graphics_dlls >> "$LOG_FILE" 2>&1 || true
    else
        if [ "$LANG_CODE" = "de" ]; then
            output::substep "$(i18n::get "create_prefix_dir")"
            output::info "Prefix wird still initialisiert (Proton-GE, kein winecfg nötig)"
        else
            output::substep "Creating Wine prefix directory..."
            output::info "Initializing prefix silently (Proton-GE, no winecfg needed)"
        fi
        echo ""

        mkdir -p "$WINE_PREFIX" || error "Cannot create Wine prefix directory: $WINE_PREFIX"
        export WINEARCH=win64

        local wine_version_output=$("$wine_binary" --version 2>/dev/null | head -1)
        local wine_major=$(echo "$wine_version_output" | grep -oP '(?<=wine-)[\d]+' | head -1)
        local wineboot_timeout=30
        local wait_timeout=30

        if [ -n "$wine_major" ] && [ "$wine_major" -ge 10 ]; then
            wineboot_timeout=90
            wait_timeout=90
            if [ "$LANG_CODE" = "de" ]; then
                output::substep "Wine 10.x Initialisierung (bis zu 90s, bitte warten)..."
            else
                output::substep "Wine 10.x initialization (up to 90s, please wait)..."
            fi
        fi

        if ! photoshop_setup::init_prefix_silent "$wine_binary" "$wineboot_timeout" "$wait_timeout"; then
            error "Prefix-Initialisierung fehlgeschlagen — siehe Log: $LOG_FILE"
        fi
        checkpoint::create "wine_prefix_initialized"
        if [ "$LANG_CODE" = "de" ]; then
            show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}$(i18n::get "prefix_configured")${C_RESET}"
        else
            show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}Prefix configured...${C_RESET}"
        fi
    fi

    if [ -f "$WINE_PREFIX/user.reg" ]; then
        set_dark_mod
    else
        error "user.reg Not Found after initialization :("
    fi
   
    rmdir_if_exist $RESOURCES_PATH

    if photoshop_setup::wine_runtime_ready; then
        if [ "$LANG_CODE" = "de" ]; then
            output::info "Wine-Laufzeit (MSXML/Prefix) bereits bereit — überspringe Basis-Komponenten"
        else
            output::info "Wine runtime (MSXML/prefix) already ready — skipping base components"
        fi
        photoshop_setup::ensure_native_msxml >> "$LOG_FILE" 2>&1 || {
            error "MSXML-Installation fehlgeschlagen — siehe ${ERROR_LOG:-$LOG_FILE}"
        }
        wine_runtime::deploy_proton_graphics_dlls >> "$LOG_FILE" 2>&1 || true
    elif ! install_wine_components; then
        error "$(i18n::get "wine_components_failed" 2>/dev/null || echo "Wine component installation failed")"
    fi
    
    # Proton-GE: DXVK/vkd3d direkt aus Runtime (winetricks dxvk scheitert unter Proton 10 — kein Fallback)
    output::step "Proton-GE Grafik-DLLs (DXVK/vkd3d)"
    log_debug "Deploy Proton-GE graphics DLLs (kein winetricks dxvk — inkompatibel mit Proton 10.x)"
    if wine_runtime::deploy_proton_graphics_dlls >> "$LOG_FILE" 2>&1; then
        output::success "Proton-GE Grafik-DLLs ins Prefix kopiert"
    else
        log_error "deploy_proton_graphics_dlls fehlgeschlagen — Photoshop-Start kann scheitern"
        output::error "Proton-GE Grafik-DLLs konnten nicht deployed werden (siehe Log)"
        return 1
    fi
    
    # CRITICAL: Ensure d3d11.dll override is set (required for Photoshop 2021+)
    # winetricks may not always set this correctly, so we set it explicitly
    log "${C_YELLOW}  →${C_RESET} ${C_GRAY}Setze d3d11.dll Override (erforderlich für Photoshop 2021+)...${C_RESET}"
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v d3d11 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || log "  ⚠ d3d11 Override konnte nicht gesetzt werden"
    log "${C_GREEN}  ✓${C_RESET} ${C_CYAN}d3d11.dll Override gesetzt${C_RESET}"
    
    # CRITICAL: Additional DLL overrides for better graphics compatibility
    # These help fix rendering artifacts and glitchy UI (recommended for Wine 10.x + Photoshop 2021)
    log "${C_YELLOW}  →${C_RESET} ${C_GRAY}Setze zusätzliche DLL-Overrides für bessere Grafik-Kompatibilität...${C_RESET}"
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v dxgi /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || {
        log_warning "Registry operation failed for DllOverrides\\dxgi (non-critical)"
    }
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v d3dcompiler_47 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || {
        log_warning "Registry operation failed for DllOverrides\\d3dcompiler_47 (non-critical)"
    }
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v d3dcompiler_43 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || {
        log_warning "Registry operation failed for DllOverrides\\d3dcompiler_43 (non-critical)"
    }
    # d2d1 helps with 2D rendering and text (fixes text rendering issues)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v d2d1 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || {
        log_warning "Registry operation failed for DllOverrides\\d2d1 (non-critical)"
    }
    # opcservices helps with export functionality (fixes export issues)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v opcservices /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || {
        log_warning "Registry operation failed for DllOverrides\\opcservices (non-critical)"
    }
    log "${C_GREEN}  ✓${C_RESET} ${C_CYAN}Zusätzliche DLL-Overrides gesetzt (dxgi, d3dcompiler, d2d1, opcservices)${C_RESET}"
    
    # Zusätzliche Performance & Rendering Fixes
    show_message "${C_YELLOW}→${C_RESET} ${C_CYAN}$(i18n::get "configuring_registry")${C_RESET}"
    log "${C_CYAN}Konfiguriere Wine-Registry...${C_RESET}"
    
    # Enable CSMT for better performance (Command Stream Multi-Threading)
    log "  - CSMT aktivieren"
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v csmt /t REG_DWORD /d 1 /f >> "$LOG_FILE" 2>&1 || {
        log_warning "Registry operation failed for Direct3D\\csmt (non-critical)"
    }
    
    # Disable shader cache to avoid corruption (Issue #206 - Black Screen)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v shader_backend /t REG_SZ /d glsl /f 2>/dev/null || {
        log_warning "Registry operation failed for Direct3D\\shader_backend (non-critical)"
    }
    
    # Force DirectDraw renderer (helps with screen update issues - Issue #161)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v DirectDrawRenderer /t REG_SZ /d opengl /f 2>/dev/null || {
        log_warning "Registry operation failed for Direct3D\\DirectDrawRenderer (non-critical)"
    }
    
    # Disable vertical sync for better responsiveness
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v StrictDrawOrdering /t REG_SZ /d disabled /f 2>/dev/null || {
        log_warning "Registry operation failed for Direct3D\\StrictDrawOrdering (non-critical)"
    }
    
    # Fix UI scaling issues (Issue #56)
    show_message "${C_YELLOW}→${C_RESET} ${C_CYAN}$(i18n::get "configuring_dpi")${C_RESET}"
    wine reg add "HKEY_CURRENT_USER\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d 96 /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Fonts" /v Smoothing /t REG_DWORD /d 2 /f >> "$LOG_FILE" 2>&1 || true
    
    # BEST PRACTICE: Additional Registry Tweaks from Internet (Performance & Compatibility)
    log "  → Setze zusätzliche Registry-Tweaks für bessere Performance..."
    
    # VideoMemorySize: Set GPU memory size (helps with rendering performance)
    # Default: 0 (auto-detect), but setting it explicitly can help
    # 2048 MB is a good default for most systems, can be increased to 4096 if RAM is sufficient
    # Since GPU is disabled, this mainly affects Wine's internal memory management
    local video_memory=2048
    # Check available RAM and increase if sufficient (optional optimization)
    if command -v free >/dev/null 2>&1; then
        local total_ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "0")
        # CRITICAL: Validate that total_ram_mb is a number before comparison
        if [ -n "$total_ram_mb" ] && [[ "$total_ram_mb" =~ ^[0-9]+$ ]] && [ "$total_ram_mb" -gt 16384 ]; then  # If more than 16GB RAM
            video_memory=4096
            log "    ℹ Mehr als 16GB RAM erkannt - VideoMemorySize auf 4096 MB erhöht"
        fi
    fi
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" /v VideoMemorySize /t REG_DWORD /d $video_memory /f >> "$LOG_FILE" 2>&1 || true
    log "    ✓ VideoMemorySize gesetzt ($video_memory MB)"
    
    # WindowManagerManaged: Better window management (prevents window issues)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver" /v WindowManagerManaged /t REG_SZ /d "Y" /f >> "$LOG_FILE" 2>&1 || true
    log "    ✓ WindowManagerManaged aktiviert"
    
    # WindowManagerDecorated: Keep window decorations (better integration)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver" /v WindowManagerDecorated /t REG_SZ /d "Y" /f >> "$LOG_FILE" 2>&1 || true
    log "    ✓ WindowManagerDecorated aktiviert"
    
    # FontSmoothing: Set to RGB (best quality, recommended for Photoshop)
    # This ensures crisp, clear text rendering (fontsmooth=rgb via winetricks + registry)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\Fonts" /v FontSmoothing /t REG_DWORD /d 2 /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Control Panel\\Desktop" /v FontSmoothing /t REG_DWORD /d 2 /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Control Panel\\Desktop" /v FontSmoothingType /t REG_DWORD /d 2 /f >> "$LOG_FILE" 2>&1 || true
    log "    ✓ FontSmoothing RGB aktiviert (beste Textqualität)"
    
    # Virtual Desktop: resolution detect now, enable only after Adobe install (PIM/IE installer breaks in VD)
    log "  → Virtual Desktop: Auflösung merken, Aktivierung nach Photoshop-Installation..."
    
    # Try to detect screen resolution (for virtual desktop)
    local screen_resolution="1920x1080"  # Default fallback
    if command -v xrandr >/dev/null 2>&1; then
        # Try to get primary display resolution
        local detected_res=$(xrandr 2>/dev/null | grep -E "^\s+[0-9]+x[0-9]+" | head -1 | awk '{print $1}' | grep -E "^[0-9]+x[0-9]+" || echo "")
        if [ -n "$detected_res" ]; then
            screen_resolution="$detected_res"
            log "    ℹ Bildschirmauflösung erkannt: $screen_resolution"
        fi
    elif command -v xdpyinfo >/dev/null 2>&1; then
        # Alternative method to get screen resolution
        local detected_res=$(xdpyinfo 2>/dev/null | grep -oP 'dimensions:\s+\K[0-9]+x[0-9]+' || echo "")
        if [ -n "$detected_res" ]; then
            screen_resolution="$detected_res"
            log "    ℹ Bildschirmauflösung erkannt: $screen_resolution"
        fi
    fi
    export PHOTOSHOP_VIRTUAL_DESKTOP_RES="$screen_resolution"

    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver" /v "UseTakeFocus" /t REG_SZ /d "N" /f >> "$LOG_FILE" 2>&1 || log_warning "Registry add failed for UseTakeFocus"
    log "    ✓ Virtual Desktop vorbereitet ($screen_resolution) — wird nach Installation aktiviert"
    
    # CRITICAL: Set Windows version explicitly to Windows 10
    # (winetricks installations can reset the version, especially IE8)
    if [ "$LANG_CODE" = "de" ]; then
        output::spinner_line "Setze Windows-Version auf Windows 10..."
    else
        output::spinner_line "Setting Windows version to Windows 10..."
    fi
    if photoshop_setup::ensure_win10; then
        printf "\n"
        output::success "$(i18n::get "msg_set_win10" 2>/dev/null || echo "Windows 10 configured")"
    else
        output::error "$(i18n::get "win10_install_failed" 2>/dev/null || echo "Windows 10 configuration failed")"
        return 1
    fi
    echo ""
    
    #install photoshop
    install_photoshopSE
    
    replacement

    if [ -d $RESOURCES_PATH ];then
        log "$(i18n::get "deleting_resources_folder")"
        # CRITICAL: Use safe_remove for security
        if type filesystem::safe_remove >/dev/null 2>&1; then
            filesystem::safe_remove "$RESOURCES_PATH" "PhotoshopSetup" || log_error "Löschen von $RESOURCES_PATH fehlgeschlagen"
        else
            # Fallback if filesystem::safe_remove not available
            if [ -z "$RESOURCES_PATH" ]; then
                log_error "RESOURCES_PATH is empty - skipping deletion"
            elif [ "$RESOURCES_PATH" = "/" ]; then
                log_error "RESOURCES_PATH ist root - überspringe Löschung (Sicherheit)"
            elif [ ! -e "$RESOURCES_PATH" ]; then
                log_debug "RESOURCES_PATH existiert nicht: $RESOURCES_PATH"
            elif [ -d "$RESOURCES_PATH" ]; then
                # CRITICAL: Use safe_remove for security
                if type filesystem::safe_remove >/dev/null 2>&1; then
                    filesystem::safe_remove "$RESOURCES_PATH" "PhotoshopSetup" || log_error "Löschen von $RESOURCES_PATH fehlgeschlagen"
                else
                    # Fallback: validate before rm -rf
                    if [ -z "$RESOURCES_PATH" ] || [ "$RESOURCES_PATH" = "/" ] || [ "$RESOURCES_PATH" = "/root" ]; then
                        log_error "Unsichere RESOURCES_PATH: $RESOURCES_PATH"
                    else
                        rm -rf "$RESOURCES_PATH" || log_error "Löschen von $RESOURCES_PATH fehlgeschlagen"
                    fi
                fi
            else
                log_error "RESOURCES_PATH ist kein Verzeichnis: $RESOURCES_PATH"
            fi
        fi
    else
        error "resources folder Not Found"
    fi

    # CRITICAL: Don't call launcher() here - it's called later in install_photoshopSE() after installation
    # Don't show "installation_completed" here - it's shown in finish_installation()
    # All cleanup and launcher creation happens in finish_installation()
}

function replacement() {
    # Replacement component ist optional für die lokale Installation
    # Diese Dateien werden normalerweise nur für UI-Icons benötigt
    # Silent - don't show message to user (irrelevant info)
    log_debug "Überspringe replacement component (optional für lokale Installation)..."
    
    # Verwende dynamischen Pfad basierend auf erkannte Version
    local destpath="$PS_INSTALL_PATH/Resources"
    if [ ! -d "$destpath" ]; then
        show_message "${C_YELLOW}→${C_RESET} ${C_GRAY}Photoshop Resources-Pfad noch nicht vorhanden, wird später erstellt...${C_RESET}"
    fi
    
    unset destpath
}

# ============================================================================
# @function install_wine_components
# @description Install Wine components required for Photoshop (VC++, fonts, XML)
# @return 0 on success, 1 on error
# ============================================================================
install_wine_components() {
    # Install Wine components
    # Based on GitHub Issues #23, #45, #67: Minimal, stable components
    show_message "$(i18n::get "msg_install_components")"
    printf "\033[1;33m%s\033[0m\n" "$(i18n::get "msg_wait")"
    
    # Windows-Version wird später beim tatsächlichen Setzen angezeigt (keine vorzeitige Meldung)
    
    # CRITICAL: Use winetricks with spinner and ensure it uses the correct Wine binary
    # winetricks automatically uses the Wine binary from PATH
    # CRITICAL: WINEPREFIX should already be set by export_var(), but run_with_spinner will ensure it
    # CRITICAL: Add timeout to prevent hanging (winetricks can hang on version mismatch)
    log_debug "Setting Windows version to Windows 10..."
    log_debug "WINEPREFIX: ${WINEPREFIX:-not set}"
    log_debug "Wine binary: $(photoshop_setup::wine_binary 2>/dev/null || echo 'not found')"

    if photoshop_setup::ensure_win10; then
        log_debug "Windows version set to Windows 10 successfully"
    else
        log_error "winetricks -q win10 failed (critical)"
        output::error "$(i18n::get "win10_install_failed" 2>/dev/null || echo "winetricks win10 failed — installation aborted")"
        return 1
    fi
    
    # CRITICAL: Visual C++ Runtimes Installation
    # For Photoshop 2021+, we use the official Microsoft Visual C++ 2015-2022 Redistributable x64 installer
    # This installer contains ALL versions (2015, 2017, 2019, 2022) - no need for separate vcrun2010-2015
    # The official installer is more reliable and ensures correct x86-64 DLLs (fixes ARM64 bug in winetricks)
    # 
    # For older Photoshop versions (< 2021), we still use winetricks vcrun2010-2015 for compatibility
    if [[ "${PS_VERSION:-}" =~ "2021" ]] || [[ "${PS_VERSION:-}" =~ "2022" ]]; then
        # For 2021+: Skip old vcrun2010-2015, use official 2015-2022 installer instead (installed in next step)
        # Info-Meldung entfernt - Installation passiert sofort im nächsten Schritt
        :  # Empty command - installation happens in next step
    else
        # For older versions: Install vcrun2010-2015 via winetricks
        echo ""
        output::spinner_line "$(i18n::get "installing_vc_runtimes")"
        
        # CRITICAL: winetricks output to log file only (prevents blocking and spam)
        # Filter out Wine warnings - they're not useful for the user
        winetricks -q vcrun2010 vcrun2012 vcrun2013 vcrun2015 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1 &
        local winetricks_pid=$!
        
        # Use spinner for long operation (simpler and more reliable)
        spinner $winetricks_pid
        wait $winetricks_pid
        local winetricks_exit_code=$?
        echo ""
        
        if [ $winetricks_exit_code -eq 0 ]; then
            checkpoint::create "wine_components_installed"
            output::success "$(i18n::get "vc_runtimes_installed")"
        else
            output::error "$(i18n::get "vc_runtimes_failed" "$winetricks_exit_code")"
            return 1
        fi
    fi
    
    if [ "$LANG_CODE" = "de" ]; then
        output::spinner_line "$(i18n::get "installing_fonts_libs")"
    else
        output::spinner_line "Installing fonts and libraries..."
    fi
    
    # Filter out Wine warnings - output to log only
    winetricks -q atmlib corefonts fontsmooth=rgb 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1 &
    local fonts_pid=$!
    spinner $fonts_pid
    wait $fonts_pid
    echo ""
    
    echo ""
    if [ "$LANG_CODE" = "de" ]; then
        output::spinner_line "$(i18n::get "installing_xml_gdi")"
    else
        output::spinner_line "Installing XML and GDI+ components..."
    fi
    # gdiplus only here — MSXML via ensure_native_msxml (native Microsoft DLLs required)
    winetricks -q gdiplus 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1 &
    local xml_pid=$!
    spinner $xml_pid
    wait $xml_pid
    if ! photoshop_setup::ensure_native_msxml; then
        return 1
    fi
    echo ""
    
    # OPTIMIZATION: For newer versions (2021+) install official Visual C++ 2015-2022 Redistributable
    # CRITICAL: The official 2015-2022 installer contains ALL versions (2015, 2017, 2019, 2022)
    # This replaces the need for separate vcrun2010-2015 and vcrun2019 installations
    # It also fixes the ARM64 DLL bug in winetricks vcrun2019
    # .NET Framework ist NICHT notwendig für Photoshop 2021/2022 - wurde komplett entfernt
    # Photoshop läuft erfolgreich ohne .NET Framework
    if [[ "${PS_VERSION:-}" =~ "2021" ]] || [[ "${PS_VERSION:-}" =~ "2022" ]]; then
        echo ""
        output::step "$(i18n::get "installing_additional_components")"
        echo ""
        
        # Install official Microsoft Visual C++ 2015-2022 Redistributable x64
        # This contains ALL VC++ versions (2015, 2017, 2019, 2022) - no need for separate installations
        if [ "$LANG_CODE" = "de" ]; then
            output::spinner_line "Installiere Visual C++ 2015-2022 Redistributable x64 (enthält alle Versionen)..."
        else
            output::spinner_line "Installing Visual C++ 2015-2022 Redistributable x64 (contains all versions)..."
        fi
        
        # CRITICAL: Kill ALL Wine processes before installation (prevents wineserver -w hang)
        # Try graceful shutdown first, then force kill as fallback
        photoshop_setup::kill_all_wineservers
        sleep 1
        pkill -9 wine 2>/dev/null || true
        pkill -9 wineboot 2>/dev/null || true
        sleep 2
        
        # Download official Microsoft Visual C++ 2015-2022 Redistributable x64
        local vc_redist_url="https://aka.ms/vc14/vc_redist.x64.exe"
        # Use CACHE_PATH if available, otherwise use SCR_PATH/cache
        local cache_dir="${CACHE_PATH:-$(wine_software_cache_dir 2>/dev/null || echo "$SCR_PATH/cache")}"
        local vc_redist_file="$cache_dir/vc_redist.x64.exe"
        local vcrun_exit=1
        
        # Create cache directory if it doesn't exist
        mkdir -p "$cache_dir"
        
        # CRITICAL: Ensure WINE_PREFIX exists before installation
        if [ ! -d "$WINE_PREFIX" ]; then
            log_error "WINE_PREFIX existiert nicht: $WINE_PREFIX"
            if [ "$LANG_CODE" = "de" ]; then
                output::error "Wine-Prefix nicht gefunden - Installation kann nicht fortgesetzt werden"
            else
                output::error "Wine prefix not found - installation cannot continue"
            fi
            return 1
        fi
        
        # Download installer if not already cached
        if [ ! -f "$vc_redist_file" ]; then
            # #region agent log
            # #endregion
            
            if [ "$LANG_CODE" = "de" ]; then
                output::spinner_line "Lade Visual C++ Redistributable x64 herunter..."
            else
                output::spinner_line "Downloading Visual C++ Redistributable x64..."
            fi
            
            # Download with clean progress display (percentage only)
            if command -v wget >/dev/null 2>&1; then
                # wget: Show only percentage, redirect full output to log
                wget --progress=dot:giga -O "$vc_redist_file" "$vc_redist_url" 2>&1 | \
                    while IFS= read -r line; do
                        # Extract percentage from wget output (format: " 45%")
                        if [[ "$line" =~ ([0-9]+)% ]]; then
                            printf "\r${C_YELLOW}→${C_RESET} ${C_CYAN}Download: %s%%${C_RESET}" "${BASH_REMATCH[1]}"
                        fi
                        # Also log to file
                        echo "$line" >> "$LOG_FILE" 2>/dev/null || true
                    done
                echo ""  # New line after download
                
                if [ -f "$vc_redist_file" ] && [ -s "$vc_redist_file" ]; then
                    # #region agent log
                    local file_size=$(stat -f%z "$vc_redist_file" 2>/dev/null || stat -c%s "$vc_redist_file" 2>/dev/null || echo "0")
                    # #endregion
                    output::success "Download erfolgreich"
                else
                    # #region agent log
                    # #endregion
                    log_warning "Download fehlgeschlagen, versuche winetricks als Fallback..."
                    # Fallback to winetricks if download fails
                    winetricks --force -q vcrun2019 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1
                    vcrun_exit=$?
                fi
            elif command -v curl >/dev/null 2>&1; then
                # curl: Show only percentage
                curl -L --progress-bar -o "$vc_redist_file" "$vc_redist_url" 2>&1 | \
                    while IFS= read -r line; do
                        # Extract percentage from curl progress (format: "# 45%")
                        if [[ "$line" =~ ([0-9]+)% ]]; then
                            printf "\r${C_YELLOW}→${C_RESET} ${C_CYAN}Download: %s%%${C_RESET}" "${BASH_REMATCH[1]}"
                        fi
                        # Also log to file
                        echo "$line" >> "$LOG_FILE" 2>/dev/null || true
                    done
                echo ""  # New line after download
                
                if [ -f "$vc_redist_file" ] && [ -s "$vc_redist_file" ]; then
                    output::success "Download erfolgreich"
                else
                    log_warning "Download fehlgeschlagen, versuche winetricks als Fallback..."
                    winetricks --force -q vcrun2019 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1
                    vcrun_exit=$?
                fi
            else
                log_warning "wget/curl nicht verfügbar, verwende winetricks..."
                winetricks --force -q vcrun2019 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1
                vcrun_exit=$?
            fi
        else
            # File already exists
            if [ "$LANG_CODE" = "de" ]; then
                output::info "Visual C++ Redistributable bereits im Cache vorhanden"
            else
                output::info "Visual C++ Redistributable already cached"
            fi
        fi
        
        # Install using official installer if file exists
        if [ -f "$vc_redist_file" ]; then
            local install_message
            if [ "$LANG_CODE" = "de" ]; then
                install_message="Installiere Visual C++ 2015-2022 Redistributable x64..."
            else
                install_message="Installing Visual C++ 2015-2022 Redistributable x64..."
            fi
            
            # Backup old DLL if it exists (in case it's ARM64)
            if [ -f "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll" ]; then
                mv "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll" "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll.bak" 2>/dev/null || true
            fi
            
            # Install using wine (silent mode) with spinner and timeout
            # CRITICAL: Ensure WINEPREFIX is set and exists
            # WINE_PREFIX should already be set by configure_wine_prefix(), but verify it
            if [ -z "${WINE_PREFIX:-}" ]; then
                WINE_PREFIX="${SCR_PATH}/prefix"
            fi
            export WINEPREFIX="$WINE_PREFIX"
            
            if [ ! -d "$WINEPREFIX" ]; then
                log_error "WINEPREFIX existiert nicht: $WINEPREFIX"
                if [ "$LANG_CODE" = "de" ]; then
                    output::error "Wine-Prefix nicht gefunden: $WINEPREFIX - kann VC++ nicht installieren"
                else
                    output::error "Wine prefix not found: $WINEPREFIX - cannot install VC++"
                fi
                vcrun_exit=1
            else
                # Show initial message
                printf "${C_YELLOW}→${C_RESET} ${C_CYAN}%s${C_RESET} " "$install_message"
                
                # #region agent log
                # #endregion
                
                # Start installation in background
                # CRITICAL: Use absolute path for wine executable and installer file
                # CRITICAL: Ensure WINEPREFIX is exported before wine call
                # CRITICAL: Use full path to wine executable to avoid PATH issues
                local wine_binary
                wine_binary="$(photoshop_setup::wine_binary)"
                "$wine_binary" "$vc_redist_file" /quiet /norestart >> "$LOG_FILE" 2>&1 &
                local install_pid=$!
                
                # Small delay to ensure process started
                sleep 0.5
                
                # Verify process is actually running
                if ! kill -0 "$install_pid" 2>/dev/null; then
                    # Process died immediately - check exit code
                    wait $install_pid 2>/dev/null
                    vcrun_exit=$?
                    # #region agent log
                    # #endregion
                    log_error "VC++ Installer beendet sich sofort (Exit-Code: $vcrun_exit) - prüfe Log-Datei"
                    if [ "$LANG_CODE" = "de" ]; then
                        output::warning "VC++ Installation fehlgeschlagen - prüfe Log-Datei für Details"
                    else
                        output::warning "VC++ installation failed - check log file for details"
                    fi
                else
                    # Process is running - show spinner
                    # #region agent log
                    # #endregion
                
                    # Show spinner with elapsed time
                    local spinstr='|/-\'
                    local spin_idx=0
                    local elapsed=0
                    local start_time=$(date +%s)
                    local max_wait_time=300  # 5 minutes max
                    
                    # Wait for process with spinner
                    while [ $elapsed -lt $max_wait_time ]; do
                        # Check if process is still running
                        if ! kill -0 "$install_pid" 2>/dev/null; then
                            # Process finished - wait for it and get exit code
                            wait $install_pid 2>/dev/null
                            vcrun_exit=$?
                            # #region agent log
                            # #endregion
                            break
                        fi
                        
                        local spin_char=${spinstr:$spin_idx:1}
                        elapsed=$(($(date +%s) - start_time))
                        
                        # Show spinner with elapsed time (update same line)
                        printf "\r${C_YELLOW}→${C_RESET} ${C_CYAN}%s${C_RESET} ${C_CYAN}[%c]${C_RESET} (${elapsed}s)" "$install_message" "$spin_char"
                        
                        spin_idx=$(((spin_idx + 1) % 4))
                        sleep 0.2
                    done
                    
                    # Check if we hit timeout
                    if [ $elapsed -ge $max_wait_time ]; then
                        # #region agent log
                        # #endregion
                        log_warning "Installation-Timeout erreicht (5 Minuten) - beende Prozess..."
                        kill "$install_pid" 2>/dev/null || true
                        wait $install_pid 2>/dev/null
                        vcrun_exit=124
                    fi
                    
                    # Clear spinner line and show result
                    printf "\r${C_GREEN}✓${C_RESET} ${C_CYAN}%s${C_RESET} ${C_GREEN}abgeschlossen${C_RESET} (${elapsed}s)\n" "$install_message"
                    
                    # Wait for process if still running
                    if kill -0 "$install_pid" 2>/dev/null; then
                        wait $install_pid
                        vcrun_exit=$?
                    fi
                    
                    # #region agent log
                    # #endregion
                fi
            fi
            
            # Verify DLL architecture after installation
            if [ -f "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll" ]; then
                local dll_arch=$(file "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll" 2>/dev/null | grep -o "x86-64\|ARM64\|i386" || echo "unknown")
                # #region agent log
                # #endregion
                if [[ "$dll_arch" == "ARM64" ]]; then
                    log_warning "MSVCP140.dll ist immer noch ARM64 - verwende winetricks als Fallback..."
                    # Restore backup if winetricks also fails
                    if [ -f "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll.bak" ]; then
                        mv "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll.bak" "$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll" 2>/dev/null || true
                    fi
                    winetricks --force -q vcrun2019 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1
                    vcrun_exit=$?
                elif [[ "$dll_arch" == "x86-64" ]]; then
                    log "✓ MSVCP140.dll Architektur korrekt (x86-64)"
                fi
            fi
        fi
        
        # CRITICAL: Winetricks sets Windows version to win7 internally - restore to win10
        photoshop_setup::kill_all_wineservers
        sleep 1
        photoshop_setup::ensure_win10 >> "$LOG_FILE" 2>&1 || true
        
        echo ""
        if [ $vcrun_exit -eq 0 ]; then
            # Use i18n for consistent messaging (no duplicate checkmarks)
            if [ "$LANG_CODE" = "de" ]; then
                output::success "Visual C++ 2015-2022 Redistributable x64 erfolgreich installiert"
            else
                output::success "Visual C++ 2015-2022 Redistributable x64 installed successfully"
            fi
        else
            if [ "$LANG_CODE" = "de" ]; then
                output::warning "Visual C++ 2015-2022 Redistributable Installation fehlgeschlagen"
                output::info "Visual C++ ist optional - Installation kann ohne fortgesetzt werden"
            else
                output::warning "Visual C++ 2015-2022 Redistributable installation failed"
                output::info "Visual C++ is optional - installation can continue without it"
            fi
        fi
    fi
}

# ============================================================================
# @function configure_ie_engine
# @description Configure IE engine for Adobe Installer (IE8, DLL-Overrides, Registry-Tweaks)
# @return 0 on success, 1 on error
# ============================================================================
configure_ie_engine() {
    # Erklärung welche Wine-Version verwendet wird
    # REMOVED: Proton GE support - only Wine Standard/Staging supported
    log "ℹ Verwende: Wine für Installer UND Photoshop"
    echo ""
    if [ "$LANG_CODE" = "de" ]; then
        output::header "WICHTIG: Adobe Installer IE-Engine"
        output::info "Der Adobe Installer verwendet eine IE-Engine, die in Wine nicht vollständig funktioniert."
        output::info "Falls Buttons nicht reagieren, ist das ein bekanntes Problem (nicht dein Fehler!)."
    else
        output::header "IMPORTANT: Adobe Installer IE Engine"
        output::info "The Adobe Installer uses an IE engine that doesn't fully work in Wine."
        output::info "If buttons don't respond, this is a known issue (not your fault!)."
    fi
    echo ""
    
    # Workaround für "Weiter"-Button Problem: Setze DLL-Overrides für IE-Engine
    # Adobe Installer verwendet IE-Engine (mshtml.dll), die in Wine nicht vollständig funktioniert
    # BEST PRACTICE: IE8 installieren + umfassende DLL-Overrides für maximale Kompatibilität
    log "$(i18n::get "configuring_ie_engine")"
    echo ""
    
    # IE8 Installation (skip if already present from a prior run)
    if photoshop_setup::ie8_present; then
        if [ "$LANG_CODE" = "de" ]; then
            output::success "IE8 bereits installiert – aktualisiere Registrierung"
        else
            output::success "IE8 already installed – refreshing registration"
        fi
        log_debug "IE8 already present in prefix, re-registering DLLs for Adobe installer"
        photoshop_setup::kill_all_wineservers
        sleep 1
        photoshop_setup::reregister_ie8_dlls
    else
        if [ "$LANG_CODE" = "de" ]; then
            output::spinner_line "$(i18n::get "installing_ie8")"
        else
            output::spinner_line "Installing IE8 (takes 5-10 minutes)..."
        fi

        local ie8_exit_file="${SCR_PATH}/.ie8_exit.$$"
        (
            winetricks -q ie8 >> "$LOG_FILE" 2>&1
            echo $? > "$ie8_exit_file"
        ) &
        local ie8_pid=$!
        spinner $ie8_pid
        wait $ie8_pid || true
        local ie8_exit_code=1
        if [ -f "$ie8_exit_file" ]; then
            ie8_exit_code="$(cat "$ie8_exit_file")"
            rm -f "$ie8_exit_file"
        fi

        if [ "$ie8_exit_code" -eq 0 ] || photoshop_setup::ie8_present; then
            output::success "$(i18n::get "ie8_installed_success")"
        else
            output::warning "$(i18n::get "ie8_install_failed")"
            log_warning "winetricks ie8 failed (exit $ie8_exit_code) — continuing with DLL workarounds"
        fi
    fi

    photoshop_setup::kill_all_wineservers
    sleep 1
    photoshop_setup::ensure_win10 >> "$LOG_FILE" 2>&1 || true
    echo ""
    output::substep "$(i18n::get "setting_dll_overrides")"
    
    # Best Practice: native,builtin (versuche native zuerst, dann builtin als Fallback)
    # For critical IE components we use native,builtin
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v mshtml /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v jscript /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v vbscript /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v urlmon /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v wininet /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v shdocvw /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v ieframe /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v actxprxy /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v browseui /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    # Dxtrans.dll und msimtf.dll - für JavaScript/IE-Engine (verhindert viele Fehler im Log)
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v dxtrans /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v msimtf /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    
    # Fix for DLL-Forward-Fehler: shlwapi.ShellMessageBoxW
    # This fixes the "find_forwarded_export function not found" errors
    log_debug "Setze shlwapi.dll Override (behebt DLL-Forward-Fehler)..."
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v shlwapi /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v shell32 /t REG_SZ /d "native,builtin" /f >> "$LOG_FILE" 2>&1 || true
    
    # Zusätzliche Registry-Tweaks für bessere IE-Kompatibilität
    log_debug "Setze Registry-Tweaks für IE-Kompatibilität..."
    wine reg add "HKEY_CURRENT_USER\\Software\\Microsoft\\Internet Explorer\\Main" /v "DisableScriptDebugger" /t REG_SZ /d "yes" /f >> "$LOG_FILE" 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\\Software\\Microsoft\\Internet Explorer\\Main" /v "DisableFirstRunCustomize" /t REG_SZ /d "1" /f >> "$LOG_FILE" 2>&1 || true

    photoshop_setup::export_ie_dll_overrides

    # Show important notice about Adobe Installer button issues (only once, clean format)
    output::header "$(i18n::get "important_next_button")"
}

# ============================================================================
# @function show_post_installation_tips
# @description Display helpful tips after successful installation
# @return 0 on success
# ============================================================================
show_post_installation_tips() {
    output::header "$(i18n::get "post_install_tips_title" 2>/dev/null || echo "Nächste Schritte & Tipps")"
    
    output::item 0 "$(i18n::get "tip_virtual_desktop" 2>/dev/null || echo "→ Empfohlen: winecfg → Graphics → Emulate a virtual desktop (für stabile UI)")"
    output::item 0 "$(i18n::get "tip_gpu_glitches" 2>/dev/null || echo "→ Bei Glitches: Preferences → Performance → Use Graphics Processor deaktivieren")"
    output::item 0 "$(i18n::get "tip_documentation" 2>/dev/null || echo "→ Mehr Infos: https://github.com/benjarogit/photoshopCClinux")"
    
    echo ""
}

# ============================================================================
# @function finish_installation
# @description Show completion message and ask if user wants to start Photoshop
# @return 0 on success
# ============================================================================
finish_installation() {
    log "=== finish_installation() gestartet ==="
    echo ""
    output::success "$(i18n::get "installation_completed")"
    echo ""

    if [ "${LAUNCHER_GUI:-0}" = "1" ]; then
        echo "RECIPE_LOG_FILE=${LOG_FILE:-}"
        echo "RECIPE_ERROR_LOG=${ERROR_LOG:-}"
        echo "RECIPE_DEBUG_LOG=${DEBUG_LOG:-}"
        output::info "Installation abgeschlossen — starte die App über „Starten“ im Rezepte-Launcher."
        return 0
    fi
    
    # Show helpful tips after successful installation
    show_post_installation_tips
    
    # Ask user if they want to start Photoshop now
    # Skip in quiet mode
    local start_photoshop=false
    if [ "${QUIET:-0}" != "1" ]; then
        log "Zeige Photoshop-Start-Abfrage..."
        output::section "$(i18n::get "start_photoshop_question")"
        local start_prompt="$(i18n::get "start_photoshop_prompt")"
        log_prompt "$start_prompt"
        IFS= read -r -p "$start_prompt" start_response
        log_input "$start_response"
        
        # Default to yes if empty (Enter pressed)
        if [ -z "$start_response" ] || [[ "$start_response" =~ ^[JjYy]$ ]]; then
            start_photoshop=true
        fi
    else
        # In quiet mode, don't start Photoshop automatically
        log "Quiet mode: Skipping Photoshop start prompt"
    fi
    
    if [ "$start_photoshop" = true ]; then
        echo ""
        output::step "$(i18n::get "starting_photoshop")"
        log "Starte Photoshop automatisch nach Installation..."
        
        # Start Photoshop - capture errors but don't block
        if [ -f "$SCR_PATH/launcher/launcher.sh" ]; then
            # Log debug info to file only (not shown to user)
            log_debug "Starte Launcher: $SCR_PATH/launcher/launcher.sh"
            log_debug "SCR_PATH: $SCR_PATH"
            log_debug "WINE_PREFIX: ${WINE_PREFIX:-not set}"
            log_debug "RESOURCES_PATH: ${RESOURCES_PATH:-not set}"
            
            # Export necessary variables for launcher
            export SCR_PATH
            export WINE_PREFIX
            export RESOURCES_PATH
            
            # Start in background but capture output to log file
            # Use nohup to prevent immediate termination if parent script exits
            nohup bash "$SCR_PATH/launcher/launcher.sh" >> "$LOG_FILE" 2>&1 &
            local ps_pid=$!
            log "Photoshop gestartet (PID: $ps_pid)"
            output::success "$(i18n::get "photoshop_starting")"
            
            # Wait a moment to check if process started successfully
            sleep 2
            if ! kill -0 "$ps_pid" 2>/dev/null; then
                if [ "$LANG_CODE" = "de" ]; then
                    output::warning "Photoshop-Prozess konnte nicht gestartet werden. Bitte manuell starten: photoshop"
                    output::info "Prüfe Logs: $LOG_FILE"
                else
                    output::warning "Photoshop process could not be started. Please start manually: photoshop"
                    output::info "Check logs: $LOG_FILE"
                fi
                log_error "Photoshop-Prozess (PID: $ps_pid) beendet sich sofort nach Start"
                # Show last few lines of log for debugging (only in verbose mode)
                if [ "${VERBOSE:-0}" = "1" ] && [ -f "$LOG_FILE" ]; then
                    log_error "Letzte Zeilen aus Launcher-Output:"
                    tail -20 "$LOG_FILE" | while IFS= read -r line; do
                        log_error "  $line"
                    done
                fi
            else
                log_debug "Photoshop-Prozess läuft (PID: $ps_pid)"
            fi
        else
            output::error "$(printf "$(i18n::get "launcher_not_found")" "$SCR_PATH/launcher/launcher.sh")"
            log_error "Launcher nicht gefunden: $SCR_PATH/launcher/launcher.sh"
        fi
    else
        output::info "$(i18n::get "photoshop_not_auto_start")"
    fi
    
    # CRITICAL: Final .lnk file cleanup after finish_installation
    # Adobe installer may create .lnk files during installation or when Photoshop starts
    log_debug "Final cleanup after finish_installation: Removing any remaining .lnk files..."
    local xdg_desktop="$(xdg-user-dir DESKTOP 2>/dev/null || echo '')"
    local desktop_dirs=("$HOME/Desktop" "$HOME/Schreibtisch" "$HOME/desktop" "$HOME/schreibtisch")
    # Add XDG desktop dir if it exists and is not empty
    if [ -n "$xdg_desktop" ] && [ -d "$xdg_desktop" ]; then
        desktop_dirs+=("$xdg_desktop")
    fi
    
    # Check standard desktop directories
    for desktop_dir in "${desktop_dirs[@]}"; do
        if [ -n "$desktop_dir" ] && [ -d "$desktop_dir" ]; then
            find "$desktop_dir" -maxdepth 1 -type f \( -name "*.lnk" -o -name "*Photoshop*.lnk" -o -name "*Adobe*.lnk" -o -name "*2021*.lnk" \) 2>/dev/null | while IFS= read -r lnk_file; do
                if [ -f "$lnk_file" ]; then
                    log_debug "Removing .lnk file after finish_installation: $lnk_file"
                    rm -f "$lnk_file" 2>/dev/null || true
                fi
            done
        fi
    done
    
    # CRITICAL: Also check Wine Desktop directory (Wine may create .lnk files there)
    if [ -d "$WINE_PREFIX/drive_c/users" ]; then
        find "$WINE_PREFIX/drive_c/users" -type d -name "Desktop" 2>/dev/null | while IFS= read -r wine_desktop; do
            if [ -d "$wine_desktop" ]; then
                find "$wine_desktop" -maxdepth 1 -type f \( -name "*.lnk" -o -name "*Photoshop*.lnk" -o -name "*Adobe*.lnk" -o -name "*2021*.lnk" \) 2>/dev/null | while IFS= read -r lnk_file; do
                    if [ -f "$lnk_file" ]; then
                        log_debug "Removing .lnk file from Wine Desktop directory: $lnk_file"
                        rm -f "$lnk_file" 2>/dev/null || true
                    fi
                done
            fi
        done
    fi
}

# ============================================================================
# @function run_photoshop_installer
# @description Run Adobe Photoshop installer and handle exit codes
# @return 0 on success, 1 on error
# ============================================================================
run_photoshop_installer() {
    log_debug 'Starte Adobe Installer (Set-up.exe)...'
    photoshop_setup::prepare_adobe_installer_env

    local setup_exe setup_dir installer_args=()
    setup_exe="$(photoshop_setup::resolve_setup_exe)" || {
        log_error "Set-up.exe nicht gefunden (C:\\AdobeSetup oder resources)"
        return 1
    }
    setup_dir="$(dirname "$setup_exe")"
    log_debug "Adobe Installer: $setup_exe (cwd: $setup_dir)"

    if [ "${PHOTOSHOP_INSTALLER_GUI:-0}" = "1" ]; then
        if [ "$LANG_CODE" = "de" ]; then
            output::info "GUI-Installer (PHOTOSHOP_INSTALLER_GUI=1) — Weiter-Button kann unter Wine grau bleiben"
        else
            output::info "GUI installer (PHOTOSHOP_INSTALLER_GUI=1) — Next button may stay gray under Wine"
        fi
    else
        installer_args=(--silent=1)
        if [ "$LANG_CODE" = "de" ]; then
            output::info "Silent-Installation (Adobe ESD) — umgeht PIM/CommBridge-GUI-Bug unter Wine"
            output::info "Fortschritt erscheint als Progress: N% (dauert ca. 2–4 Minuten)"
        else
            output::info "Silent install (Adobe ESD) — bypasses PIM/CommBridge GUI bug under Wine"
            output::info "Progress shown as Progress: N% (typically 2–4 minutes)"
        fi
    fi

    local install_status=0
    (
        cd "$setup_dir" || exit 1
        # shellcheck disable=SC2091
        wine "./Set-up.exe" "${installer_args[@]}" 2>&1 | tee -a "$LOG_FILE" | tee -a "$SCR_PATH/wine-error.log" | while IFS= read -r _line; do
            case "$_line" in
                Progress:*)
                    echo "$_line"
                    if [ "${LAUNCHER_GUI:-0}" = "1" ]; then
                        _pct=$(echo "$_line" | grep -oE '[0-9]+' | tail -1)
                        [ -n "$_pct" ] && printf '@progress:%s\n' "$_pct"
                    fi
                    ;;
                *Exit\ Code*)
                    echo "$_line"
                    ;;
            esac
        done || true
        exit "${PIPESTATUS[0]}"
    ) || install_status=$?

    photoshop_setup::kill_all_wineservers
    
    log_debug "Installation beendet mit Exit-Code: $install_status"
    
    if [ $install_status -ne 0 ]; then
        output::warning "$(i18n::get "install_exit_code" "$install_status")"
        log_error "FEHLER: Installation mit Exit-Code $install_status beendet"
        return $install_status
    fi

    if ! validate_photoshop_installation; then
        if [ "$LANG_CODE" = "de" ]; then
            output::error "Adobe-Installer beendet, aber Photoshop wurde nicht installiert."
            output::info "Ursache GUI: PIM/CommBridge localhost (127.0.0.1) — unter Wine normal. Nutze Silent-Modus (Standard)."
            output::info "Log: $WINE_PREFIX/drive_c/users/*/AppData/Local/Temp/CreativeCloud/ACC/AdobeDownload/HDInstaller.log"
            output::info "Fix: Prefix löschen und Install erneut starten:"
            output::info "  rm -rf \"$WINE_PREFIX\""
        else
            output::error "Adobe installer exited but Photoshop was not installed."
            output::info "Usually: gray Next button (IE engine) or installer closed early."
            output::info "Fix: delete prefix and run Install again:"
            output::info "  rm -rf \"$WINE_PREFIX\""
        fi
        log_error "Installation reported exit 0 but Photoshop.exe not found"
        return 1
    fi

    output::success "$(i18n::get "photoshop_install_completed")"
    log "$(i18n::get "msg_complete")"
    return 0
}

# ============================================================================
# @function configure_photoshop
# @description Configure Photoshop after installation (remove plugins, disable GPU, etc.)
# @return 0 on success, 1 on error
# ============================================================================
configure_photoshop() {
    photoshop_setup::enable_virtual_desktop "${PHOTOSHOP_VIRTUAL_DESKTOP_RES:-1920x1080}"

    # Versuche problematische Plugins zu entfernen (falls vorhanden)
    output::step "$(i18n::get "configuring_photoshop")"
    log_debug "$(i18n::get "msg_search_plugins")"
    
    # Mögliche Installationspfade (dynamisch basierend auf erkannte Version)
    local possible_paths=(
        "$PS_INSTALL_PATH"
        "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop CC 2021"
        "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop CC 2019"
        "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop 2022"
        "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop 2021"
        "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop CC 2018"
        "$WINE_PREFIX/drive_c/users/$USER/PhotoshopSE"
    )
    
    # After installation, check which version was actually installed
    local actual_version=""
    for ps_path in "${possible_paths[@]}"; do
        if [ -d "$ps_path" ]; then
            show_message "$(i18n::get "msg_found_in") $ps_path"
            
            # Detect actual installed version from directory name
            local dirname
            dirname=$(basename "$ps_path")
            if [[ "$dirname" =~ "2022" ]]; then
                actual_version="2022"
            elif [[ "$dirname" =~ "2021" ]]; then
                actual_version="2021"
            elif [[ "$dirname" =~ "CC 2019" ]] || [[ "$dirname" =~ "2019" ]]; then
                actual_version="CC 2019"
            fi
            
            # Update PS_VERSION if different from detected
            if [ -n "$actual_version" ]; then
                local version_msg
                if [ "$LANG_CODE" = "de" ]; then
                    version_msg=$(printf "Tatsächlich installierte Version: %s (vorher erkannt: %s)" "$actual_version" "$PS_VERSION")
                else
                    version_msg=$(printf "Actually installed version: %s (previously detected: %s)" "$actual_version" "$PS_VERSION")
                fi
                log_info "$version_msg"
                PS_VERSION="$actual_version"
                PS_INSTALL_PATH=$(get_photoshop_install_path "$PS_VERSION")
                PS_PREFS_PATH=$(get_photoshop_prefs_path "$PS_VERSION")
            fi
            
            # Entferne problematische Plugins (GitHub Issues #12, #56, #78)
            # JavaScript-Extensions (CEP) funktionieren nicht richtig in Wine
            local problematic_plugins=(
                "$ps_path/Required/Plug-ins/Spaces/Adobe Spaces Helper.exe"
                "$ps_path/Required/CEP/extensions/com.adobe.DesignLibraryPanel.html"
                "$ps_path/Required/Plug-ins/Extensions/ScriptingSupport.8li"
                # JavaScript-Extension "Startseite" (Homepage) - verursacht Fehler
                "$ps_path/Required/CEP/extensions/com.adobe.HomePagePanel.html"
                "$ps_path/Required/CEP/extensions/com.adobe.HomePagePanel"
            )
            
            for plugin in "${problematic_plugins[@]}"; do
                if [ -f "$plugin" ]; then
                    log_debug "$(i18n::get "msg_remove_plugin") $(basename "$plugin")"
                    rm "$plugin" 2>/dev/null
                fi
            done
            
            # GPU-Probleme vermeiden (GitHub Issue #45)
            output::substep "$(i18n::get "disabling_gpu")"
            # Verwende dynamischen Prefs-Pfad basierend auf erkannte Version
            local prefs_file="$PS_PREFS_PATH/Adobe Photoshop $PS_VERSION Prefs.psp"
            # Fallback für CC 2019 Format
            if [ ! -d "$(dirname "$prefs_file")" ]; then
                prefs_file="$PS_PREFS_PATH/Adobe Photoshop CC 2019 Prefs.psp"
            fi
            local prefs_dir
            prefs_dir=$(dirname "$prefs_file")
            
            # mkdir -p is idempotent, no need to check if directory exists
            mkdir -p "$prefs_dir"
            
            # Erstelle Prefs-Datei mit GPU-Deaktivierung
            # Diese Einstellungen verhindern GPU-Treiber-Warnungen
            cat > "$prefs_file" << 'EOF'
useOpenCL 0
useGraphicsProcessor 0
GPUAcceleration 0
EOF
            
            # BEST PRACTICE: Create PSUserConfig.txt with GPUForce 0 (GPU deaktiviert - empfohlen für Wine)
            # GPU acceleration causes rendering artifacts, glitchy UI, and display errors in 80-90% of cases
            # Disabling GPU is the recommended solution for Wine + Photoshop 2021
            # Path: AppData/Roaming/Adobe/Adobe Photoshop [VERSION]/Adobe Photoshop [VERSION] Settings/PSUserConfig.txt
            local ps_user_config_dir="$PS_PREFS_PATH/Adobe Photoshop $PS_VERSION Settings"
            if [ ! -d "$ps_user_config_dir" ]; then
                # Fallback for CC 2019 format
                ps_user_config_dir="$PS_PREFS_PATH/Adobe Photoshop CC 2019 Settings"
            fi
            
            if [ ! -d "$ps_user_config_dir" ]; then
                mkdir -p "$ps_user_config_dir"
            fi
            
            local ps_user_config_file="$ps_user_config_dir/PSUserConfig.txt"
            if [ -f "$ps_user_config_file" ]; then
                # Backup existing file
                cp "$ps_user_config_file" "${ps_user_config_file}.bak" 2>/dev/null || true
            fi
            
            # CRITICAL: Create PSUserConfig.txt with GPUForce 0 and UseOpenCL 0 (disable GPU acceleration)
            # GPU acceleration causes rendering artifacts, glitchy UI, and display errors in 80-90% of cases
            # Disabling GPU is the recommended solution for Wine + Photoshop 2021
            # User can enable it later in Photoshop Preferences if needed
            cat > "$ps_user_config_file" << 'EOF'
# GPU Configuration - Disable GPU acceleration (recommended for Wine)
# GPU acceleration often causes rendering artifacts and glitchy UI under Wine
# Set GPUForce to 1 to enable GPU (not recommended unless you have specific needs)
[GPU]
GPUForce 0
UseOpenCL 0
EOF
            log "  → PSUserConfig.txt erstellt mit GPUForce 0 (GPU deaktiviert - empfohlen für Wine)"
            
            # Zusätzlich: Deaktiviere GPU in Registry für bessere Kompatibilität
            log "  → Setze Registry-Einstellungen für GPU-Deaktivierung..."
            wine reg add "HKEY_CURRENT_USER\\Software\\Adobe\\Photoshop\\Settings" /v "GPUAcceleration" /t REG_DWORD /d 0 /f >> "$LOG_FILE" 2>&1 || true
            wine reg add "HKEY_CURRENT_USER\\Software\\Adobe\\Photoshop\\Settings" /v "useOpenCL" /t REG_DWORD /d 0 /f >> "$LOG_FILE" 2>&1 || true
            wine reg add "HKEY_CURRENT_USER\\Software\\Adobe\\Photoshop\\Settings" /v "useGraphicsProcessor" /t REG_DWORD /d 0 /f >> "$LOG_FILE" 2>&1 || true
            
            # PNG Save Fix (Issue #209): Installiere zusätzliche GDI+ Komponenten
            output::substep "$(i18n::get "installing_png_export")"
            winetricks -q gdiplus_winxp 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "$LOG_FILE" 2>&1 || true
            
            break
        fi
    done
}

function install_photoshopSE() {
    # Detect Photoshop version
    PS_VERSION=$(detect_photoshop_version)
    PS_INSTALL_PATH=$(get_photoshop_install_path "$PS_VERSION")
    PS_PREFS_PATH=$(get_photoshop_prefs_path "$PS_VERSION")
    
    # Clean section header
    output::section "$(i18n::get "photoshop_installation_section")"
    
    # Log detailed info (not shown to user)
    log_debug "Photoshop Installation gestartet: $(date '+%Y-%m-%d %H:%M:%S')"
    log_debug "Erkannte Version: $PS_VERSION"
    log_debug "Installations-Pfad: $PS_INSTALL_PATH"
    log_debug "Log-Datei: $LOG_FILE"
    
    # Show version to user (clean format)
    if [ "$LANG_CODE" = "de" ]; then
        output::info "Erkannte Version: $PS_VERSION"
    else
        output::info "Detected version: $PS_VERSION"
    fi
    echo ""
    
    # Verwende das lokale Adobe Photoshop Installationspaket
    local installer_dir=""
    if ! installer_dir="$(photoshop::resolve_installer_dir "$PROJECT_ROOT")"; then
        if [ "$LANG_CODE" = "de" ]; then
            error "Photoshop-Installer nicht gefunden.
Bitte kopiere Set-up.exe nach: $PROJECT_ROOT/photoshop/
Oder setze PHOTOSHOP_INSTALLER_DIR=/pfad/zum/installer"
        else
            error "Local Photoshop installer not found.
Copy Set-up.exe to: $PROJECT_ROOT/photoshop/
Or set PHOTOSHOP_INSTALLER_DIR=/path/to/installer"
        fi
    fi
    export PHOTOSHOP_INSTALLER_DIR="$installer_dir"
    local local_installer="$installer_dir/Set-up.exe"
    
    log_debug "$(i18n::get "msg_ps_found")"

    if ! photoshop_setup::deploy_installer_to_c_drive "$installer_dir"; then
        error "Konnte Adobe-Installer nicht nach C:\\AdobeSetup kopieren"
        return 1
    fi
    log_debug "Installer: C:\\AdobeSetup\\Set-up.exe (PIM braucht Windows-Pfad, kein Z:)"

    echo "===============| Adobe Photoshop $PS_VERSION |===============" >> "$SCR_PATH/wine-error.log"
    output::step "$(i18n::get "starting_installer")"
    output::header "$(i18n::get "important_installer_choice")"
    log_debug "Starte Adobe Photoshop Setup..."
    
    # Configure IE engine for Adobe Installer
    if ! configure_ie_engine; then
        error "$(i18n::get "ie8_install_failed" 2>/dev/null || echo "IE8 configuration failed")"
        return 1
    fi
    
    # Run Adobe Photoshop installer
    run_photoshop_installer
    local install_status=$?

    if [ $install_status -ne 0 ]; then
        log_error "Photoshop installation failed (status $install_status)"
        if type checkpoint::rollback >/dev/null 2>&1; then
            checkpoint::rollback "photoshop_installed" 2>/dev/null || true
        fi
        error "$(i18n::get "installation_failed" 2>/dev/null || echo "Installation failed")"
        return 1
    fi
    
    # Configure Photoshop after installation
    configure_photoshop
    
    # CRITICAL: Final .lnk file cleanup after Photoshop installation
    # Adobe installer may create .lnk files during installation
    log_debug "Final cleanup: Removing any remaining .lnk files..."
    local xdg_desktop="$(xdg-user-dir DESKTOP 2>/dev/null || echo '')"
    local desktop_dirs=("$HOME/Desktop" "$HOME/Schreibtisch" "$HOME/desktop" "$HOME/schreibtisch")
    # Add XDG desktop dir if it exists and is not empty
    if [ -n "$xdg_desktop" ] && [ -d "$xdg_desktop" ]; then
        desktop_dirs+=("$xdg_desktop")
    fi
    for desktop_dir in "${desktop_dirs[@]}"; do
        if [ -n "$desktop_dir" ] && [ -d "$desktop_dir" ]; then
            find "$desktop_dir" -maxdepth 1 -type f \( -name "*.lnk" -o -name "*Photoshop*.lnk" -o -name "*Adobe*.lnk" -o -name "*2021*.lnk" \) 2>/dev/null | while IFS= read -r lnk_file; do
                if [ -f "$lnk_file" ]; then
                    log_debug "Removing .lnk file after Photoshop installation: $lnk_file"
                    rm -f "$lnk_file" 2>/dev/null || true
                fi
            done
        fi
    done
    
    if command -v notify-send >/dev/null 2>&1; then
        if notify-send "Photoshop CC" "Photoshop Installation abgeschlossen" -i "photoshop" 2>/dev/null; then
            log_debug "Notification sent successfully"
        else
            log_debug "Notification failed (non-critical, likely no DBus session)"
        fi
    else
        log_debug "notify-send not available - skipping notification"
    fi
    log "Adobe Photoshop $PS_VERSION installiert..."
    
    # Create checkpoint after successful installation
    checkpoint::create "photoshop_installed"
    
    # CRITICAL: Save paths including Wine version info (PROTON_PATH) for uninstaller
    # This must be called AFTER PROTON_PATH is set (which happens in select_wine_version)
    save_paths
    
    # Cleanup checkpoints after successful installation
    checkpoint::cleanup
    
    # CRITICAL: Create launcher BEFORE finish_installation (needed for Photoshop start)
    # The launcher must exist before we try to start Photoshop
    # CRITICAL: Skip interactive command creation during installation to prevent blocking
    export SKIP_COMMAND_CREATION="true"
    log "Erstelle Launcher..."
    # CRITICAL: Temporarily disable errexit to prevent script termination if launcher() fails
    set +e
    if type launcher >/dev/null 2>&1; then
        launcher
        local launcher_exit=$?
        if [ $launcher_exit -eq 0 ]; then
            log "Launcher erfolgreich erstellt"
        else
            log_error "Launcher-Erstellung fehlgeschlagen (Exit-Code: $launcher_exit)"
            # Continue anyway - launcher might already exist or can be created manually
        fi
    else
        log_warning "launcher() function not found - skipping launcher creation"
    fi
    # Re-enable errexit
    set -e
    unset SKIP_COMMAND_CREATION
    
    # CRITICAL: Call finish_installation to show completion message and ask if user wants to start Photoshop
    log "Rufe finish_installation() auf..."
    finish_installation
    log "finish_installation() abgeschlossen"
    
    # After installation, return to main menu (if called from setup.sh)
    if [ -n "${RETURN_TO_MENU:-}" ]; then
        if [ "$LANG_CODE" = "de" ]; then
            echo ""
            output::info "Installation abgeschlossen. Kehre zum Hauptmenü zurück..."
            sleep 2
        else
            echo ""
            output::info "Installation completed. Returning to main menu..."
            sleep 2
        fi
    fi
    
    unset local_installer install_status possible_paths
}

# Parse command line arguments for Wine method selection
# Extract our custom parameters BEFORE check_arg (which uses getopts)
# NOTE: Logging is not yet initialized here, so we can't use log_debug
WINE_METHOD="proton-ge"
QUIET="${QUIET:-0}"
VERBOSE="${VERBOSE:-0}"
filtered_args=()
for arg in "$@"; do
    case "$arg" in
        --quiet|-q)
            QUIET=1
            ;;
        --verbose|-v)
            VERBOSE=1
            ;;
        --proton-ge)
            ;;
        --wine-standard)
            echo "Error: --wine-standard removed. Proton-GE only." >&2
            exit 1
            ;;
        *)
            filtered_args+=("$arg")
            ;;
    esac
done

# Export variables so they're available in all functions
export WINE_METHOD
export QUIET
export VERBOSE

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Call check_arg with filtered arguments (without --wine-standard)
    check_arg "${filtered_args[@]}"
    # NOTE: save_paths() is called at the END of installation
    main
fi




