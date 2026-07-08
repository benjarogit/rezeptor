#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Internationalization (i18n) Module
#
# Description:
#   Centralized internationalization system for DE/EN language support.
#   Uses external language files (de.lang, en.lang) for better maintainability.
#
# Author:       Sunny C.
# Website:      https://sunnyc.de
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-2.0
# Copyright:    (c) 2024-2026 Sunny C.
################################################################################

# ============================================================================
# @namespace i18n
# @description Internationalization functions for multi-language support
# ============================================================================

# Initialize LANG_CODE if not set
LANG_CODE="${LANG_CODE:-}"

# ============================================================================
# @function i18n::init
# @description Initialize i18n system by detecting language
# @return 0 on success, 1 on error
# ============================================================================
i18n::init() {
    if [ -z "$LANG_CODE" ]; then
        if [[ "$LANG" =~ ^de ]]; then
            LANG_CODE="de"
        else
            LANG_CODE="en"
        fi
    fi
    export LANG_CODE
}

# ============================================================================
# @function i18n::get_lang_file
# @description Get path to language file
# @param $1 Language code (de, en)
# @return Path to language file (echoed to stdout)
# ============================================================================
i18n::get_lang_file() {
    local lang="${1:-en}"
    
    # Get script directory
    local script_dir=""
    if [ -n "${SCRIPT_DIR:-}" ]; then
        script_dir="$SCRIPT_DIR"
    elif [ -n "${BASH_SOURCE[0]:-}" ]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "")"
    else
        script_dir="$(pwd)"
    fi
    
    local lang_file="$script_dir/locales/${lang}.lang"
    
    # Check if file exists, fallback to English
    if [ ! -f "$lang_file" ] && [ "$lang" != "en" ]; then
        lang_file="$script_dir/locales/en.lang"
    fi
    
    if [ -f "$lang_file" ]; then
        echo "$lang_file"
        return 0
    fi
    
    return 1
}

# ============================================================================
# @function i18n::get
# @description Get translated text based on current language
# @param $1 Translation key
# @param $2 Optional: Default text if key not found
# @return Translated text (echoed to stdout)
# @example i18n::get "install_photoshop"
# ============================================================================
i18n::get() {
    local key="$1"
    local default="${2:-}"
    
    # Initialize if not already done
    if [ -z "$LANG_CODE" ]; then
        i18n::init
    fi
    
    # Get language file path
    local lang_file
    lang_file=$(i18n::get_lang_file "$LANG_CODE")
    
    # If language file not found, try English
    if [ -z "$lang_file" ] || [ ! -f "$lang_file" ]; then
        if [ "$LANG_CODE" != "en" ]; then
            lang_file=$(i18n::get_lang_file "en")
        fi
    fi
    
    # If still no file, return default or key
    if [ -z "$lang_file" ] || [ ! -f "$lang_file" ]; then
        if [ -n "$default" ]; then
            echo "$default"
        else
            echo "$key"
        fi
        return 0
    fi
    
    # Search for key in language file
    # Format: key=value
    local translation=""
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Check if line starts with key=
        if [[ "$line" =~ ^[[:space:]]*"$key"[[:space:]]*= ]]; then
            # Extract value (everything after =)
            translation="${line#*=}"
            # Remove leading/trailing whitespace
            translation=$(echo "$translation" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            break
        fi
    done < "$lang_file"
    
    # If not found in current language, try English
    if [ -z "$translation" ] && [ "$LANG_CODE" != "en" ]; then
        local en_lang_file
        en_lang_file=$(i18n::get_lang_file "en")
        if [ -n "$en_lang_file" ] && [ -f "$en_lang_file" ]; then
            while IFS= read -r line; do
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "$line" ]] && continue
                [[ "$line" =~ ^[[:space:]]*$ ]] && continue
                
                if [[ "$line" =~ ^[[:space:]]*"$key"[[:space:]]*= ]]; then
                    translation="${line#*=}"
                    translation=$(echo "$translation" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    break
                fi
            done < "$en_lang_file"
        fi
    fi
    
    # Return translation, default, or key
    if [ -n "$translation" ]; then
        echo "$translation"
    elif [ -n "$default" ]; then
        echo "$default"
    else
        echo "$key"
    fi
}

# ============================================================================
# @function i18n::is_de
# @description Check if current language is German
# @return 0 if German, 1 otherwise
# ============================================================================
i18n::is_de() {
    if [ -z "$LANG_CODE" ]; then
        i18n::init
    fi
    [ "$LANG_CODE" = "de" ]
}

# ============================================================================
# @function i18n::is_en
# @description Check if current language is English
# @return 0 if English, 1 otherwise
# ============================================================================
i18n::is_en() {
    if [ -z "$LANG_CODE" ]; then
        i18n::init
    fi
    [ "$LANG_CODE" = "en" ]
}

# Auto-initialize on source
i18n::init
