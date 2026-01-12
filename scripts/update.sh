#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Update Check Module
#
# Description:
#   Automatically checks for new versions on GitHub and notifies users
#   when updates are available. Non-blocking and runs in background.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

# ============================================================================
# @namespace update
# @description Update check functions for version management
# ============================================================================

# GitHub repository information
GITHUB_REPO="benjarogit/photoshopCClinux"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# Cache file for update check results (to avoid too frequent checks)
UPDATE_CACHE_FILE="${UPDATE_CACHE_FILE:-$HOME/.photoshop/.update_cache}"
UPDATE_CACHE_TTL="${UPDATE_CACHE_TTL:-86400}"  # 24 hours in seconds

# ============================================================================
# @function update::get_current_version
# @description Get current version from git or VERSION file
# @return Current version (echoed to stdout)
# ============================================================================
update::get_current_version() {
    # PRIORITY 1: Try to get version from VERSION file (local installed version)
    # This is the actual installed version, not the git tag
    if [ -f "VERSION" ]; then
        local version_content
        version_content=$(cat "VERSION" | tr -d '[:space:]')
        if [ -n "$version_content" ]; then
            # Ensure it starts with 'v' if it's a version number
            if [[ "$version_content" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                echo "v$version_content"
            elif [[ "$version_content" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                echo "$version_content"
            else
                echo "$version_content"
            fi
            return 0
        fi
    fi
    
    # PRIORITY 2: Try to get version from git tag (for development)
    if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
        local git_version
        git_version=$(git describe --tags --exact-match 2>/dev/null || git describe --tags 2>/dev/null || echo "")
        if [ -n "$git_version" ]; then
            echo "$git_version"
            return 0
        fi
    fi
    
    # PRIORITY 3: Fallback: try to extract from CHANGELOG.md
    if [ -f "CHANGELOG.md" ]; then
        local changelog_version
        # Try both formats: "## [v3.0.0]" and "## [3.0.0]"
        changelog_version=$(grep -m 1 "^## \[" CHANGELOG.md 2>/dev/null | sed -E 's/^## \[v?([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/' || echo "")
        if [ -n "$changelog_version" ]; then
            echo "v$changelog_version"
            return 0
        fi
    fi
    
    # Last resort: return unknown
    echo "unknown"
    return 1
}

# ============================================================================
# @function update::get_latest_version
# @description Get latest version from GitHub API
# @return Latest version (echoed to stdout), empty string on error
# ============================================================================
update::get_latest_version() {
    # Check if we have cached result and it's still valid
    if [ -f "$UPDATE_CACHE_FILE" ]; then
        local cache_time
        cache_time=$(stat -c %Y "$UPDATE_CACHE_FILE" 2>/dev/null || stat -f %m "$UPDATE_CACHE_FILE" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local age=$((current_time - cache_time))
        
        if [ $age -lt $UPDATE_CACHE_TTL ]; then
            # Cache is still valid, return cached version
            cat "$UPDATE_CACHE_FILE"
            return 0
        fi
    fi
    
    # Fetch latest version from GitHub API
    local latest_version=""
    if command -v curl >/dev/null 2>&1; then
        local api_response
        api_response=$(curl -s --connect-timeout 10 --max-time 30 "$GITHUB_API" 2>/dev/null || echo "")
        if [ -n "$api_response" ]; then
            # Extract tag_name (handle both with and without spaces: "tag_name":"v3.0.0" or "tag_name": "v3.0.0")
            latest_version=$(echo "$api_response" | grep -oE '"tag_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"tag_name"\s*:\s*"([^"]*)".*/\1/' || echo "")
        fi
    elif command -v wget >/dev/null 2>&1; then
        local api_response
        api_response=$(wget -q --timeout=30 -O- "$GITHUB_API" 2>/dev/null || echo "")
        if [ -n "$api_response" ]; then
            # Extract tag_name (handle both with and without spaces)
            latest_version=$(echo "$api_response" | grep -oE '"tag_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"tag_name"\s*:\s*"([^"]*)".*/\1/' || echo "")
        fi
    fi
    
    # Cache the result
    if [ -n "$latest_version" ]; then
        mkdir -p "$(dirname "$UPDATE_CACHE_FILE")"
        echo "$latest_version" > "$UPDATE_CACHE_FILE"
    fi
    
    echo "$latest_version"
}

# ============================================================================
# @function update::compare_versions
# @description Compare two version strings
# @param $1 Version 1
# @param $2 Version 2
# @return 0 if v1 < v2, 1 if v1 >= v2
# ============================================================================
update::compare_versions() {
    local v1="$1"
    local v2="$2"
    
    # Remove 'v' prefix if present
    v1="${v1#v}"
    v2="${v2#v}"
    
    # Simple version comparison (handles x.y.z format)
    # Convert to comparable format by padding with zeros
    local v1_padded
    v1_padded=$(echo "$v1" | awk -F. '{printf "%03d%03d%03d", $1, $2, $3}')
    local v2_padded
    v2_padded=$(echo "$v2" | awk -F. '{printf "%03d%03d%03d", $1, $2, $3}')
    
    if [ "$v1_padded" -lt "$v2_padded" ]; then
        return 0  # v1 < v2
    else
        return 1  # v1 >= v2
    fi
}

# ============================================================================
# @function update::check
# @description Check for updates (non-blocking)
# @param $1 Optional: Force check (ignore cache)
# @return 0 if update available, 1 if up to date or error
# ============================================================================
update::check() {
    local force="${1:-false}"
    
    # Clear cache if force check
    if [ "$force" = "true" ] && [ -f "$UPDATE_CACHE_FILE" ]; then
        rm -f "$UPDATE_CACHE_FILE"
    fi
    
    local current_version
    current_version=$(update::get_current_version)
    local latest_version
    latest_version=$(update::get_latest_version)
    
    # If we couldn't determine versions, silently fail
    if [ -z "$current_version" ] || [ -z "$latest_version" ] || [ "$current_version" = "unknown" ]; then
        return 1
    fi
    
    # Compare versions
    if update::compare_versions "$current_version" "$latest_version"; then
        # Update available
        return 0
    else
        # Up to date
        return 1
    fi
}

# ============================================================================
# @function update::notify
# @description Display update notification (non-blocking)
# @param $1 Optional: Current version
# @param $2 Optional: Latest version
# @return 0 on success, 1 on error
# ============================================================================
update::notify() {
    local current_version="${1:-}"
    local latest_version="${2:-}"
    
    # Get versions if not provided
    if [ -z "$current_version" ]; then
        current_version=$(update::get_current_version)
    fi
    if [ -z "$latest_version" ]; then
        latest_version=$(update::get_latest_version)
    fi
    
    # Check if update is available
    if ! update::check; then
        return 1
    fi
    
    # Display notification
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "           Update verfügbar / Update Available"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Aktuelle Version / Current Version: $current_version"
    echo "  Neue Version / New Version:         $latest_version"
    echo ""
    echo "  Repository: https://github.com/${GITHUB_REPO}"
    echo "  Releases:   https://github.com/${GITHUB_REPO}/releases"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    return 0
}

# ============================================================================
# @function update::check_async
# @description Check for updates in background (non-blocking)
# @return 0 on success, 1 on error
# ============================================================================
update::check_async() {
    # Run update check in background
    (
        if update::check; then
            # Update available - log it but don't block
            log::info "Update available: $(update::get_latest_version)"
        fi
    ) &
    
    return 0
}

# ============================================================================
# @function update::init_version_file
# @description Initialize VERSION file if it doesn't exist
# @return 0 on success, 1 on error
# ============================================================================
update::init_version_file() {
    # If VERSION file already exists, don't do anything
    if [ -f "VERSION" ]; then
        return 0
    fi
    
    local detected_version=""
    
    # PRIORITY 1: Try to get version from GitHub API (most accurate)
    detected_version=$(update::get_latest_version 2>/dev/null || echo "")
    if [ -n "$detected_version" ] && [ "$detected_version" != "" ]; then
        local version_clean="${detected_version#v}"
        echo "$version_clean" > "VERSION"
        return 0
    fi
    
    # PRIORITY 2: Try to get version from git tag (for development)
    if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
        local git_version
        git_version=$(git describe --tags --exact-match 2>/dev/null || git describe --tags 2>/dev/null || echo "")
        if [ -n "$git_version" ]; then
            local version_clean="${git_version#v}"
            echo "$version_clean" > "VERSION"
            return 0
        fi
    fi
    
    # PRIORITY 3: Try to extract from CHANGELOG.md
    if [ -f "CHANGELOG.md" ]; then
        local changelog_version
        changelog_version=$(grep -m 1 "^## \[" CHANGELOG.md 2>/dev/null | sed -E 's/^## \[v?([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/' || echo "")
        if [ -n "$changelog_version" ]; then
            echo "$changelog_version" > "VERSION"
            return 0
        fi
    fi
    
    # If we couldn't determine version, return error
    return 1
}

# ============================================================================
# @function update::update_version_file
# @description Update VERSION file with latest GitHub release version
# @return 0 on success, 1 on error
# ============================================================================
update::update_version_file() {
    local latest_version
    latest_version=$(update::get_latest_version)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "" ]; then
        return 1
    fi
    
    # Remove 'v' prefix if present (VERSION file should contain "3.0.1" not "v3.0.1")
    local version_clean="${latest_version#v}"
    
    # Write to VERSION file
    echo "$version_clean" > "VERSION"
    
    # Invalidate update cache so new version is immediately recognized
    if [ -f "$UPDATE_CACHE_FILE" ]; then
        rm -f "$UPDATE_CACHE_FILE"
    fi
    
    return 0
}
