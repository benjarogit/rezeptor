#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Uninstaller
#
# Description:
#   Removes Adobe Photoshop CC installation including Wine prefix,
#   desktop entries, and all associated files.
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

# CRITICAL: Robust error handling
# set -e: Exit on errors
# set -u: Exit on undefined variables
# set -o pipefail: Exit on pipeline errors
# BusyBox compatibility: pipefail may be missing, so || true
set -eu
(set -o pipefail 2>/dev/null) || true

# CRITICAL: Initialize LANG_CODE BEFORE sharedFuncs.sh (sharedFuncs.sh enables set -u)
# Initialize LANG_CODE (will be set by detect_language if not already set)
LANG_CODE="${LANG_CODE:-}"

# CRITICAL: Prevent source hijacking - always use absolute path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
# Source modules in correct order
source "$SCRIPT_DIR/i18n.sh"
source "$SCRIPT_DIR/security.sh"
source "$SCRIPT_DIR/sharedFuncs.sh"

# Setup comprehensive logging for uninstaller (similar to PhotoshopSetup.sh)
setup_uninstaller_logging() {
    # Get project root (parent of scripts directory)
    local project_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    local log_dir="$project_root/logs"
    
    # Create logs directory if it doesn't exist
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # Generate timestamp for log filename (ISO format for better sorting)
    local timestamp_iso=$(date +%Y-%m-%d_%H-%M-%S)
    local timestamp=$(date '+%d.%m.%y %H:%M Uhr' 2>/dev/null || date '+%d.%m.%y %H:%M Uhr')
    local log_file="$log_dir/Uninstall_${timestamp_iso}.log"
    local warning_log_file="$log_dir/Uninstall_${timestamp_iso}_warnings.log"
    local error_log_file="$log_dir/Uninstall_${timestamp_iso}_errors.log"
    
    # Export log file paths for use in other functions
    export LOG_FILE="$log_file"
    export WARNING_LOG="$warning_log_file"
    export ERROR_LOG="$error_log_file"
    export PROJECT_ROOT="$project_root"
    export LOG_DIR="$log_dir"
    
    # Initialize log files with structured headers
    echo "═══════════════════════════════════════════════════════════════" > "$log_file"
    echo "            Photoshop Uninstaller Log" >> "$log_file"
    echo "═══════════════════════════════════════════════════════════════" >> "$log_file"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
    echo "Log file: $log_file" >> "$log_file"
    echo "Warning log: $warning_log_file" >> "$log_file"
    echo "Error log: $error_log_file" >> "$log_file"
    echo "" >> "$log_file"
    
    echo "═══════════════════════════════════════════════════════════════" > "$warning_log_file"
    echo "            Uninstaller Warnings Log" >> "$warning_log_file"
    echo "═══════════════════════════════════════════════════════════════" >> "$warning_log_file"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$warning_log_file"
    echo "" >> "$warning_log_file"
    
    echo "═══════════════════════════════════════════════════════════════" > "$error_log_file"
    echo "            Uninstaller Errors Log" >> "$error_log_file"
    echo "═══════════════════════════════════════════════════════════════" >> "$error_log_file"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$error_log_file"
    echo "" >> "$error_log_file"
    
    # Log initial information
    log_debug "=== Uninstaller Initialization ==="
    log_debug "SCRIPT_DIR: $SCRIPT_DIR"
    log_debug "PROJECT_ROOT: $project_root"
    log_debug "LOG_DIR: $log_dir"
    log_debug "LOG_FILE: $log_file"
    log_debug "ERROR_LOG: $error_log_file"
    log_debug "=== End Uninstaller Initialization ==="
}

# Enhanced logging function for uninstaller (similar to log_debug in PhotoshopSetup.sh)
log_debug() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Always log to file
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] DEBUG: $@" >> "${LOG_FILE}"
    fi
    
    # Only show on console in verbose mode (and not in quiet mode)
    if [ "${VERBOSE:-0}" = "1" ] && [ "${QUIET:-0}" != "1" ]; then
        # Use C_GRAY if available, otherwise plain text
        if [ -n "${C_GRAY:-}" ]; then
            echo -e "${C_GRAY}[DEBUG]${C_RESET} $@" >&2
        else
            echo "[DEBUG] $@" >&2
        fi
    fi
}

# Log error messages
log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    local category="${1:-UNINSTALL}"
    shift
    local message="$*"
    
    # Check if first argument is a category
    if [[ ! "$category" =~ ^[A-Z_]+$ ]] || [ "$category" = "UNINSTALL" ]; then
        message="$category $*"
        category="UNINSTALL"
    fi
    
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] [ERROR] [$category] $message" >> "${LOG_FILE}"
    fi
    if [ -n "${ERROR_LOG:-}" ] && [ -f "${ERROR_LOG:-}" ]; then
        echo "[$timestamp] [$category] $message" >> "${ERROR_LOG}"
    fi
}

# Log warning messages
log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    local category="${1:-UNINSTALL}"
    shift
    local message="$*"
    
    # Check if first argument is a category
    if [[ ! "$category" =~ ^[A-Z_]+$ ]] || [ "$category" = "UNINSTALL" ]; then
        message="$category $*"
        category="UNINSTALL"
    fi
    
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] [WARNING] [$category] $message" >> "${LOG_FILE}"
    fi
    if [ -n "${WARNING_LOG:-}" ] && [ -f "${WARNING_LOG:-}" ]; then
        echo "[$timestamp] [$category] $message" >> "${WARNING_LOG}"
    fi
}

# Log info messages
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] INFO: $@" >> "${LOG_FILE}"
    fi
}

# Detect language (same as setup.sh)
detect_language() {
    # Skip detection if LANG_CODE is already set (e.g., by manual toggle)
    if [ -z "${LANG_CODE:-}" ]; then
        if [[ "$LANG" =~ ^de ]]; then
            LANG_CODE="de"
        else
            LANG_CODE="en"
        fi
    fi
}

# Multi-language messages
msg_uninstall_confirm() {
    echo -e "${C_YELLOW}⚠${C_RESET} ${C_CYAN}$(i18n::get "uninstall_confirm")${C_RESET}"
}

msg_goodbye() {
    echo "$(i18n::get "goodbye")"
}

msg_remove_dir() {
    echo "$(i18n::get "removing_photoshop_directory")"
}

msg_dir_not_found() {
    echo "$(i18n::get "photoshop_directory_not_found")"
}

msg_remove_command() {
    echo "$(i18n::get "removing_launcher_command")"
}

msg_command_not_found() {
    echo "$(i18n::get "launcher_command_not_found")"
}

msg_remove_desktop() {
    echo "$(i18n::get "removing_desktop_entry")"
}

msg_desktop_not_found() {
    echo "$(i18n::get "desktop_entry_not_found")"
}

msg_cache_info() {
    echo "$(i18n::get "cache_info_line1")"
    echo "$(i18n::get "cache_info_line2")"
    echo "$(i18n::get "cache_dir_label")"
}

msg_delete_cache() {
    echo "$(i18n::get "delete_cache_question")"
}

msg_cache_removed() {
    echo "$(i18n::get "cache_removed")"
}

msg_cache_kept() {
    echo "$(i18n::get "cache_kept")"
}

msg_cache_not_found() {
    echo "$(i18n::get "cache_not_found")"
}

main() {    
    # Setup comprehensive logging FIRST (before any other operations)
    setup_uninstaller_logging
    
    # Detect language
    detect_language
    
    log_debug "=== Uninstaller Started ==="
    log_debug "Language: $LANG_CODE"
    log_debug "User: ${USER:-$(id -un)}"
    log_debug "Home: ${HOME:-}"

    CMD_PATH="/usr/local/bin/photoshop"
    ENTRY_PATH="$HOME/.local/share/applications/photoshop.desktop"
    
    log_debug "CMD_PATH: $CMD_PATH"
    log_debug "ENTRY_PATH: $ENTRY_PATH"
    
    local start_msg="$(i18n::get "uninstaller_started")"
    if command -v notify-send >/dev/null 2>&1; then
        if notify-send "Photoshop" "$start_msg" -i "photoshop" 2>/dev/null; then
            log_debug "Notification sent successfully"
        else
            log_debug "Notification failed (non-critical, likely no DBus session)"
        fi
    else
        log_debug "notify-send not available - skipping notification"
    fi
    log_info "$start_msg"

    # CRITICAL: Load installation paths and Wine version info BEFORE using them
    # This ensures WINE_VERSION_INFO is available for the uninstallation logic
    log_debug "Loading installation paths from ~/.psdata.txt..."
    if [ -f "$HOME/.psdata.txt" ]; then
        load_paths "true"  # Skip validation for uninstaller
        log_debug "SCR_PATH: ${SCR_PATH:-not set}"
        log_debug "CACHE_PATH: ${CACHE_PATH:-not set}"
        log_debug "WINE_VERSION_INFO: ${WINE_VERSION_INFO:-not set}"
    else
        log_warning "Installation data file not found: ~/.psdata.txt"
        log_warning "Continuing with uninstallation anyway..."
    fi

    # Show which Wine version was used (if available)
    if [ -n "${WINE_VERSION_INFO:-}" ] && [ -n "$WINE_VERSION_INFO" ]; then
        echo -e "${C_CYAN}ℹ${C_RESET} ${C_GRAY}$(i18n::get "uninstaller_using_proton")${C_RESET}"
        setup_log "$(i18n::get "uninstaller_using_proton") ($WINE_VERSION_INFO)" 2>/dev/null || true
    else
        echo -e "${C_CYAN}ℹ${C_RESET} ${C_GRAY}$(i18n::get "uninstaller_using_wine")${C_RESET}"
        setup_log "$(i18n::get "uninstaller_using_wine")" 2>/dev/null || true
    fi
    echo ""

    # CRITICAL: Only ask once if user is sure - then proceed automatically with spinner
    ask_question "$(msg_uninstall_confirm)" "N"
    if [ "$result" = "no" ]; then
        log_info "User cancelled uninstallation"
        msg_goodbye
        exit 0
    fi
    
    log_info "User confirmed uninstallation"
    
    # Show spinner message
    echo -e "${C_YELLOW}→${C_RESET} ${C_CYAN}$(i18n::get "uninstalling_photoshop")${C_RESET}"
    
    # CRITICAL: Kill all Wine/Proton processes before removing the prefix
    # This prevents "version mismatch" errors and ensures clean uninstallation
    echo -e "${C_YELLOW}→${C_RESET} ${C_CYAN}$(i18n::get "stopping_wine_processes")${C_RESET}"
    
    log_debug "Killing Wine/Proton processes..."
    
    # Kill wineserver if it exists
    if command -v wineserver >/dev/null 2>&1; then
        log_debug "Killing wineserver..."
        wineserver -k 2>/dev/null || log_warning "Failed to kill wineserver"
        sleep 1
    else
        log_debug "wineserver not found"
    fi
    
    # Kill any remaining wine processes for this prefix
    if [ -n "${SCR_PATH:-}" ] && [ -d "${SCR_PATH:-}/prefix" ]; then
        log_debug "Killing Wine processes for prefix: ${SCR_PATH}/prefix"
        # Set WINEPREFIX temporarily to kill processes for this prefix
        export WINEPREFIX="${SCR_PATH}/prefix"
        wineserver -k 2>/dev/null || log_warning "Failed to kill wineserver for prefix"
        unset WINEPREFIX
        sleep 1
    else
        log_debug "Prefix directory not found: ${SCR_PATH:-}/prefix"
    fi
    
    # Kill any wine processes that might be using the prefix
    log_debug "Killing any remaining Wine/Proton processes..."
    pkill -f "wine.*${SCR_PATH}" 2>/dev/null && log_debug "Killed Wine processes" || log_debug "No Wine processes found"
    pkill -f "proton.*${SCR_PATH}" 2>/dev/null && log_debug "Killed Proton processes" || log_debug "No Proton processes found"
    sleep 1
    
    #remove photoshop directory
    # CRITICAL: Works for both Wine Standard and Proton GE (both use the same prefix)
    log_debug "Removing Photoshop directory: ${SCR_PATH:-}"
    if [ -d "$SCR_PATH" ];then
        msg_remove_dir
        log_info "Removing directory: $SCR_PATH"
        # CRITICAL: Use safe_remove for security
        if type filesystem::safe_remove >/dev/null 2>&1; then
            if filesystem::safe_remove "$SCR_PATH" "uninstaller"; then
                log_info "Successfully removed Photoshop directory"
            else
                log_error "Failed to remove Photoshop directory"
                error2 "$(i18n::get "remove_prefix_failed")"
            fi
        else
            # Fallback if filesystem::safe_remove not available (should not happen)
            if [ -z "$SCR_PATH" ] || [ "$SCR_PATH" = "/" ] || [ "$SCR_PATH" = "/root" ]; then
                error2 "$(printf "$(i18n::get "unsafe_path_removal")" "$SCR_PATH")"
            elif rm -rf "$SCR_PATH" 2>&1; then
                log_info "Successfully removed Photoshop directory"
            else
                log_error "Failed to remove Photoshop directory"
                error2 "$(i18n::get "remove_prefix_failed")"
            fi
        fi
    else
        log_warning "Photoshop directory not found: $SCR_PATH"
        msg_dir_not_found
    fi
    
    #Unlink command 
    if [ -L "$CMD_PATH" ];then
        msg_remove_command
        # CRITICAL: Validate path before sudo operation
        if type security::validate_path >/dev/null 2>&1; then
            if ! security::validate_path "$CMD_PATH"; then
                error2 "$(printf "$(i18n::get "unsafe_path_sudo")" "$CMD_PATH")"
            fi
        fi
        
        # TOCTOU-Schutz: Prüfe nochmal ob es wirklich ein Symlink ist
        if [ ! -L "$CMD_PATH" ]; then
            error2 "$(i18n::get "cmd_path_toctou")"
        fi
        
        sudo unlink "$CMD_PATH" 2>/dev/null || error2 "$(i18n::get "remove_launcher_failed")"
    else
        msg_command_not_found
    fi

    #delete desktop entry (alle Varianten finden und entfernen)
    msg_remove_desktop
    
    # Search for all possible desktop entries (menu entries)
    local desktop_entries=(
        "$HOME/.local/share/applications/photoshop.desktop"
        "$HOME/.local/share/applications/Adobe Photoshop CC 2019.desktop"
        "$HOME/.local/share/applications/Adobe Photoshop.desktop"
        "$HOME/.local/share/applications/photoshopCC.desktop"
        "$HOME/.local/share/applications/Adobe Photoshop 2021.desktop"
        "$HOME/.local/share/applications/Adobe Photoshop 2022.desktop"
    )
    
    # Search also in Wine categories (e.g., ~/.local/share/applications/wine/Programs/)
    # CRITICAL: Wine creates desktop entries in wine/Programs/ subdirectories
    if [ -d "$HOME/.local/share/applications/wine" ]; then
        while IFS= read -r -d '' entry; do
            desktop_entries+=("$entry")
        done < <(find "$HOME/.local/share/applications/wine" -type f \( -name "*Photoshop*" -o -name "*photoshop*" \) -print0 2>/dev/null || true)
    fi
    
    # Also search in wine/Programs/ directly (common location)
    if [ -d "$HOME/.local/share/applications/wine/Programs" ]; then
        while IFS= read -r -d '' entry; do
            desktop_entries+=("$entry")
        done < <(find "$HOME/.local/share/applications/wine/Programs" -type f \( -name "*Photoshop*" -o -name "*photoshop*" \) -print0 2>/dev/null || true)
    fi

    # Search for desktop icons (Desktop shortcuts)
    # Desktop directory can be "Desktop" (English) or "Schreibtisch" (German)
    local desktop_dirs=(
        "$HOME/Desktop"
        "$HOME/Schreibtisch"
        "$HOME/desktop"
        "$HOME/schreibtisch"
    )
    
    local desktop_icons=()
    for desktop_dir in "${desktop_dirs[@]}"; do
        if [ -d "$desktop_dir" ]; then
            while IFS= read -r -d '' icon; do
                desktop_icons+=("$icon")
            done < <(find "$desktop_dir" -type f \( -name "*Photoshop*" -o -name "*photoshop*" \) -print0 2>/dev/null || true)
        fi
    done
    
    local found_any=false
    
    # Remove menu entries
    for entry in "${desktop_entries[@]}"; do
        if [ -f "$entry" ]; then
            if rm "$entry" 2>/dev/null; then
                found_any=true
                local removed_msg
                if [ "$LANG_CODE" = "de" ]; then
                    removed_msg=$(printf "Entfernt (Menü): %s" "$entry")
                else
                    removed_msg=$(printf "Removed (menu): %s" "$entry")
                fi
                setup_log "$removed_msg" 2>/dev/null || true
            fi
        fi
    done
    
    # Remove desktop icons
    for icon in "${desktop_icons[@]}"; do
        if [ -f "$icon" ]; then
            if rm "$icon" 2>/dev/null; then
                found_any=true
                local removed_msg
                if [ "$LANG_CODE" = "de" ]; then
                    removed_msg=$(printf "Entfernt (Desktop): %s" "$icon")
                else
                    removed_msg=$(printf "Removed (desktop): %s" "$icon")
                fi
                setup_log "$removed_msg" 2>/dev/null || true
            fi
        fi
    done
    
    # Also remove empty Wine directories if they exist
    if [ -d "$HOME/.local/share/applications/wine/Programs" ]; then
        # Check if Programs directory is empty or only contains empty subdirectories
        if [ -z "$(find "$HOME/.local/share/applications/wine/Programs" -mindepth 1 -maxdepth 1 -type f 2>/dev/null)" ]; then
            # Remove empty Programs directory
            rmdir "$HOME/.local/share/applications/wine/Programs" 2>/dev/null || true
            # If wine directory is also empty, remove it
            rmdir "$HOME/.local/share/applications/wine" 2>/dev/null || true
        fi
    fi
    
    if [ "$found_any" = false ]; then
        msg_desktop_not_found
    fi
    
    # Aktualisiere Desktop-Datenbank
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    
    # CRITICAL: Remove installed icons (PNG and SVG)
    # Icons are installed in ~/.local/share/icons/hicolor/
    echo -e "${C_YELLOW}→${C_RESET} ${C_CYAN}$(i18n::get "removing_icons")${C_RESET}"
    
    local hicolor_dir="$HOME/.local/share/icons/hicolor"
    local icon_name="photoshop"
    local icons_removed=false
    
    # Remove PNG icons in all sizes
    for size in 16 22 24 32 48 64 128 256 512; do
        local icon_file="$hicolor_dir/${size}x${size}/apps/${icon_name}.png"
        if [ -f "$icon_file" ]; then
            rm -f "$icon_file" 2>/dev/null && icons_removed=true
        fi
    done
    
    # Remove SVG icon
    local svg_icon="$hicolor_dir/scalable/apps/${icon_name}.svg"
    if [ -f "$svg_icon" ]; then
        rm -f "$svg_icon" 2>/dev/null && icons_removed=true
    fi
    
    # Update icon cache after removal
    if [ "$icons_removed" = true ]; then
        if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$hicolor_dir" ]; then
            gtk-update-icon-cache -f -t "$hicolor_dir" 2>/dev/null || true
        fi
        if command -v kbuildsycoca4 >/dev/null 2>&1; then
            kbuildsycoca4 --noincremental 2>/dev/null || true
        fi
        log_info "$(i18n::get "icons_removed_updated")"
    else
        log_debug "$(i18n::get "no_icons_found")"
    fi

    #delete cache directory (automatic - no confirmation needed)
    if [ -d "$CACHE_PATH" ];then
        local cache_msg
        if [ "$LANG_CODE" = "de" ]; then
            cache_msg=$(printf "Entferne Cache-Verzeichnis: %s" "$CACHE_PATH")
        else
            cache_msg=$(printf "Removing cache directory: %s" "$CACHE_PATH")
        fi
        log_info "$cache_msg"
        # CRITICAL: Use safe_remove for security
        if type filesystem::safe_remove >/dev/null 2>&1; then
            filesystem::safe_remove "$CACHE_PATH" "uninstaller" || log_warning "Konnte Cache-Verzeichnis nicht entfernen"
        else
            # Fallback if filesystem::safe_remove not available
            if [ -n "$CACHE_PATH" ] && [ "$CACHE_PATH" != "/" ] && [ "$CACHE_PATH" != "/root" ]; then
                # Additional validation before fallback rm -rf
                if type security::validate_path >/dev/null 2>&1; then
                    if security::validate_path "$CACHE_PATH"; then
                        rm -rf "$CACHE_PATH" 2>/dev/null || log_warning "Konnte Cache-Verzeichnis nicht entfernen"
                    else
                        log_warning "Unsafe cache path, skipping removal: $CACHE_PATH"
                    fi
                else
                    rm -rf "$CACHE_PATH" 2>/dev/null || log_warning "Konnte Cache-Verzeichnis nicht entfernen"
                fi
            fi
        fi
    fi
    
    # CRITICAL: Check if Wine Standard or Proton GE should be uninstalled
    # Only uninstall if they were installed specifically for Photoshop
    # WINE_VERSION_INFO should already be loaded at the beginning of main()
    
    # Check if Wine Standard should be uninstalled
    # Only uninstall if:
    # 1. Wine Standard was used (not Proton GE)
    # 2. No other Wine prefixes exist (except Photoshop prefix which is already deleted)
    # 3. Wine is installed via package manager
    if [ -z "${WINE_VERSION_INFO:-}" ] || [[ "${WINE_VERSION_INFO:-}" != *"Proton"* ]]; then
        # Wine Standard was used - check if we should uninstall it
        local other_wine_prefixes=0
        
        # Check for other Wine prefixes (common locations)
        local wine_prefix_locations=(
            "$HOME/.wine"
            "$HOME/.local/share/wineprefixes"
            "$HOME/.wineprefixes"
        )
        
        for prefix_dir in "${wine_prefix_locations[@]}"; do
            if [ -d "$prefix_dir" ] && [ "$prefix_dir" != "$SCR_PATH/prefix" ]; then
                # Check if directory contains actual Wine prefixes
                if [ -f "$prefix_dir/system.reg" ] || [ -f "$prefix_dir/user.reg" ] || [ -n "$(find "$prefix_dir" -maxdepth 2 -name "*.reg" 2>/dev/null | head -1)" ]; then
                    other_wine_prefixes=1
                    break
                fi
            fi
        done
        
        # Also check for other Wine prefixes in common locations
        if [ -d "$HOME/.local/share/wineprefixes" ]; then
            local prefix_count=$(find "$HOME/.local/share/wineprefixes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            if [ "$prefix_count" -gt 0 ]; then
                other_wine_prefixes=1
            fi
        fi
        
        # If no other Wine prefixes exist, automatically uninstall Wine (no confirmation needed)
        if [ "$other_wine_prefixes" -eq 0 ]; then
            log_info "$(i18n::get "wine_only_for_photoshop")"
            
            # Try to uninstall Wine via package manager (silent, no confirmation)
            if command -v pacman >/dev/null 2>&1; then
                # Arch-based
                sudo pacman -Rns wine wine-staging wine-mono wine-gecko 2>/dev/null || sudo pacman -Rns wine 2>/dev/null || true
            elif command -v apt >/dev/null 2>&1; then
                # Debian-based
                sudo apt remove --purge wine wine-stable wine-staging 2>/dev/null || true
            elif command -v dnf >/dev/null 2>&1; then
                # Fedora-based
                sudo dnf remove wine 2>/dev/null || true
            fi
        fi
    fi
    
    # Check if Proton GE should be uninstalled
    # Only uninstall if:
    # 1. Proton GE was used (not Wine Standard)
    # 2. It's NOT Steam Proton (Steam Proton should not be touched)
    # 3. It was installed via package manager or manually for Photoshop
    if [ -n "${WINE_VERSION_INFO:-}" ] && [[ "${WINE_VERSION_INFO:-}" =~ "Proton" ]]; then
        # Proton GE was used - check if we should uninstall it
        local proton_ge_path=""
        
        # Check for system-wide Proton GE (not Steam)
        local possible_proton_paths=(
            "$HOME/.local/share/proton-ge"
            "/usr/local/share/proton-ge"
            "/opt/proton-ge"
        )
        
        for path in "${possible_proton_paths[@]}"; do
            if [ -d "$path" ] && [ -f "$path/files/bin/wine" ] 2>/dev/null; then
                # Make sure it's NOT Steam Proton
                if [[ ! "$path" =~ steam ]] && [[ ! "$path" =~ Steam ]]; then
                    proton_ge_path="$path"
                    break
                fi
            fi
        done
        
        # Also check for AUR-installed Proton GE
        if [ -z "$proton_ge_path" ] && command -v pacman >/dev/null 2>&1; then
            if pacman -Q proton-ge-custom-bin >/dev/null 2>&1; then
                proton_ge_path="aur"
            fi
        fi
        
        # If Proton GE was found (and it's not Steam), automatically uninstall (no confirmation needed)
        if [ -n "$proton_ge_path" ]; then
            log_info "$(i18n::get "proton_only_for_photoshop")"
            
            if [ "$proton_ge_path" = "aur" ]; then
                # AUR-installed: Use package manager (silent, no confirmation)
                if command -v yay >/dev/null 2>&1; then
                    yay -Rns proton-ge-custom-bin 2>/dev/null || true
                elif command -v paru >/dev/null 2>&1; then
                    paru -Rns proton-ge-custom-bin 2>/dev/null || true
                elif command -v pacman >/dev/null 2>&1; then
                    sudo pacman -Rns proton-ge-custom-bin 2>/dev/null || true
                fi
            else
                # Manually installed: Remove directory
                if [ -d "$proton_ge_path" ]; then
                    # CRITICAL: Use safe_remove for security
                    if type filesystem::safe_remove >/dev/null 2>&1; then
                        filesystem::safe_remove "$proton_ge_path" "uninstaller" || log_warning "Konnte Proton GE Verzeichnis nicht entfernen: $proton_ge_path"
                    else
                        # Fallback: validate before rm -rf
                        if [ -z "$proton_ge_path" ] || [ "$proton_ge_path" = "/" ] || [ "$proton_ge_path" = "/root" ]; then
                            log_warning "Unsichere Proton GE Pfad, überspringe Löschung: $proton_ge_path"
                        else
                            rm -rf "$proton_ge_path" 2>/dev/null || log_warning "Konnte Proton GE Verzeichnis nicht entfernen: $proton_ge_path"
        fi
                    fi
                fi
            fi
        fi
    fi
    
    # Exit cleanly (fixes hanging issue)
    echo ""
    echo "$(i18n::get "uninstall_completed")"
    exit 0
}

#parameters [Message] [default flag [Y/N]]
function ask_question() {
    result=""
    # CRITICAL: == is not POSIX, use =
    if [ "$2" = "Y" ];then
        # CRITICAL: Reset IFS after read
        local old_IFS="${IFS:-}"
        IFS= read -r -p "$1 [Y/n] " response
        if locale noexpr >/dev/null 2>&1 && [[ "$response" =~ $(locale noexpr) ]];then
            result="no"
        elif [ -n "$response" ] && [[ "$response" =~ ^[Nn] ]]; then
            result="no"
        else
            result="yes"
        fi
        # CRITICAL: Reset IFS
        IFS="$old_IFS"
    elif [ "$2" = "N" ];then
        # CRITICAL: Reset IFS after read
        local old_IFS="${IFS:-}"
        IFS= read -r -p "$1 [N/y] " response
        if locale yesexpr >/dev/null 2>&1 && [[ "$response" =~ $(locale yesexpr) ]];then
            result="yes"
        elif [ -n "$response" ] && [[ "$response" =~ ^[Yy] ]]; then
            result="yes"
        else
            result="no"
        fi
        # CRITICAL: Reset IFS
        IFS="$old_IFS"
    fi
}

# Load paths with skip_validation=true to allow uninstall even if directories are deleted
load_paths "true"

# Detect language before main() is called
detect_language

main



