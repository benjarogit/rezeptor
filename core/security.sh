#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Security Module
#
# Description:
#   Centralized security functions for path validation, input sanitization,
#   and shell injection protection.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/rezeptor
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

# ============================================================================
# @namespace security
# @description Security functions for validation and sanitization
# ============================================================================

# ============================================================================
# @function security::validate_path
# @description Validate that a path is safe (not pointing to system directories)
# @param $1 Path to validate
# @param $2 Optional: Allow root paths (default: false)
# @return 0 if path is safe, 1 if unsafe
# @example security::validate_path "$HOME/.photoshop"
# ============================================================================
security::validate_path() {
    local path="$1"
    local allow_root="${2:-false}"
    
    # Check if path is empty
    if [ -z "$path" ]; then
        return 1
    fi
    
    # Check if path points to system directories (security risk)
    local unsafe_patterns=(
        "^/etc"
        "^/usr/bin"
        "^/usr/sbin"
        "^/bin"
        "^/sbin"
        "^/lib"
        "^/var/log"
        "^/root"
        "^/sys"
        "^/proc"
        "^/dev"
    )
    
    for pattern in "${unsafe_patterns[@]}"; do
        if [[ "$path" =~ $pattern ]]; then
            if [ "$allow_root" = "false" ]; then
                return 1
            fi
        fi
    done
    
    # Check for path traversal attempts
    if [[ "$path" =~ \.\. ]]; then
        return 1
    fi
    
    # Note: Null byte check removed - paths with null bytes would fail anyway
    # and the check was causing false positives
    
    return 0
}

# ============================================================================
# @function security::sanitize_input
# @description Sanitize user input to prevent shell injection
# @param $1 Input string to sanitize
# @return Sanitized string (echoed to stdout)
# @example sanitized=$(security::sanitize_input "$user_input")
# ============================================================================
security::sanitize_input() {
    local input="$1"
    
    # Remove null bytes
    input="${input//$'\0'/}"
    
    # Remove command substitution attempts
    input="${input//\`/}"
    input="${input//\$(/}"
    
    # Remove semicolons (command separator)
    input="${input//;/}"
    
    # Remove pipes
    input="${input//|/}"
    
    # Remove redirects
    input="${input//</}"
    input="${input//>/}"
    
    # Remove ampersands (background processes)
    input="${input//&/}"
    
    # Remove newlines
    input="${input//$'\n'/}"
    input="${input//$'\r'/}"
    
    echo "$input"
}

# ============================================================================
# @function security::validate_url
# @description Validate that a URL is from an allowed domain
# @param $1 URL to validate
# @param $2 Optional: Array of allowed domains (default: common download domains)
# @return 0 if URL is safe, 1 if unsafe
# @example security::validate_url "https://github.com/release.tar.gz"
# ============================================================================
security::validate_url() {
    local url="$1"
    shift
    local allowed_domains=("$@")
    
    # Default allowed domains if none provided
    if [ ${#allowed_domains[@]} -eq 0 ]; then
        allowed_domains=(
            "github.com"
            "githubusercontent.com"
            "sourceforge.net"
            "archive.org"
        )
    fi
    
    # Extract domain from URL
    local url_domain
    url_domain=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|' | sed 's|^www\.||')
    
    # Check if domain is in allowed list
    for domain in "${allowed_domains[@]}"; do
        if [[ "$url_domain" == "$domain" ]] || [[ "$url_domain" == *".$domain" ]]; then
            return 0
        fi
    done
    
    return 1
}

# ============================================================================
# @function security::safe_eval
# @description Safely evaluate a command with validation
# @param $1 Command to evaluate
# @param $2 Optional: Allowed command patterns (whitelist)
# @return 0 on success, 1 on validation failure
# @example security::safe_eval "wine --version" "wine"
# ============================================================================
security::safe_eval() {
    local cmd="$1"
    shift
    local allowed_patterns=("$@")
    
    # If whitelist provided, check against it
    if [ ${#allowed_patterns[@]} -gt 0 ]; then
        local allowed=0
        for pattern in "${allowed_patterns[@]}"; do
            if [[ "$cmd" =~ $pattern ]]; then
                allowed=1
                break
            fi
        done
        
        if [ $allowed -eq 0 ]; then
            return 1
        fi
    fi
    
    # Check for dangerous shell injection characters (if no whitelist provided)
    # When whitelist is provided, we trust the patterns, but still check for obvious injection attempts
    if [ ${#allowed_patterns[@]} -eq 0 ]; then
        # Check for shell injection attempts: semicolon, ampersand, pipe, backtick, command substitution
        # Use case statement to avoid regex parsing issues with shellcheck
        case "$cmd" in
            *';'*|*'&'*|*'|'*|*'`'*|*'${'*|*'$('*)
                return 1
                ;;
        esac
    fi
    
    # Check for dangerous patterns
    local dangerous_patterns=(
        "rm -rf"
        "rm -f /"
        "dd if="
        "mkfs"
        "fdisk"
        "format"
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$cmd" =~ $pattern ]]; then
            return 1
        fi
    done
    
    return 0
}

# ============================================================================
# @function security::check_file_permissions
# @description Check that file has safe permissions
# @param $1 File path
# @param $2 Optional: Maximum permissions (octal, default: 755)
# @return 0 if permissions are safe, 1 if unsafe
# @example security::check_file_permissions "/path/to/script.sh" 755
# ============================================================================
security::check_file_permissions() {
    local file="$1"
    local max_perms="${2:-755}"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    local current_perms
    current_perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null || echo "000")
    
    # Remove leading zeros for comparison
    current_perms=$((10#$current_perms))
    max_perms=$((10#$max_perms))
    
    if [ $current_perms -gt $max_perms ]; then
        return 1
    fi
    
    return 0
}

# ============================================================================
# @namespace filesystem
# @description Safe filesystem operations
# ============================================================================

# ============================================================================
# @function filesystem::safe_remove
# @description Safely remove a directory or file with comprehensive validation
# @param $1 Path to remove
# @param $2 Optional: Error message prefix (default: "filesystem::safe_remove")
# @return 0 on success, 1 on error
# @example filesystem::safe_remove "$HOME/.photoshop"
# ============================================================================
filesystem::safe_remove() {
    local path="$1"
    local error_prefix="${2:-filesystem::safe_remove}"
    
    # Check if path is empty
    if [ -z "$path" ]; then
        if type error >/dev/null 2>&1; then
            error "$error_prefix: Path is empty"
        else
            echo "ERROR: $error_prefix: Path is empty" >&2
        fi
        return 1
    fi
    
    # Check for root directory (critical security check)
    if [ "$path" = "/" ] || [ "$path" = "/root" ]; then
        if type error >/dev/null 2>&1; then
            error "$error_prefix: Attempted to remove root directory (security risk): $path"
        else
            echo "ERROR: $error_prefix: Attempted to remove root directory (security risk): $path" >&2
        fi
        return 1
    fi
    
    # Validate path using security::validate_path if available
    if type security::validate_path >/dev/null 2>&1; then
        if ! security::validate_path "$path"; then
            if type error >/dev/null 2>&1; then
                error "$error_prefix: Unsafe path: $path"
            else
                echo "ERROR: $error_prefix: Unsafe path: $path" >&2
            fi
            return 1
        fi
    else
        # Fallback validation if security::validate_path not available
        # Check for path traversal attempts
        if [[ "$path" =~ \.\. ]]; then
            if type error >/dev/null 2>&1; then
                error "$error_prefix: Path traversal attempt detected: $path"
            else
                echo "ERROR: $error_prefix: Path traversal attempt detected: $path" >&2
            fi
            return 1
        fi
        
        # Check for system directories
        if [[ "$path" =~ ^/(etc|usr/bin|usr/sbin|bin|sbin|lib|var/log|root|sys|proc|dev) ]]; then
            if type error >/dev/null 2>&1; then
                error "$error_prefix: Attempted to remove system directory: $path"
            else
                echo "ERROR: $error_prefix: Attempted to remove system directory: $path" >&2
            fi
            return 1
        fi
    fi
    
    # Check if path exists
    if [ ! -e "$path" ]; then
        # Path doesn't exist - this is not an error, just return success
        if type log::debug >/dev/null 2>&1; then
            log::debug "$error_prefix: Path does not exist (skipping): $path"
        fi
        return 0
    fi
    
    # Perform the removal
    if rm -rf "$path" 2>/dev/null; then
        if type log::debug >/dev/null 2>&1; then
            log::debug "$error_prefix: Successfully removed: $path"
        fi
        return 0
    else
        if type error >/dev/null 2>&1; then
            error "$error_prefix: Failed to remove: $path"
        else
            echo "ERROR: $error_prefix: Failed to remove: $path" >&2
        fi
        return 1
    fi
}

