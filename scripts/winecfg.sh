#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Wine Configuration Launcher
#
# Description:
#   Opens Wine configuration (winecfg) for the Photoshop Wine prefix.
#   Allows users to adjust Wine settings, Windows version, and drives.
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

# KRITISCH: Source-Hijacking verhindern - immer absoluten Pfad verwenden
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source security module if available (for path validation)
if [ -f "$SCRIPT_DIR/security.sh" ]; then
    source "$SCRIPT_DIR/security.sh"
fi
source "$SCRIPT_DIR/sharedFuncs.sh"

function main() {
    # Try to load Photoshop paths, but continue if not installed
    if load_paths "true" 2>/dev/null && [ -n "$SCR_PATH" ] && [ -d "$SCR_PATH/prefix" ]; then
        # Photoshop is installed - use its Wine prefix
    RESOURCES_PATH="$SCR_PATH/resources"
    WINE_PREFIX="$SCR_PATH/prefix"
    # KRITISCH: WINEPREFIX-Validierung - verhindere Manipulation
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
        
        echo "═══════════════════════════════════════════════════════════════"
        echo "           Wine-Konfiguration für Photoshop CC"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Wine-Prefix: $WINE_PREFIX"
    else
        # Photoshop not installed - use default Wine prefix
        echo "═══════════════════════════════════════════════════════════════"
        echo "           Wine-Konfiguration (Standard)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "ℹ Photoshop ist noch nicht installiert."
        echo "  Öffne Standard-Wine-Konfiguration..."
        echo ""
        WINE_PREFIX="$HOME/.wine"
        # KRITISCH: WINEPREFIX-Validierung - verhindere Manipulation
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
        echo "Wine-Prefix: $WINE_PREFIX"
    fi
    echo ""
    echo "EMPFOHLENE EINSTELLUNGEN:"
    echo "  1. Applications Tab:"
    echo "     → Windows Version: Windows 10"
    echo ""
    echo "  2. Graphics Tab:"
    echo "     → Screen resolution: 96 DPI (Standard)"
    echo "     → Emulate a virtual desktop: Optional (bei Problemen aktivieren)"
    echo ""
    echo "  3. Staging Tab (falls vorhanden):"
    echo "     → CSMT für bessere Performance aktivieren"
    echo ""
    echo "BEKANNTE PROBLEME UND LÖSUNGEN (GitHub Issues):"
    echo "  - Photoshop stürzt ab: GPU-Beschleunigung in PS deaktivieren"
    echo "  - Schrift unleserlich: Font-Smoothing auf RGB setzen"
    echo "  - Langsamer Start: Normal beim ersten Start (1-2 Min)"
    echo "  - VCRUNTIME140.dll fehlt: vcrun2015 über winetricks nachinstallieren"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    notify-send "Photoshop CC" "Wine-Konfiguration wird geöffnet..." -i "photoshop"
    sleep 2
    
    # Suppress Wine fixme/err messages and allow CTRL+C
    # Use trap to handle CTRL+C gracefully
    trap 'echo ""; echo "Wine-Konfiguration abgebrochen."; exit 0' INT TERM
    
    # Run winecfg and suppress fixme/err messages (they're normal Wine warnings)
    # Use WINEDEBUG=-all to suppress all Wine debug messages
    WINEDEBUG=-all winecfg 2>/dev/null || true
    
    # Clear trap
    trap - INT TERM
    
    echo ""
    echo "✓ Konfiguration abgeschlossen!"
}

main



