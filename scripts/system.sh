#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - System Detection Module
#
# Description:
#   Detects Linux distribution, desktop environment, kernel version, and
#   system architecture. Provides functions to handle different systems
#   appropriately.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

# ============================================================================
# @namespace system
# @description System detection and environment-specific operations
# ============================================================================

# Cache for detected values (avoid multiple detections)
_SYSTEM_DISTRO=""
_SYSTEM_DESKTOP=""
_SYSTEM_KERNEL=""
_SYSTEM_ARCH=""

# ============================================================================
# @function system::detect_distro
# @description Detect Linux distribution
# @return Distribution name (e.g., "Arch", "Ubuntu", "Debian")
# ============================================================================
system::detect_distro() {
    if [ -n "$_SYSTEM_DISTRO" ]; then
        echo "$_SYSTEM_DISTRO"
        return 0
    fi
    
    if [ -f /etc/os-release ]; then
        _SYSTEM_DISTRO=$(grep -E "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' | tr '[:lower:]' '[:upper:]')
        # Normalize common distributions
        case "$_SYSTEM_DISTRO" in
            "arch"|"archlinux")
                _SYSTEM_DISTRO="Arch"
                ;;
            "ubuntu"|"debian")
                _SYSTEM_DISTRO="$_SYSTEM_DISTRO"
                ;;
            "fedora")
                _SYSTEM_DISTRO="Fedora"
                ;;
            "opensuse"|"opensuse-tumbleweed"|"opensuse-leap")
                _SYSTEM_DISTRO="openSUSE"
                ;;
            *)
                # Capitalize first letter
                _SYSTEM_DISTRO=$(echo "$_SYSTEM_DISTRO" | sed 's/^./\U&/')
                ;;
        esac
    elif [ -f /etc/arch-release ]; then
        _SYSTEM_DISTRO="Arch"
    elif [ -f /etc/debian_version ]; then
        _SYSTEM_DISTRO="Debian"
    elif [ -f /etc/redhat-release ]; then
        _SYSTEM_DISTRO=$(awk '{print $1}' /etc/redhat-release)
    else
        _SYSTEM_DISTRO="Unknown"
    fi
    
    echo "$_SYSTEM_DISTRO"
}

# ============================================================================
# @function system::detect_desktop
# @description Detect desktop environment
# @return Desktop environment name (e.g., "KDE", "GNOME", "XFCE", "Unknown")
# ============================================================================
system::detect_desktop() {
    if [ -n "$_SYSTEM_DESKTOP" ]; then
        echo "$_SYSTEM_DESKTOP"
        return 0
    fi
    
    # Try multiple methods to detect desktop environment
    local desktop=""
    
    # Method 1: XDG_CURRENT_DESKTOP (most reliable)
    if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        desktop="${XDG_CURRENT_DESKTOP}"
    # Method 2: DESKTOP_SESSION
    elif [ -n "${DESKTOP_SESSION:-}" ]; then
        desktop="${DESKTOP_SESSION}"
    # Method 3: XDG_SESSION_DESKTOP
    elif [ -n "${XDG_SESSION_DESKTOP:-}" ]; then
        desktop="${XDG_SESSION_DESKTOP}"
    # Method 4: Check running processes
    elif pgrep -x "plasmashell" >/dev/null 2>&1 || pgrep -x "kwin" >/dev/null 2>&1; then
        desktop="KDE"
    elif pgrep -x "gnome-shell" >/dev/null 2>&1; then
        desktop="GNOME"
    elif pgrep -x "xfce4-session" >/dev/null 2>&1; then
        desktop="XFCE"
    elif pgrep -x "mate-session" >/dev/null 2>&1; then
        desktop="MATE"
    elif pgrep -x "cinnamon" >/dev/null 2>&1; then
        desktop="Cinnamon"
    elif pgrep -x "lxqt-session" >/dev/null 2>&1; then
        desktop="LXQT"
    fi
    
    # Normalize desktop name
    case "$desktop" in
        *[Kk][Dd][Ee]*|*[Pp][Ll][Aa][Ss][Mm][Aa]*)
            _SYSTEM_DESKTOP="KDE"
            ;;
        *[Gg][Nn][Oo][Mm][Ee]*)
            _SYSTEM_DESKTOP="GNOME"
            ;;
        *[Xx][Ff][Cc][Ee]*)
            _SYSTEM_DESKTOP="XFCE"
            ;;
        *[Mm][Aa][Tt][Ee]*)
            _SYSTEM_DESKTOP="MATE"
            ;;
        *[Cc][Ii][Nn][Nn][Aa][Mm][Oo][Nn]*)
            _SYSTEM_DESKTOP="Cinnamon"
            ;;
        *[Ll][Xx][Qq][Tt]*)
            _SYSTEM_DESKTOP="LXQT"
            ;;
        "")
            _SYSTEM_DESKTOP="Unknown"
            ;;
        *)
            # Capitalize first letter
            _SYSTEM_DESKTOP=$(echo "$desktop" | sed 's/^./\U&/')
            ;;
    esac
    
    echo "$_SYSTEM_DESKTOP"
}

# ============================================================================
# @function system::detect_kernel
# @description Detect kernel version
# @return Kernel version (e.g., "6.18.0")
# ============================================================================
system::detect_kernel() {
    if [ -n "$_SYSTEM_KERNEL" ]; then
        echo "$_SYSTEM_KERNEL"
        return 0
    fi
    
    _SYSTEM_KERNEL=$(uname -r 2>/dev/null || echo "Unknown")
    echo "$_SYSTEM_KERNEL"
}

# ============================================================================
# @function system::detect_arch
# @description Detect system architecture
# @return Architecture (e.g., "x86_64", "aarch64")
# ============================================================================
system::detect_arch() {
    if [ -n "$_SYSTEM_ARCH" ]; then
        echo "$_SYSTEM_ARCH"
        return 0
    fi
    
    _SYSTEM_ARCH=$(uname -m 2>/dev/null || echo "Unknown")
    echo "$_SYSTEM_ARCH"
}

# ============================================================================
# @function system::is_kde
# @description Check if desktop environment is KDE/Plasma
# @return 0 if KDE, 1 otherwise
# ============================================================================
system::is_kde() {
    [ "$(system::detect_desktop)" = "KDE" ]
}

# ============================================================================
# @function system::is_gnome
# @description Check if desktop environment is GNOME
# @return 0 if GNOME, 1 otherwise
# ============================================================================
system::is_gnome() {
    [ "$(system::detect_desktop)" = "GNOME" ]
}

# ============================================================================
# @function system::is_xfce
# @description Check if desktop environment is XFCE
# @return 0 if XFCE, 1 otherwise
# ============================================================================
system::is_xfce() {
    [ "$(system::detect_desktop)" = "XFCE" ]
}

# ============================================================================
# @function system::update_icon_cache
# @description Update icon cache for current desktop environment
# @return 0 on success, 1 on error
# ============================================================================
system::update_icon_cache() {
    local hicolor_dir="$HOME/.local/share/icons/hicolor"
    
    if [ ! -d "$hicolor_dir" ]; then
        return 1
    fi
    
    # GTK-based desktops (GNOME, XFCE, MATE, Cinnamon)
    if system::is_gnome || system::is_xfce || [ "$(system::detect_desktop)" = "MATE" ] || [ "$(system::detect_desktop)" = "Cinnamon" ]; then
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -f -t "$hicolor_dir" 2>/dev/null || return 1
            return 0
        fi
    fi
    
    # KDE/Plasma
    if system::is_kde; then
        if command -v kbuildsycoca4 >/dev/null 2>&1; then
            kbuildsycoca4 --noincremental 2>/dev/null || return 1
            return 0
        fi
    fi
    
    # Fallback: Try both
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$hicolor_dir" 2>/dev/null || true
    fi
    if command -v kbuildsycoca4 >/dev/null 2>&1; then
        kbuildsycoca4 --noincremental 2>/dev/null || true
    fi
    
    return 0
}

# ============================================================================
# @function system::update_desktop_database
# @description Update desktop database for current desktop environment
# @return 0 on success, 1 on error
# ============================================================================
system::update_desktop_database() {
    local apps_dir="$HOME/.local/share/applications"
    
    if [ ! -d "$apps_dir" ]; then
        return 1
    fi
    
    # All desktop environments use update-desktop-database
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" 2>/dev/null || return 1
        return 0
    fi
    
    # KDE also uses kbuildsycoca4
    if system::is_kde && command -v kbuildsycoca4 >/dev/null 2>&1; then
        kbuildsycoca4 --noincremental 2>/dev/null || true
    fi
    
    return 0
}

# ============================================================================
# @function system::get_info
# @description Get complete system information
# @return System info as formatted string
# ============================================================================
system::get_info() {
    local distro=$(system::detect_distro)
    local desktop=$(system::detect_desktop)
    local kernel=$(system::detect_kernel)
    local arch=$(system::detect_arch)
    
    echo "Distribution: $distro | Desktop: $desktop | Kernel: $kernel | Arch: $arch"
}

