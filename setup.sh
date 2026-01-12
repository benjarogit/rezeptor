#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux Installer - Main Setup Script
#
# Description:
#   Interactive menu system for installing and managing Adobe Photoshop CC
#   on Linux using Wine. Supports multi-language (English/German) interface
#   with ANSI colored banner display.
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

# KRITISCH: Robuste Fehlerbehandlung aktivieren
# set -e: Exit bei Fehlern
# set -u: Exit bei undefinierten Variablen
# set -o pipefail: Exit bei Pipeline-Fehlern
# BusyBox-Kompatibilität: pipefail kann fehlen, daher || true
set -eu
(set -o pipefail 2>/dev/null) || true

# Locale/UTF-8 für DE/EN sicherstellen (mit Prüfung auf existierende Locale)
# KRITISCH: Prüfe ob Locale existiert (Alpine hat oft nur C.UTF-8)
if command -v locale >/dev/null 2>&1; then
    if locale -a 2>/dev/null | grep -qE "^(de_DE|de_DE\.utf8|de_DE\.UTF-8)$"; then
        export LANG="${LANG:-de_DE.UTF-8}"
    elif locale -a 2>/dev/null | grep -qE "^(C\.utf8|C\.UTF-8)$"; then
        export LANG="${LANG:-C.UTF-8}"
    else
        export LANG="${LANG:-C}"
    fi
else
    # Fallback wenn locale nicht verfügbar
    export LANG="${LANG:-C.UTF-8}"
fi
export LC_ALL="${LC_ALL:-$LANG}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source security module for input validation
if [ -f "$SCRIPT_DIR/scripts/security.sh" ]; then
    source "$SCRIPT_DIR/scripts/security.sh"
fi

# Load update module for version checking
if [ -f "$SCRIPT_DIR/scripts/update.sh" ]; then
    source "$SCRIPT_DIR/scripts/update.sh"
    # Initialize VERSION file if it doesn't exist (non-blocking, silent on error)
    if type update::init_version_file >/dev/null 2>&1; then
        update::init_version_file 2>/dev/null || true
    fi
fi

# Set PROJECT_ROOT for functions that need it (like detect_photoshop_version)
export PROJECT_ROOT="$SCRIPT_DIR"

# Initialize LANG_CODE (will be set by detect_language if not already set)
LANG_CODE="${LANG_CODE:-}"

# ANSI Color codes (initialize globally for use throughout script)
# CRITICAL: Must be initialized before any function uses them
if [ -t 1 ] && [ "$TERM" != "dumb" ]; then
    C_RESET="\033[0m"
    C_CYAN="\033[0;36;1m"
    C_MAGENTA="\033[0;35;1m"
    C_BLUE="\033[0;34;1m"
    C_BLUE_LIGHT="\033[1;34m"  # Helles Blau für PS-Logo
    C_YELLOW="\033[0;33;1m"
    C_WHITE="\033[0;37;1m"
    C_GREEN="\033[0;32;1m"
    C_GRAY="\033[0;37m"
    C_RED="\033[1;31m"
    C_BRACKET="\033[0;90m"  # Dunkles Grau für Klammern
else
    C_RESET=""
    C_CYAN=""
    C_MAGENTA=""
    C_BLUE=""
    C_BLUE_LIGHT=""
    C_YELLOW=""
    C_WHITE=""
    C_GREEN=""
    C_GRAY=""
    C_RED=""
    C_BRACKET=""
fi

# Detect system language (only if not already set by user)
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
msg_choose_option() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "[Wähle eine Option]$ "
    else
        echo "[choose an option]$ "
    fi
}

msg_run_photoshop() {
    # Silent - PhotoshopSetup.sh will show proper headers
    # Don't show redundant messages here
    :
}

msg_run_camera_raw() {
    if [ "$LANG_CODE" = "de" ]; then
        echo -n "Starte Adobe Camera Raw Installer"
    else
        echo -n "run adobe camera Raw installer"
    fi
}

msg_run_winecfg() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "Starte winecfg..."
        echo -n "Öffne virtuelles Laufwerk Konfiguration..."
    else
        echo "run winecfg..."
        echo -n "open virtualdrive configuration..."
    fi
}

msg_uninstall() {
    if [ "$LANG_CODE" = "de" ]; then
        echo -ne "${C_YELLOW}→${C_RESET} ${C_MAGENTA}Deinstalliere Photoshop ...${C_RESET}"
    else
        echo -n "uninstall photoshop CC ..."
    fi
}

msg_pre_check() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "Starte System-Vorprüfung..."
    else
        echo "run pre-installation check..."
    fi
}

msg_troubleshoot() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "Starte Fehlerbehebung..."
    else
        echo "run troubleshooting..."
    fi
}

msg_exit() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "Setup beenden..."
    else
        echo "exit setup..."
    fi
}

msg_goodbye() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "Auf Wiedersehen :)"
    else
        echo "Good Bye :)"
    fi
}

msg_found() {
    if [ "$LANG_CODE" = "de" ]; then
        echo "$1 gefunden..."
    else
        echo "$1 Found..."
    fi
}

msg_not_found() {
    if [ "$LANG_CODE" = "de" ]; then
        error "$1 nicht gefunden..."
    else
        error "$1 not Found..."
    fi
}

msg_banner_not_found() {
    if [ "$LANG_CODE" = "de" ]; then
        error "Banner nicht gefunden..."
    else
        error "banner not Found..."
    fi
}

function show_uninstall_menu() {
    local uninstall_choice=""
    
    while true; do
        clear && echo ""
        
        if [ "$LANG_CODE" = "de" ]; then
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_CYAN}            Photoshop Deinstallation & Prozess-Killer${C_RESET}"
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo ""
            echo -e "  ${C_YELLOW}[1]${C_RESET} ${C_WHITE}Photoshop deinstallieren${C_RESET}"
            echo -e "  ${C_YELLOW}[2]${C_RESET} ${C_RED}Photoshop Prozesse zwangsweise beenden${C_RESET}"
            echo -e "  ${C_YELLOW}[3]${C_RESET} ${C_WHITE}Zurück zum Hauptmenü${C_RESET}"
            echo ""
            IFS= read -r -p "$(echo -e "${C_CYAN}Wähle eine Option [1-3]:${C_RESET} ") " uninstall_choice
            # CRITICAL: Sanitize and validate user input
            if type security::sanitize_input >/dev/null 2>&1; then
                uninstall_choice=$(security::sanitize_input "$uninstall_choice")
            fi
            # Validate input is 1-3
            if [[ ! "$uninstall_choice" =~ ^[1-3]$ ]]; then
                echo -e "${C_RED}Ungültige Eingabe. Bitte wähle 1, 2 oder 3.${C_RESET}"
                sleep 1
                continue
            fi
        else
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_CYAN}            Photoshop Uninstall & Process Killer${C_RESET}"
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo ""
            echo -e "  ${C_YELLOW}[1]${C_RESET} ${C_WHITE}Uninstall Photoshop${C_RESET}"
            echo -e "  ${C_YELLOW}[2]${C_RESET} ${C_RED}Force kill Photoshop processes${C_RESET}"
            echo -e "  ${C_YELLOW}[3]${C_RESET} ${C_WHITE}Back to main menu${C_RESET}"
            echo ""
            IFS= read -r -p "$(echo -e "${C_CYAN}Choose an option [1-3]:${C_RESET} ") " uninstall_choice
            # CRITICAL: Sanitize and validate user input
            if type security::sanitize_input >/dev/null 2>&1; then
                uninstall_choice=$(security::sanitize_input "$uninstall_choice")
            fi
            # Validate input is 1-3
            if [[ ! "$uninstall_choice" =~ ^[1-3]$ ]]; then
                echo -e "${C_RED}Invalid input. Please choose 1, 2, or 3.${C_RESET}"
                sleep 1
                continue
            fi
        fi
        
        # Valid input received, break out of loop
        break
    done
    
    case "$uninstall_choice" in
        1)
            msg_uninstall
            run_script "scripts/uninstaller.sh" "uninstaller.sh"
            wait_second 2
            main
            ;;
        2)
            if [ "$LANG_CODE" = "de" ]; then
                echo -e "${C_YELLOW}→${C_RESET} ${C_RED}Beende Photoshop Prozesse zwangsweise...${C_RESET}"
            else
                echo -e "${C_YELLOW}→${C_RESET} ${C_RED}Force killing Photoshop processes...${C_RESET}"
            fi
            run_script "scripts/kill-photoshop.sh" "kill-photoshop.sh"
            wait_second 2
            main
            ;;
        3|"")
            main
            ;;
        *)
            if [ "$LANG_CODE" = "de" ]; then
                warning "Ungültige Auswahl. Zurück zum Hauptmenü..."
            else
                warning "Invalid selection. Returning to main menu..."
            fi
            wait_second 2
            main
            ;;
    esac
}

# ============================================================================
# @function show_install_or_update_menu
# @description Show menu to choose between install or update
# ============================================================================
show_install_or_update_menu() {
    # IMMER Frage stellen, ob installieren oder updaten
    local choice=""
    while true; do
        clear && echo ""
        if [ "$LANG_CODE" = "de" ]; then
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_CYAN}            Photoshop Installieren oder Updaten?${C_RESET}"
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo ""
            echo -e "  ${C_YELLOW}[1]${C_RESET} ${C_WHITE}Photoshop installieren${C_RESET}"
            echo -e "  ${C_YELLOW}[2]${C_RESET} ${C_GREEN}Photoshop updaten${C_RESET}"
            echo -e "  ${C_YELLOW}[3]${C_RESET} ${C_WHITE}Zurück zum Hauptmenü${C_RESET}"
            echo ""
            IFS= read -r -p "$(echo -e "${C_CYAN}Wähle eine Option [1-3]:${C_RESET} ") " choice
        else
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_CYAN}            Install or Update Photoshop?${C_RESET}"
            echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
            echo ""
            echo -e "  ${C_YELLOW}[1]${C_RESET} ${C_WHITE}Install Photoshop${C_RESET}"
            echo -e "  ${C_YELLOW}[2]${C_RESET} ${C_GREEN}Update Photoshop${C_RESET}"
            echo -e "  ${C_YELLOW}[3]${C_RESET} ${C_WHITE}Back to main menu${C_RESET}"
            echo ""
            IFS= read -r -p "$(echo -e "${C_CYAN}Choose an option [1-3]:${C_RESET} ") " choice
        fi
        
        # Sanitize input
        if type security::sanitize_input >/dev/null 2>&1; then
            choice=$(security::sanitize_input "$choice")
        fi
        
        # Validate input
        if [[ ! "$choice" =~ ^[1-3]$ ]]; then
            if [ "$LANG_CODE" = "de" ]; then
                echo -e "${C_RED}Ungültige Eingabe. Bitte wähle 1, 2 oder 3.${C_RESET}"
            else
                echo -e "${C_RED}Invalid input. Please choose 1, 2, or 3.${C_RESET}"
            fi
            sleep 1
            continue
        fi
        
        break
    done
    
    case "$choice" in
        1)
            # Install
            show_wine_selection_menu
            ;;
        2)
            # Update
            if [ "$LANG_CODE" = "de" ]; then
                echo "Starte Update..."
            else
                echo "Starting update..."
            fi
            
            # Try git pull if in git repository
            if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
                if git pull origin main 2>/dev/null || git pull origin master 2>/dev/null; then
                    # Update VERSION file with latest GitHub release version
                    # Load update module if not already loaded
                    if ! type update::update_version_file >/dev/null 2>&1; then
                        if [ -f "$SCRIPT_DIR/scripts/update.sh" ]; then
                            source "$SCRIPT_DIR/scripts/update.sh" 2>/dev/null || true
                        fi
                    fi
                    
                    # Update VERSION file if function is available
                    if type update::update_version_file >/dev/null 2>&1; then
                        if ! update::update_version_file 2>/dev/null; then
                            # Warning but don't fail - git pull was successful
                            # Use simple echo since this is non-critical
                            if [ "$LANG_CODE" = "de" ]; then
                                echo -e "${C_YELLOW}⚠ Hinweis: VERSION-Datei konnte nicht aktualisiert werden, aber Update war erfolgreich${C_RESET}" >&2
                            else
                                echo -e "${C_YELLOW}⚠ Note: Could not update VERSION file, but update was successful${C_RESET}" >&2
                            fi
                        fi
                    fi
                    
                    if [ "$LANG_CODE" = "de" ]; then
                        echo -e "${C_GREEN}Update erfolgreich!${C_RESET}"
                    else
                        echo -e "${C_GREEN}Update successful!${C_RESET}"
                    fi
                    wait_second 2
                    main
                    return 0
                fi
            fi
            
            # If git pull failed or not in git repo, show manual instructions
            if [ "$LANG_CODE" = "de" ]; then
                echo ""
                echo -e "${C_YELLOW}Git-Update nicht möglich. Bitte manuell updaten:${C_RESET}"
                echo "1. Gehe zu: https://github.com/benjarogit/photoshopCClinux/releases"
                echo "2. Lade die neueste Version herunter"
                echo "3. Ersetze die Dateien im Projekt-Verzeichnis"
            else
                echo ""
                echo -e "${C_YELLOW}Git update not possible. Please update manually:${C_RESET}"
                echo "1. Go to: https://github.com/benjarogit/photoshopCClinux/releases"
                echo "2. Download the latest version"
                echo "3. Replace files in project directory"
            fi
            wait_second 5
            main
            ;;
        3|"")
            main
            ;;
    esac
}

function show_wine_selection_menu() {
    # Direkt zur Installation mit Wine Standard
    msg_run_photoshop
    # Export RETURN_TO_MENU so PhotoshopSetup.sh knows to return to menu
    export RETURN_TO_MENU="true"
    run_script "$SCRIPT_DIR/scripts/PhotoshopSetup.sh" "PhotoshopSetup.sh" --wine-standard
    local exit_code=$?
    unset RETURN_TO_MENU
    # Exit code 130 = STRG+C (user interrupt) - return to main menu
    # Exit code 0 = successful installation - return to main menu
    if [ $exit_code -eq 130 ] || [ $exit_code -eq 0 ]; then
        if [ $exit_code -eq 130 ]; then
            if [ "$LANG_CODE" = "de" ]; then
                echo ""
                echo "Installation abgebrochen. Zurück zum Hauptmenü..."
            else
                echo ""
                echo "Installation cancelled. Returning to main menu..."
            fi
        fi
        wait_second 2
        main
    fi
}

function main() {
    # Detect language
    detect_language
    
    #print banner
    banner

    #read inputs
    read_input
    local answer="${CHOICE:-}"  # Use empty string if CHOICE is not set

    case "$answer" in

    1)  
        # Show Install/Update menu
        show_install_or_update_menu
        ;;
    2)  
        msg_run_camera_raw
        export RETURN_TO_MENU="true"
        run_script "scripts/cameraRawInstaller.sh" "cameraRawInstaller.sh"
        local exit_code=$?
        unset RETURN_TO_MENU
        wait_second 2
        main
        ;;
    3)  
        msg_pre_check
        # Pre-check is in root directory - use script directory
        local precheck_path="$SCRIPT_DIR/pre-check.sh"
        if [ -f "$precheck_path" ]; then
            chmod +x "$precheck_path"
            bash "$precheck_path"
        else
            error "pre-check.sh not found at $precheck_path"
        fi
        wait_second 2
        main
        ;;
    4)  
        msg_troubleshoot
        # Troubleshoot is in root directory - use script directory
        export RETURN_TO_MENU="true"
        local troubleshoot_path="$SCRIPT_DIR/troubleshoot.sh"
        if [ -f "$troubleshoot_path" ]; then
            chmod +x "$troubleshoot_path"
            bash "$troubleshoot_path"
        else
            error "troubleshoot.sh not found at $troubleshoot_path"
        fi
        unset RETURN_TO_MENU
        wait_second 2
        main
        ;;
    5)  
        msg_run_winecfg
        run_script "scripts/winecfg.sh" "winecfg.sh"
        wait_second 2
        main
        ;;
    6)  
        # Toggle Internet
        toggle_internet
        wait_second 2
        main
        ;;
    7)  
        # Toggle language
        if [ "$LANG_CODE" = "de" ]; then
            LANG_CODE="en"
            echo "Language switched to English"
        else
            LANG_CODE="de"
            echo "Sprache auf Deutsch umgestellt"
        fi
        
        wait_second 2
        main
        ;;
    8)  
        show_uninstall_menu
        ;;
    9)  
        msg_exit
        # GitHub-Seite automatisch öffnen beim Beenden
        if type open_url >/dev/null 2>&1; then
            open_url "https://github.com/benjarogit/photoshopCClinux" 2>/dev/null || true
        fi
        exitScript
        ;;
    esac
}

#arguments 1=script_path 2=script_name [additional args...]
function run_script() {
    local script_path=$1
    local script_name=$2
    shift 2  # Remove first two arguments, rest are passed to script

    wait_second 5
    
    # KRITISCH: File-System-Umleitung verhindern - verwende absoluten Pfad
    local absolute_script_path="$SCRIPT_DIR/scripts/$script_name"
    
    # Prüfe dass Script wirklich im erwarteten Verzeichnis ist
    if [[ "$absolute_script_path" != "$SCRIPT_DIR/scripts/"* ]]; then
        error "Script-Pfad außerhalb erwartetem Verzeichnis (Sicherheitsrisiko): $absolute_script_path"
        return 1
    fi
    
    if [ -f "$absolute_script_path" ];then
        # Silent - don't show "found" message to user (irrelevant info)
        chmod +x "$absolute_script_path"
    else
        msg_not_found "$script_name"
        return 1
    fi
    
    # KRITISCH: Führe Script mit absolutem Pfad aus (kein cd + relativer Name)
    bash "$absolute_script_path" "$@"
    local exit_code=$?
    
    unset script_path absolute_script_path
    return $exit_code  # Preserve the script's exit code
}

function toggle_internet() {
    if ! command -v nmcli &> /dev/null; then
        if [ "$LANG_CODE" = "de" ]; then
            warning "nmcli nicht gefunden - kann Internet nicht umschalten"
            echo "Manuell alle Verbindungen auflisten: nmcli connection show"
            echo "Manuell deaktivieren: nmcli connection down <name>"
        else
            warning "nmcli not found - cannot toggle internet"
            echo "Manual list connections: nmcli connection show"
            echo "Manual disable: nmcli connection down <name>"
        fi
        return 1
    fi
    
    # KRITISCH: mktemp statt vorhersagbarem Dateinamen (Sicherheit)
    local disabled_connections_file
    disabled_connections_file=$(mktemp "/tmp/.photoshop_disabled_connections.XXXXXX" 2>/dev/null) || {
        if [ "$LANG_CODE" = "de" ]; then
            warning "mktemp fehlgeschlagen - verwende Fallback"
        else
            warning "mktemp failed - using fallback"
        fi
        disabled_connections_file="/tmp/.photoshop_disabled_connections.$$"
    }
    
    # KRITISCH: TOCTOU-Schutz - prüfe dass tmp_file keine Symlink ist
    if [ -L "$disabled_connections_file" ]; then
        rm -f "$disabled_connections_file" 2>/dev/null || true
        error "Temporäre Datei ist Symlink (Sicherheitsrisiko)"
        return 1
    fi
    
    # KRITISCH: Cleanup bei allen Signalen (nicht nur EXIT) - verhindere Race-Conditions
    trap "rm -f '$disabled_connections_file' 2>/dev/null" EXIT INT TERM HUP
    
    # Check if any connection is active (exclude loopback)
    local active_connections=$(nmcli -t -f NAME,STATE connection show | grep ":activated" | cut -d: -f1 | grep -v "^lo$")
    
    if [ -n "$active_connections" ]; then
        # Internet is ON - turn it OFF
        if [ "$LANG_CODE" = "de" ]; then
            echo "Deaktiviere alle Netzwerkverbindungen..."
        else
            echo "Disabling all network connections..."
        fi
        
        # Save disabled connections to file for later restoration
        echo "$active_connections" > "$disabled_connections_file"
        
        while IFS= read -r conn; do
            if [ -n "$conn" ]; then
                nmcli connection down "$conn" &> /dev/null
                if [ "$LANG_CODE" = "de" ]; then
                    echo "  ✓ $conn deaktiviert"
                else
                    echo "  ✓ $conn disabled"
                fi
            fi
        done <<< "$active_connections"
        
        if [ "$LANG_CODE" = "de" ]; then
            echo -e "\n\033[1;32m✓\033[0m Alle Verbindungen deaktiviert (PERFEKT für Installation!)"
        else
            echo -e "\n\033[1;32m✓\033[0m All connections disabled (PERFECT for installation!)"
        fi
    else
        # Internet is OFF - turn it ON
        if [ "$LANG_CODE" = "de" ]; then
            echo "Aktiviere Netzwerkverbindungen..."
        else
            echo "Enabling network connections..."
        fi
        
        # Re-enable only the connections that were previously disabled
        if [ -f "$disabled_connections_file" ]; then
            local connections_to_restore=$(cat "$disabled_connections_file")
            
            while IFS= read -r conn; do
                if [ -n "$conn" ]; then
                    nmcli connection up "$conn" &> /dev/null && {
                        if [ "$LANG_CODE" = "de" ]; then
                            echo "  ✓ $conn aktiviert"
                        else
                            echo "  ✓ $conn enabled"
                        fi
                    }
                fi
            done <<< "$connections_to_restore"
            
            # Clean up temp file
            rm -f "$disabled_connections_file"
        else
            # Fallback: if no saved state, try to enable the first active ethernet/wifi connection
            if [ "$LANG_CODE" = "de" ]; then
                echo "  (Keine gespeicherten Verbindungen - verwende Fallback)"
            else
                echo "  (No saved connections - using fallback)"
            fi
            
            local fallback_conn=$(nmcli -t -f NAME,TYPE connection show | grep -E ":(802-3-ethernet|802-11-wireless)" | head -1 | cut -d: -f1)
            if [ -n "$fallback_conn" ]; then
                nmcli connection up "$fallback_conn" &> /dev/null && {
                    if [ "$LANG_CODE" = "de" ]; then
                        echo "  ✓ $fallback_conn aktiviert"
                    else
                        echo "  ✓ $fallback_conn enabled"
                    fi
                }
            fi
        fi
        
        if [ "$LANG_CODE" = "de" ]; then
            echo -e "\n\033[1;32m✓\033[0m Verbindungen wiederhergestellt"
        else
            echo -e "\n\033[1;32m✓\033[0m Connections restored"
        fi
    fi
}

function wait_second() {
    for (( i=0 ; i<$1 ; i++ ));do
        echo -n "."
        sleep 1
    done
    echo ""
}

function read_input() {
    # KRITISCH: IFS zurücksetzen nach read
    local old_IFS="${IFS:-}"
    while true ;do
        # KRITISCH: read -r verhindert Backslash-Interpretation
        IFS= read -r -p "$(msg_choose_option)" choose
        
        # CRITICAL: Sanitize and validate user input
        if type security::sanitize_input >/dev/null 2>&1; then
            choose=$(security::sanitize_input "$choose")
        fi
        
        # Accept 1-9 for menu selection
        if [[ "$choose" =~ ^[1-9]$ ]];then
            break
        fi
        
        # Additional validation: reject empty input and dangerous patterns
        if [ -z "$choose" ]; then
            if [ "$LANG_CODE" = "de" ]; then
                warning "Bitte wähle eine Option (1-9)"
            else
                warning "Please choose an option (1-9)"
            fi
        elif [[ "$choose" == *";"* ]] || [[ "$choose" == *"&"* ]] || [[ "$choose" == *"|"* ]] || [[ "$choose" == *"\`"* ]] || [[ "$choose" == *"\$"* ]] || [[ "$choose" == *"("* ]]; then
            # Reject dangerous characters that might have passed sanitization
            if [ "$LANG_CODE" = "de" ]; then
                warning "Ungültige Eingabe erkannt. Bitte wähle eine Zahl zwischen 1 und 9"
            else
                warning "Invalid input detected. Please choose a number between 1 and 9"
            fi
        else
            if [ "$LANG_CODE" = "de" ]; then
                warning "Wähle eine Zahl zwischen 1 und 9"
            else
                warning "Choose a number between 1 and 9"
            fi
        fi
    done

    # Return the choice as a global variable (since return can only be 0-255)
    CHOICE="$choose"
    # KRITISCH: IFS zurücksetzen
    IFS="$old_IFS"
}

# ============================================================================
# @function open_url
# @description Open URL in default browser (cross-platform: Linux, macOS, WSL2)
# @param $1 URL to open
# @return 0 on success, 1 on error
# ============================================================================
open_url() {
    local url="$1"
    
    # macOS
    if [[ "${OSTYPE:-}" == "darwin"* ]]; then
        open "$url" 2>/dev/null && return 0
    fi
    
    # WSL2 (Windows Subsystem for Linux)
    if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
        # Try wslview first (if installed)
        if command -v wslview >/dev/null 2>&1; then
            wslview "$url" 2>/dev/null && return 0
        fi
        # Fallback to cmd.exe
        cmd.exe /c start "$url" 2>/dev/null && return 0
    fi
    
    # Linux (default)
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" 2>/dev/null && return 0
    fi
    
    # Fallback: Try other common commands
    for cmd in sensible-browser www-browser links lynx; do
        if command -v "$cmd" >/dev/null 2>&1; then
            "$cmd" "$url" 2>/dev/null && return 0
        fi
    done
    
    return 1
}

function exitScript() {
    msg_goodbye
}

function get_system_info() {
    # Get system information for display
    local distro=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown Linux")
    local kernel=$(uname -r | cut -d'-' -f1)
    # Force C locale for consistent output across all languages
    local ram_mb=$(LC_ALL=C free -m | awk '/^Mem:/{print $2}')
    # Ceiling division: round up RAM to nearest GB (avoid showing 0GB)
    local ram_gb=$(( (ram_mb + 1023) / 1024 ))
    [ $ram_gb -eq 0 ] && ram_gb=1  # Minimum 1GB display
    local wine_ver=$(wine --version 2>/dev/null | cut -d'-' -f2 || echo "not installed")
    
    # Detect architecture
    local arch=$(uname -m 2>/dev/null || echo "unknown")
    local arch_display=""
    case "$arch" in
        "x86_64")
            arch_display="(64-bit)"
            ;;
        "aarch64")
            arch_display="(ARM64)"
            ;;
        *)
            arch_display="($arch)"
            ;;
    esac
    
    # Detect GPU
    local gpu=""
    # Try nvidia-smi first (most reliable for Nvidia)
    if command -v nvidia-smi >/dev/null 2>&1; then
        gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | sed 's/ NVIDIA.*//' | sed 's/GeForce //' | sed 's/ RTX / RTX/' | sed 's/ GTX / GTX/' || echo "")
        if [ -n "$gpu" ]; then
            gpu="Nvidia $gpu"
        fi
    fi
    
    # Fallback to lspci if nvidia-smi didn't work
    if [ -z "$gpu" ] && command -v lspci >/dev/null 2>&1; then
        gpu=$(lspci | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //' | sed 's/ \[.*\]//' || echo "")
        # Shorten common GPU names
        if [ -n "$gpu" ]; then
            # Extract manufacturer and model (first 2-3 words usually)
            gpu=$(echo "$gpu" | awk '{print $1, $2, $3, $4}' | sed 's/  */ /g' | sed 's/ $//')
        fi
    fi
    
    # Fallback to glxinfo if available
    if [ -z "$gpu" ] && command -v glxinfo >/dev/null 2>&1; then
        gpu=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | sed 's/.*: //' | head -1 || echo "")
    fi
    
    # Format GPU for display (shorten if too long)
    local gpu_display=""
    if [ -n "$gpu" ]; then
        # Limit GPU name to ~25 characters for display
        if [ ${#gpu} -gt 25 ]; then
            gpu_display="GPU: ${gpu:0:22}..."
        else
            gpu_display="GPU: $gpu"
        fi
    fi
    
    echo "$distro|$arch_display|$kernel|${ram_gb}GB|$gpu_display|$wine_ver"
}

# ============================================================================
# @function detect_photoshop_version_from_dir
# @description Detect Photoshop version from photoshop/ directory
# @description Cross-platform compatible (Linux, macOS, WSL2) - uses only standard tools
# @description Based on detect_photoshop_version() from PhotoshopSetup.sh
# @return Version string (e.g., "CC 2019", "2021", "2022") or empty string
# ============================================================================
detect_photoshop_version_from_dir() {
    local installer_dir="$SCRIPT_DIR/photoshop"
    local version=""
    local setup_exe="$installer_dir/Set-up.exe"
    
    # Check if photoshop directory exists
    if [ ! -d "$installer_dir" ]; then
        return 1
    fi
    
    # METHOD 1: Check Driver.xml (MOST RELIABLE for Adobe installers) - Cross-platform
    # Driver.xml contains <Name>Photoshop 2021</Name> and <CodexVersion>22.0</CodexVersion>
    if [ -f "$installer_dir/products/Driver.xml" ]; then
        local name_line=$(grep -iE "<Name>.*Photoshop.*</Name>" "$installer_dir/products/Driver.xml" 2>/dev/null | head -1)
        if [ -n "$name_line" ]; then
            if echo "$name_line" | grep -qiE "2022"; then
                version="2022"
            elif echo "$name_line" | grep -qiE "2021"; then
                version="2021"
            elif echo "$name_line" | grep -qiE "CC 2019|2019"; then
                version="CC 2019"
            fi
        fi
        
        # Also check CodexVersion/BaseVersion (22.0 = 2021, 23.0 = 2022, 20.x = CC 2019)
        if [ -z "$version" ]; then
            local codex_version=$(grep -iE "<CodexVersion>|<BaseVersion>" "$installer_dir/products/Driver.xml" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1)
            if [ -n "$codex_version" ]; then
                local major_version=$(echo "$codex_version" | cut -d. -f1)
                if [ "$major_version" -ge 23 ]; then
                    version="2022"
                elif [ "$major_version" -ge 22 ]; then
                    version="2021"
                elif [ "$major_version" -ge 20 ]; then
                    version="CC 2019"
                fi
            fi
        fi
    fi
    
    # METHOD 2: Check directory structure (Cross-platform - uses find/grep)
    if [ -z "$version" ]; then
        # Check for version-specific directories in root (cross-platform safe)
        for dir in "$installer_dir"/Adobe\ Photoshop*; do
            if [ -d "$dir" ]; then
                local dirname=$(basename "$dir")
                if [[ "$dirname" =~ "2022" ]]; then
                    version="2022"
                    break
                elif [[ "$dirname" =~ "2021" ]]; then
                    version="2021"
                    break
                elif [[ "$dirname" =~ "CC 2019" ]] || [[ "$dirname" =~ "2019" ]]; then
                    version="CC 2019"
                    break
                fi
            fi
        done
        
        # Also check in packages and products subdirectories
        if [ -z "$version" ] || [ "$version" = "CC 2019" ]; then
            for subdir in "$installer_dir/packages" "$installer_dir/products"; do
                if [ -d "$subdir" ]; then
                    for item in "$subdir"/*; do
                        if [ -d "$item" ] || [ -f "$item" ]; then
                            local basename_item=$(basename "$item")
                            if [[ "$basename_item" =~ "2022" ]] || [[ "$basename_item" =~ "23\.0" ]]; then
                                version="2022"
                                break 2
                            elif [[ "$basename_item" =~ "2021" ]] || [[ "$basename_item" =~ "22\.0" ]]; then
                                version="2021"
                                break 2
                            elif [[ "$basename_item" =~ "CC 2019" ]] || [[ "$basename_item" =~ "2019" ]] || [[ "$basename_item" =~ "20\.0" ]]; then
                                if [ -z "$version" ]; then
                                    version="CC 2019"
                                fi
                            fi
                        fi
                    done
                fi
            done
        fi
    fi
    
    # METHOD 3: Try to extract version from EXE using cross-platform tools (optional)
    # Only if other methods failed and tools are available
    if [ -z "$version" ] && [ -f "$setup_exe" ]; then
        # Try peres (lightweight, cross-platform if available)
        if command -v peres >/dev/null 2>&1; then
            local exe_version=$(peres -v "$setup_exe" 2>/dev/null | awk '{print $3}' | head -1)
            if [ -n "$exe_version" ] && [[ "$exe_version" =~ ^[0-9] ]]; then
                local major_version=$(echo "$exe_version" | cut -d. -f1)
                if [ "$major_version" -ge 23 ]; then
                    version="2022"
                elif [ "$major_version" -ge 22 ]; then
                    version="2021"
                elif [ "$major_version" -ge 20 ]; then
                    version="CC 2019"
                fi
            fi
        # Try ExifTool (cross-platform if available)
        elif command -v exiftool >/dev/null 2>&1; then
            local product_version=$(exiftool "$setup_exe" 2>/dev/null | grep -iE "Product Version|File Version" | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
            if [ -n "$product_version" ]; then
                local major_version=$(echo "$product_version" | cut -d. -f1)
                if [ "$major_version" -ge 23 ]; then
                    version="2022"
                elif [ "$major_version" -ge 22 ]; then
                    version="2021"
                elif [ "$major_version" -ge 20 ]; then
                    version="CC 2019"
                fi
            fi
        fi
    fi
    
    # METHOD 4: Check files in installer directory (cross-platform)
    if [ -z "$version" ] || [ "$version" = "CC 2019" ]; then
        for file in "$installer_dir"/*; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                if [[ "$filename" =~ "2022" ]]; then
                    version="2022"
                    break
                elif [[ "$filename" =~ "2021" ]]; then
                    version="2021"
                    break
                fi
            fi
        done
    fi
    
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    
    return 1
}

function banner() {
        clear && echo ""
    
    # Check if terminal supports colors (fallback for dumb terminals)
    # ANSI Color codes are now global (defined at script start)
    
    # Get system information
    local sys_info=$(get_system_info)
    local distro=$(echo "$sys_info" | cut -d'|' -f1)
    local arch_display=$(echo "$sys_info" | cut -d'|' -f2)
    local kernel=$(echo "$sys_info" | cut -d'|' -f3)
    local ram=$(echo "$sys_info" | cut -d'|' -f4)
    local gpu_display=$(echo "$sys_info" | cut -d'|' -f5)
    local wine_ver=$(echo "$sys_info" | cut -d'|' -f6)
    
    # Dynamic copyright year (start year - current year)
    # Note: This fork started in 2025, so start_year is 2025 (not 2024 from original project)
    local start_year="2025"
    local current_year=$(date +%Y)
    local copyright="© ${start_year}-${current_year} benjarogit | GPL-3.0 License"
    
    # Define menu options based on language
    # Check internet status for menu display (check all connections except loopback)
    local internet_status=""
    if command -v nmcli &> /dev/null; then
        local active_connections=$(nmcli -t -f NAME,STATE connection show | grep ":activated" | cut -d: -f1 | grep -v "^lo$" | wc -l)
        if [ "$active_connections" -gt 0 ]; then
            internet_status="ON "
        else
            internet_status="OFF "  # Add space to match ON length
        fi
    else
        internet_status="N/A "  # Add space for consistent length
    fi
    
    # Determine internet status color - nur der Status-Text (ON/OFF), nicht das ganze
    local internet_status_text=""
    local internet_color=""
    if [ "$internet_status" = "ON " ]; then
        internet_status_text="ON"
        internet_color="${C_GREEN}"
    elif [ "$internet_status" = "OFF " ]; then
        internet_status_text="OFF"
        internet_color="${C_RED}"
    else
        internet_status_text="N/A"
        internet_color="${C_GRAY}"
    fi
    
    # Determine language color - nur der Sprache-Text
    local lang_color="${C_YELLOW}"  # Andere Farbe für Sprache
    local lang_text=""
    if [ "$LANG_CODE" = "de" ]; then
        lang_text="Deutsch"
    else
        lang_text="English"
    fi
    
    # Detect Photoshop version from photoshop/ directory
    local ps_version=""
    if type detect_photoshop_version_from_dir >/dev/null 2>&1; then
        ps_version=$(detect_photoshop_version_from_dir 2>/dev/null || echo "")
    fi
    
    if [ "$LANG_CODE" = "de" ]; then
        if [ -n "$ps_version" ]; then
            local opt1="${C_CYAN}1-${C_RESET} Installieren / Update ${C_BRACKET}(${ps_version})${C_RESET}"
        else
            local opt1="${C_CYAN}1-${C_RESET} Installieren / Update"
        fi
        local opt2="${C_CYAN}2-${C_RESET} Camera Raw v12 installieren"
        local opt3="${C_CYAN}3-${C_RESET} System-Vorprüfung ${C_BRACKET}(empfohlen)${C_RESET}"
        local opt4="${C_CYAN}4-${C_RESET} Fehlerbehebung"
        local opt5="${C_CYAN}5-${C_RESET} Wine konfigurieren ${C_BRACKET}(winecfg)${C_RESET}"
        local opt6="${C_CYAN}6-${C_RESET} Internet: ${internet_color}${internet_status_text}${C_RESET}"
        local opt7="${C_CYAN}7-${C_RESET} Sprache: ${lang_color}${lang_text}${C_RESET}"
        local opt8="${C_CYAN}8-${C_RESET} Deinstallieren / Killen"
        local opt9="${C_CYAN}9-${C_RESET} Schließen"
        local sys_label="System:"
    else
        if [ -n "$ps_version" ]; then
            local opt1="${C_CYAN}1-${C_RESET} Install / Update ${C_BRACKET}(${ps_version})${C_RESET}"
        else
            local opt1="${C_CYAN}1-${C_RESET} Install / Update"
        fi
        local opt2="${C_CYAN}2-${C_RESET} Install camera raw v12"
        local opt3="${C_CYAN}3-${C_RESET} Pre-installation check ${C_BRACKET}(recommended)${C_RESET}"
        local opt4="${C_CYAN}4-${C_RESET} Troubleshooting"
        local opt5="${C_CYAN}5-${C_RESET} Configure wine ${C_BRACKET}(winecfg)${C_RESET}"
        local opt6="${C_CYAN}6-${C_RESET} Internet: ${internet_color}${internet_status_text}${C_RESET}"
        local opt7="${C_CYAN}7-${C_RESET} Language: ${lang_color}${lang_text}${C_RESET}"
        local opt8="${C_CYAN}8-${C_RESET} Uninstall / Kill"
        local opt9="${C_CYAN}9-${C_RESET} Exit"
        local sys_label="System:"
    fi
    
    # Banner width for text padding
    # Use terminal width with reasonable limits (min 62, max 120)
    local terminal_width=$(tput cols 2>/dev/null || echo 80)
    local text_width=$terminal_width
    # Clamp between 62 and 120 for readability
    if [ "$text_width" -lt 62 ]; then
        text_width=62
    elif [ "$text_width" -gt 120 ]; then
        text_width=120
    fi
    
    # Calculate padding for options (strip ANSI codes for length calculation)
    # Helper function to strip ANSI codes
    strip_ansi() {
        echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
    }
    
    local opt1_plain=$(strip_ansi "$opt1")
    local opt2_plain=$(strip_ansi "$opt2")
    local opt3_plain=$(strip_ansi "$opt3")
    local opt4_plain=$(strip_ansi "$opt4")
    local opt5_plain=$(strip_ansi "$opt5")
    local opt6_plain=$(strip_ansi "$opt6")
    local opt7_plain=$(strip_ansi "$opt7")
    local opt8_plain=$(strip_ansi "$opt8")
    local opt9_plain=$(strip_ansi "$opt9")
    
    # Add padding to options (with safety check for negative values)
    local pad1=$((text_width - ${#opt1_plain})); [ $pad1 -lt 0 ] && pad1=0
    local pad2=$((text_width - ${#opt2_plain})); [ $pad2 -lt 0 ] && pad2=0
    local pad3=$((text_width - ${#opt3_plain})); [ $pad3 -lt 0 ] && pad3=0
    local pad4=$((text_width - ${#opt4_plain})); [ $pad4 -lt 0 ] && pad4=0
    local pad5=$((text_width - ${#opt5_plain})); [ $pad5 -lt 0 ] && pad5=0
    local pad6=$((text_width - ${#opt6_plain})); [ $pad6 -lt 0 ] && pad6=0
    local pad7=$((text_width - ${#opt7_plain})); [ $pad7 -lt 0 ] && pad7=0
    local pad8=$((text_width - ${#opt8_plain})); [ $pad8 -lt 0 ] && pad8=0
    local pad9=$((text_width - ${#opt9_plain})); [ $pad9 -lt 0 ] && pad9=0
    
    opt1="${opt1}$(printf '%*s' $pad1 '')"
    opt2="${opt2}$(printf '%*s' $pad2 '')"
    opt3="${opt3}$(printf '%*s' $pad3 '')"
    opt4="${opt4}$(printf '%*s' $pad4 '')"
    opt5="${opt5}$(printf '%*s' $pad5 '')"
    opt6="${opt6}$(printf '%*s' $pad6 '')"
    opt7="${opt7}$(printf '%*s' $pad7 '')"
    opt8="${opt8}$(printf '%*s' $pad8 '')"
    opt9="${opt9}$(printf '%*s' $pad9 '')"
    
    # System info line - width is 74 chars (75 from empty line - 1 for leading space in echo)
    local sys_info_width=74
    # Build system info line with architecture and GPU
    local sys_info_line="${sys_label} ${distro} ${arch_display} | Kernel ${kernel} | RAM ${ram}"
    if [ -n "$gpu_display" ] && [ "$gpu_display" != "" ]; then
        sys_info_line="${sys_info_line} | ${gpu_display}"
    fi
    sys_info_line="${sys_info_line} | Wine ${wine_ver}"
    
    # Truncate distro if line is too long
    if [ ${#sys_info_line} -gt $sys_info_width ]; then
        local overflow=$((${#sys_info_line} - sys_info_width))
        local new_distro_len=$((${#distro} - overflow - 3))  # -3 for "..."
        
        # Only truncate if result would be shorter than original distro (avoid expanding short names)
        if [ $new_distro_len -gt 3 ] && [ $((new_distro_len + 3)) -lt ${#distro} ]; then
            distro="${distro:0:$new_distro_len}..."
            # Rebuild system info line with truncated distro
            sys_info_line="${sys_label} ${distro} ${arch_display} | Kernel ${kernel} | RAM ${ram}"
            if [ -n "$gpu_display" ] && [ "$gpu_display" != "" ]; then
                sys_info_line="${sys_info_line} | ${gpu_display}"
            fi
            sys_info_line="${sys_info_line} | Wine ${wine_ver}"
        fi
        # If distro is already very short, leave it unchanged - padding will be reduced to fit
    fi
    
    # Pad to exact 74 chars
    local sys_padding=$((sys_info_width - ${#sys_info_line}))
    [ $sys_padding -lt 0 ] && sys_padding=0
    sys_info_line="${sys_info_line}$(printf '%*s' $sys_padding '')"
    
    # Load update module and get version info
    local current_version=""
    local latest_version=""
    local version_display="Photoshop Installer"
    
    if type update::get_current_version >/dev/null 2>&1; then
        current_version=$(update::get_current_version 2>/dev/null || echo "")
        
        # Clean version strings - remove git commit hash if present (e.g., "v2.2.18-16-g8f6dc65" -> "v2.2.18")
        if [ -n "$current_version" ]; then
            current_version=$(echo "$current_version" | sed 's/-[0-9]*-g[0-9a-f]*$//')
            # Ensure it starts with 'v' if it's a version number
            if [[ ! "$current_version" =~ ^v ]]; then
                current_version="v${current_version}"
            fi
        fi
        
        # Always try to get GitHub version (non-blocking, may fail silently)
        latest_version=$(update::get_latest_version 2>/dev/null || echo "")
        
        # Always show local version and GitHub version
        if [ -n "$current_version" ] && [ "$current_version" != "unknown" ]; then
            # Show local version
            version_display="Photoshop Installer ${current_version}"
            
            # Always add GitHub version if available
            if [ -n "$latest_version" ] && [ "$latest_version" != "" ]; then
                # Remove 'v' prefix for display (we add it back)
                local latest_clean=$(echo "$latest_version" | sed 's/^v//')
                version_display="${version_display} ${C_BRACKET}- Github v${latest_clean}${C_RESET}"
            fi
        else
            # If no local version found, show GitHub version only
            if [ -n "$latest_version" ] && [ "$latest_version" != "" ]; then
                local latest_clean=$(echo "$latest_version" | sed 's/^v//')
                version_display="Photoshop Installer ${C_BRACKET}(Github v${latest_clean})${C_RESET}"
            else
                version_display="Photoshop Installer"
            fi
        fi
    fi
    
    # Print colored banner with echo -e (bash/sh compatible)
    # Calculate consistent banner width (25 chars for both header and footer)
    local banner_width=25
    local banner_line_top=$(printf "━%.0s" $(seq 1 $banner_width))
    local banner_line_bottom=$(printf "━%.0s" $(seq 1 $banner_width))
    echo -e "${C_CYAN}                     ┏${banner_line_top}┫ ${C_MAGENTA}${version_display}${C_CYAN} ┣${banner_line_top}┓${C_RESET}"
    echo -e "${C_CYAN}                     ┃${C_RESET} ${C_GRAY}${sys_info_line}${C_RESET}"
    echo -e "${C_CYAN}                     ┃${C_RESET}                                                                           ${C_RESET}"
    echo -e "${C_CYAN}  ███████████████████████████${C_RESET}                                                                    ${C_RESET}"
    echo -e "${C_CYAN}  ██${C_RESET}                       ${C_CYAN}██${C_RESET}      ${opt1}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███████▆▃${C_RESET}            ${C_CYAN}██${C_RESET}      ${opt2}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███   ▝██▙${C_RESET} ${C_YELLOW}Linux${C_RESET}     ${C_CYAN}██${C_RESET}      ${opt3}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███    ███${C_RESET}           ${C_CYAN}██${C_RESET}      ${opt4}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███   ▟██▛▗▟████▙${C_RESET}    ${C_CYAN}██${C_RESET}      ${opt5}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███████▛  ██▋${C_RESET}        ${C_CYAN}██${C_RESET}      ${opt6}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███       ▝▜█████▙${C_RESET}   ${C_CYAN}██${C_RESET}      ${opt7}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███   ${C_MAGENTA}2021${C_RESET}      ${C_BLUE_LIGHT}██▌${C_RESET}  ${C_CYAN}██${C_RESET}      ${opt8}${C_RESET}"
    echo -e "${C_CYAN}  ██  ${C_BLUE_LIGHT}███        ▗▟████▛${C_RESET}   ${C_CYAN}██${C_RESET}                                                                    ${C_RESET}"
    echo -e "${C_CYAN}  ██${C_RESET}                       ${C_CYAN}██${C_RESET}      ${opt9}${C_RESET}"
    echo -e "${C_CYAN}  ███████████████████████████${C_RESET}                                                                    ${C_RESET}"
    echo -e "${C_CYAN}                     ┃${C_RESET}                                                                           ${C_RESET}"
    # GitHub link with OSC 8 for clickable links in modern terminals
    local github_url="https://github.com/benjarogit/photoshopCClinux"
    # Use consistent banner width (same as header)
    local banner_width=25
    local banner_line_bottom=$(printf "━%.0s" $(seq 1 $banner_width))
    # Use printf to properly escape ANSI codes
    printf "${C_CYAN}                     ┗${banner_line_bottom}┫ "
    printf "\033]8;;%s\033\\" "$github_url"
    printf "${C_WHITE}%s" "$github_url"
    printf "\033]8;;\033\\"
    printf "${C_CYAN} ┣${banner_line_bottom}┛${C_RESET}\n"
    echo -e "                     ${C_GRAY}${copyright}${C_RESET}"
    
    echo ""
}

function error() {
    echo -e "\033[1;31merror:\e[0m $@"
    exit 1
}

function warning() {
    echo -e "\033[1;33mWarning:\e[0m $@"
}

main



