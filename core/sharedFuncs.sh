#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Shared Functions Library
#
# Description:
#   Common utility functions used across all installer scripts including
#   package detection, path management, progress indicators, and notifications.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/rezeptor
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
#
# Based on:     photoshopCClinux by Gictorbit
#               https://github.com/Gictorbit/photoshopCClinux
################################################################################

# CRITICAL: Robust error handling (if not already set)
if [ "${BASH_SET_EUO:-}" != "set" ]; then
    set -eu
    (set -o pipefail 2>/dev/null) || true
    export BASH_SET_EUO="set"
fi

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

sharedFuncs::_core_dir() {
    if [ -n "${CORE_DIR:-}" ]; then
        echo "$CORE_DIR"
    elif [ -n "${PROJECT_ROOT:-}" ] && [ -d "${PROJECT_ROOT}/core" ]; then
        echo "${PROJECT_ROOT}/core"
    else
        echo "${BASH_SOURCE[0]%/*}"
    fi
}

sharedFuncs::_validate_path() {
    local path="$1"
    if ! type security::validate_path >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "$(sharedFuncs::_core_dir)/security.sh"
    fi
    security::validate_path "$path"
}

# Get PROJECT_ROOT from environment or derive from SCRIPT_DIR
PROJECT_ROOT="${PROJECT_ROOT:-}"
if [ -z "$PROJECT_ROOT" ] && [ -n "${SCRIPT_DIR:-}" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd 2>/dev/null || echo "")"
fi
# LOG_DIR if set by setup.sh / recipe hooks, otherwise PROJECT_ROOT/logs
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT:-}/logs}"
TIMESTAMP="${TIMESTAMP:-$(date +%d.%m.%y\ %H:%M\ Uhr)}"

# Fallback log_debug function (if not already defined by caller)
if ! command -v log_debug >/dev/null 2>&1; then
    log_debug() {
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
        local message="$*"
        
        # Always log to file if LOG_FILE is set
        if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
            echo "[$timestamp] DEBUG: $message" >> "${LOG_FILE}" 2>/dev/null || true
        fi
        
        # Only show on console in verbose mode (and not in quiet mode)
        if [ "${VERBOSE:-0}" = "1" ] && [ "${QUIET:-0}" != "1" ]; then
            # Use C_GRAY if available, otherwise plain text
            if [ -n "${C_GRAY:-}" ]; then
                echo -e "${C_GRAY}[DEBUG]${C_RESET} $message" >&2
            else
                echo "[DEBUG] $message" >&2
            fi
        fi
    }
fi

# ANSI Color codes (same as setup.sh)
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

#has tow mode [pkgName] [mode=summary]
function package_installed() {
    # CRITICAL: command -v instead of which (POSIX-compliant, safer)
    # CRITICAL: "$1" quoted against command injection
    if command -v "$1" >/dev/null 2>&1; then
        local pkginstalled=0
    else
        local pkginstalled=1
    fi

    # CRITICAL: == is not POSIX, use =
    # CRITICAL: $2 is optional, therefore use ${2:-}
    if [ "${2:-}" = "summary" ];then
        if [ "$pkginstalled" -eq 0 ];then
            echo "true"
        else
            echo "false"
        fi
    else    
        if [ "$pkginstalled" -eq 0 ];then
            # Use output::success if available, otherwise fallback to show_message
            if type output::success >/dev/null 2>&1; then
                output::success "package $1 is installed"
            else
                show_message "${C_GREEN}✓${C_RESET} package ${C_CYAN}$1${C_RESET} is installed..."
            fi
        else
            # Use output::error if available, otherwise fallback to warning
            if type output::error >/dev/null 2>&1; then
                output::error "package $1 is not installed"
            else
                warning "${C_YELLOW}⚠${C_RESET} package ${C_YELLOW}$1${C_RESET} is not installed.\nplease make sure it's already installed"
            fi
            ask_question "would you continue?" "N"
            if [ "$question_result" = "no" ];then
                echo -e "${C_RED}exit...${C_RESET}"
                exit 5
            fi
        fi
    fi
}

# Get main log file if available (from setup.sh / recipe hooks)
get_main_log() {
    # Try to find the main log file from environment or project root
    if [ -n "${LOG_FILE:-}" ]; then
        echo "${LOG_FILE}"
    elif [ -n "${PROJECT_ROOT:-}" ] && [ -d "${PROJECT_ROOT}/logs" ]; then
        # Find the most recent log file
        ls -t "${PROJECT_ROOT}/logs"/*.log 2>/dev/null | head -1 || echo ""
    else
        echo ""
    fi
}

function setup_log() {
    local main_log=$(get_main_log)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to main log if available
    if [ -n "${main_log:-}" ] && [ -f "${main_log}" ]; then
        echo "[$timestamp] $*" >> "${main_log}"
    fi
    
    # Also log to LOG_FILE if available
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] $*" >> "${LOG_FILE}" 2>/dev/null || true
    fi
    
    # Also log to old location for compatibility (only if SCR_PATH is set and directory exists)
    if [ -n "${SCR_PATH:-}" ] && [ -d "${SCR_PATH:-}" ]; then
        echo -e "$(date) : $*" >> "${SCR_PATH}/setuplog.log" 2>/dev/null || true
    fi
}

# ============================================================================
# @function show_message
# @description Display colored message and log to all available log files
# @param $@ Message(s) to display
# @param $1 Optional: "simple" to only log to main_log (like old show_message2)
# @return 0 (always succeeds)
# @example show_message "${C_GREEN}Installation complete${C_RESET}"
# @example show_message "simple" "Simple message"  # Only log to main_log
# ============================================================================
function show_message() {
    local simple_mode=false
    local message=""
    
    # Check for optional flag
    if [ "$1" = "simple" ]; then
        simple_mode=true
        shift
    fi
    
    message="$*"
    
    local main_log=$(get_main_log)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Strip ANSI codes for logging (keep only plain text)
    local plain_message=$(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Log to main log file if available (plain text, no colors)
    if [ -n "${main_log:-}" ] && [ -f "${main_log}" ]; then
        echo "[$timestamp] $plain_message" >> "${main_log}"
    fi
    
    # Extended logging (unless simple mode)
    if [ "$simple_mode" = false ]; then
        # Also log to LOG_FILE if available
        if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
            echo "[$timestamp] $plain_message" >> "${LOG_FILE}"
        fi
        
        # Also log to old setuplog.log for compatibility
        if [ -n "${SCR_PATH:-}" ] && [ -d "${SCR_PATH:-}" ]; then
            echo -e "$(date) : $plain_message" >> "${SCR_PATH}/setuplog.log" 2>/dev/null || true
        fi
    fi
    
    # Display with colors
    echo -e "$message"
}

# ============================================================================
# @function error
# @description Display error message and exit with code 1
# @param $@ Error message(s)
# @param $1 Optional: "no_setup_log" to skip setup_log call
# @param $1 Optional: "no_error_log" to skip error log file
# @return Never returns (exits with code 1)
# @example error "File not found"
# @example error "no_setup_log" "File not found"  # Skip setup_log
# ============================================================================
function error() {
    local skip_setup_log=false
    local skip_error_log=false
    local message=""
    
    # Check for optional flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "no_setup_log")
                skip_setup_log=true
                shift
                ;;
            "no_error_log")
                skip_error_log=true
                shift
                ;;
            *)
                message="$message $1"
                shift
                ;;
        esac
    done
    
    # Trim leading space
    message="${message# }"
    
    local main_log=$(get_main_log)
    local error_log=""
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Try to find error log
    if [ "$skip_error_log" = false ]; then
        if [ -n "$ERROR_LOG" ]; then
            error_log="$ERROR_LOG"
        elif [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT/logs" ]; then
            error_log=$(ls -t "$PROJECT_ROOT/logs"/*_errors.log 2>/dev/null | head -1 || echo "")
        fi
    fi
    
    # Strip ANSI codes for logging
    local plain_message=$(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Display error using output::error for consistency
    # output::error is sourced from output.sh in setup.sh/main script
    if type output::error >/dev/null 2>&1; then
        output::error "$message"
    else
        # Fallback if output::error is not available (should not happen in normal flow)
        echo -e "${C_RED}✗ ERROR:${C_RESET} ${C_RED}$message${C_RESET}" >&2
    fi
    
    # Log to main log if available (plain text)
    if [ -n "$main_log" ] && [ -f "$main_log" ]; then
        echo "[$timestamp] ERROR: $plain_message" >> "$main_log"
    fi
    
    # Log to error log if available
    if [ -n "$error_log" ] && [ -f "$error_log" ]; then
        echo "[$timestamp] ERROR: $plain_message" >> "$error_log"
    fi
    
    # Call setup_log unless skipped
    if [ "$skip_setup_log" = false ]; then
        setup_log "ERROR: $plain_message"
    fi
    
    exit 1
}

# DEPRECATED: Use error() instead. This function is kept for backward compatibility.
# Will be removed in a future version.
function error2() {
    error "no_setup_log" "no_error_log" "$@"
}

# ============================================================================
# @function warning
# @description Display warning message (non-fatal)
# @param $@ Warning message(s)
# @param $1 Optional: "no_setup_log" to skip setup_log call
# @return 0 (always succeeds)
# @example warning "File not found, using default"
# @example warning "no_setup_log" "File not found"  # Skip setup_log
# ============================================================================
function warning() {
    local skip_setup_log=false
    local message=""
    
    # Check for optional flag
    if [ "$1" = "no_setup_log" ]; then
        skip_setup_log=true
        shift
    fi
    
    message="$*"
    
    local main_log=$(get_main_log)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Strip ANSI codes for logging
    local plain_message=$(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Display with yellow color
    echo -e "${C_YELLOW}⚠ WARNING:${C_RESET} ${C_YELLOW}$message${C_RESET}"
    
    # Log to main log if available (plain text)
    if [ -n "$main_log" ] && [ -f "$main_log" ]; then
        echo "[$timestamp] WARNING: $plain_message" >> "$main_log"
    fi
    
    # Call setup_log unless skipped
    if [ "$skip_setup_log" = false ]; then
        setup_log "WARNING: $plain_message"
    fi
}

# DEPRECATED: Use warning() instead. This function is kept for backward compatibility.
# Will be removed in a future version.
function warning2() {
    warning "no_setup_log" "$@"
}

# DEPRECATED: Use show_message() with "simple" flag instead. This function is kept for backward compatibility.
# Will be removed in a future version.
function show_message2() {
    show_message "simple" "$@"
}


function export_var() {
    # CRITICAL: WINEPREFIX validation - prevent manipulation
    if ! sharedFuncs::_validate_path "$WINE_PREFIX"; then
        error "WINEPREFIX zeigt auf System-Verzeichnis (Sicherheitsrisiko): $WINE_PREFIX"
        return 1
    fi
    export WINEPREFIX="$WINE_PREFIX"
    if [ "${LAUNCHER_GUI:-0}" != "1" ]; then
        show_message "wine variables exported..."
    else
        log_debug "WINEPREFIX=$WINEPREFIX"
    fi
}

#parameters is [PATH] [CheckSum] [URL] [FILE NAME]
function download_component() {
    local tout=0
    local url="$3"
    
    # CRITICAL: Download URL validation - prevent malicious URLs
    if [[ ! "$url" =~ ^https:// ]]; then
        error "Download URL must use HTTPS (security risk): $url"
        return 1
    fi
    
    if type security::validate_url >/dev/null 2>&1; then
        if ! security::validate_url "$url" "microsoft.com" "adobe.com"; then
            error "Download-URL von nicht erlaubter Domain (Sicherheitsrisiko): $url"
            return 1
        fi
    else
        local allowed_domains=(
            "github.com"
            "githubusercontent.com"
            "sourceforge.net"
            "microsoft.com"
            "adobe.com"
        )
        local url_domain
        url_domain=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|' | sed 's|^www\.||')
        local domain_allowed=0
        for domain in "${allowed_domains[@]}"; do
            if [[ "$url_domain" == "$domain" ]] || [[ "$url_domain" == *".$domain" ]]; then
                domain_allowed=1
                break
            fi
        done
        if [ $domain_allowed -eq 0 ]; then
            error "Download-URL von nicht erlaubter Domain (Sicherheitsrisiko): $url_domain"
            return 1
        fi
    fi
    
    while true;do
        if [ $tout -ge 3 ];then
            error "sorry something went wrong during download $4"
        fi
        if [ -f $1 ];then
            # Integrity: SHA-256 (MD5 is collision-broken; callers pass sha256 hex).
            local FILE_ID
            FILE_ID=$(sha256sum "$1" | cut -d" " -f1)
            if [ "$FILE_ID" = "${2:-}" ];then
                show_message "\033[1;36m$4\e[0m detected"
                return 0
            else
                show_message "sha256 is not match"
                rm $1 
            fi
        else   
            show_message "downloading $4 ..."
            ariapkg=$(package_installed aria2c "summary")
            curlpkg=$(package_installed curl "summary")
            
            if [ "$ariapkg" = "true" ];then
                show_message "using aria2c to download $4"
                aria2c -c -x 8 -d "$CACHE_PATH" -o $4 "$url"
                
                if [ $? -eq 0 ];then
                    if declare -F recipe_notify::send >/dev/null 2>&1; then
                        recipe_notify::send "Photoshop" "$4 download completed" "" "download"
                    else
                        notify-send -a "Photoshop" "$4 download completed" -i "download" 2>/dev/null || true
                    fi
                fi

            elif [ "$curlpkg" = "true" ];then
                show_message "using curl to download $4"
                curl "$url" -o $1
            else
                show_message "using wget to download $4"
                wget "$url" -P "$CACHE_PATH"
                
                if [ $? -eq 0 ];then
                    if declare -F recipe_notify::send >/dev/null 2>&1; then
                        recipe_notify::send "Photoshop" "$4 download completed" "" "download"
                    else
                        notify-send -a "Photoshop" "$4 download completed" -i "download" 2>/dev/null || true
                    fi
                fi
            fi
            ((tout++))
        fi
    done
}

function rmdir_if_exist() {
    # CRITICAL: Safe rm -rf with validation
    local dir="$1"
    if [ -z "$dir" ]; then
        error "rmdir_if_exist: Verzeichnisname ist leer"
        return 1
    fi
    if [ "$dir" = "/" ]; then
        error "rmdir_if_exist: Verzeichnis ist root (Sicherheit)"
        return 1
    fi
    if [ -d "$dir" ]; then
        # CRITICAL: Use filesystem::safe_remove if available, otherwise fallback
        if type filesystem::safe_remove >/dev/null 2>&1; then
            filesystem::safe_remove "$dir" "rmdir_if_exist" || { error "rmdir_if_exist: Löschen fehlgeschlagen: $dir"; return 1; }
        else
            rm -rf "$dir" || { error "rmdir_if_exist: Löschen fehlgeschlagen: $dir"; return 1; }
        fi
        # log_debug "$dir directory exists, deleting it..."  # Commented out - log_debug may not be available
    fi
    mkdir -p "$dir" || { error "rmdir_if_exist: Erstellen fehlgeschlagen: $dir"; return 1; }
    # log_debug "Created directory: $dir"  # Commented out - log_debug may not be available
}

# ============================================================================
# @namespace wait
# @description Polling functions to replace sleep calls for better performance
# ============================================================================

# ============================================================================
# @function wait::for_file
# @description Wait for a file to exist (polling instead of sleep)
# @param $1 File path to wait for
# @param $2 Optional: Timeout in seconds (default: 30)
# @param $3 Optional: Poll interval in seconds (default: 0.5)
# @return 0 if file exists, 1 on timeout
# @example wait::for_file "/path/to/file" 60
# ============================================================================
wait::for_file() {
    local file="$1"
    local timeout="${2:-30}"
    local interval="${3:-0.5}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$file" ]; then
            return 0
        fi
        sleep "$interval"
        elapsed=$(echo "$elapsed + $interval" | bc -l 2>/dev/null || echo "$((elapsed + 1))")
    done
    
    return 1
}

# ============================================================================
# @function wait::for_process
# @description Wait for a process to finish (polling instead of sleep)
# @param $1 Process ID (PID)
# @param $2 Optional: Timeout in seconds (default: 300)
# @param $3 Optional: Poll interval in seconds (default: 0.5)
# @return 0 if process finished, 1 on timeout
# @example wait::for_process "$pid" 60
# ============================================================================
wait::for_process() {
    local pid="$1"
    local timeout="${2:-300}"
    local interval="${3:-0.5}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            # Process no longer exists
            return 0
        fi
        sleep "$interval"
        elapsed=$(echo "$elapsed + $interval" | bc -l 2>/dev/null || echo "$((elapsed + 1))")
    done
    
    return 1
}

# ============================================================================
# @function wait::for_wine_prefix
# @description Wait for Wine prefix to be initialized (user.reg exists)
# @param $1 Wine prefix path
# @param $2 Optional: Timeout in seconds (default: 60)
# @param $3 Optional: Poll interval in seconds (default: 1)
# @return 0 if prefix initialized, 1 on timeout
# @example wait::for_wine_prefix "$WINEPREFIX" 60
# ============================================================================
wait::for_wine_prefix() {
    local prefix="$1"
    local timeout="${2:-60}"
    local interval="${3:-1}"
    local user_reg="$prefix/user.reg"
    local system_reg="$prefix/system.reg"
    local elapsed=0
    local last_size=0
    local stable_count=0
    
    # CRITICAL: Validate prefix path before waiting
    if [ -z "$prefix" ]; then
        log_debug "wait::for_wine_prefix: prefix is empty"
        return 1
    fi
    
    # Check if prefix directory exists
    if [ ! -d "$prefix" ]; then
        log_debug "wait::for_wine_prefix: prefix directory does not exist: $prefix"
        return 1
    fi
    
    while [ $elapsed -lt $timeout ]; do
        # Check if user.reg exists (main indicator of prefix initialization)
        if [ -f "$user_reg" ]; then
            # NEW: Check if file size is stable (Wine 10.x writes slowly)
            local current_size=$(stat -c%s "$user_reg" 2>/dev/null || echo "0")
            
            if [ "$current_size" -gt 0 ]; then
                # File exists and is not empty
                if [ "$current_size" -eq "$last_size" ]; then
                    # Size hasn't changed - file is stable
                    stable_count=$((stable_count + 1))
                    
                    # Wait for 2 consecutive stable checks (prevents false positives)
                    if [ $stable_count -ge 2 ]; then
            # Also check if system.reg exists (secondary check)
            if [ -f "$system_reg" ]; then
                            log_debug "wait::for_wine_prefix: Prefix initialized successfully (user.reg stable at ${current_size} bytes)"
                    return 0
                else
                            log_debug "wait::for_wine_prefix: user.reg stable but system.reg missing, continuing..."
                        fi
                fi
            else
                    # Size changed - still being written
                    log_debug "wait::for_wine_prefix: user.reg growing (${current_size} bytes)"
                    stable_count=0
                fi
                last_size=$current_size
            else
                log_debug "wait::for_wine_prefix: user.reg exists but is empty, continuing..."
            fi
        fi
        sleep "$interval"
        elapsed=$((elapsed + 1))
    done
    
    # Final check before returning failure
    if [ -f "$user_reg" ] && [ -s "$user_reg" ]; then
        log_debug "wait::for_wine_prefix: Prefix initialized (timed out waiting for stability but file exists)"
        return 0
    fi
    
    log_debug "wait::for_wine_prefix: Timeout after ${timeout}s, prefix not initialized"
    return 1
}

# ============================================================================
# @namespace progress
# @description Progress bar functions for long-running operations
# ============================================================================

# ============================================================================
# @function progress::bar
# @description Display a progress bar for long-running operations
# @param $1 Message to display
# @param $2 Process ID to monitor (optional, if not provided, just shows spinner)
# @param $3 Optional: Estimated total time in seconds (for percentage calculation)
# @return 0 on success, 1 on error
# @example progress::bar "Installing dotnet48..." "$pid" 1200
# ============================================================================
progress::bar() {
    local message="$1"
    local pid="${2:-}"
    local estimated_time="${3:-0}"
    local width=50
    local elapsed=0
    local interval=1
    
    # If no PID provided, just show a simple spinner
    if [ -z "$pid" ]; then
        local spinstr='|/-\'
        while true; do
            local temp=${spinstr#?}
            printf "\r${C_YELLOW}%s${C_RESET} [%c]" "$message" "$spinstr"
            spinstr=$temp${spinstr%"$temp"}
            sleep 0.2
        done
        return 0
    fi
    
    # Show spinner while process is running (simpler and more reliable than progress bar)
    # CRITICAL: Use stderr for spinner output to avoid interfering with process output
    
    local spinstr='|/-\'
    local spin_idx=0
    
    while kill -0 "$pid" 2>/dev/null; do
        local spin_char=${spinstr:$spin_idx:1}
        
        # Display spinner with elapsed time (use stderr to avoid interfering with process output)
        if [ $estimated_time -gt 0 ]; then
            local percentage=$((elapsed * 100 / estimated_time))
            if [ $percentage -gt 100 ]; then
                percentage=100
            fi
            printf "\r${C_YELLOW}%s${C_RESET} [%c] %d%% (%ds)" "$message" "$spin_char" "$percentage" "$elapsed" >&2
        else
            printf "\r${C_YELLOW}%s${C_RESET} [%c] (%ds)" "$message" "$spin_char" "$elapsed" >&2
        fi
        
        # Debug logging removed
        
        # Update spinner character
        spin_idx=$(((spin_idx + 1) % 4))
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    # Wait a moment to ensure process is really done
    sleep 0.1
    
    # Clear spinner and show completion (use stderr)
    printf "\r${C_GREEN}%s${C_RESET} ✓ (completed)\n" "$message" >&2
    
    return 0
}

# ============================================================================
# @namespace retry
# @description Retry mechanism with exponential backoff for robust error handling
# ============================================================================

# ============================================================================
# @function retry::with_backoff
# @description Retry a command with exponential backoff
# @param $1 Command to execute (as string, will be eval'd)
# @param $2 Optional: Maximum number of retries (default: 3)
# @param $3 Optional: Initial backoff in seconds (default: 2)
# @param $4 Optional: Maximum backoff in seconds (default: 60)
# @return 0 on success, 1 if all retries failed
# @example retry::with_backoff "winetricks -q vcrun2015" 3 2
# ============================================================================
retry::with_backoff() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local initial_backoff="${3:-2}"
    local max_backoff="${4:-60}"
    local attempt=1
    local backoff=$initial_backoff
    
    while [ $attempt -le $max_retries ]; do
        # CRITICAL: Validate command before execution if security::safe_eval available
        if type security::safe_eval >/dev/null 2>&1; then
            if ! security::safe_eval "$cmd" "wine" "winetricks"; then
                log::warning "Unsafe command detected: $cmd"
                return 1
            fi
        fi
        
        # Execute command and capture exit code
        # CRITICAL: Use bash -c instead of eval for security
        if bash -c "$cmd"; then
            return 0
        fi
        
        local exit_code=$?
        
        # If this was the last attempt, return failure
        if [ $attempt -eq $max_retries ]; then
            log::warning "Command failed after $max_retries attempts: $cmd"
            return $exit_code
        fi
        
        # Wait with exponential backoff
        log::debug "Command failed (attempt $attempt/$max_retries), retrying in ${backoff}s: $cmd"
        sleep "$backoff"
        
        # Calculate next backoff (exponential, capped at max_backoff)
        backoff=$((backoff * 2))
        if [ $backoff -gt $max_backoff ]; then
            backoff=$max_backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# ============================================================================
# @function retry::simple
# @description Retry a command with fixed delay (simpler than exponential backoff)
# @param $1 Command to execute (as string, will be eval'd)
# @param $2 Optional: Maximum number of retries (default: 3)
# @param $3 Optional: Delay between retries in seconds (default: 5)
# @return 0 on success, 1 if all retries failed
# @example retry::simple "winetricks -q win10" 3 5
# ============================================================================
retry::simple() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local delay="${3:-5}"
    local attempt=1
    
    # Check if command contains winetricks - if so, filter output and set WINEDEBUG
    local filter_output=false
    if [[ "$cmd" =~ winetricks ]]; then
        filter_output=true
        # Ensure WINEDEBUG is set to suppress warnings (inherited from parent if already set)
        export WINEDEBUG="${WINEDEBUG:--all,+err}"
    fi
    
    while [ $attempt -le $max_retries ]; do
        # CRITICAL: Validate command before execution if security::safe_eval available
        if type security::safe_eval >/dev/null 2>&1; then
            if ! security::safe_eval "$cmd" "wine" "winetricks"; then
                log::warning "Unsafe command detected: $cmd"
                return 1
            fi
        fi
        
        # Execute command and capture exit code
        # CRITICAL: Use bash -c instead of eval for security
        if [ "$filter_output" = true ]; then
            # Filter winetricks output - suppress warnings and redirect to log only
            bash -c "$cmd" 2>&1 | grep -vE "warning:.*64-bit|warning:.*wow64|Executing|Using winetricks|------------------------------------------------------" >> "${LOG_FILE:-/dev/null}" 2>&1
            local exit_code=${PIPESTATUS[0]}
        else
            # Normal execution
            bash -c "$cmd"
            local exit_code=$?
        fi
        
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        
        # If this was the last attempt, return failure
        if [ $attempt -eq $max_retries ]; then
            log::warning "Command failed after $max_retries attempts: $cmd"
            return $exit_code
        fi
        
        # Wait with fixed delay
        log::debug "Command failed (attempt $attempt/$max_retries), retrying in ${delay}s: $cmd"
        sleep "$delay"
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

function check_arg() {
    # Initialize variables before use (required for set -u)
    local dashd=0
    local dashc=0
    
    while getopts "hd:c:" OPTION; do
        case $OPTION in
        d)
            PARAMd="$OPTARG"
            SCR_PATH=$(readlink -f "$PARAMd")
            
            dashd=1
            echo "install path is $SCR_PATH"
            setup_log "install path is $SCR_PATH"
            ;;
        c)
            PARAMc="$OPTARG"
            CACHE_PATH=$(readlink -f "$PARAMc")
            dashc=1
            echo "cahce is $CACHE_PATH"
            setup_log "cache is $CACHE_PATH"
            ;;
        h)
            usage
            ;; 
        *)
            echo "wrong argument"
            exit 1
            ;;
        esac
    done
    shift $(($OPTIND - 1))

    if [[ $# != 0 ]];then
        usage
        error2 "unknown argument"
    fi

    if [[ $dashd != 1 ]] ;then
        # Only log, don't show to user (less noise)
        local _default_data
        if type recipe_data_root >/dev/null 2>&1; then
            _default_data="$(recipe_data_root "${RECIPE_ID:-photoshop}")"
        else
            _default_data="${HOME}/.local/share/wine-software/photoshop"
        fi
        setup_log "-d not defined, using default directory: $_default_data"
        # KRITISCH: Umgebungsvariablen-Validierung - prüfe dass $HOME sicher ist
        if [ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ]; then
            error "Unsichere HOME-Umgebungsvariable: ${HOME:-not set}"
            exit 1
        fi
        SCR_PATH="$_default_data"
        DATA_ROOT="$SCR_PATH"
    fi

    if [[ $dashc != 1 ]];then
        # Only log, don't show to user (less noise)
        local _default_cache
        if type wine_software_cache_dir >/dev/null 2>&1; then
            _default_cache="$(wine_software_cache_dir)"
        else
            _default_cache="${HOME}/.local/share/wine-software/cache/winetricks"
        fi
        setup_log "-c not defined, using default cache directory: $_default_cache"
        # KRITISCH: Umgebungsvariablen-Validierung - prüfe dass $HOME sicher ist
        if [ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ]; then
            error "Unsichere HOME-Umgebungsvariable: ${HOME:-not set}"
            exit 1
        fi
        CACHE_PATH="$_default_cache"
    fi
}

function is64() {
    local arch=$(uname -m)
    if [ $arch != "x86_64"  ];then
        warning "your distro is not 64 bit"
        read -r -p "Would you continue? [N/y] " response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
           echo "Good Bye!"
           exit 0
        fi
    fi
   show_message "is64 checked..."
}

#parameters [Message] [default flag [Y/N]]
function ask_question() {
    question_result=""
    # KRITISCH: == ist nicht POSIX, verwende =
    # CRITICAL: read -r with IFS= for whitespace safety
    # CRITICAL: Reset IFS after read
    # KRITISCH: $2 ist optional, daher ${2:-} verwenden
    local old_IFS="${IFS:-}"
    if [ "${2:-}" = "Y" ];then
        IFS= read -r -p "$1 [Y/n] " response
        # CRITICAL: locale yesexpr/noexpr may be missing, fallback
        if locale noexpr >/dev/null 2>&1 && [[ "$response" =~ $(locale noexpr) ]];then
            question_result="no"
        elif [ -n "$response" ] && [[ "$response" =~ ^[Nn] ]]; then
            question_result="no"
        else
            question_result="yes"
        fi
    elif [ "${2:-}" = "N" ];then
        IFS= read -r -p "$1 [N/y] " response
        if locale yesexpr >/dev/null 2>&1 && [[ "$response" =~ $(locale yesexpr) ]];then
            question_result="yes"
        elif [ -n "$response" ] && [[ "$response" =~ ^[Yy] ]]; then
            question_result="yes"
        else
            question_result="no"
        fi
    fi
    # CRITICAL: Reset IFS
    IFS="$old_IFS"
}

function usage() {
    echo "USAGE: [-c cache directory] [-d installation directory]"
}

function save_paths() {
    # CRITICAL: Validation BEFORE saving - prevent privilege escalation
    if ! sharedFuncs::_validate_path "$SCR_PATH"; then
        error "SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
        return 1
    fi
    if ! sharedFuncs::_validate_path "$CACHE_PATH"; then
        error "CACHE_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $CACHE_PATH"
        return 1
    fi
    
    # Prüfe dass Pfade nicht leer sind
    if [ -z "$SCR_PATH" ]; then
        error "SCR_PATH ist leer (Sicherheitsrisiko)"
        return 1
    fi
    
    if [ -z "$CACHE_PATH" ]; then
        error "CACHE_PATH ist leer (Sicherheitsrisiko)"
        return 1
    fi
    
    # KRITISCH: Umgebungsvariablen-Validierung - prüfe dass $HOME sicher ist
    if [ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ]; then
        error "Unsichere HOME-Umgebungsvariable: ${HOME:-not set}"
        return 1
    fi
    
    local datafile="$HOME/.psdata.txt"
    echo "$SCR_PATH" > "$datafile"
    echo "$CACHE_PATH" >> "$datafile"
    # Save Wine version info (PROTON_PATH if Proton GE was used, empty if Wine Standard)
    echo "${PROTON_PATH:-}" >> "$datafile"
    unset datafile
}

function load_paths() {
    local skip_validation="${1:-false}"  # Optional parameter: skip directory validation
    local datafile="$HOME/.psdata.txt"
    
    # Validate datafile exists and is readable
    if [ ! -f "$datafile" ]; then
        if [ "$skip_validation" = "true" ]; then
            if [ -n "${SCR_PATH:-}" ] && [ -n "${CACHE_PATH:-}" ]; then
                return 0
            fi
            SCR_PATH="${SCR_PATH:-}"
            CACHE_PATH="${CACHE_PATH:-}"
            return 0
        fi
        echo "ERROR: Installation data file not found: $datafile"
        if [ "$skip_validation" = "false" ]; then
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        else
            # For uninstaller: set empty paths and continue
            SCR_PATH=""
            CACHE_PATH=""
            return 0
        fi
    fi
    
    if [ ! -r "$datafile" ]; then
        echo "ERROR: Cannot read installation data file: $datafile"
        if [ "$skip_validation" = "false" ]; then
            echo "Please check file permissions"
            exit 1
        else
            # For uninstaller: set empty paths and continue
            SCR_PATH=""
            CACHE_PATH=""
            return 0
        fi
    fi
    
    # Load paths and validate they are not empty
    SCR_PATH=$(head -n 1 "$datafile" 2>/dev/null)
    CACHE_PATH=$(sed -n '2p' "$datafile" 2>/dev/null)
    # Load Wine version info (line 3, optional - may not exist in old installations)
    # If line 3 exists and is not empty, it contains PROTON_PATH (or empty for Wine Standard)
    WINE_VERSION_INFO=$(sed -n '3p' "$datafile" 2>/dev/null || echo "")
    
    if [ -z "$SCR_PATH" ]; then
        echo "ERROR: Installation path (SCR_PATH) is empty or corrupted in $datafile"
        if [ "$skip_validation" = "false" ]; then
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        fi
    fi
    
    if [ -z "$CACHE_PATH" ]; then
        echo "ERROR: Cache path (CACHE_PATH) is empty or corrupted in $datafile"
        if [ "$skip_validation" = "false" ]; then
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        fi
    fi
    
    # CRITICAL: Path security check - prevent privilege escalation
    if ! sharedFuncs::_validate_path "$SCR_PATH"; then
        echo "ERROR: SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
        if [ "$skip_validation" = "false" ]; then
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        fi
    fi
    if ! sharedFuncs::_validate_path "$CACHE_PATH"; then
        echo "ERROR: CACHE_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $CACHE_PATH"
        if [ "$skip_validation" = "false" ]; then
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        fi
    fi
    
    # Check that SCR_PATH is really a directory (not a file)
    if [ "$skip_validation" = "false" ]; then
        if [ ! -d "$SCR_PATH" ]; then
            echo "ERROR: Installation directory does not exist or is not a directory: $SCR_PATH"
            echo "Photoshop may have been moved or deleted"
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        fi
        
        if [ ! -d "$CACHE_PATH" ]; then
            echo "ERROR: Cache directory does not exist: $CACHE_PATH"
            echo "Photoshop cache may have been moved or deleted"
            echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
            exit 1
        fi
    fi
    
    unset datafile
}

# ============================================================================
# @namespace photoshop
# ============================================================================

photoshop::possible_exe_paths() {
    local prefix="${1:-${WINE_PREFIX:-${WINEPREFIX:-}}}"
    local user_name="${USER:-$(id -un)}"
    if [ -z "$prefix" ]; then
        return 0
    fi
    printf '%s\n' \
        "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop 2021/Photoshop.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2021/Photoshop.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop 2022/Photoshop.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2019/Photoshop.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2018/Photoshop.exe" \
        "$prefix/drive_c/users/$user_name/PhotoshopSE/Photoshop.exe" \
        "$prefix/drive_c/Program Files (x86)/Adobe/Adobe Photoshop CC 2021/Photoshop.exe" \
        "$prefix/drive_c/Program Files (x86)/Adobe/Adobe Photoshop CC 2019/Photoshop.exe"
}

photoshop::find_exe() {
    local prefix="${1:-${WINE_PREFIX:-${WINEPREFIX:-}}}"
    local path=""
    while IFS= read -r path; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done < <(photoshop::possible_exe_paths "$prefix")
    return 1
}

# Generic Adobe offline installer folder (Set-up.exe + packages/).
# Extra drop dirs: space-separated relative to project_root (e.g. "photoshop premiere").
# Ordner mit Set-up.exe — Root oder eine Ebene darunter (z. B. ISO: Adobe 2024/).
adobe::find_setup_dir() {
    local root="${1:-}" sub=""
    [ -n "$root" ] && [ -d "$root" ] || return 1
    root="$(cd "$root" && pwd)" || return 1
    if [ -f "$root/Set-up.exe" ]; then
        echo "$root"
        return 0
    fi
    shopt -s nullglob 2>/dev/null || true
    for sub in "$root"/*/Set-up.exe; do
        [ -f "$sub" ] || continue
        echo "$(cd "$(dirname "$sub")" && pwd)"
        shopt -u nullglob 2>/dev/null || true
        return 0
    done
    shopt -u nullglob 2>/dev/null || true
    return 1
}

# Adobe Offline-ISO → Staging entpacken (7z/bsdtar), Set-up-Ordner zurückgeben.
adobe::extract_iso_setup_dir() {
    local iso="${1:-}" staging="${2:-}"
    local dest setup_dir=""
    [ -n "$iso" ] && [ -f "$iso" ] || return 1
    case "${iso,,}" in
        *.iso) ;;
        *) return 1 ;;
    esac
    if [ -z "$staging" ]; then
        staging="${CACHE_PATH:-${DATA_ROOT:-${TMPDIR:-/tmp}}/adobe-iso-$$}/extract"
    fi
    dest="$staging"
    rm -rf "$dest" 2>/dev/null || true
    mkdir -p "$dest" || return 1
    if type recipe_source::extract_archive >/dev/null 2>&1; then
        recipe_source::extract_archive "$iso" "$dest" || return 1
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$iso" -C "$dest" || return 1
    elif command -v 7z >/dev/null 2>&1; then
        7z x -y -o"$dest" "$iso" >/dev/null || return 1
    else
        return 1
    fi
    setup_dir="$(adobe::find_setup_dir "$dest")" || return 1
    echo "$setup_dir"
}

adobe::resolve_installer_dir() {
    local project_root="${1:-${PROJECT_ROOT:-}}"
    local drop_dirs="${2:-photoshop premiere}"
    local candidate="" parent="" d env_dir iso_path="" setup_dir=""

    # GUI / prepare_source: gewählter Ordner oder Installer-Datei
    if setup_dir="$(adobe::find_setup_dir "${RECIPE_WORK_ROOT:-}")"; then
        echo "$setup_dir"
        return 0
    fi
    if setup_dir="$(adobe::find_setup_dir "${RECIPE_SOURCE_ROOT:-}")"; then
        echo "$setup_dir"
        return 0
    fi
    if [ -n "${RECIPE_SOURCE_ROOT:-}" ] && [ -d "${RECIPE_SOURCE_ROOT}" ]; then
        shopt -s nullglob 2>/dev/null || true
        for iso_path in "${RECIPE_SOURCE_ROOT}"/*.iso "${RECIPE_SOURCE_ROOT}"/*/*.iso; do
            [ -f "$iso_path" ] || continue
            if setup_dir="$(adobe::extract_iso_setup_dir "$iso_path")"; then
                echo "$setup_dir"
                shopt -u nullglob 2>/dev/null || true
                return 0
            fi
        done
        shopt -u nullglob 2>/dev/null || true
    fi
    if [ -n "${RECIPE_INSTALLER_PATH:-}" ] && [ -f "${RECIPE_INSTALLER_PATH}" ]; then
        case "${RECIPE_INSTALLER_PATH,,}" in
            *.iso)
                if setup_dir="$(adobe::extract_iso_setup_dir "${RECIPE_INSTALLER_PATH}")"; then
                    echo "$setup_dir"
                    return 0
                fi
                ;;
            *)
                parent="$(cd "$(dirname "${RECIPE_INSTALLER_PATH}")" && pwd)"
                if setup_dir="$(adobe::find_setup_dir "$parent")"; then
                    echo "$setup_dir"
                    return 0
                fi
                ;;
        esac
    fi
    if [ -n "${RECIPE_ARCHIVE_PATH:-}" ] && [ -f "${RECIPE_ARCHIVE_PATH}" ]; then
        case "${RECIPE_ARCHIVE_PATH,,}" in
            *.iso)
                if setup_dir="$(adobe::extract_iso_setup_dir "${RECIPE_ARCHIVE_PATH}")"; then
                    echo "$setup_dir"
                    return 0
                fi
                ;;
        esac
    fi

    for env_dir in \
        "${PHOTOSHOP_INSTALLER_DIR:-}" \
        "${PREMIERE_INSTALLER_DIR:-}" \
        "${ADOBE_INSTALLER_DIR_HOST:-}"; do
        [ -n "$env_dir" ] || continue
        if [ -f "$env_dir" ]; then
            case "${env_dir,,}" in
                *.iso)
                    if setup_dir="$(adobe::extract_iso_setup_dir "$env_dir")"; then
                        echo "$setup_dir"
                        return 0
                    fi
                    ;;
            esac
            continue
        fi
        if setup_dir="$(adobe::find_setup_dir "$env_dir")"; then
            echo "$setup_dir"
            return 0
        fi
    done

    for d in $drop_dirs; do
        candidate="$project_root/$d"
        if setup_dir="$(adobe::find_setup_dir "$candidate")"; then
            echo "$setup_dir"
            return 0
        fi
        # Drop-Dir: lose .iso im Ordner
        shopt -s nullglob 2>/dev/null || true
        for iso_path in "$candidate"/*.iso; do
            [ -f "$iso_path" ] || continue
            if setup_dir="$(adobe::extract_iso_setup_dir "$iso_path")"; then
                echo "$setup_dir"
                shopt -u nullglob 2>/dev/null || true
                return 0
            fi
        done
        shopt -u nullglob 2>/dev/null || true
    done

    return 1
}

photoshop::resolve_installer_dir() {
    adobe::resolve_installer_dir "${1:-${PROJECT_ROOT:-}}" "photoshop"
}

premiere::possible_exe_paths() {
    local prefix="${1:-${WINE_PREFIX:-${WINEPREFIX:-}}}"
    if [ -z "$prefix" ]; then
        return 0
    fi
    printf '%s\n' \
        "$prefix/drive_c/Program Files/Adobe/Adobe Premiere Pro 2024/Adobe Premiere Pro.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Premiere Pro 2025/Adobe Premiere Pro.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Premiere Pro 2023/Adobe Premiere Pro.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Premiere Pro 2022/Adobe Premiere Pro.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Premiere Pro 2021/Adobe Premiere Pro.exe" \
        "$prefix/drive_c/Program Files/Adobe/Adobe Premiere Pro CC 2021/Adobe Premiere Pro.exe"
}

premiere::find_exe() {
    local prefix="${1:-${WINE_PREFIX:-${WINEPREFIX:-}}}"
    local path=""
    while IFS= read -r path; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done < <(premiere::possible_exe_paths "$prefix")
    return 1
}

premiere::resolve_installer_dir() {
    adobe::resolve_installer_dir "${1:-${PROJECT_ROOT:-}}" "premiere"
}

# ============================================================================
# @namespace winetricks_helper
# ============================================================================

winetricks_helper::check_network() {
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    if getent hosts download.microsoft.com >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

winetricks_helper::run_critical() {
    local package="$1"
    shift
    local log_file="${LOG_FILE:-/dev/null}"
    local wt_cmd="winetricks"

    if type wine_runtime::winetricks >/dev/null 2>&1; then
        wt_cmd="wine_runtime::winetricks"
    elif ! command -v winetricks >/dev/null 2>&1; then
        log_error "winetricks not found (critical package: $package)"
        return 127
    fi

    if ! winetricks_helper::check_network; then
        if [ ! -d "${HOME}/.cache/winetricks/$package" ] && \
           [ ! -d "${WINETRICKS_CACHE:-}/$package" ]; then
            log_error "Offline and winetricks cache missing for: $package"
            return 2
        fi
    fi

    if $wt_cmd -q "$package" "$@" >> "$log_file" 2>&1; then
        return 0
    fi
    log_error "winetricks failed for critical package: $package"
    return 1
}


