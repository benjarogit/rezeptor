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
    local canonical="" chosen=""
    export RECIPE_YML="$yml"
    export RECIPE_ID
    RECIPE_ID="$(recipe_get "$yml" id)" || return 1
    # Kanonischer data_root aus YAML; optionaler Override (GUI-Zielordner) via
    # RECIPE_DATA_ROOT oder Persistenz in data_root.path.
    canonical="$(paths_expand "$(recipe_get "$yml" data_root)")"
    mkdir -p "$canonical" 2>/dev/null || true
    if [ -n "${RECIPE_DATA_ROOT:-}" ]; then
        chosen="$(paths_expand "$RECIPE_DATA_ROOT")"
        printf '%s\n' "$chosen" >"$canonical/data_root.path"
    elif [ -f "$canonical/data_root.path" ]; then
        chosen="$(tr -d '\r\n' <"$canonical/data_root.path")"
        chosen="$(paths_expand "${chosen:-}")"
        # Verwaistes Ziel (gelöscht) ignorieren — kanonischer data_root
        if [ -n "$chosen" ] && [ ! -d "$chosen" ]; then
            chosen=""
        fi
    fi
    export DATA_ROOT
    if [ -n "$chosen" ]; then
        DATA_ROOT="$chosen"
    else
        DATA_ROOT="$canonical"
    fi
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
