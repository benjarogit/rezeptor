#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Troubleshooting Script
#
# Description:
#   Automatic diagnosis and troubleshooting for common Photoshop CC issues.
#   Checks Wine configuration, installation integrity, and provides fixes.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

echo "═══════════════════════════════════════════════════════════════"
echo "    Photoshop CC - Troubleshooting & Diagnose Tool"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Pfade - verwende load_paths() für Kompatibilität mit altem und neuem Pfad
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source sharedFuncs.sh to use load_paths()
if [ -f "$SCRIPT_DIR/scripts/sharedFuncs.sh" ]; then
    source "$SCRIPT_DIR/scripts/sharedFuncs.sh" 2>/dev/null || true
    if [ -f "$SCRIPT_DIR/scripts/wine-runtime.sh" ]; then
        source "$SCRIPT_DIR/scripts/wine-runtime.sh" 2>/dev/null || true
    fi
    # Try to load paths (skip validation for troubleshooting)
    if [ -f "$HOME/.psdata.txt" ]; then
        load_paths "true" 2>/dev/null || true
    fi
fi

# Fallback to default paths if load_paths didn't work
SCR_PATH="${SCR_PATH:-$HOME/.photoshop}"
# Also check old path for compatibility
if [ ! -d "$SCR_PATH" ] && [ -d "$HOME/.photoshopCCV19" ]; then
SCR_PATH="$HOME/.photoshopCCV19"
fi

WINE_PREFIX="$SCR_PATH/prefix"

if type wine_runtime::init >/dev/null 2>&1; then
    wine_runtime::init 2>/dev/null || true
    echo -e "${BLUE}[INFO]${NC} Runtime: $(wine_runtime::describe 2>/dev/null || echo n/a)"
fi

# Use new structured logs if available, fallback to old location
if [ -d "$SCRIPT_DIR/logs" ]; then
    # Find most recent wine log
    LOG_FILE=$(find "$SCRIPT_DIR/logs" -name "wine_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
        # Fallback to old location
        LOG_FILE="$SCR_PATH/wine-error.log"
    fi
else
LOG_FILE="$SCR_PATH/wine-error.log"
fi

# Zähler für Probleme
ISSUES_FOUND=0
ISSUES_FIXED=0

echo -e "${BLUE}[INFO]${NC} Starte Systemdiagnose..."
echo ""

# Funktion für OK-Status
check_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Funktion für Warnung
check_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    ((ISSUES_FOUND++))
}

# Funktion für Fehler
check_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((ISSUES_FOUND++))
}

# Funktion für Fix
check_fixed() {
    echo -e "${GREEN}[FIX]${NC} $1"
    ((ISSUES_FIXED++))
}

echo "─────────────────────────────────────────────────────────────"
echo "1. Überprüfe System-Voraussetzungen"
echo "─────────────────────────────────────────────────────────────"

# Check 64-bit System
if [ "$(uname -m)" == "x86_64" ]; then
    check_ok "64-bit System erkannt"
else
    check_error "Kein 64-bit System! Photoshop benötigt 64-bit"
fi

# Check Wine
if command -v wine &> /dev/null; then
    WINE_VERSION=$(wine --version 2>/dev/null)
    check_ok "Wine installiert: $WINE_VERSION"
else
    check_error "Wine nicht installiert! Installiere mit: sudo pacman -S wine"
fi

# Check Winetricks
if command -v winetricks &> /dev/null; then
    check_ok "Winetricks installiert"
else
    check_error "Winetricks nicht installiert! Installiere mit: sudo pacman -S winetricks"
fi

# Check md5sum
if command -v md5sum &> /dev/null; then
    check_ok "md5sum verfügbar"
else
    check_warning "md5sum nicht gefunden (normalerweise nicht kritisch)"
fi

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "2. Überprüfe Photoshop Installation"
echo "─────────────────────────────────────────────────────────────"

# Check Installation Directory
if [ -d "$SCR_PATH" ]; then
    check_ok "Installations-Verzeichnis gefunden: $SCR_PATH"
else
    check_error "Installations-Verzeichnis nicht gefunden: $SCR_PATH"
    # If called from setup.sh, return to menu
    if [ -n "${RETURN_TO_MENU:-}" ]; then
        echo ""
        read -p "Drücke Enter, um zum Hauptmenü zurückzukehren... " dummy
        exit 0
    fi
    echo "        → Photoshop ist nicht installiert. Führe setup.sh aus."
    exit 1
fi

# Check Wine Prefix
if [ -d "$WINE_PREFIX" ]; then
    check_ok "Wine-Prefix gefunden: $WINE_PREFIX"
else
    check_error "Wine-Prefix nicht gefunden: $WINE_PREFIX"
    exit 1
fi

# Check Photoshop.exe
PHOTOSHOP_EXE=""
if type photoshop::find_exe >/dev/null 2>&1 && photoshop_exe="$(photoshop::find_exe "$WINE_PREFIX" 2>/dev/null)"; then
    PHOTOSHOP_EXE="$photoshop_exe"
    check_ok "Photoshop.exe gefunden: $PHOTOSHOP_EXE"
else
POSSIBLE_PATHS=(
    "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop 2021/Photoshop.exe"
    "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop 2022/Photoshop.exe"
    "$WINE_PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop CC 2019/Photoshop.exe"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        PHOTOSHOP_EXE="$path"
        check_ok "Photoshop.exe gefunden: $path"
        break
    fi
done
fi

if [ -z "$PHOTOSHOP_EXE" ]; then
    check_error "Photoshop.exe nicht gefunden!"
    echo "        → Installation könnte fehlgeschlagen sein"
    exit 1
fi

# Check Launcher
if [ -f "$SCR_PATH/launcher/launcher.sh" ]; then
    check_ok "Launcher-Script vorhanden"
else
    check_error "Launcher-Script fehlt: $SCR_PATH/launcher/launcher.sh"
fi

# Check Desktop Entry
if [ -f "$HOME/.local/share/applications/photoshop.desktop" ]; then
    check_ok "Desktop-Eintrag vorhanden"
else
    check_warning "Desktop-Eintrag fehlt (nicht kritisch)"
fi

# Check Command
if [ -L "/usr/local/bin/photoshop" ]; then
    check_ok "Photoshop-Befehl verfügbar"
else
    check_warning "Photoshop-Befehl nicht verfügbar (nicht kritisch)"
fi

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "3. Überprüfe Wine-Konfiguration"
echo "─────────────────────────────────────────────────────────────"

export WINEPREFIX="$WINE_PREFIX"

# Check Windows Version
WIN_VERSION=$(WINEPREFIX="$WINE_PREFIX" wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion 2>/dev/null | grep CurrentVersion | awk '{print $3}')

if [ -n "$WIN_VERSION" ]; then
    if [[ "$WIN_VERSION" == "10.0" ]]; then
        check_ok "Windows Version: 10.0 (Optimal)"
    elif [[ "$WIN_VERSION" == "6.1" ]]; then
        check_warning "Windows Version: 7 (Empfohlen: Windows 10)"
        echo "        → Führe aus: WINEPREFIX=$WINE_PREFIX winetricks win10"
    else
        check_warning "Windows Version: $WIN_VERSION (Unbekannt)"
    fi
else
    check_warning "Windows Version konnte nicht ermittelt werden"
fi

# Check VCRun installations
echo ""
echo "Prüfe Visual C++ Runtime Installationen..."

VCRUN_DLLS=(
    "drive_c/windows/system32/msvcp140.dll"
    "drive_c/windows/system32/vcruntime140.dll"
    "drive_c/windows/system32/msvcp120.dll"
)

ALL_VCRUN_OK=true
for dll in "${VCRUN_DLLS[@]}"; do
    if [ -f "$WINE_PREFIX/$dll" ]; then
        check_ok "$(basename $dll) vorhanden"
    else
        check_error "$(basename $dll) fehlt!"
        ALL_VCRUN_OK=false
    fi
done

if [ "$ALL_VCRUN_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}Möchtest du die fehlenden Visual C++ Runtimes jetzt installieren? [y/N]${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Installiere VCRun Komponenten..."
        WINEPREFIX="$WINE_PREFIX" winetricks -q vcrun2010 vcrun2012 vcrun2013 vcrun2015
        check_fixed "Visual C++ Runtimes installiert"
    fi
fi

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "4. Überprüfe bekannte Probleme"
echo "─────────────────────────────────────────────────────────────"

# Check for problematic plugins
PHOTOSHOP_DIR=$(dirname "$PHOTOSHOP_EXE")
PROBLEMATIC_PLUGINS=(
    "$PHOTOSHOP_DIR/Required/Plug-ins/Spaces/Adobe Spaces Helper.exe"
)

for plugin in "${PROBLEMATIC_PLUGINS[@]}"; do
    if [ -f "$plugin" ]; then
        check_warning "Problematisches Plugin gefunden: $(basename "$plugin")"
        echo "        → Kann zu Abstürzen führen"
        echo -e "${YELLOW}        Möchtest du es entfernen? [y/N]${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            rm "$plugin"
            check_fixed "Plugin entfernt: $(basename "$plugin")"
        fi
    fi
done

# Check Photoshop Preferences
PREFS_DIR="$WINE_PREFIX/drive_c/users/$USER/AppData/Roaming/Adobe/Adobe Photoshop CC 2019/Adobe Photoshop CC 2019 Settings"
if [ ! -d "$PREFS_DIR" ]; then
    check_warning "Photoshop-Einstellungen noch nicht erstellt (normal vor erstem Start)"
else
    check_ok "Photoshop-Einstellungen vorhanden"
fi

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "5. Analysiere Log-Dateien"
echo "─────────────────────────────────────────────────────────────"

# Check for logs in new structured location
LOG_DIR="$SCRIPT_DIR/logs"
if [ -d "$LOG_DIR" ]; then
    # Find most recent installation log
    INSTALL_LOG=$(find "$LOG_DIR" -name "Installation_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    ERROR_LOG=$(find "$LOG_DIR" -name "*_errors.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$INSTALL_LOG" ] && [ -f "$INSTALL_LOG" ]; then
        check_ok "Installations-Log gefunden: $(basename "$INSTALL_LOG")"
        LOG_FILE="$INSTALL_LOG"
    elif [ -n "$ERROR_LOG" ] && [ -f "$ERROR_LOG" ]; then
        check_ok "Fehler-Log gefunden: $(basename "$ERROR_LOG")"
        LOG_FILE="$ERROR_LOG"
    fi
fi

if [ -f "$LOG_FILE" ]; then
    check_ok "Log-Datei gefunden: $LOG_FILE"
    
    # Suche nach häufigen Fehlermeldungen
    echo ""
    echo "Suche nach bekannten Fehlern in Logs..."
    
    if grep -q "VCRUNTIME140.dll\|vcrun" "$LOG_FILE" 2>/dev/null; then
        check_error "VCRUNTIME140.dll Fehler in Logs gefunden"
        echo "        → Lösung: WINEPREFIX=$WINE_PREFIX winetricks vcrun2015"
    fi
    
    if grep -q "d3d11" "$LOG_FILE" 2>/dev/null; then
        check_warning "DirectX 11 Warnungen gefunden (GPU-Probleme möglich)"
        echo "        → Lösung: GPU-Beschleunigung in Photoshop deaktivieren"
    fi
    
    if grep -q "X Error\|X11" "$LOG_FILE" 2>/dev/null; then
        check_warning "X11 Fehler gefunden (Grafik-Probleme möglich)"
        echo "        → Lösung: Virtual Desktop in winecfg aktivieren"
    fi
    
    # Zeige letzte Fehler
    echo ""
    echo "Letzte 10 Fehlerzeilen aus Logs:"
    echo "─────────────────────────────────────────────────────────────"
    grep -i "error\|err:" "$LOG_FILE" 2>/dev/null | tail -n 10 | while read -r line; do
        echo "  $line"
    done || echo "  (Keine Fehler gefunden)"
else
    check_warning "Keine Log-Datei gefunden (normal vor erstem Start)"
    if [ -d "$LOG_DIR" ]; then
        echo "        → Log-Verzeichnis: $LOG_DIR"
        echo "        → Verfügbare Logs:"
        ls -1 "$LOG_DIR"/*.log 2>/dev/null | head -5 | while read -r log; do
            echo "          - $(basename "$log")"
        done || echo "          (Keine Logs gefunden)"
    fi
fi

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "6. Performance-Check"
echo "─────────────────────────────────────────────────────────────"

# Check available RAM (force C locale for consistent output)
TOTAL_RAM_MB=$(LC_ALL=C free -m | awk '/^Mem:/{print $2}')
# Only calculate if we got a valid number
if [ -n "$TOTAL_RAM_MB" ] && [ "$TOTAL_RAM_MB" -gt 0 ]; then
    TOTAL_RAM=$(( (TOTAL_RAM_MB + 1023) / 1024 ))  # Ceiling division: round up to nearest GB
    [ $TOTAL_RAM -eq 0 ] && TOTAL_RAM=1  # Minimum 1GB display
else
    TOTAL_RAM=""  # Mark as unknown if detection failed
fi

if [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -ge 8 ]; then
    check_ok "RAM: ${TOTAL_RAM}GB (Ausreichend)"
elif [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -ge 4 ]; then
    check_warning "RAM: ${TOTAL_RAM}GB (Minimum, 8GB empfohlen)"
elif [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -gt 0 ]; then
    check_error "RAM: ${TOTAL_RAM}GB (Zu wenig! Mindestens 4GB benötigt)"
else
    check_warning "RAM konnte nicht ermittelt werden"
fi

# Check available disk space (force C locale for consistent output)
AVAILABLE_SPACE=$(LC_ALL=C df -h "$HOME" | awk 'NR==2 {print $4}')
check_ok "Verfügbarer Speicherplatz in /home: $AVAILABLE_SPACE"

# Check GPU
if command -v lspci &> /dev/null; then
    GPU_INFO=$(lspci | grep -i vga | cut -d: -f3)
    if [ -n "$GPU_INFO" ]; then
        check_ok "Grafikkarte:$GPU_INFO"
        
        # Check for Nvidia
        if echo "$GPU_INFO" | grep -iq "nvidia"; then
            if command -v nvidia-smi &> /dev/null; then
                check_ok "Nvidia-Treiber installiert"
            else
                check_warning "Nvidia-Karte erkannt, aber nvidia-smi nicht verfügbar"
                echo "        → Installiere Nvidia-Treiber für beste Performance"
            fi
        fi
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    DIAGNOSE ZUSAMMENFASSUNG"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ Keine Probleme gefunden! Photoshop sollte funktionieren.${NC}"
    echo ""
    echo "Starte Photoshop mit:"
    echo "  photoshop"
    echo ""
    echo "Bei Problemen beim Start:"
    echo "  1. GPU-Beschleunigung deaktivieren (Strg+K in Photoshop)"
    echo "  2. Siehe README.de.md für weitere Tipps"
elif [ $ISSUES_FIXED -gt 0 ]; then
    echo -e "${GREEN}✓ $ISSUES_FIXED Problem(e) wurden behoben!${NC}"
    echo -e "${YELLOW}⚠ $((ISSUES_FOUND - ISSUES_FIXED)) Problem(e) benötigen manuelle Behebung${NC}"
else
    echo -e "${YELLOW}⚠ $ISSUES_FOUND Problem(e) gefunden!${NC}"
    echo ""
    echo "Bitte behebe die oben aufgeführten Probleme."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    SCHNELL-FIXES"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. GPU-Probleme (häufigster Fehler):"
echo "   → In Photoshop: Bearbeiten > Voreinstellungen > Leistung"
echo "   → Deaktiviere 'Grafikprozessor verwenden'"
echo ""
echo "2. VCRUNTIME140.dll fehlt:"
echo "   → WINEPREFIX=$WINE_PREFIX winetricks vcrun2015"
echo ""
echo "3. Photoshop startet nicht:"
if [ -f "$LOG_FILE" ]; then
echo "   → Prüfe Logs: tail -n 50 $LOG_FILE"
else
    echo "   → Prüfe Logs: tail -n 50 $LOG_DIR/*.log"
fi
echo "   → Versuche: WINEPREFIX=$WINE_PREFIX winecfg"
echo "   → Setze Windows-Version auf Windows 10"
echo ""
echo "4. Wine neu konfigurieren:"
echo "   → cd <projekt-verzeichnis>"
echo "   → ./setup.sh → Option 3"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Weitere Hilfe: README.de.md oder GitHub Issues"
echo "https://github.com/Gictorbit/photoshopCClinux/issues"
echo ""

# Return to main menu
echo ""
read -p "Drücke Enter, um zum Hauptmenü zurückzukehren... " dummy
exit 0

