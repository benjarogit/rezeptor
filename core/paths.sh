#!/usr/bin/env bash
# Unified user data layout for wine-software recipes

wine_software_base() {
    echo "${WINE_SOFTWARE_BASE:-$HOME/.local/share/wine-software}"
}

wine_software_runtime_dir() {
    echo "$(wine_software_base)/runtime/proton-ge"
}

wine_software_logs_dir() {
    echo "$(wine_software_base)/logs"
}

wine_software_cache_dir() {
    echo "$(wine_software_base)/cache/winetricks"
}

recipe_data_root() {
    local id="${1:?recipe id required}"
    echo "$(wine_software_base)/$id"
}

paths_expand() {
    local p="${1/#\~/$HOME}"
    echo "$p"
}

paths_init_recipe() {
    local id="${RECIPE_ID:?RECIPE_ID required}"
    export DATA_ROOT="${DATA_ROOT:-$(recipe_data_root "$id")}"
    export SCR_PATH="$DATA_ROOT"
    export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
    export RESOURCES_PATH="${RESOURCES_PATH:-$DATA_ROOT/resources}"
    export CACHE_PATH="${CACHE_PATH:-$(wine_software_cache_dir)}"
    export WINE_SOFTWARE_BASE="$(wine_software_base)"
}

# Optional: PROTON_PATH from legacy ~/.psdata.txt line 3 (never overrides DATA_ROOT)
paths_read_psdata_proton_path() {
    local f="$HOME/.psdata.txt"
    [ -f "$f" ] || return 1
    sed -n '3p' "$f" 2>/dev/null | grep -v '^[[:space:]]*$' || return 1
}
