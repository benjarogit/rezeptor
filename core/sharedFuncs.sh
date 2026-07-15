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

# DEBUG MODE: Debug log function for runtime tracking
# Use LOG_DIR from environment if available (set by PhotoshopSetup.sh), otherwise fallback
# Get PROJECT_ROOT from environment or derive from SCRIPT_DIR
PROJECT_ROOT="${PROJECT_ROOT:-}"
if [ -z "$PROJECT_ROOT" ] && [ -n "${SCRIPT_DIR:-}" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd 2>/dev/null || echo "")"
fi
# Use LOG_DIR if set (from PhotoshopSetup.sh), otherwise use PROJECT_ROOT/logs
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT:-}/logs}"
TIMESTAMP="${TIMESTAMP:-$(date +%d.%m.%y\ %H:%M\ Uhr)}"
# Do not overwrite DEBUG_LOG when install.sh already set structured paths
if [ -z "${DEBUG_LOG:-}" ]; then
    DEBUG_LOG="${LOG_DIR}/debug.log"
fi
debug_log() {
    local location="$1"
    local message="$2"
    local data="$3"
    local hypothesis_id="${4:-}"
    local timestamp=$(date +%s%3N 2>/dev/null || date +%s000)
    local session_id="debug-session-$(date +%s)"
    local run_id="${RUN_ID:-run1}"
    echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"${session_id}\",\"runId\":\"${run_id}\",\"hypothesisId\":\"${hypothesis_id}\"}" >> "$DEBUG_LOG" 2>/dev/null || true
}

# Fallback log_debug function (if not defined by PhotoshopSetup.sh)
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

# ANSI Color codes (same as setup.sh and PhotoshopSetup.sh)
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

# Get main log file if available (from PhotoshopSetup.sh)
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
    
    # Also log to new LOG_FILE if available (from PhotoshopSetup.sh)
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
        # Also log to new LOG_FILE if available (from PhotoshopSetup.sh)
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

function launcher() {

    local project_root="${PROJECT_ROOT:-}"
    if [ -z "$project_root" ] && [ -n "${SCRIPT_DIR:-}" ]; then
        project_root="$(cd "$SCRIPT_DIR/.." && pwd 2>/dev/null || true)"
    fi
    if [ -z "$project_root" ]; then
        error "PROJECT_ROOT nicht gesetzt - kann Launcher nicht deployen"
        return 1
    fi

    local core_dir="$project_root/core"
    local recipe_launcher="$project_root/recipes/photoshop/launch.sh"
    local desktop_entry="$project_root/scripts/photoshop.desktop"
    local launcher_dest="$SCR_PATH/launcher"

    rmdir_if_exist "$launcher_dest"
    mkdir -p "$launcher_dest" || error "can't create launcher directory"

    if [ ! -f "$recipe_launcher" ]; then
        error "recipes/photoshop/launch.sh Not Found: $recipe_launcher"
        return 1
    fi

    cp "$recipe_launcher" "$launcher_dest/launcher.sh" || error "can't copy launcher"

    for _f in sharedFuncs.sh wine-runtime.sh paths.sh env-file.sh recipe-win10.sh recipe-guard.sh; do
        if [ -f "$core_dir/$_f" ]; then
            cp "$core_dir/$_f" "$launcher_dest/" || error "can't copy $_f"
        fi
    done

    if [ -f "$project_root/core/runtime.lock" ]; then
        cp "$project_root/core/runtime.lock" "$launcher_dest/" || true
    fi

    # shellcheck source=/dev/null
    source "$core_dir/env-file.sh"
    env_file_write "$launcher_dest/install.env" \
        DATA_ROOT "$SCR_PATH" \
        SCR_PATH "$SCR_PATH" \
        WINE_PREFIX "$SCR_PATH/prefix" \
        PROJECT_ROOT "$project_root"

    chmod +x "$launcher_dest/launcher.sh" || error "can't chmod launcher script"

    # Legacy block removed — paths resolved above
    local launcher_path="$launcher_dest/launcher.sh"
    local desktop_entry_dest="$HOME/.local/share/applications/photoshop.desktop"

    if [ -f "$desktop_entry" ]; then
        # Silent - don't show "detected" message to user (irrelevant info)
        # Backup existing desktop entry before overwriting
        if [ -f "$desktop_entry_dest" ]; then
            local backup_file="${desktop_entry_dest}.bak.$(date +%Y%m%d_%H%M%S)"
            cp "$desktop_entry_dest" "$backup_file" 2>/dev/null || {
                if type log_warning >/dev/null 2>&1; then
                    log_warning "Could not backup existing desktop entry (non-critical)"
                fi
            }
            show_message "${C_YELLOW}→${C_RESET} ${C_GRAY}desktop entry${C_RESET} exist deleted..."
            rm "$desktop_entry_dest"
        fi
        cp "$desktop_entry" "$desktop_entry_dest" || error "can't copy desktop entry"
        
        # Replace pspath placeholder in desktop entry
        # CRITICAL: sed -i GNU/BusyBox compatibility
        # CRITICAL: Use absolute path and remove "bash" (script is executable)
        local launcher_script_path="$SCR_PATH/launcher/launcher.sh"
        if sed -i '' "s|bash pspath/launcher/launcher.sh|$launcher_script_path|g" "$desktop_entry_dest" 2>/dev/null; then
            : # GNU sed (kein Backup)
        elif sed -i.bak "s|bash pspath/launcher/launcher.sh|$launcher_script_path|g" "$desktop_entry_dest" 2>/dev/null; then
            rm -f "${desktop_entry_dest}.bak" 2>/dev/null || true
        else
            # KRITISCH: mktemp statt vorhersagbarem .tmp (Symlink-Angriff verhindern)
            local tmp_file
            tmp_file=$(mktemp "${desktop_entry_dest}.XXXXXX" 2>/dev/null) || {
                error "mktemp failed for desktop entry"
                return 1
            }
            # KRITISCH: TOCTOU-Schutz - prüfe dass tmp_file keine Symlink ist
            if [ -L "$tmp_file" ]; then
                rm -f "$tmp_file"
                error "Temporäre Datei ist Symlink (Sicherheitsrisiko)"
                return 1
            fi
            # KRITISCH: Cleanup bei allen Signalen (nicht nur EXIT) - verhindere Race-Conditions
            # Use function instead of string for trap (safer)
            # shellcheck disable=SC2064
            trap 'rm -f "$tmp_file" 2>/dev/null || true' EXIT INT TERM HUP
            # KRITISCH: Escaping für sed
            local escaped_path
            escaped_path=$(printf '%s\n' "$SCR_PATH" | sed 's/[[\.*^$()+?{|]/\\&/g; s|/|\\/|g')
            sed "s|bash pspath/launcher/launcher.sh|$launcher_script_path|g" "$desktop_entry_dest" > "$tmp_file" || {
                rm -f "$tmp_file"
                error "can't edit desktop entry"
                return 1
            }
            # CRITICAL: install instead of mv (atomic)
            install -m "$(stat -c '%a' "$desktop_entry_dest" 2>/dev/null || echo 644)" "$tmp_file" "$desktop_entry_dest" 2>/dev/null || {
                if [ -f "$tmp_file" ] && [ ! -L "$tmp_file" ]; then
                    mv "$tmp_file" "$desktop_entry_dest" || {
                        rm -f "$tmp_file"
                        error "can't edit desktop entry"
                        return 1
                    }
                else
                    rm -f "$tmp_file"
                    error "can't edit desktop entry"
                    return 1
                fi
            }
            rm -f "$tmp_file" 2>/dev/null || true
        fi
        
        # Mache Desktop-Entry ausführbar
        chmod +x "$desktop_entry_dest" || warning "can't make desktop entry executable"
        
        # BEST PRACTICE: Correct Wine-generated desktop entries instead of deleting them
        # Wine creates desktop entries that we can fix by updating Exec and Icon paths
        # This is cleaner than deleting and recreating - follows Wine community best practices
        # #region agent log
        debug_log "sharedFuncs.sh:396" "Before correcting Wine desktop entries" "{}" "H4"
        # #endregion
        
        # Function to correct a Wine desktop entry
        correct_wine_desktop_entry() {
            local entry="$1"
            if [ ! -f "$entry" ]; then
                return 1
            fi
            
            # Check if it's a Wine-generated entry that needs correction
            # Fix grep warnings: Use separate grep calls or fix escaping
            if grep -q "WINEPREFIX=" "$entry" 2>/dev/null || grep -q "wine.*Photoshop.exe" "$entry" 2>/dev/null || grep -q "'C:\\\\" "$entry" 2>/dev/null || grep -q "Exec=env.*wine" "$entry" 2>/dev/null; then
                # #region agent log
                debug_log "sharedFuncs.sh:407" "Correcting Wine desktop entry" "{\"entry\":\"${entry}\"}" "H4"
                # #endregion
                
                # Backup original
                cp "$entry" "${entry}.bak" 2>/dev/null || true
                
                # Update Exec to use our launcher script
                local launcher_script_path="$SCR_PATH/launcher/launcher.sh"
                if grep -q "^Exec=" "$entry" 2>/dev/null; then
                    # Replace Exec line with our launcher
                    sed -i "s|^Exec=.*|Exec=${launcher_script_path} %F|g" "$entry" 2>/dev/null || true
                fi
                
                # Update Icon if we have one
                local launch_icon="$SCR_PATH/launcher/AdobePhotoshop-icon.png"
                if [ -f "$launch_icon" ] && grep -q "^Icon=" "$entry" 2>/dev/null; then
                    sed -i "s|^Icon=.*|Icon=${launch_icon}|g" "$entry" 2>/dev/null || true
                fi
                
                # Update Name to "Photoshop" (standardized)
                if grep -q "^Name=" "$entry" 2>/dev/null; then
                    sed -i "s|^Name=.*|Name=Photoshop|g" "$entry" 2>/dev/null || true
                fi
                
                # Remove backup
                rm -f "${entry}.bak" 2>/dev/null || true
                
                log_debug "Corrected Wine desktop entry: $entry"
                return 0
            fi
            return 1
        }
        
        # Correct Wine desktop entries in wine/Programs/ directory
        local wine_apps_dir="$HOME/.local/share/applications/wine"
        if [ -d "$wine_apps_dir" ]; then
            find "$wine_apps_dir" -type f \( -name "*Photoshop*" -o -name "*photoshop*" -o -name "*Adobe*" \) 2>/dev/null | while IFS= read -r entry; do
                correct_wine_desktop_entry "$entry" || true
            done
        fi
        
        # Correct Wine desktop entries in main applications directory
        local wine_desktop_entries=(
            "$HOME/.local/share/applications/Adobe Photoshop CC 2019.desktop"
            "$HOME/.local/share/applications/Adobe Photoshop.desktop"
            "$HOME/.local/share/applications/photoshopCC.desktop"
            "$HOME/.local/share/applications/Adobe Photoshop 2021.desktop"
            "$HOME/.local/share/applications/Adobe Photoshop 2022.desktop"
        )
        for entry in "${wine_desktop_entries[@]}"; do
            correct_wine_desktop_entry "$entry" || true
        done
        
        # Update desktop database to refresh menu
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        fi
    else
        error "desktop entry Not Found"
    fi

    # Create desktop shortcut (copy to Desktop directory)
    local desktop_dir=""
    if [ -n "${XDG_DESKTOP_DIR:-}" ] && [ -d "$XDG_DESKTOP_DIR" ]; then
        desktop_dir="$XDG_DESKTOP_DIR"
    elif command -v xdg-user-dir >/dev/null 2>&1; then
        desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null || echo "")
    fi
    # Fallback: Common desktop directory names
    if [ -z "$desktop_dir" ] || [ ! -d "$desktop_dir" ]; then
        for dir in "$HOME/Desktop" "$HOME/Schreibtisch" "$HOME/desktop" "$HOME/schreibtisch"; do
            if [ -d "$dir" ]; then
                desktop_dir="$dir"
                break
            fi
        done
    fi
    
    # BEST PRACTICE: Correct Wine-generated desktop entries on Desktop instead of deleting
    # .lnk files are Windows shortcuts that can't be used - remove them
    # Desktop entries can be corrected to use our launcher
    if [ -n "$desktop_dir" ] && [ -d "$desktop_dir" ]; then
        # #region agent log
        debug_log "sharedFuncs.sh:467" "Before cleaning/correcting desktop directory" "{\"desktop_dir\":\"${desktop_dir}\"}" "H4"
        # #endregion
        
        # Remove .lnk files (Windows shortcuts - can't be used on Linux, must be removed)
        # These are created by Wine when Windows programs create desktop shortcuts
        local lnk_files=$(find "$desktop_dir" -maxdepth 1 -type f \( -name "*.lnk" -o -name "*Photoshop*.lnk" -o -name "*Adobe*.lnk" \) 2>/dev/null | wc -l)
        # #region agent log
        debug_log "sharedFuncs.sh:473" "Found .lnk files on desktop" "{\"lnk_count\":${lnk_files}}" "H4"
        # #endregion
        find "$desktop_dir" -maxdepth 1 -type f \( -name "*.lnk" -o -name "*Photoshop*.lnk" -o -name "*Adobe*.lnk" \) 2>/dev/null | while IFS= read -r lnk_file; do
            if [ -f "$lnk_file" ]; then
                # #region agent log
                debug_log "sharedFuncs.sh:477" "Removing .lnk file (Windows shortcut, unusable on Linux)" "{\"lnk_file\":\"${lnk_file}\"}" "H4"
                # #endregion
                rm -f "$lnk_file" 2>/dev/null || true
            fi
        done
        
        # BEST PRACTICE: Correct Wine-generated desktop entries instead of deleting
        # If there's already a Wine entry, we correct it to use our launcher
        find "$desktop_dir" -maxdepth 1 -type f \( -name "*Photoshop*.desktop" -o -name "*Adobe*.desktop" \) ! -name "photoshop.desktop" 2>/dev/null | while IFS= read -r entry; do
            if [ -f "$entry" ]; then
                # Check if it's a Wine-generated entry that needs correction
                # Fix grep warnings: Use separate grep calls or fix escaping
                if grep -q "WINEPREFIX=" "$entry" 2>/dev/null || grep -q "wine.*Photoshop.exe" "$entry" 2>/dev/null || grep -q "'C:\\\\" "$entry" 2>/dev/null || grep -q "Exec=env.*wine" "$entry" 2>/dev/null; then
                    # #region agent log
                    debug_log "sharedFuncs.sh:488" "Correcting Wine desktop entry on desktop" "{\"entry\":\"${entry}\"}" "H4"
                    # #endregion
                    
                    # Correct the entry to use our launcher
                    local launcher_script_path="$SCR_PATH/launcher/launcher.sh"
                    local launch_icon="$SCR_PATH/launcher/AdobePhotoshop-icon.png"

                    # Backup and correct
                    cp "$entry" "${entry}.bak" 2>/dev/null || true
                    sed -i "s|^Exec=.*|Exec=${launcher_script_path} %F|g" "$entry" 2>/dev/null || true
                    if [ -f "$launch_icon" ]; then
                        sed -i "s|^Icon=.*|Icon=${launch_icon}|g" "$entry" 2>/dev/null || true
                    fi
                    sed -i "s|^Name=.*|Name=Photoshop|g" "$entry" 2>/dev/null || true
                    rm -f "${entry}.bak" 2>/dev/null || true
                    
                    # Rename to photoshop.desktop if it's not already
                    if [ "$(basename "$entry")" != "photoshop.desktop" ]; then
                        mv "$entry" "$desktop_dir/photoshop.desktop" 2>/dev/null || true
                    fi
                    
                    log_debug "Corrected Wine desktop entry on desktop: $entry"
                fi
            fi
        done
        
        # #region agent log
        debug_log "sharedFuncs.sh:465" "After cleaning desktop, before creating shortcut" "{\"desktop_dir\":\"${desktop_dir}\",\"desktop_entry_dest\":\"${desktop_entry_dest}\"}" "H4"
        # #endregion
        
        # Now create the correct desktop shortcut
        cp "$desktop_entry_dest" "$desktop_dir/photoshop.desktop" 2>/dev/null && chmod +x "$desktop_dir/photoshop.desktop" 2>/dev/null || true
        # #region agent log
        debug_log "sharedFuncs.sh:470" "After creating desktop shortcut" "{\"shortcut_exists\":$([ -f "$desktop_dir/photoshop.desktop" ] && echo "true" || echo "false"),\"icon_in_entry\":$(grep -q "Icon=" "$desktop_dir/photoshop.desktop" 2>/dev/null && echo "true" || echo "false")}" "H4"
        # #endregion
        show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}Desktop-Verknüpfung${C_RESET} erstellt"
    fi

    #change photoshop icon of desktop entry
    # CRITICAL: Prefer SVG over PNG (better quality, no scaling issues)
    # Find icon using PROJECT_ROOT or SCRIPT_DIR, prefer SVG
    local entry_icon=""
    local icon_ext=""
    
    # First try to find SVG icon
    if [ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/images/AdobePhotoshop-icon.svg" ]; then
        entry_icon="${PROJECT_ROOT}/images/AdobePhotoshop-icon.svg"
        icon_ext="svg"
    elif [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/../images/AdobePhotoshop-icon.svg" ]; then
        entry_icon="$(cd "${SCRIPT_DIR}/.." && pwd)/images/AdobePhotoshop-icon.svg"
        icon_ext="svg"
    elif [ -f "$(dirname "$(dirname "$SCR_PATH")")/images/AdobePhotoshop-icon.svg" ]; then
        entry_icon="$(cd "$(dirname "$(dirname "$SCR_PATH")")" && pwd)/images/AdobePhotoshop-icon.svg"
        icon_ext="svg"
    # Fallback to PNG if SVG not found
    elif [ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/images/AdobePhotoshop-icon.png" ]; then
        entry_icon="${PROJECT_ROOT}/images/AdobePhotoshop-icon.png"
        icon_ext="png"
    elif [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/../images/AdobePhotoshop-icon.png" ]; then
        entry_icon="$(cd "${SCRIPT_DIR}/.." && pwd)/images/AdobePhotoshop-icon.png"
        icon_ext="png"
    elif [ -f "$(dirname "$(dirname "$SCR_PATH")")/images/AdobePhotoshop-icon.png" ]; then
        entry_icon="$(cd "$(dirname "$(dirname "$SCR_PATH")")" && pwd)/images/AdobePhotoshop-icon.png"
        icon_ext="png"
    fi
    
    local launch_icon="$launcher_dest/AdobePhotoshop-icon.${icon_ext:-png}"

    if [ -n "$entry_icon" ] && [ -f "$entry_icon" ]; then
        cp "$entry_icon" "$launcher_dest" || error "can't copy icon image"
        # CRITICAL: sed -i GNU/BusyBox compatibility + security
        # CRITICAL: Escaping for sed pattern/replacement
        sed_escape() {
            # Escape sed-spezielle Zeichen: / \ & . * ^ $ ( ) + ? { | [ ]
            printf '%s\n' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g; s|/|\\/|g'
        }
        
        safe_sed_replace() {
            local file="$1" pattern="$2" replacement="$3"
            local escaped_pattern escaped_replacement
            
            # KRITISCH: Escape Pattern und Replacement
            escaped_pattern=$(sed_escape "$pattern")
            escaped_replacement=$(sed_escape "$replacement")
            
            # Versuche sed -i (GNU/BusyBox)
            if sed -i '' "s|$escaped_pattern|$escaped_replacement|g" "$file" 2>/dev/null; then
                : # GNU sed (kein Backup)
            elif sed -i.bak "s|$escaped_pattern|$escaped_replacement|g" "$file" 2>/dev/null; then
                rm -f "${file}.bak" 2>/dev/null || true
            else
                # KRITISCH: mktemp statt vorhersagbarem .tmp (Symlink-Angriff verhindern)
                local tmp_file
                tmp_file=$(mktemp "${file}.XXXXXX" 2>/dev/null) || {
                    error "mktemp failed for $file"
                    return 1
                }
                # KRITISCH: TOCTOU-Schutz: Prüfe dass tmp_file keine Symlink ist
                if [ -L "$tmp_file" ]; then
                    rm -f "$tmp_file"
                    error "Temporäre Datei ist Symlink (Sicherheitsrisiko)"
                    return 1
                fi
                # KRITISCH: Cleanup bei allen Signalen (nicht nur EXIT) - verhindere Race-Conditions
                # shellcheck disable=SC2064
                trap 'rm -f "$tmp_file" 2>/dev/null || true' EXIT INT TERM HUP
                sed "s|$escaped_pattern|$escaped_replacement|g" "$file" > "$tmp_file" || {
                    rm -f "$tmp_file"
                    return 1
                }
                # CRITICAL: install instead of mv (atomic on many filesystems)
                install -m "$(stat -c '%a' "$file" 2>/dev/null || echo 644)" "$tmp_file" "$file" 2>/dev/null || {
                    # Fallback to mv with check
                    if [ -f "$tmp_file" ] && [ ! -L "$tmp_file" ]; then
                        mv "$tmp_file" "$file" || {
                            rm -f "$tmp_file"
                            return 1
                        }
                    else
                        rm -f "$tmp_file"
                        return 1
                    fi
                }
                rm -f "$tmp_file" 2>/dev/null || true
            fi
        }
        # Copy icon to system icon directory for better compatibility
        # CRITICAL: If using SVG, only install scalable version (no need for fixed sizes)
        # SVG scales perfectly to any size, so we don't need to generate multiple PNG sizes
        local icon_name="photoshop"
        
        # CRITICAL: Generate PNG icons even if SVG is available
        # KDE and some desktop environments need PNG icons in specific sizes for proper display
        # SVG is installed separately in scalable/apps/ for best quality, but PNG icons are still needed
        local generate_png=true
        if [ "$icon_ext" = "svg" ]; then
            log_debug "Using SVG icon - will also generate PNG icons for compatibility (KDE needs PNG icons)"
        fi
        
        if [ "$generate_png" = true ]; then
            # Generate PNG icons in various sizes (needed for KDE and some desktop environments)
            # CRITICAL: Limit to essential sizes to prevent long delays - only generate most important sizes
            # Full set would be: 16 22 24 32 48 64 128 256 512, but that takes too long
            # Most desktop environments work fine with just: 48 64 128 256
            local icon_sizes=(48 64 128 256)
            
            for size in "${icon_sizes[@]}"; do
            local icon_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
            mkdir -p "$icon_dir" 2>/dev/null || true
            
            # CRITICAL: Try magick first (ImageMagick v7), then convert (v6 or v7)
            local magick_cmd=""
            if command -v magick >/dev/null 2>&1; then
                magick_cmd="magick"
            elif command -v convert >/dev/null 2>&1; then
                magick_cmd="convert"
            fi
            
            if [ -n "$magick_cmd" ]; then
                # Resize icon to specific size (CRITICAL: Use -resize with ! to force exact size)
                # For icons, we want exact size to match desktop environment expectations
                # CRITICAL: Use -background transparent and -extent to ensure exact size
                # Also use -gravity center to center the image
                # CRITICAL: Remove old icon first to ensure clean resize
                # CRITICAL: Use -define png:ignore-crc to handle corrupted PNG files
                rm -f "$icon_dir/${icon_name}.png" 2>/dev/null || true
                
                # Try resize with extent - suppress warnings but keep errors
                # CRITICAL: Use timeout to prevent hanging if ImageMagick has issues
                timeout 5 $magick_cmd "$entry_icon" -define png:ignore-crc -resize ${size}x${size}! -background transparent -gravity center -extent ${size}x${size} -quality 95 "$icon_dir/${icon_name}.png" 2>&1 | grep -v "warning\|deprecated\|WARNING" || true
                
                # Verify icon was resized correctly - CRITICAL: Check actual dimensions
                local actual_size=$(identify "$icon_dir/${icon_name}.png" 2>/dev/null | awk '{print $3}' | cut -dx -f1,2 || echo "")
                if [ -z "$actual_size" ]; then
                    # Fallback: try file command
                    actual_size=$(file "$icon_dir/${icon_name}.png" 2>/dev/null | grep -o "[0-9]* x [0-9]*" | head -1 | tr ' ' 'x' || echo "")
                fi
                
                # Normalize actual_size format
                actual_size=$(echo "$actual_size" | tr ' ' 'x' | tr -d ' ')
                
                if [ -z "$actual_size" ] || [ "$actual_size" != "${size}x${size}" ]; then
                    # Icon was not resized correctly, try again with different method
                    log_debug "Icon resize failed for ${size}x${size} (got '$actual_size'), retrying with -thumbnail..."
                    rm -f "$icon_dir/${icon_name}.png" 2>/dev/null || true
                    timeout 5 $magick_cmd "$entry_icon" -define png:ignore-crc -thumbnail ${size}x${size}! -background transparent -gravity center -extent ${size}x${size} -quality 95 "$icon_dir/${icon_name}.png" 2>&1 | grep -v "warning\|deprecated\|WARNING" || true
                    
                    # Verify again
                    actual_size=""
                    if command -v identify >/dev/null 2>&1; then
                        actual_size=$(identify "$icon_dir/${icon_name}.png" 2>/dev/null | awk '{print $3}' || echo "")
                    fi
                    if [ -z "$actual_size" ]; then
                        actual_size=$(file "$icon_dir/${icon_name}.png" 2>/dev/null | grep -o "[0-9]* x [0-9]*" | head -1 | tr ' ' 'x' || echo "")
                    fi
                    actual_size=$(echo "$actual_size" | tr ' ' 'x' | tr -d ' ')
                    
                    if [ -z "$actual_size" ] || [ "$actual_size" != "${size}x${size}" ]; then
                        log_debug "Icon resize still failed for ${size}x${size} (got '$actual_size'), trying -scale..."
                        rm -f "$icon_dir/${icon_name}.png" 2>/dev/null || true
                        timeout 5 $magick_cmd "$entry_icon" -define png:ignore-crc -scale ${size}x${size}! -background transparent -gravity center -extent ${size}x${size} -quality 95 "$icon_dir/${icon_name}.png" 2>&1 | grep -v "warning\|deprecated\|WARNING" || true
                        
                        # Final verification
                        actual_size=""
                        if command -v identify >/dev/null 2>&1; then
                            actual_size=$(identify "$icon_dir/${icon_name}.png" 2>/dev/null | awk '{print $3}' || echo "")
                        fi
                        if [ -z "$actual_size" ]; then
                            actual_size=$(file "$icon_dir/${icon_name}.png" 2>/dev/null | grep -o "[0-9]* x [0-9]*" | head -1 | tr ' ' 'x' || echo "")
                        fi
                        actual_size=$(echo "$actual_size" | tr ' ' 'x' | tr -d ' ')
                        
                        if [ -z "$actual_size" ] || [ "$actual_size" != "${size}x${size}" ]; then
                            log_debug "Icon resize failed for ${size}x${size} after all attempts (got '$actual_size'), using fallback: copy original (desktop environment will scale)"
                            # Last fallback: copy original icon - desktop environment will scale it
                            # This is not ideal but better than no icon
                            rm -f "$icon_dir/${icon_name}.png" 2>/dev/null || true
                            cp "$entry_icon" "$icon_dir/${icon_name}.png" 2>/dev/null || true
                        fi
                    fi
                fi
            else
                # Fallback: copy original icon (will be scaled by desktop environment)
                cp "$entry_icon" "$icon_dir/${icon_name}.png" 2>/dev/null || true
            fi
            
            # Verify icon was created and has correct size
            if [ -f "$icon_dir/${icon_name}.png" ]; then
                log_debug "Icon installed: $icon_dir/${icon_name}.png"
            else
                log_debug "Warning: Failed to install icon at size ${size}x${size}"
            fi
            done
        fi
        
        # CRITICAL: Create scalable directory and install SVG if available
        local scalable_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
        mkdir -p "$scalable_dir" 2>/dev/null || true
        
        # Install scalable SVG if available (preferred over PNG)
        local svg_icon=""
        if [ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/images/AdobePhotoshop-icon.svg" ]; then
            svg_icon="${PROJECT_ROOT}/images/AdobePhotoshop-icon.svg"
        elif [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/../images/AdobePhotoshop-icon.svg" ]; then
            svg_icon="$(cd "${SCRIPT_DIR}/.." && pwd)/images/AdobePhotoshop-icon.svg"
        fi
        
        if [ -n "$svg_icon" ] && [ -f "$svg_icon" ]; then
            cp "$svg_icon" "$scalable_dir/${icon_name}.svg" 2>/dev/null || true
            log_debug "SVG icon installed: $scalable_dir/${icon_name}.svg"
        else
            log_debug "SVG icon not found, using PNG fallback"
        fi
        
        # Update icon cache (CRITICAL: Force update to ensure icons are visible)
        local hicolor_dir="$HOME/.local/share/icons/hicolor"
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            # Create index.theme if it doesn't exist (required for icon cache)
            if [ ! -f "$hicolor_dir/index.theme" ]; then
                mkdir -p "$hicolor_dir" 2>/dev/null || true
                # Create index.theme according to freedesktop.org Icon Theme Specification
                # https://specifications.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html
                cat > "$hicolor_dir/index.theme" << 'EOF'
[Icon Theme]
Name=hicolor
Comment=Default fallback theme (freedesktop.org standard)
Directories=16x16/apps,22x22/apps,24x24/apps,32x32/apps,48x48/apps,64x64/apps,128x128/apps,256x256/apps,512x512/apps,scalable/apps

[16x16/apps]
Size=16
Type=Fixed
Context=Applications

[22x22/apps]
Size=22
Type=Fixed
Context=Applications

[24x24/apps]
Size=24
Type=Fixed
Context=Applications

[32x32/apps]
Size=32
Type=Fixed
Context=Applications

[48x48/apps]
Size=48
Type=Fixed
Context=Applications

[64x64/apps]
Size=64
Type=Fixed
Context=Applications

[128x128/apps]
Size=128
Type=Fixed
Context=Applications

[256x256/apps]
Size=256
Type=Fixed
Context=Applications

[512x512/apps]
Size=512
Type=Fixed
Context=Applications

[scalable/apps]
Size=48
Type=Scalable
MinSize=16
MaxSize=512
Context=Applications
EOF
            fi
            # Force update icon cache (CRITICAL: Remove old cache first, then update)
            # Remove old cache to force regeneration
            rm -f "$hicolor_dir/icon-theme.cache" 2>/dev/null || true
            
            # #region agent log
            # #endregion
            
            # Check icon files before cache update
            local icon_count=0
            for size in 16 22 24 32 48 64 128 256 512; do
                if [ -f "$hicolor_dir/${size}x${size}/apps/${icon_name}.png" ]; then
                    local icon_size=$(stat -c%s "$hicolor_dir/${size}x${size}/apps/${icon_name}.png" 2>/dev/null || echo "0")
                    local icon_dimensions=$(file "$hicolor_dir/${size}x${size}/apps/${icon_name}.png" 2>/dev/null | grep -o "[0-9]* x [0-9]*" || echo "unknown")
                    # #region agent log
                    # #endregion
                    icon_count=$((icon_count + 1))
                fi
            done
            
            # #region agent log
            # #endregion
            
            # CRITICAL: Fix icon cache issues - validate icon files first
            # Check for corrupted or invalid icon files that might cause cache to be invalid
            local invalid_icons=0
            for size in 16 22 24 32 48 64 128 256 512; do
                local icon_file="$hicolor_dir/${size}x${size}/apps/${icon_name}.png"
                if [ -f "$icon_file" ]; then
                    # Check if file is valid PNG and has correct dimensions
                    if ! file "$icon_file" 2>/dev/null | grep -q "PNG image"; then
                        log_debug "Removing invalid icon file: $icon_file"
                        rm -f "$icon_file" 2>/dev/null || true
                        invalid_icons=$((invalid_icons + 1))
                    else
                        # Verify dimensions match expected size
                        local actual_dim=$(identify "$icon_file" 2>/dev/null | awk '{print $3}' | cut -dx -f1 || echo "")
                        if [ -n "$actual_dim" ] && [ "$actual_dim" != "$size" ]; then
                            log_debug "Icon has wrong size (expected ${size}x${size}, got ${actual_dim}x${actual_dim}): $icon_file"
                            # Don't remove, but log it - might still work
                        fi
                    fi
                fi
            done
            
            # Update icon cache (capture errors for debugging)
            # CRITICAL: Even if cache is marked as "invalid", it may still work
            # Some desktop environments can use icons without a valid cache
            # CRITICAL: Use timeout to prevent hanging
            local cache_output
            cache_output=$(timeout 15 gtk-update-icon-cache -f -t "$hicolor_dir" 2>&1)
            local cache_exit=$?
            
            # #region agent log
            # #endregion
            
            # Check if cache was created (even if marked as invalid)
            if [ -f "$hicolor_dir/icon-theme.cache" ]; then
                local cache_size=$(stat -c%s "$hicolor_dir/icon-theme.cache" 2>/dev/null || echo "0")
                # #region agent log
                # #endregion
                if [ $cache_exit -eq 0 ]; then
                    log_debug "Icon cache updated successfully: $hicolor_dir"
                else
                    # Cache was created but marked as invalid - try to fix by removing and regenerating
                    log_debug "Icon cache marked as invalid, attempting to fix: $cache_output"
                    rm -f "$hicolor_dir/icon-theme.cache" 2>/dev/null || true
                    # Try again without -t flag (sometimes helps) - with timeout
                    timeout 15 gtk-update-icon-cache -f "$hicolor_dir" 2>&1 | grep -v "invalid" || true
                fi
            else
                # #region agent log
                # #endregion
                log_debug "Warning: Icon cache file not created (icons will use icon name lookup): $cache_output"
                # Try alternative method (without -t flag) - with timeout
                timeout 15 gtk-update-icon-cache -f "$hicolor_dir" 2>&1 | grep -v "invalid" || true
            fi
        fi
        # CRITICAL: Update icon cache and desktop database using system detection
        # This ensures correct handling for different desktop environments (KDE, GNOME, XFCE, etc.)
        if type system::update_icon_cache >/dev/null 2>&1; then
            system::update_icon_cache
            log_debug "Icon cache updated (desktop: $(system::detect_desktop))"
        else
            # Fallback: Try both methods if system module not available
            local hicolor_dir="$HOME/.local/share/icons/hicolor"
            if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$hicolor_dir" ]; then
                timeout 15 gtk-update-icon-cache -f -t "$hicolor_dir" 2>/dev/null || true
            fi
            if command -v kbuildsycoca4 >/dev/null 2>&1; then
                # Run with timeout to prevent hanging (KDE icon cache can hang)
                timeout 10 kbuildsycoca4 --noincremental 2>/dev/null || true
            fi
        fi
        
        # CRITICAL: Update desktop database BEFORE setting icon (ensures desktop entries are recognized)
        # This must happen before we modify the desktop entry
        if type system::update_desktop_database >/dev/null 2>&1; then
            system::update_desktop_database
            log_debug "Desktop database updated (desktop: $(system::detect_desktop))"
        elif command -v update-desktop-database >/dev/null 2>&1; then
            # Run with timeout to prevent hanging
            timeout 10 update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
            log_debug "Desktop database updated"
        fi
        
        # CRITICAL: Set icon in desktop entry
        # Try icon name first (preferred for theme integration), fallback to absolute path if needed
        # Desktop environments work better with icon names that are registered in the icon theme system
        # However, absolute paths are also supported and can be more reliable if icon cache fails
        # The template already has Icon=photoshop, but we need to ensure it's set correctly
        # #region agent log
        debug_log "sharedFuncs.sh:585" "Before setting icon in desktop entry" "{\"icon_name\":\"${icon_name}\",\"icon_exists\":$([ -f "$HOME/.local/share/icons/hicolor/48x48/apps/${icon_name}.png" ] && echo "true" || echo "false"),\"svg_exists\":$([ -f "$HOME/.local/share/icons/hicolor/scalable/apps/${icon_name}.svg" ] && echo "true" || echo "false"),\"desktop_entry_dest\":\"${desktop_entry_dest}\"}" "H4"
        # #endregion
        
        # CRITICAL: Use icon NAME, not absolute path (KDE and most DEs prefer icon names)
        # According to freedesktop.org Desktop Entry Specification, Icon field can be:
        # 1. Icon name (without extension) - preferred for theme integration
        # 2. Absolute path - fallback if icon name doesn't work
        # KDE Plasma specifically works better with icon names that are registered in the icon theme
        local icon_value="$icon_name"
        local hicolor_dir="$HOME/.local/share/icons/hicolor"
        
        # Verify icon exists in theme (SVG or PNG)
        local icon_exists=false
        if [ -f "$hicolor_dir/scalable/apps/${icon_name}.svg" ]; then
            icon_exists=true
            log_debug "SVG icon available in theme: scalable/apps/${icon_name}.svg"
        elif [ -f "$hicolor_dir/48x48/apps/${icon_name}.png" ]; then
            icon_exists=true
            log_debug "PNG icon available in theme: 48x48/apps/${icon_name}.png"
        fi
        
        # Use icon name (preferred) - desktop environment will resolve it from theme
        # Only use absolute path as last resort if icon doesn't exist in theme
        if [ "$icon_exists" = false ]; then
            # Last resort: use absolute path if icon not in theme
            if [ -f "$hicolor_dir/scalable/apps/${icon_name}.svg" ]; then
                icon_value="$hicolor_dir/scalable/apps/${icon_name}.svg"
                log_debug "Using absolute SVG path (icon not in theme): $icon_value"
            elif [ -f "$hicolor_dir/48x48/apps/${icon_name}.png" ]; then
                icon_value="$hicolor_dir/48x48/apps/${icon_name}.png"
                log_debug "Using absolute PNG path (icon not in theme): $icon_value"
            else
                log_debug "Using icon name (theme lookup): $icon_name"
            fi
        else
            log_debug "Using icon name for theme integration: $icon_name"
        fi
        
        # CRITICAL: Ensure Icon field is set correctly (replace photoshopicon placeholder or set if missing)
        if grep -q "^Icon=photoshopicon" "$desktop_entry_dest" 2>/dev/null; then
            # Replace placeholder
            safe_sed_replace "$desktop_entry_dest" "photoshopicon" "$icon_value" || error "can't edit desktop entry"
        elif ! grep -q "^Icon=" "$desktop_entry_dest" 2>/dev/null; then
            # Add Icon field if missing (shouldn't happen, but be safe)
            if grep -q "^\[Desktop Entry\]" "$desktop_entry_dest" 2>/dev/null; then
                sed -i '/^\[Desktop Entry\]/a Icon='"$icon_value" "$desktop_entry_dest" 2>/dev/null || true
            fi
        else
            # Icon field exists but might be wrong - ensure it's correct
            sed -i "s|^Icon=.*|Icon=$icon_value|g" "$desktop_entry_dest" 2>/dev/null || true
        fi
        if grep -q "^StartupWMClass=" "$desktop_entry_dest" 2>/dev/null; then
            sed -i 's|^StartupWMClass=.*|StartupWMClass=Photoshop.exe|g' "$desktop_entry_dest" 2>/dev/null || true
        else
            sed -i '/^StartupNotify=/a StartupWMClass=Photoshop.exe' "$desktop_entry_dest" 2>/dev/null || true
        fi
        # Also update desktop shortcut if it exists (use same icon_value)
        if [ -n "${desktop_dir:-}" ] && [ -f "${desktop_dir}/photoshop.desktop" ]; then
            # #region agent log
            debug_log "sharedFuncs.sh:590" "Updating icon in desktop shortcut" "{\"desktop_shortcut\":\"${desktop_dir}/photoshop.desktop\",\"icon_value\":\"${icon_value}\"}" "H4"
            # #endregion
            # CRITICAL: Update icon in desktop shortcut (same logic as main desktop entry)
            if grep -q "^Icon=photoshopicon" "${desktop_dir}/photoshop.desktop" 2>/dev/null; then
                safe_sed_replace "${desktop_dir}/photoshop.desktop" "photoshopicon" "$icon_value" 2>/dev/null || true
            else
                sed -i "s|^Icon=.*|Icon=$icon_value|g" "${desktop_dir}/photoshop.desktop" 2>/dev/null || true
            fi
            # #region agent log
            debug_log "sharedFuncs.sh:593" "After updating icon in desktop shortcut" "{\"icon_set\":$(grep -q "Icon=${icon_value}" "${desktop_dir}/photoshop.desktop" 2>/dev/null && echo "true" || echo "false")}" "H4"
            # #endregion
        fi
        # Update launcher script with absolute path (for launcher script itself)
        safe_sed_replace "$launcher_dest/launcher.sh" "photoshopicon" "$launch_icon" || error "can't edit launcher script"
        
        # CRITICAL: Final icon cache update AFTER desktop entry is modified
        # Some desktop environments need the cache refreshed after desktop entry changes
        # Use system detection for proper desktop-specific handling
        local hicolor_dir="$HOME/.local/share/icons/hicolor"
        if type system::update_icon_cache >/dev/null 2>&1; then
            system::update_icon_cache
            log_debug "Icon cache refreshed after desktop entry update (desktop: $(system::detect_desktop))"
        elif command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$hicolor_dir" ]; then
            timeout 15 gtk-update-icon-cache -f -t "$hicolor_dir" 2>/dev/null || true
            log_debug "Icon cache refreshed after desktop entry update"
        fi
        
        # CRITICAL: Final desktop database update AFTER icon is set
        # This ensures the desktop environment recognizes the updated icon
        if type system::update_desktop_database >/dev/null 2>&1; then
            system::update_desktop_database
            log_debug "Desktop database refreshed after icon update (desktop: $(system::detect_desktop))"
        elif command -v update-desktop-database >/dev/null 2>&1; then
            timeout 10 update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
            log_debug "Desktop database refreshed after icon update"
        fi
    else
        warning "Icon not found, using default icon"
    fi
    
    # WINAPPS-TECHNIK: MIME-Type Registrierung für "Öffnen mit Photoshop"
    # Erstelle MIME-Type Definition für Photoshop-Dateien
    # KRITISCH: Umgebungsvariablen-Validierung - prüfe dass $HOME sicher ist
    if [ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ]; then
        warning "Unsichere HOME-Umgebungsvariable, überspringe MIME-Type Registrierung"
        return 0
    fi
    local mime_dir="$HOME/.local/share/mime/packages"
    mkdir -p "$mime_dir" 2>/dev/null || true
    
    if [ -d "$mime_dir" ]; then
        local mime_file="$mime_dir/photoshop.xml"
        # Use absolute path for icon (launch_icon is set earlier in the function)
        local icon_path="$launch_icon"
        if [ ! -f "$icon_path" ]; then
            # Fallback: try to find icon in launcher directory
            icon_path="$launcher_dest/AdobePhotoshop-icon.png"
        fi
        
        # Create MIME-Type XML with absolute icon path
        cat > "$mime_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="image/vnd.adobe.photoshop">
    <comment>Adobe Photoshop Document</comment>
    <comment xml:lang="de">Adobe Photoshop Dokument</comment>
    <glob pattern="*.psd"/>
    <glob pattern="*.PSD"/>
    <icon>$icon_path</icon>
  </mime-type>
  <mime-type type="image/x-photoshop">
    <comment>Adobe Photoshop Document</comment>
    <comment xml:lang="de">Adobe Photoshop Dokument</comment>
    <glob pattern="*.psd"/>
    <glob pattern="*.psb"/>
    <glob pattern="*.PSD"/>
    <glob pattern="*.PSB"/>
    <icon>$icon_path</icon>
  </mime-type>
  <mime-type type="application/x-photoshop">
    <comment>Adobe Photoshop Document</comment>
    <comment xml:lang="de">Adobe Photoshop Dokument</comment>
    <glob pattern="*.psd"/>
    <glob pattern="*.psb"/>
    <glob pattern="*.PSD"/>
    <glob pattern="*.PSB"/>
    <icon>$icon_path</icon>
  </mime-type>
</mime-info>
EOF
        # Aktualisiere MIME-Datenbank - with timeouts to prevent hanging
        if command -v update-desktop-database &>/dev/null; then
            timeout 10 update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        fi
        if command -v update-mime-database &>/dev/null; then
            timeout 10 update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
        fi
        show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}MIME-Type Registrierung${C_RESET} erstellt (PSD/PSB Dateien können mit Photoshop geöffnet werden)"
    fi
    
    #create photoshop command
    # CRITICAL: Skip interactive command creation during installation
    # The command creation is optional and can be done later manually
    # During installation, we just create the launcher and desktop entry
    # User can create the command later if needed
    local skip_command_creation="${SKIP_COMMAND_CREATION:-false}"
    
    # If called during installation (from PhotoshopSetup.sh), skip interactive command creation
    # This prevents blocking the installation flow
    if [ "$skip_command_creation" = "true" ]; then
        log_debug "Skipping interactive command creation during installation"
    else
        show_message "${C_YELLOW}→${C_RESET} ${C_CYAN}create photoshop command...${C_RESET}"
        # CRITICAL: Validation BEFORE sudo operation - prevent privilege escalation
        # Use centralized security::validate_path function if available
        if type security::validate_path >/dev/null 2>&1; then
            if ! security::validate_path "$SCR_PATH"; then
                error "SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
                return 1
            fi
        else
            # Fallback to inline validation if security module not loaded
            if [[ "$SCR_PATH" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
                error "SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
                return 1
            fi
        fi
        if [ ! -f "$SCR_PATH/launcher/launcher.sh" ]; then
            error "Launcher-Script nicht gefunden: $SCR_PATH/launcher/launcher.sh"
            return 1
        fi
        
        # Try to create system-wide command (requires sudo)
        # Ask user if they want to create system-wide command or use user-local
        local command_created=0
        local command_path="/usr/local/bin/photoshop"
        local user_bin_dir="$HOME/.local/bin"
        
        # Ask user if they want system-wide installation
        local use_system_wide=false
        # LANG_CODE should be set by PhotoshopSetup.sh, default to "de" if not set
        local lang_code="${LANG_CODE:-de}"
        if [ "$lang_code" = "de" ]; then
            echo ""
            log_prompt "   [J] Ja - System-weit installieren (benötigt sudo)  [N] Nein - Nur benutzer-lokal [J/n]: "
            IFS= read -r -p "   [J] Ja - System-weit installieren (benötigt sudo)  [N] Nein - Nur benutzer-lokal [J/n]: " use_system_response
            log_input "$use_system_response"
        else
            echo ""
            log_prompt "   [Y] Yes - Install system-wide (requires sudo)  [N] No - User-local only [Y/n]: "
            IFS= read -r -p "   [Y] Yes - Install system-wide (requires sudo)  [N] No - User-local only [Y/n]: " use_system_response
            log_input "$use_system_response"
        fi
        
        # Default to system-wide if empty (Enter pressed)
        if [ -z "$use_system_response" ] || [[ "$use_system_response" =~ ^[JjYy]$ ]]; then
            use_system_wide=true
        fi
    
        # Remove existing command if it exists
        if [ -f "$command_path" ] || [ -L "$command_path" ]; then
            show_message "${C_YELLOW}→${C_RESET} ${C_GRAY}photoshop command${C_RESET} existiert, lösche..."
            if [ "$use_system_wide" = true ]; then
                # CRITICAL: Validate path before sudo operation
                if type security::validate_path >/dev/null 2>&1; then
                    if ! security::validate_path "$command_path"; then
                        warning "Unsafe command path: $command_path"
                        return 1
                    fi
                fi
                # CRITICAL: Don't suppress errors - let user see sudo password prompt
                sudo rm -f "$command_path" || {
                    warning "$(i18n::get "could_not_remove_command")"
                }
            fi
        fi
        
        # Try system-wide installation if user chose it
        if [ "$use_system_wide" = true ]; then
            # BEST PRACTICE: Try graphical password prompt first (zenity/systemd-ask-password)
            # Falls nicht verfügbar, verwendet sudo normal (zeigt Passwort-Abfrage)
            local sudo_password=""
            if command -v zenity >/dev/null 2>&1; then
                # Use zenity for graphical password prompt
                sudo_password=$(zenity --password --title="$(i18n::get "password_required")" 2>/dev/null || echo "")
                if [ -n "$sudo_password" ]; then
                    echo "$sudo_password" | sudo -S ln -s "$SCR_PATH/launcher/launcher.sh" "$command_path" 2>/dev/null && command_created=1 || sudo_password=""
                fi
            elif command -v systemd-ask-password >/dev/null 2>&1; then
                # Use systemd-ask-password for systemd-integrated prompt
                sudo_password=$(systemd-ask-password "$(i18n::get "password_required")" 2>/dev/null || echo "")
                if [ -n "$sudo_password" ]; then
                    echo "$sudo_password" | sudo -S ln -s "$SCR_PATH/launcher/launcher.sh" "$command_path" 2>/dev/null && command_created=1 || sudo_password=""
                fi
            fi
            
            # Fallback: Use normal sudo (will prompt for password if needed)
            if [ $command_created -eq 0 ]; then
                # CRITICAL: Don't suppress errors (2>/dev/null) - let user see sudo password prompt
                # sudo will prompt for password if needed
                if sudo ln -s "$SCR_PATH/launcher/launcher.sh" "$command_path"; then
                    command_created=1
                    show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}$(i18n::get "command_created_system" "$command_path")${C_RESET}"
                else
                    warning "$(i18n::get "system_wide_install_failed")"
                    use_system_wide=false  # Fallback to user-local
                fi
            fi
        fi
        
        # Fallback or user-local installation
        if [ $command_created -eq 0 ]; then
            mkdir -p "$user_bin_dir" 2>/dev/null || true
            if [ -d "$user_bin_dir" ]; then
                local user_command_path="$user_bin_dir/photoshop"
                if [ -f "$user_command_path" ] || [ -L "$user_command_path" ]; then
                    rm -f "$user_command_path" 2>/dev/null || true
                fi
                if ln -s "$SCR_PATH/launcher/launcher.sh" "$user_command_path" 2>/dev/null; then
                    command_created=1
                    command_path="$user_command_path"
                    if [ "$lang_code" = "de" ]; then
                        show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}photoshop command${C_RESET} erstellt (benutzer-lokal: $command_path)"
                        show_message "${C_YELLOW}⚠${C_RESET} ${C_GRAY}Hinweis: Füge $user_bin_dir zu deinem PATH hinzu, falls noch nicht geschehen${C_RESET}"
                    else
                        show_message "${C_GREEN}✓${C_RESET} ${C_CYAN}photoshop command${C_RESET} created (user-local: $command_path)"
                        show_message "${C_YELLOW}⚠${C_RESET} ${C_GRAY}Note: Add $user_bin_dir to your PATH if not already done${C_RESET}"
                    fi
                fi
            fi
        fi
        
        if [ $command_created -eq 0 ]; then
            if [ "$lang_code" = "de" ]; then
                warning "Konnte photoshop command nicht erstellen (weder system-weit noch benutzer-lokal). Du kannst Photoshop trotzdem mit dem Desktop-Eintrag oder direkt mit $SCR_PATH/launcher/launcher.sh starten."
            else
                warning "Could not create photoshop command (neither system-wide nor user-local). You can still start Photoshop with the desktop entry or directly with $SCR_PATH/launcher/launcher.sh"
            fi
        fi
    fi
    
    # Silent - don't show launcher creation details to user (irrelevant info)
    # Launcher is created, that's enough - finish_installation() will show completion message
    unset desktop_entry desktop_entry_dest launcher_path launcher_dest
}

function set_dark_mod() {
    # Use WINEPREFIX if WINE_PREFIX is not set (WINEPREFIX is the standard Wine variable)
    local wine_prefix="${WINE_PREFIX:-${WINEPREFIX:-}}"
    if [ -z "$wine_prefix" ]; then
        error "WINE_PREFIX or WINEPREFIX not set"
        return 1
    fi
    echo " " >> "$wine_prefix/user.reg"
    local colorarray=(
        '[Control Panel\\Colors] 1491939580'
        '#time=1d2b2fb5c69191c'
        '"ActiveBorder"="49 54 58"'
        '"ActiveTitle"="49 54 58"'
        '"AppWorkSpace"="60 64 72"'
        '"Background"="49 54 58"'
        '"ButtonAlternativeFace"="200 0 0"'
        '"ButtonDkShadow"="154 154 154"'
        '"ButtonFace"="49 54 58"'
        '"ButtonHilight"="119 126 140"'
        '"ButtonLight"="60 64 72"'
        '"ButtonShadow"="60 64 72"'
        '"ButtonText"="219 220 222"'
        '"GradientActiveTitle"="49 54 58"'
        '"GradientInactiveTitle"="49 54 58"'
        '"GrayText"="155 155 155"'
        '"Hilight"="119 126 140"'
        '"HilightText"="255 255 255"'
        '"InactiveBorder"="49 54 58"'
        '"InactiveTitle"="49 54 58"'
        '"InactiveTitleText"="219 220 222"'
        '"InfoText"="159 167 180"'
        '"InfoWindow"="49 54 58"'
        '"Menu"="49 54 58"'
        '"MenuBar"="49 54 58"'
        '"MenuHilight"="119 126 140"'
        '"MenuText"="219 220 222"'
        '"Scrollbar"="73 78 88"'
        '"TitleText"="219 220 222"'
        '"Window"="35 38 41"'
        '"WindowFrame"="49 54 58"'
        '"WindowText"="219 220 222"'
    )
    for i in "${colorarray[@]}";do
        echo "$i" >> "$WINE_PREFIX/user.reg"
    done
    # Use i18n for translation
    if type i18n::get >/dev/null 2>&1; then
        show_message "$(i18n::get "set_dark_mode")"
    else
    show_message "set dark mode for wine..." 
    fi
    unset colorarray
}

function export_var() {
    # CRITICAL: WINEPREFIX validation - prevent manipulation
    # Use centralized security::validate_path function if available
    # Use type instead of command -v for namespace functions (::)
    if type security::validate_path >/dev/null 2>&1; then
        if ! security::validate_path "$WINE_PREFIX"; then
            error "WINEPREFIX zeigt auf System-Verzeichnis (Sicherheitsrisiko): $WINE_PREFIX"
            return 1
        fi
    else
        # Fallback to inline validation if security module not loaded
        if [[ "$WINE_PREFIX" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
            error "WINEPREFIX zeigt auf System-Verzeichnis (Sicherheitsrisiko): $WINE_PREFIX"
            return 1
        fi
    fi
    export WINEPREFIX="$WINE_PREFIX"
    if [ "${LAUNCHER_GUI:-0}" != "1" ]; then
        if type i18n::get >/dev/null 2>&1; then
            show_message "$(i18n::get "wine_variables_exported")"
        else
            show_message "wine variables exported..."
        fi
    else
        log_debug "WINEPREFIX=$WINEPREFIX"
    fi
}

#parameters is [PATH] [CheckSum] [URL] [FILE NAME]
function download_component() {
    local tout=0
    local url="$3"
    
    # CRITICAL: Download URL validation - prevent malicious URLs
    # Whitelist: Nur erlaubte Domains
    local allowed_domains=(
        "github.com"
        "githubusercontent.com"
        "sourceforge.net"
        "microsoft.com"
        "adobe.com"
    )
    
    # Check that URL starts with https:// (HTTPS enforcement)
    if [[ ! "$url" =~ ^https:// ]]; then
        error "Download URL must use HTTPS (security risk): $url"
        return 1
    fi
    
    # Check that URL is from allowed domain
    local url_domain=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|' | sed 's|^www\.||')
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
    
    while true;do
        if [ $tout -ge 3 ];then
            error "sorry something went wrong during download $4"
        fi
        if [ -f $1 ];then
            local FILE_ID=$(md5sum $1 | cut -d" " -f1)
            if [ "$FILE_ID" = "${2:-}" ];then
                show_message "\033[1;36m$4\e[0m detected"
                return 0
            else
                show_message "md5 is not match"
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
    # #region agent log
    # #endregion
    
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
    # Use centralized security::validate_path function if available, otherwise fallback to inline check
    if command -v security::validate_path >/dev/null 2>&1; then
        if ! security::validate_path "$SCR_PATH"; then
            error "SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
            return 1
        fi
        
        if ! security::validate_path "$CACHE_PATH"; then
            error "CACHE_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $CACHE_PATH"
            return 1
        fi
    else
        # Fallback to inline validation if security module not loaded
        if [[ "$SCR_PATH" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
            error "SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
            return 1
        fi
        
        if [[ "$CACHE_PATH" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
            error "CACHE_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $CACHE_PATH"
            return 1
        fi
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
    # Use centralized security::validate_path function if available
    if command -v security::validate_path >/dev/null 2>&1; then
        if ! security::validate_path "$SCR_PATH"; then
            echo "ERROR: SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
            if [ "$skip_validation" = "false" ]; then
                echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
                exit 1
            fi
        fi
        
        if ! security::validate_path "$CACHE_PATH"; then
            echo "ERROR: CACHE_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $CACHE_PATH"
            if [ "$skip_validation" = "false" ]; then
                echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
                exit 1
            fi
        fi
    else
        # Fallback to inline validation if security module not loaded
        if [[ "$SCR_PATH" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
            echo "ERROR: SCR_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $SCR_PATH"
            if [ "$skip_validation" = "false" ]; then
                echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
                exit 1
            fi
        fi
        
        if [[ "$CACHE_PATH" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
            echo "ERROR: CACHE_PATH zeigt auf System-Verzeichnis (Sicherheitsrisiko): $CACHE_PATH"
            if [ "$skip_validation" = "false" ]; then
                echo -e "${C_RED}✗${C_RESET} ${C_YELLOW}Please reinstall Photoshop using setup.sh${C_RESET}"
                exit 1
            fi
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

photoshop::resolve_installer_dir() {
    local project_root="${1:-${PROJECT_ROOT:-}}"
    local candidate="" parent=""

    # GUI / prepare_source: gewählter Ordner oder Installer-Datei
    if [ -n "${RECIPE_WORK_ROOT:-}" ] && [ -f "${RECIPE_WORK_ROOT}/Set-up.exe" ]; then
        echo "$(cd "${RECIPE_WORK_ROOT}" && pwd)"
        return 0
    fi
    if [ -n "${RECIPE_SOURCE_ROOT:-}" ] && [ -f "${RECIPE_SOURCE_ROOT}/Set-up.exe" ]; then
        echo "$(cd "${RECIPE_SOURCE_ROOT}" && pwd)"
        return 0
    fi
    if [ -n "${RECIPE_INSTALLER_PATH:-}" ] && [ -f "${RECIPE_INSTALLER_PATH}" ]; then
        parent="$(cd "$(dirname "${RECIPE_INSTALLER_PATH}")" && pwd)"
        if [ -f "$parent/Set-up.exe" ]; then
            echo "$parent"
            return 0
        fi
    fi

    if [ -n "${PHOTOSHOP_INSTALLER_DIR:-}" ] && [ -f "${PHOTOSHOP_INSTALLER_DIR}/Set-up.exe" ]; then
        echo "$(cd "${PHOTOSHOP_INSTALLER_DIR}" && pwd)"
        return 0
    fi

    candidate="$project_root/photoshop"
    if [ -f "$candidate/Set-up.exe" ]; then
        echo "$(cd "$candidate" && pwd)"
        return 0
    fi

    return 1
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


