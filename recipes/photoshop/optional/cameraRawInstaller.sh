#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Camera Raw Installer
################################################################################

function main() {
    local _opt_dir _recipe_dir
    _opt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _recipe_dir="$(cd "$_opt_dir/.." && pwd)"
    PROJECT_ROOT="$(cd "$_recipe_dir/../.." && pwd)"
    CORE_DIR="$PROJECT_ROOT/core"
    export PROJECT_ROOT RECIPE_DIR="$_recipe_dir" CORE_DIR
    SCRIPT_DIR="$CORE_DIR"

    # shellcheck source=/dev/null
    source "$CORE_DIR/paths.sh"
    # shellcheck source=/dev/null
    source "$CORE_DIR/recipe.sh"
    recipe_export_env "$_recipe_dir/recipe.yml"
    # shellcheck source=/dev/null
    source "$CORE_DIR/sharedFuncs.sh"
    # shellcheck source=/dev/null
    source "$CORE_DIR/wine-runtime.sh"
    wine() { wine_runtime::wine "$@"; }

    export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"
    WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
    RESOURCES_PATH="${RESOURCES_PATH:-$DATA_ROOT/resources}"
    export WINEPREFIX="$WINE_PREFIX"

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

    if declare -F recipe_notify::send >/dev/null 2>&1; then
        recipe_notify::send "Photoshop CC" "Adobe Camera Raw v12 installed successfully" "" "photoshop"
    else
        notify-send -a "Photoshop CC" "Adobe Camera Raw v12 installed successfully" -i "photoshop" 2>/dev/null || true
    fi
    show_message2 "Adobe Camera Raw v12 installed..."
    unset filename filemd5 filelink filepath
}

main
