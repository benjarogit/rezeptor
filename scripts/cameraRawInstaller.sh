#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Camera Raw Installer
#
# Description:
#   Installs Adobe Camera Raw v12 plugin for Photoshop CC.
#   Handles file extraction and integration into the Photoshop installation.
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

function main() {
    
    # KRITISCH: Source-Hijacking verhindern - immer absoluten Pfad verwenden
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/sharedFuncs.sh"

    load_paths
    WINE_PREFIX="$SCR_PATH/prefix"

    #resources will be remove after installation
    RESOURCES_PATH="$SCR_PATH/resources"

    check_ps_installed
    
    export_var
    install_cameraRaw
}

function check_ps_installed() {
    if [ -d "$SCR_PATH" ] && [ -d "$CACHE_PATH" ] && [ -d "$WINE_PREFIX" ]; then
        show_message2 "photoshop installed"
        return 0
    else
        error2 "photoshop not found you should intsall photoshop first"
        # Return to main menu if called from setup.sh
        if [ -n "${RETURN_TO_MENU:-}" ]; then
            if [ "$LANG_CODE" = "de" ]; then
                echo ""
                echo "Drücke Enter, um zum Hauptmenü zurückzukehren..."
                read -r dummy
            else
                echo ""
                echo "Press Enter to return to main menu..."
                read -r dummy
            fi
        fi
        exit 1
    fi
}

function install_cameraRaw() {
    local filename="CameraRaw_12_2_1.exe"
    local filemd5="b6a6b362e0c159be5ba1d0eb1ebd0054"
    local filelink="https://download.adobe.com/pub/adobe/photoshop/cameraraw/win/12.x/CameraRaw_12_2_1.exe"
    local filepath="$CACHE_PATH/$filename"

    download_component $filepath $filemd5 $filelink $filename

    echo "===============| Adobe Camera Raw v12 |===============" >> "$SCR_PATH/wine-error.log"
    show_message2 "Adobe Camera Raw v12 installation..."

    wine $filepath &>> "$SCR_PATH/wine-error.log" || error2 "sorry something went wrong during Adobe Camera Raw v12 installation"

    notify-send "Photoshop CC" "Adobe Camera Raw v12 installed successfully" -i "photoshop"
    show_message2 "Adobe Camera Raw v12 installed..."
    unset filename filemd5 filelink filepath
}

main



