#!/usr/bin/env bash
# Minimal recipe.yml loader (flat keys only)

recipe_get() {
    local file="$1" key="$2"
    local line
    line=$(grep -E "^${key}:" "$file" 2>/dev/null | head -1) || return 1
    line="${line#*:}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%$'\r'}"
    line="${line#\"}"
    line="${line%\"}"
    echo "$line"
}

recipe_export_env() {
    local yml="${1:?recipe.yml path required}"
    export RECIPE_YML="$yml"
    export RECIPE_ID
    RECIPE_ID="$(recipe_get "$yml" id)" || return 1
    # Immer aus diesem recipe.yml — kein vererbtes DATA_ROOT von einem anderen Rezept.
    export DATA_ROOT
    DATA_ROOT="$(paths_expand "$(recipe_get "$yml" data_root)")"
    export RECIPE_NAME
    RECIPE_NAME="$(recipe_get "$yml" name)"
    paths_init_recipe
    local rt
    rt="$(recipe_get "$yml" runtime 2>/dev/null || true)"
    export WINE_METHOD="${rt:-proton-ge}"
    export RECIPE_RUNTIME="$WINE_METHOD"
    local wow64
    wow64="$(recipe_get "$yml" disable_wow64 2>/dev/null || true)"
    export RECIPE_DISABLE_WOW64="$wow64"
}
