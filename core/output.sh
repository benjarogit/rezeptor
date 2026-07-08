#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Standardized Output Module
#
# Description:
#   Provides consistent, formatted console output throughout the installation.
#   All output follows a unified format for better readability.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

# ============================================================================
# @namespace output
# @description Standardized output functions for consistent console display
# ============================================================================

# ANSI Color codes (if not already defined)
if [ -z "${C_RESET:-}" ]; then
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
fi

output::_gui_emit() {
    local tag="$1"
    shift
    [ "${LAUNCHER_GUI:-0}" = "1" ] || return 0
    printf '@%s:%s\n' "$tag" "$*"
}

output::_gui_skip_console() {
    [ "${QUIET:-0}" = "1" ] || [ "${LAUNCHER_GUI:-0}" = "1" ]
}

# @function output::progress
# @param $1 Percent 0–100
# @param $* Optional step label
output::progress() {
    local pct="$1"
    shift
    local message="${*:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] Progress: ${pct}%" >> "$LOG_FILE"
        [ -n "$message" ] && echo "[$timestamp] → $message" >> "$LOG_FILE"
    fi

    if [ "${LAUNCHER_GUI:-0}" = "1" ]; then
        output::_gui_emit progress "$pct"
        [ -n "$message" ] && output::_gui_emit step "$message"
        return 0
    fi

    if [ -n "$message" ]; then
        printf "${C_YELLOW}→${C_RESET} ${C_CYAN}%s${C_RESET} (${pct}%%)\n" "$message"
    else
        printf "${C_CYAN}Progress: ${pct}%%${C_RESET}\n"
    fi
}

# @function output::user_action
# @description GUI-Hinweis wenn der User ggf. manuell reagieren muss
output::user_action() {
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] USER: $message" >> "$LOG_FILE"
    fi

    if [ "${LAUNCHER_GUI:-0}" = "1" ]; then
        output::_gui_emit warn "AKTION: $message"
        return 0
    fi

    printf "${C_YELLOW}⚠ AKTION:${C_RESET} ${C_YELLOW}%s${C_RESET}\n" "$message" >&2
}

# ============================================================================
# @function output::step
# @description Display a step message (→ prefix, cyan) - Modern, consistent style
# @param $* Step message
# @return 0 (always succeeds)
# @example output::step "Installing components..."
# ============================================================================
output::step() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] → $message" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        output::_gui_emit step "$message"
        return 0
    fi
    
    # Display to console (modern, consistent style)
    printf "${C_YELLOW}→${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$message"
}

# ============================================================================
# @function output::success
# @description Display a success message (✓ prefix, green) - Modern, consistent style
# @param $* Success message
# @return 0 (always succeeds)
# @example output::success "Installation complete"
# ============================================================================
output::success() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] ✓ $message" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        output::_gui_emit ok "$message"
        return 0
    fi
    
    # Display to console (modern, consistent style)
    printf "${C_GREEN}✓${C_RESET} ${C_GREEN}%s${C_RESET}\n" "$message"
}

# ============================================================================
# @function output::warning
# @description Display a warning message (⚠ prefix, yellow) - Modern, consistent style
# @param $* Warning message
# @return 0 (always succeeds)
# @example output::warning "This may take a while"
# ============================================================================
output::warning() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] ⚠ $message" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        output::_gui_emit warn "$message"
        return 0
    fi
    
    # Display to console (modern, consistent style)
    printf "${C_YELLOW}⚠${C_RESET} ${C_YELLOW}%s${C_RESET}\n" "$message"
}

# ============================================================================
# @function output::error
# @description Display an error message (✗ prefix, red) - Modern, consistent style
# @param $* Error message
# @return 0 (always succeeds)
# @example output::error "Installation failed"
# ============================================================================
output::error() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] ✗ $message" >> "$LOG_FILE"
    fi
    if [ -n "${ERROR_LOG:-}" ] && [ -f "${ERROR_LOG:-}" ]; then
        echo "[$timestamp] ERROR: $message" >> "$ERROR_LOG"
    fi

    if [ "${LAUNCHER_GUI:-0}" = "1" ]; then
        output::_gui_emit error "$message"
        return 0
    fi
    
    # Display to console (modern, consistent style)
    printf "${C_RED}✗${C_RESET} ${C_RED}%s${C_RESET}\n" "$message" >&2
}

# ============================================================================
# @function output::info
# @description Display an info message (ℹ prefix, cyan) - Modern, consistent style
# @param $* Info message
# @return 0 (always succeeds)
# @example output::info "This is informational"
# ============================================================================
output::info() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] ℹ $message" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        output::_gui_emit info "$message"
        return 0
    fi
    
    # Display to console (modern, consistent style)
    printf "${C_CYAN}ℹ${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$message"
}

# ============================================================================
# @function output::spinner_line
# @description Display a line with spinner placeholder (for use with spinner) - Modern style
# @param $* Message to display
# @return 0 (always succeeds)
# @example output::spinner_line "Installing..." (then call spinner)
# ============================================================================
output::spinner_line() {
    local message="$*"
    if [ "${LAUNCHER_GUI:-0}" = "1" ]; then
        output::_gui_emit step "$message"
        return 0
    fi
    printf "${C_YELLOW}→${C_RESET} ${C_CYAN}%s${C_RESET} " "$message"
}

# ============================================================================
# @function output::section
# @description Display a section header (consistent ═══ format)
# @param $* Optional: Section title
# @return 0 (always succeeds)
# @example output::section "Installation Phase 1"
# ============================================================================
output::section() {
    local title="${*:-}"
    local width=63
    local line=$(printf "═%.0s" $(seq 1 $width))
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        if [ -n "$title" ]; then
            echo "[$timestamp] ═══ $title ═══" >> "$LOG_FILE"
        else
            echo "[$timestamp] ════════════════════════════════════════════════════════════" >> "$LOG_FILE"
        fi
    fi
    
    if output::_gui_skip_console; then
        [ -n "$title" ] && output::_gui_emit step "$title"
        return 0
    fi
    
    if [ -n "$title" ]; then
        # Consistent header format (same as output::header)
        printf "${C_CYAN}%s${C_RESET}\n" "$line"
        # Center title (approximately) - same format as output::header
        local title_len=${#title}
        local padding=$(( (width - title_len) / 2 ))
        printf "${C_CYAN}%*s%s${C_RESET}\n" $padding "" "$title"
        printf "${C_CYAN}%s${C_RESET}\n" "$line"
    else
        # Simple separator
        printf "${C_CYAN}%s${C_RESET}\n" "$line"
    fi
    echo ""
}

# ============================================================================
# @function output::log_path
# @description Display log file path in a clean, short format
# @param $1 Label (e.g., "Log-Datei" or "Log file")
# @param $2 Full path to log file
# @return 0 (always succeeds)
# @example output::log_path "Log-Datei" "/path/to/log.log"
# ============================================================================
output::log_path() {
    local label="$1"
    local full_path="$2"
    
    # Extract just the filename for cleaner display
    local filename=$(basename "$full_path" 2>/dev/null || echo "$full_path")
    
    # Display in a clean format
    printf "${C_GRAY}%s:${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$label" "$filename"
}

# ============================================================================
# @function output::substep
# @description Display a substep message (indented, gray) - For less important steps
# @param $* Substep message
# @return 0 (always succeeds)
# @example output::substep "Checking architecture..."
# ============================================================================
output::substep() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    
    # Log to file (plain text)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp]   $message" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        return 0
    fi
    
    # Display to console (indented, gray)
    printf "  ${C_GRAY}%s${C_RESET}\n" "$message"
}

# ============================================================================
# @function output::box
# @description Display a message in a modern box - Beautiful, modern design
# @param $* Message to display
# @return 0 (always succeeds)
# @example output::box "Important notice"
# ============================================================================
output::box() {
    local message="$*"
    # Responsive width based on terminal size, with reasonable limits
    local width=$(tput cols 2>/dev/null || echo 80)
    # Clamp between 40 and 80 characters for readability
    if [ "$width" -lt 40 ]; then
        width=40
    elif [ "$width" -gt 80 ]; then
        width=80
    fi
    local line=$(printf "─%.0s" $(seq 1 $width))
    
    printf "${C_CYAN}┌%s┐${C_RESET}\n" "$line"
    printf "${C_CYAN}│${C_RESET} %-$(($width - 2))s ${C_CYAN}│${C_RESET}\n" "$message"
    printf "${C_CYAN}└%s┘${C_RESET}\n" "$line"
    echo ""
}

# ============================================================================
# @function output::header
# @description Display a section header (consistent ═══ format)
# @param $1 Header title
# @param $2 Optional: Indent level (default: 0, ignored for consistency)
# @return 0 (always succeeds)
# @example output::header "Installation Phase" 0
# ============================================================================
output::header() {
    local title="$1"
    # Responsive width based on terminal size, with reasonable limits
    local width=$(tput cols 2>/dev/null || echo 80)
    # Clamp between 40 and 80 characters for readability
    if [ "$width" -lt 40 ]; then
        width=40
    elif [ "$width" -gt 80 ]; then
        width=80
    fi
    local line=$(printf "═%.0s" $(seq 1 $width))
    
    # Log to file (plain text)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] ═══ $title ═══" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        output::_gui_emit step "$title"
        return 0
    fi
    
    # Display to console (consistent format - same as output::section)
    printf "${C_CYAN}%s${C_RESET}\n" "$line"
    # Center title (approximately)
    local title_len=${#title}
    local padding=$(( (width - title_len) / 2 ))
    printf "${C_CYAN}%*s%s${C_RESET}\n" $padding "" "$title"
    printf "${C_CYAN}%s${C_RESET}\n" "$line"
    echo ""
}

# ============================================================================
# @function output::item
# @description Display an item in a list (with indentation)
# @param $1 Indent level (0-3)
# @param $* Item text
# @return 0 (always succeeds)
# @example output::item 1 "Sub-item text"
# ============================================================================
output::item() {
    local indent_level="$1"
    shift
    local message="$*"
    local indent_str=""
    
    # Create indent string (2 spaces per level)
    for ((i=0; i<indent_level; i++)); do
        indent_str="${indent_str}  "
    done
    
    # Log to file (plain text)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        echo "[$timestamp] $indent_str• $message" >> "$LOG_FILE"
    fi
    
    if output::_gui_skip_console; then
        return 0
    fi
    
    # Display to console (with indentation)
    printf "${indent_str}${C_GRAY}•${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$message"
}

# ============================================================================
# @function output::empty_line
# @description Display an empty line (respects quiet mode)
# @return 0 (always succeeds)
# @example output::empty_line
# ============================================================================
output::empty_line() {
    # In quiet mode, don't output empty lines
    if [ "${QUIET:-0}" != "1" ]; then
        echo ""
    fi
}

