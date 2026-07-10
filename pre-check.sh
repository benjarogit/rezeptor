#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Pre-Installation Check
#
# Description:
#   Validates system requirements before installation including Wine version,
#   required packages, disk space, and local installation files.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
export PROJECT_ROOT
# shellcheck source=core/paths.sh
source "$PROJECT_ROOT/core/paths.sh"
export SCR_PATH="${SCR_PATH:-$(recipe_data_root photoshop)}"
export WINE_SOFTWARE_BASE="$(wine_software_base)"
if [ -f "$PROJECT_ROOT/core/system.sh" ]; then
    # shellcheck source=core/system.sh
    source "$PROJECT_ROOT/core/system.sh"
else
    echo "ERROR: core/system.sh fehlt" >&2
    exit 1
fi
if [ -f "$PROJECT_ROOT/core/wine-runtime.sh" ]; then
    # shellcheck source=core/wine-runtime.sh
    source "$PROJECT_ROOT/core/wine-runtime.sh"
fi

echo "═══════════════════════════════════════════════════════════════"
echo "    Photoshop CC - Pre-Installation Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

REZEPTOR_MODE=0
for _arg in "$@"; do
    case "$_arg" in
        --rezeptor) REZEPTOR_MODE=1 ;;
    esac
done

check_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((CHECKS_PASSED++))
}

check_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((CHECKS_FAILED++))
}

check_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    ((CHECKS_WARNING++))
}

echo "Überprüfe System-Voraussetzungen..."
echo ""

# Check 1: 64-bit System
echo "1. Überprüfe System-Architektur..."
if [ "$(uname -m)" == "x86_64" ]; then
    check_ok "64-bit System (x86_64)"
else
    check_error "Kein 64-bit System! Photoshop benötigt x86_64"
fi
echo ""

# Check 2: Required Packages / Runtime
echo "2. Überprüfe erforderliche Pakete / Runtime..."

IMMUTABLE_HINT=""
if type system::is_immutable >/dev/null 2>&1 && system::is_immutable; then
    IMMUTABLE_HINT=1
    check_warning "Immutable Distribution erkannt — AppImage empfohlen (kein sudo pacman/dnf nötig)"
fi

RUNTIME_OK=0
if type wine_runtime::init >/dev/null 2>&1 && wine_runtime::init 2>/dev/null; then
    check_ok "Proton-GE Runtime: $(wine_runtime::describe 2>/dev/null || echo OK)"
    RUNTIME_OK=1
else
    if [ -n "$IMMUTABLE_HINT" ]; then
        check_warning "Proton-GE noch nicht vorhanden — wird beim ersten Start nach $(wine_software_runtime_dir) geladen"
    else
        check_warning "Proton-GE noch nicht vorhanden — Setup lädt Runtime nach $(wine_software_runtime_dir)"
    fi
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        check_ok "Download-Tools für Proton-GE verfügbar"
        RUNTIME_OK=1
    else
        check_error "curl oder wget benötigt für Proton-GE Download"
    fi
fi

if command -v winetricks &> /dev/null; then
    check_ok "winetricks installiert"
elif [ "$RUNTIME_OK" -eq 1 ]; then
    check_warning "winetricks nicht system-weit — Setup nutzt Runtime/winetricks falls gebündelt"
else
    check_error "winetricks nicht installiert"
    echo "   Installiere mit: sudo pacman -S winetricks"
fi

if command -v md5sum &> /dev/null; then
    check_ok "md5sum verfügbar"
else
    check_warning "md5sum nicht gefunden (normalerweise unkritisch)"
fi
echo ""

# Check 3: Disk Space
echo "3. Überprüfe verfügbaren Speicherplatz..."
# Force C locale for consistent output
HOME_SPACE=$(LC_ALL=C df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')

if [ "$HOME_SPACE" -ge 5 ]; then
    check_ok "Ausreichend Speicherplatz: ${HOME_SPACE}GB verfügbar (5GB benötigt)"
else
    check_error "Nicht genug Speicherplatz: ${HOME_SPACE}GB verfügbar (5GB benötigt)"
fi
echo ""

# Check 4: RAM
echo "4. Überprüfe Arbeitsspeicher..."
# Force C locale for consistent output across all languages
TOTAL_RAM_MB=$(LC_ALL=C free -m | awk '/^Mem:/{print $2}')
# Only calculate if we got a valid number
if [ -n "$TOTAL_RAM_MB" ] && [ "$TOTAL_RAM_MB" -gt 0 ]; then
    TOTAL_RAM=$(( (TOTAL_RAM_MB + 1023) / 1024 ))  # Ceiling division: round up to nearest GB
    [ $TOTAL_RAM -eq 0 ] && TOTAL_RAM=1  # Minimum 1GB display
else
    TOTAL_RAM=""  # Mark as unknown if detection failed
fi

if [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -ge 8 ]; then
    check_ok "RAM: ${TOTAL_RAM}GB (Optimal für Photoshop)"
elif [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -ge 4 ]; then
    check_warning "RAM: ${TOTAL_RAM}GB (Funktioniert, aber 8GB empfohlen)"
elif [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -gt 0 ]; then
    check_error "RAM: ${TOTAL_RAM}GB (Zu wenig! Mindestens 4GB benötigt)"
else
    check_warning "RAM konnte nicht ermittelt werden"
fi
echo ""

# Check 5: Installation Files
echo "5. Überprüfe lokale Installationsdateien..."
# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
PHOTOSHOP_INSTALLER="$PROJECT_ROOT/photoshop/Set-up.exe"

if [ -f "$PHOTOSHOP_INSTALLER" ]; then
    check_ok "Photoshop Installer gefunden: Set-up.exe"
    
    # Check size (force C locale for consistent output)
    INSTALLER_SIZE=$(LC_ALL=C du -h "$PHOTOSHOP_INSTALLER" | cut -f1)
    echo "   Größe: $INSTALLER_SIZE"
    
    # Check if packages exist
    PACKAGES_DIR="$PROJECT_ROOT/photoshop/packages"
    if [ -d "$PACKAGES_DIR" ]; then
        PACKAGE_COUNT=$(find "$PACKAGES_DIR" -type f | wc -l)
        check_ok "Installations-Pakete gefunden ($PACKAGE_COUNT Dateien)"
    else
        check_error "Packages-Verzeichnis fehlt: $PACKAGES_DIR"
    fi
    
    # Check if products exist
    PRODUCTS_DIR="$PROJECT_ROOT/photoshop/products"
    if [ -d "$PRODUCTS_DIR" ]; then
        PRODUCTS_COUNT=$(find "$PRODUCTS_DIR" -type f -name "*.zip" | wc -l)
        check_ok "Produkt-Dateien gefunden ($PRODUCTS_COUNT ZIP-Archive)"
    else
        check_error "Products-Verzeichnis fehlt: $PRODUCTS_DIR"
    fi
else
    check_error "Photoshop Installer nicht gefunden: $PHOTOSHOP_INSTALLER"
fi
echo ""

# Check 6: Internet Connection
echo "6. Überprüfe Internet-Verbindung..."
if ping -c 1 -W 2 google.com &> /dev/null; then
    if [ "$REZEPTOR_MODE" -eq 1 ]; then
        check_ok "Internet aktiv (Rezeptor/WISO — kein Trennen nötig)"
        echo -e "   ${BLUE}Hinweis: Nur bei Adobe-Photoshop-Installation optional WLAN aus.${NC}"
    else
        check_warning "Internet-Verbindung aktiv"
        echo -e "   ${YELLOW}EMPFEHLUNG (nur Photoshop-Install): Internet kurz deaktivieren${NC}"
        echo ""

        # Nur bei explizitem J — niemals standardmäßig trennen
        if command -v nmcli &> /dev/null; then
            echo -e "   ${BLUE}Netzwerk JETZT deaktivieren? [j/N]${NC}"
            read -p "   Deine Wahl: " -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[JjYy]$ ]]; then
                echo "   Deaktiviere Verbindungen..."
                active_connections=$(nmcli -t -f NAME,STATE connection show | grep ":activated" | cut -d: -f1 | grep -v "^lo$")

                if [ -n "$active_connections" ]; then
                    echo "$active_connections" > /tmp/.photoshop_disabled_connections

                    while IFS= read -r conn; do
                        if [ -n "$conn" ]; then
                            nmcli connection down "$conn" &> /dev/null
                            echo "     ✓ $conn deaktiviert"
                        fi
                    done <<< "$active_connections"
                    echo ""
                    check_ok "Verbindungen deaktiviert (nur für Photoshop-Setup)"
                fi
            else
                echo -e "   ${GREEN}Internet bleibt aktiv.${NC}"
            fi
        else
            echo "   Manuell (nur Photoshop): nmcli connection down <name>"
        fi
    fi
else
    check_ok "Keine Internet-Verbindung"
fi
echo ""

# Check 7: Graphics Card
echo "7. Überprüfe Grafikkarte..."
if command -v lspci &> /dev/null; then
    GPU_INFO=$(lspci | grep -i vga | cut -d: -f3 | xargs)
    
    if [ -n "$GPU_INFO" ]; then
        echo "   Gefunden:$GPU_INFO"
        
        # Check for Nvidia
        if echo "$GPU_INFO" | grep -iq "nvidia"; then
            if command -v nvidia-smi &> /dev/null; then
                check_ok "Nvidia-Treiber installiert"
            else
                check_warning "Nvidia-Karte ohne nvidia-smi (proprietärer Treiber empfohlen)"
            fi
        # Check for AMD
        elif echo "$GPU_INFO" | grep -iq "amd\|radeon"; then
            check_ok "AMD Grafikkarte erkannt"
        # Check for Intel
        elif echo "$GPU_INFO" | grep -iq "intel"; then
            check_ok "Intel Grafik erkannt"
        fi
    fi
else
    check_warning "lspci nicht verfügbar, kann Grafikkarte nicht prüfen"
fi
echo ""

# Check 8: Previous Installation
echo "8. Überprüfe auf vorherige Installationen..."
# Check both old and new paths for compatibility
OLD_PATH="$HOME/.photoshopCCV19"
NEW_PATH="$HOME/.local/share/wine-software/photoshop"
LEGACY_PATH="$HOME/.photoshop"
FOUND_INSTALLATION=""

if [ -d "$NEW_PATH/prefix" ] || [ -d "$NEW_PATH" ]; then
    FOUND_INSTALLATION="$NEW_PATH"
    check_warning "Vorherige Installation gefunden in $NEW_PATH"
    echo "   ${YELLOW}Die Installation kann das Prefix überschreiben!${NC}"
elif [ -d "$LEGACY_PATH" ]; then
    FOUND_INSTALLATION="$LEGACY_PATH"
    check_warning "Legacy-Installation in ~/.photoshop (nicht mehr verwendet)"
    echo "   ${BLUE}Neue Daten liegen unter ~/.local/share/wine-software/photoshop${NC}"
elif [ -d "$OLD_PATH" ]; then
    FOUND_INSTALLATION="$OLD_PATH"
    check_warning "Vorherige Installation gefunden in ~/.photoshopCCV19 (alte Version)"
    echo "   ${YELLOW}Die Installation wird das Verzeichnis überschreiben!${NC}"
    echo "   Backup erstellen? Befehl: mv ~/.photoshopCCV19 ~/.photoshopCCV19.backup"
    echo "   ${BLUE}Hinweis: Neue Installationen liegen unter ~/.local/share/wine-software/photoshop${NC}"
else
    check_ok "Keine vorherige Installation gefunden"
fi
echo ""

# Check 9: Required Scripts
echo "9. Überprüfe Installations-Scripts..."
REQUIRED_SCRIPTS=(
    "recipes/photoshop/install.sh"
    "recipes/photoshop/launch.sh"
    "recipes/photoshop/validate.sh"
    "core/wine-runtime.sh"
    "launcher/launcher.py"
    "setup.sh"
)

ALL_SCRIPTS_OK=true
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$PROJECT_ROOT/$script" ]; then
        check_ok "Script gefunden: $script"
    else
        check_error "Script fehlt: $script"
        ALL_SCRIPTS_OK=false
    fi
done
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════"
echo "                    ZUSAMMENFASSUNG"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo -e "Bestanden: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Warnungen: ${YELLOW}$CHECKS_WARNING${NC}"
echo -e "Fehler:    ${RED}$CHECKS_FAILED${NC}"
echo ""

echo ""

# Check: PyQt6 (required launcher)
echo "PyQt6 Launcher..."
if python3 -c "import PyQt6" 2>/dev/null; then
    check_ok "PyQt6 installiert (Launcher)"
else
    check_error "PyQt6 fehlt — Launcher benötigt python-pyqt6"
    echo "   Arch/CachyOS: sudo pacman -S python-pyqt6"
    echo "   Debian/Ubuntu: sudo apt install python3-pyqt6"
fi
echo ""

if [ "$REZEPTOR_MODE" -eq 1 ]; then
    echo "Wine-Dialoge (Install/Reparatur)..."
    check_ok "Kurz Wine-Fenster möglich — Rezeptor zeigt, was zu klicken ist (OK / Installieren)"
    echo ""
fi

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Alle kritischen Checks bestanden!${NC}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                BEREIT FÜR INSTALLATION!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Nächste Schritte:"
    echo ""
    echo "1. Internet deaktivieren (optional, nur Adobe-Photoshop-Install):"
    echo -e "   ${BLUE}nmcli radio wifi off${NC}"
    echo ""
    echo "2. Launcher starten:"
    echo -e "   ${BLUE}./setup.sh${NC}"
    echo ""
    echo "3. Recipe 'photoshop' wählen → Install"
    echo ""
    echo "4. Im Adobe Setup:"
    echo "   - 'Installieren' wählen"
    echo "   - Standard-Pfad beibehalten"
    echo "   - Sprache wählen (z.B. de_DE)"
    echo "   - 10-20 Minuten warten"
    echo ""
    echo "5. Nach Installation Internet wieder aktivieren:"
    echo -e "   ${BLUE}nmcli radio wifi on${NC}"
    echo ""
    
    if [ $CHECKS_WARNING -gt 0 ]; then
        echo "⚠ HINWEISE zu den Warnungen:"
        echo ""
        
        if [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -gt 0 ] && [ "$TOTAL_RAM" -lt 8 ]; then
            echo "• RAM: Mit ${TOTAL_RAM}GB funktioniert Photoshop, aber größere"
            echo "  Dateien können langsam sein. 8GB sind optimal."
            echo ""
        fi
        
        if ping -c 1 -W 2 google.com &> /dev/null; then
            echo "• Internet: Bitte deaktiviere die Internet-Verbindung"
            echo "  für eine problemlose Installation ohne Adobe-Login."
            echo ""
        fi
        
        if [ -n "$FOUND_INSTALLATION" ]; then
            echo "• Vorherige Installation: Das Verzeichnis $FOUND_INSTALLATION wird"
            echo "  überschrieben. Erstelle ein Backup falls nötig."
            echo ""
        fi
    fi
    
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "📖 Vollständige Anleitung: README.de.md"
    echo "🚀 Schnellstart: SCHNELLSTART.md"
    echo ""
    
    exit 0
else
    echo -e "${RED}✗ Es wurden kritische Fehler gefunden!${NC}"
    echo ""
    echo "Bitte behebe die oben aufgeführten Fehler, bevor du fortfährst."
    echo ""
    
    if ! python3 -c "import PyQt6" 2>/dev/null; then
        echo "═══════════════════════════════════════════════════════════════"
        echo "PYQT6 FEHLT (Launcher-Pflicht):"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "  sudo pacman -S python-pyqt6"
        echo ""
    fi

    if ! command -v winetricks &> /dev/null && [ "$RUNTIME_OK" -eq 0 ]; then
        echo "═══════════════════════════════════════════════════════════════"
        echo "WINETRICKS EMPFOHLEN:"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "  sudo pacman -S winetricks"
        echo ""
    fi

    if [ ! -f "$PHOTOSHOP_INSTALLER" ]; then
        echo "═══════════════════════════════════════════════════════════════"
        echo "PHOTOSHOP INSTALLATIONSDATEIEN FEHLEN:"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Stelle sicher, dass sich die Photoshop-Dateien im richtigen"
        echo "Verzeichnis befinden:"
        echo ""
        echo "  $PHOTOSHOP_INSTALLER"
        echo ""
        echo "Die Struktur sollte sein:"
        echo "  photoshop/"
        echo "  ├── Set-up.exe"
        echo "  ├── packages/"
        echo "  └── products/"
        echo ""
    fi
    
    exit 1
fi




