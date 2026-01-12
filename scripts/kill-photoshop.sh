#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Kill Photoshop Process
#
# Description:
#   Properly terminates all Photoshop and Wine processes related to Photoshop
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
#
# Usage:
#   ./kill-photoshop.sh
#   or
#   bash scripts/kill-photoshop.sh
################################################################################

set -e

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sharedFuncs.sh" 2>/dev/null || {
    echo "ERROR: Cannot load sharedFuncs.sh" >&2
    exit 1
}

# Load paths
if ! load_paths "true" 2>/dev/null || [ -z "${SCR_PATH:-}" ]; then
    echo "ERROR: Photoshop not installed or paths not found" >&2
    exit 1
fi

WINE_PREFIX="${SCR_PATH}/prefix"

echo "═══════════════════════════════════════════════════════════════"
echo "           Photoshop Prozesse beenden"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Kill Photoshop processes
echo "→ Beende Photoshop Prozesse..."
pkill -f "Photoshop.exe" 2>/dev/null && echo "  ✓ Photoshop Prozesse beendet" || echo "  ℹ Keine Photoshop Prozesse gefunden"

# Kill Wine processes for this prefix
if [ -d "$WINE_PREFIX" ]; then
    export WINEPREFIX="$WINE_PREFIX"
    echo "→ Beende Wine Prozesse für Prefix..."
    wineserver -k 2>/dev/null && echo "  ✓ Wine Server beendet" || echo "  ℹ Wine Server nicht gefunden"
    
    # Kill any remaining wine processes
    pkill -f "wine.*Photoshop" 2>/dev/null && echo "  ✓ Wine Photoshop Prozesse beendet" || echo "  ℹ Keine Wine Photoshop Prozesse gefunden"
else
    echo "  ⚠ Wine Prefix nicht gefunden: $WINE_PREFIX"
fi

# Wait a moment
sleep 1

# Final check
if pgrep -f "Photoshop.exe" >/dev/null 2>&1; then
    echo ""
    echo "⚠ Einige Prozesse laufen noch - Force Kill..."
    pkill -9 -f "Photoshop.exe" 2>/dev/null || true
    wineserver -k 2>/dev/null || true
    sleep 1
fi

# Final verification
if pgrep -f "Photoshop.exe" >/dev/null 2>&1; then
    echo ""
    echo "✗ FEHLER: Photoshop Prozesse laufen noch!"
    echo "   Versuche manuell: pkill -9 -f Photoshop.exe"
    exit 1
else
    echo ""
    echo "✓ Alle Photoshop Prozesse beendet"
    exit 0
fi
