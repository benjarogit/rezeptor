#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux Launcher
#
# Description:
#   Launches Adobe Photoshop CC with optimized Wine environment variables
#   for improved performance and stability. Includes GPU acceleration tweaks
#   and multi-threading optimizations.
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

# WINAPPS-TECHNIQUE: Parameters are accepted (for "Open with")
# Files can be passed as parameters: launch.sh /path/to/file.psd

_SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
_SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"

agent_debug_log() { :; }

# Deployed copy under $DATA_ROOT/launcher/ (written by sharedFuncs::launcher)
if [ -f "$_SELF_DIR/install.env" ]; then
    CORE_DIR="$_SELF_DIR"
    SCRIPT_DIR="$_SELF_DIR"
    # shellcheck source=/dev/null
    source "$CORE_DIR/env-file.sh"
    env_file_load_export "$_SELF_DIR/install.env"
    export CORE_DIR SCRIPT_DIR DATA_ROOT SCR_PATH WINE_PREFIX PROJECT_ROOT
    # shellcheck source=/dev/null
    source "$CORE_DIR/sharedFuncs.sh"
    # shellcheck source=/dev/null
    source "$CORE_DIR/wine-runtime.sh"
    wine() { wine_runtime::wine "$@"; }
else
    RECIPE_DIR="$(cd "$_SELF_DIR" && pwd)"
    PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
    CORE_DIR="$PROJECT_ROOT/core"
    export PROJECT_ROOT RECIPE_DIR CORE_DIR
    SCRIPT_DIR="$CORE_DIR"

    # shellcheck source=/dev/null
    source "$CORE_DIR/paths.sh"
    # shellcheck source=/dev/null
    source "$CORE_DIR/recipe.sh"
    recipe_export_env "$RECIPE_DIR/recipe.yml"

    if [ -f "$CORE_DIR/security.sh" ]; then
        # shellcheck source=/dev/null
        source "$CORE_DIR/security.sh"
    fi
    # shellcheck source=/dev/null
    source "$CORE_DIR/sharedFuncs.sh"
    # shellcheck source=/dev/null
    source "$CORE_DIR/wine-runtime.sh"
    wine() { wine_runtime::wine "$@"; }
fi

export WINE_PREFIX="${WINE_PREFIX:-${DATA_ROOT}/prefix}"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"
export RESOURCES_PATH="${RESOURCES_PATH:-$DATA_ROOT/resources}"

if [ -f "$HOME/.psdata.txt" ]; then
    WINE_VERSION_INFO="$(paths_read_psdata_proton_path 2>/dev/null || true)"
fi

if [ -n "${WINE_VERSION_INFO:-}" ]; then
    if [ -d "${WINE_VERSION_INFO}/files/bin" ] && [ -x "${WINE_VERSION_INFO}/files/bin/wine" ]; then
        export PROTON_PATH="$WINE_VERSION_INFO"
        export WINE_METHOD="${WINE_METHOD:-proton-ge}"
    fi
fi
if type wine_runtime::reset >/dev/null 2>&1; then
    wine_runtime::reset
fi
if type wine_runtime::init >/dev/null 2>&1; then
    wine_runtime::init 2>/dev/null || true
    wine_runtime::export_env 2>/dev/null || true
fi

# #region agent log
agent_debug_log "{\"id\":\"log_$(date +%s)_paths_loaded\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:53\",\"message\":\"Pfade geladen\",\"data\":{\"SCR_PATH\":\"${SCR_PATH:-}\",\"WINE_PREFIX\":\"${WINE_PREFIX:-}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}"
# #endregion

# Simple log function (if not available from sharedFuncs.sh)
if ! command -v log &>/dev/null; then
    log() {
        local log_file="${DATA_ROOT}/photoshop-runtime.log"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$log_file" 2>/dev/null || true
    }
fi

# Unified notification function
send_notification() {
    local title="${1:-Photoshop}"
    local message="${2:-}"
    local icon="${3:-photoshop}"
    
    if command -v notify-send >/dev/null 2>&1; then
        if notify-send "$title" "$message" -i "$icon" 2>/dev/null; then
            log_debug "Notification sent successfully: $title - $message"
        else
            log_debug "Notification failed (non-critical, likely no DBus session): $title - $message"
        fi
    else
        log_debug "notify-send not available - skipping notification: $title - $message"
    fi
}

# #region agent log
agent_debug_log "{\"id\":\"log_$(date +%s)_wine_prefix_set\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:64\",\"message\":\"WINE_PREFIX gesetzt\",\"data\":{\"WINE_PREFIX\":\"$WINE_PREFIX\",\"WINE_PREFIX_exists\":\"$([ -d "$WINE_PREFIX" ] && echo 'true' || echo 'false')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}"
# #endregion

# CRITICAL: WINEPREFIX validation - prevent manipulation
# Use centralized security::validate_path function if available
if command -v security::validate_path >/dev/null 2>&1; then
    if ! security::validate_path "$WINE_PREFIX"; then
        echo "ERROR: WINEPREFIX zeigt auf System-Verzeichnis (Sicherheitsrisiko): $WINE_PREFIX" >&2
        exit 1
    fi
else
    # Fallback to inline validation if security module not loaded
    if [[ "$WINE_PREFIX" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
        echo "ERROR: WINEPREFIX zeigt auf System-Verzeichnis (Sicherheitsrisiko): $WINE_PREFIX" >&2
        exit 1
    fi
fi
export WINEPREFIX="$WINE_PREFIX"

export FREETYPE_PROPERTIES="${FREETYPE_PROPERTIES:-truetype:interpreter-version=35,lcdfilter:default}"

# Schriften/ClearType — nach recipe-fonts.sh (weiter unten)

# CRITICAL: Suppress Wine warnings to reduce log noise
# WINEDEBUG=-all suppresses all warnings, but we keep errors visible
# This reduces the 64-bit/WOW64 warnings during runtime
export WINEDEBUG=-all,+err

# BEST PRACTICE: Enable Esync/Fsync for better performance (Internet-Tipp)
# Esync/Fsync improve performance by using eventfd/io_uring instead of wineserver
# Check if kernel supports it (requires kernel 4.17+ for fsync, 3.17+ for esync)
if [ -d /proc/sys/fs/epoll ] || [ -c /dev/shm ]; then
    # Esync: Use eventfd for synchronization (better performance)
    export WINEESYNC=1
    # Fsync: Use io_uring for synchronization (even better, requires kernel 5.1+)
    # Check if io_uring is available (kernel 5.1+)
    if [ -f /proc/sys/fs/aio-max-nr ] && [ "$(uname -r | cut -d. -f1)" -ge 5 ] 2>/dev/null; then
        export WINEFSYNC=1
    fi
fi

# Workarounds for known issues (GitHub Issues)

# Fix for GPU issues (Issue #45, #67)
export MESA_GL_VERSION_OVERRIDE=3.3
export __GL_SHADER_DISK_CACHE=0

# CRITICAL: DLL Overrides für Photoshop (müssen mit Setup übereinstimmen)
# Diese Overrides sind ESSENTIELL für Photoshop - ohne sie startet Photoshop nicht!
export WINEDLLOVERRIDES="winemenubuilder.exe=d;d3d11=native,builtin;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin"

# Performance-Optimierungen (Issue #135 - Zoom lag)
export WINE_CPU_TOPOLOGY="4:2"  # Optimal CPU usage
export __GL_THREADED_OPTIMIZATIONS=1  # Better OpenGL performance
export __GL_YIELD="USLEEP"  # Reduce input lag

# Fix for screen update issues (Issue #161 - Undo/Redo lag)
export CSMT=enabled  # Command Stream Multi-Threading

# DXVK Configuration (if DXVK is installed)
# DXVK_ASYNC=0: Disable async shader compilation (more stable, prevents rendering glitches)
# DXVK_HUD=0: Disable HUD (cleaner output, better performance)
# These settings improve stability when GPU is enabled (currently disabled by default)
export DXVK_ASYNC=0
export DXVK_HUD=0

# Check Wine configuration
# #region agent log
agent_debug_log "{\"id\":\"log_$(date +%s)_check_wine_prefix\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:122\",\"message\":\"Prüfe Wine-Prefix\",\"data\":{\"WINE_PREFIX\":\"$WINE_PREFIX\",\"exists\":\"$([ -d "$WINE_PREFIX" ] && echo 'true' || echo 'false')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}"
# #endregion
if [ ! -d "$WINE_PREFIX" ]; then
    # #region agent log
    agent_debug_log "{\"id\":\"log_$(date +%s)_wine_prefix_missing\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:123\",\"message\":\"Wine-Prefix nicht gefunden\",\"data\":{\"WINE_PREFIX\":\"$WINE_PREFIX\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}"
    # #endregion
    echo "FEHLER: Wine-Prefix nicht gefunden: $WINE_PREFIX"
    send_notification "Photoshop CC" "Wine-Prefix nicht gefunden! Bitte Photoshop neu installieren." "error"
    exit 1
fi

# CRITICAL: Check and fix MSVCP140.dll architecture issue (ARM64 vs x86-64)
# This is a known bug where winetricks vcrun2019 installs ARM64 DLLs in 64-bit prefixes
check_and_fix_msvcp140_dll() {
    local msvcp_dll="$WINE_PREFIX/drive_c/windows/system32/msvcp140.dll"
    
    if [ ! -f "$msvcp_dll" ]; then
        return 0  # DLL doesn't exist, nothing to fix
    fi
    
    # Check DLL architecture
    local dll_arch=$(file "$msvcp_dll" 2>/dev/null | grep -o "x86-64\|ARM64\|i386" || echo "unknown")
    
    # #region agent log
    agent_debug_log "{\"id\":\"log_$(date +%s)_check_msvcp\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:153\",\"message\":\"Prüfe MSVCP140.dll Architektur\",\"data\":{\"dll_arch\":\"$dll_arch\",\"dll_path\":\"$msvcp_dll\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\"}"
    # #endregion
    
    if [[ "$dll_arch" == "ARM64" ]]; then
        log "Warnung: MSVCP140.dll hat falsche Architektur (ARM64 statt x86-64) - behebe..."
        # #region agent log
        agent_debug_log "{\"id\":\"log_$(date +%s)_fix_msvcp\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:158\",\"message\":\"Behebe MSVCP140.dll Architektur-Problem\",\"data\":{},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\"}"
        # #endregion
        
        # Backup old DLL
        mv "$msvcp_dll" "$msvcp_dll.bak" 2>/dev/null || true
        
        # Try to download and install official Microsoft Visual C++ Redistributable x64
        # Use SCR_PATH if available, otherwise use default
        local cache_dir="${CACHE_PATH:-$(wine_software_cache_dir)}"
        local vc_redist_file="$cache_dir/vc_redist.x64.exe"
        local vc_redist_url="https://aka.ms/vc14/vc_redist.x64.exe"
        
        # Ensure cache directory exists
        mkdir -p "$cache_dir" 2>/dev/null || cache_dir="$HOME/.cache/photoshop"
        mkdir -p "$cache_dir"
        
        # Download if not cached
        if [ ! -f "$vc_redist_file" ]; then
            log "Lade Microsoft Visual C++ Redistributable x64 herunter..."
            if command -v wget >/dev/null 2>&1; then
                wget -q --show-progress -O "$vc_redist_file" "$vc_redist_url" 2>&1 || {
                    log "Download fehlgeschlagen - bitte manuell installieren: wine $vc_redist_file"
                    return 1
                }
            elif command -v curl >/dev/null 2>&1; then
                curl -L --progress-bar -o "$vc_redist_file" "$vc_redist_url" 2>&1 || {
                    log "Download fehlgeschlagen - bitte manuell installieren: wine $vc_redist_file"
                    return 1
                }
            else
                log "wget/curl nicht verfügbar - bitte manuell installieren"
                return 1
            fi
        fi
        
        # Install using official installer
        if [ -f "$vc_redist_file" ]; then
            log "Installiere Visual C++ 2015-2022 Redistributable x64 (offizieller Installer)..."
            export WINEPREFIX="$WINE_PREFIX"
            wine "$vc_redist_file" /quiet /norestart >/dev/null 2>&1
            
            # Verify DLL architecture after installation
            if [ -f "$msvcp_dll" ]; then
                dll_arch=$(file "$msvcp_dll" 2>/dev/null | grep -o "x86-64\|ARM64\|i386" || echo "unknown")
                if [[ "$dll_arch" == "x86-64" ]]; then
                    log "✓ MSVCP140.dll Architektur korrigiert (x86-64)"
                    # #region agent log
                    agent_debug_log "{\"id\":\"log_$(date +%s)_msvcp_fixed\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:188\",\"message\":\"MSVCP140.dll Architektur korrigiert\",\"data\":{\"dll_arch\":\"$dll_arch\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\"}"
                    # #endregion
                    return 0
                else
                    log "Warnung: MSVCP140.dll Architektur immer noch falsch ($dll_arch)"
                    # Restore backup
                    mv "$msvcp_dll.bak" "$msvcp_dll" 2>/dev/null || true
                    return 1
                fi
            fi
        fi
    elif [[ "$dll_arch" == "x86-64" ]]; then
        # DLL architecture is correct
        return 0
    fi
    
    return 0
}

# CRITICAL: Ensure Windows 10 is set (required for Photoshop)
# shellcheck source=/dev/null
[ -f "$CORE_DIR/recipe-win10.sh" ] && source "$CORE_DIR/recipe-win10.sh"
# shellcheck source=/dev/null
[ -f "$CORE_DIR/recipe-guard.sh" ] && source "$CORE_DIR/recipe-guard.sh"
# shellcheck source=/dev/null
[ -f "$CORE_DIR/recipe-winetricks.sh" ] && source "$CORE_DIR/recipe-winetricks.sh"
# shellcheck source=/dev/null
[ -f "$CORE_DIR/recipe-fonts.sh" ] && source "$CORE_DIR/recipe-fonts.sh"

if type recipe_fonts::ensure >/dev/null 2>&1; then
    recipe_fonts::ensure "${SCR_PATH}/photoshop-fonts.log" || log "Warnung: Schriften fehlgeschlagen"
elif type recipe_fonts::registry >/dev/null 2>&1; then
    recipe_fonts::registry
fi

recipe_guard::kill_stale_winetricks 2>/dev/null || true
recipe_guard::require_mem 4096 || exit 1
recipe_guard::abort_if_running "Photoshop.exe" || exit 1

log "Überprüfe Windows-Version..."
if type recipe_win10::ensure >/dev/null 2>&1; then
    recipe_win10::ensure || log "Warnung: win10 Registry fehlgeschlagen"
else
    log "Warnung: recipe-win10.sh fehlt — Reparieren ausführen"
fi

if type recipe_dpi::logpixels >/dev/null 2>&1; then
    recipe_dpi::logpixels
fi

# CRITICAL: Check and fix MSVCP140.dll architecture issue
check_and_fix_msvcp140_dll

if type wine_runtime::deploy_proton_graphics_dlls >/dev/null 2>&1; then
    wine_runtime::deploy_proton_graphics_dlls || log "Warnung: Proton-Grafik-DLLs (vkd3d/DXVK) nicht deploybar"
fi

# Search for Photoshop.exe in various possible paths
PHOTOSHOP_EXE=""
if photoshop_exe="$(photoshop::find_exe "$WINE_PREFIX" 2>/dev/null)"; then
    PHOTOSHOP_EXE="$photoshop_exe"
    echo "✓ Photoshop gefunden: $PHOTOSHOP_EXE"
fi

if [ -z "$PHOTOSHOP_EXE" ]; then
    POSSIBLE_PATHS=()
    while IFS= read -r _p; do POSSIBLE_PATHS+=("$_p"); done < <(photoshop::possible_exe_paths "$WINE_PREFIX")

    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -f "$path" ]; then
            PHOTOSHOP_EXE="$path"
            echo "✓ Photoshop gefunden: $path"
            break
        fi
    done
fi

if [ -z "$PHOTOSHOP_EXE" ]; then
    POSSIBLE_PATHS=()
    while IFS= read -r _p; do POSSIBLE_PATHS+=("$_p"); done < <(photoshop::possible_exe_paths "$WINE_PREFIX")
    send_notification "Photoshop" "Photoshop.exe nicht gefunden! Überprüfe die Installation." "error"
    echo "═══════════════════════════════════════════════════════════════"
    echo "FEHLER: Photoshop.exe nicht in folgenden Pfaden gefunden:"
    echo "═══════════════════════════════════════════════════════════════"
    for path in "${POSSIBLE_PATHS[@]}"; do
        echo "  ✗ $path"
    done
    echo ""
    echo "Bitte überprüfe die Installation oder führe setup.sh erneut aus."
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "           Adobe Photoshop - Linux Launcher"
echo "═══════════════════════════════════════════════════════════════"
echo "Photoshop-Pfad: $PHOTOSHOP_EXE"
echo "Wine-Prefix: $WINE_PREFIX"
# Show which Wine version is being used
if [ -n "${WINE_VERSION_INFO:-}" ] && [ -n "$WINE_VERSION_INFO" ]; then
    echo "Wine-Version: Proton-GE ($WINE_VERSION_INFO)"
elif [ "${WINE_RUNTIME_MODE:-}" = "proton-ge" ] || [ -n "${PROTON_PATH:-}" ]; then
    echo "Wine-Version: Proton-GE (${PROTON_PATH:-${WINE_RUNTIME_ROOT:-runtime}})"
else
    echo "Wine-Version: Proton-GE"
fi
echo ""
echo "Tipps bei Problemen:"
echo "  - Beim ersten Start kann es 1-2 Minuten dauern"
echo "  - Bei Abstürzen: GPU-Beschleunigung deaktivieren (Strg+K)"
echo "  - Bei Fehler 'VCRUNTIME140.dll': winecfg.sh ausführen"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# WINAPPS-TECHNIK: Progress-Indikator und Status-Notification
echo ""
echo "🔄 Photoshop wird gestartet..."
# Send notification with icon if available, fallback to default icon
notify_icon_path=""
if type recipe_guard::notify_icon >/dev/null 2>&1; then
    notify_icon_path="$(recipe_guard::notify_icon)"
elif [ -f "$SCR_PATH/launcher/AdobePhotoshop-icon.png" ]; then
    notify_icon_path="$SCR_PATH/launcher/AdobePhotoshop-icon.png"
elif [ -f "$SCRIPT_DIR/../images/AdobePhotoshop-icon.png" ]; then
    notify_icon_path="$SCRIPT_DIR/../images/AdobePhotoshop-icon.png"
fi
# Send notification with icon if available, fallback to default icon
if [ -n "$notify_icon_path" ] && [ -f "$notify_icon_path" ]; then
    send_notification "Photoshop" "Photoshop wird gestartet..." "$notify_icon_path"
else
    send_notification "Photoshop" "Photoshop wird gestartet..." "photoshop"
fi

# WINAPPS-TECHNIQUE: Pass files (if passed as parameters)
# Convert Linux paths to Windows paths for Wine
wine_args=()
if [ $# -gt 0 ]; then
    for file in "$@"; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            abs_path=$(readlink -f "$file" 2>/dev/null || echo "$file")
            
            # Try winepath first (more accurate), fallback to sed
            if command -v winepath >/dev/null 2>&1 && [ -n "${WINEPREFIX:-}" ]; then
                wine_path=$(winepath -w "$abs_path" 2>/dev/null || echo "")
                if [ -z "$wine_path" ]; then
                    # Fallback to sed if winepath fails
                    wine_path=$(echo "$abs_path" | sed "s|^/|Z:/|" | sed 's|/|\\|g')
                fi
            else
                # Fallback to sed if winepath not available
                wine_path=$(echo "$abs_path" | sed "s|^/|Z:/|" | sed 's|/|\\|g')
            fi
            
            wine_args+=("$wine_path")
            echo "📂 Öffne Datei: $(basename "$file")"
            log "Öffne Datei: $file -> $wine_path"
        fi
    done
fi

# Start Photoshop with Wine (with files as parameters, if available)
# WINAPPS-TECHNIQUE: Progress display during startup
echo "⏳ Initialisiere Wine-Umgebung..."
log "Starte Photoshop: $PHOTOSHOP_EXE"

# #region agent log
agent_debug_log "{\"id\":\"log_$(date +%s)_before_wine_start\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:227\",\"message\":\"Vor Wine-Start\",\"data\":{\"PHOTOSHOP_EXE\":\"$PHOTOSHOP_EXE\",\"wine_args_count\":${#wine_args[@]},\"wine_available\":\"$(command -v wine >/dev/null 2>&1 && echo 'true' || echo 'false')\",\"wine_binary\":\"$(command -v wine || echo 'NICHT_GEFUNDEN')\",\"WINEDLLOVERRIDES\":\"$WINEDLLOVERRIDES\",\"WINEPREFIX\":\"$WINEPREFIX\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C,D,F,G\"}"
# #endregion

if [ ${#wine_args[@]} -gt 0 ]; then
    # #region agent log
    agent_debug_log "{\"id\":\"log_$(date +%s)_wine_start_with_args\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:232\",\"message\":\"Starte Wine mit Argumenten\",\"data\":{\"wine_args\":[\"${wine_args[*]}\"]},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"F,G\"}"
    # #endregion
    wine "$PHOTOSHOP_EXE" "${wine_args[@]}" >> "$SCR_PATH/photoshop-runtime.log" 2>&1
else
    # #region agent log
    agent_debug_log "{\"id\":\"log_$(date +%s)_wine_start_no_args\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:234\",\"message\":\"Starte Wine ohne Argumente\",\"data\":{},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"F,G\"}"
    # #endregion
    wine "$PHOTOSHOP_EXE" >> "$SCR_PATH/photoshop-runtime.log" 2>&1
fi

exit_code=$?

# #region agent log
agent_debug_log "{\"id\":\"log_$(date +%s)_wine_exit\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:240\",\"message\":\"Wine beendet\",\"data\":{\"exit_code\":$exit_code,\"log_file\":\"$SCR_PATH/photoshop-runtime.log\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"F,G\"}"
# #endregion

if [ $exit_code -ne 0 ]; then
    echo ""
    echo "⚠ Photoshop wurde mit Exit-Code $exit_code beendet"
    echo "Überprüfe die Logs: $SCR_PATH/photoshop-runtime.log"
    # #region agent log
    agent_debug_log "{\"id\":\"log_$(date +%s)_wine_error\",\"timestamp\":$(date +%s)000,\"location\":\"launcher.sh:243\",\"message\":\"Wine-Fehler aufgetreten\",\"data\":{\"exit_code\":$exit_code},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"F,G\"}"
    # #endregion
fi

exit $exit_code



