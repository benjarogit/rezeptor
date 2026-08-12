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
    # RECIPE_DATA_ROOT = optional override. Persist only when it matches DATA_ROOT
    # (or DATA_ROOT unset). Mismatch = stale parent env (e.g. exit-cleanup spawned
    # with another recipe selected) — never rewrite data_root.path in that case.
    if [ -n "${RECIPE_DATA_ROOT:-}" ]; then
        chosen="$(paths_expand "$RECIPE_DATA_ROOT")"
        persist=1
        if [ -n "${DATA_ROOT:-}" ]; then
            data_exp="$(paths_expand "$DATA_ROOT")"
            if [ -n "$data_exp" ] && [ "$data_exp" != "$chosen" ]; then
                chosen="$data_exp"
                persist=0
            fi
        fi
        if [ "$persist" -eq 1 ] && [ -n "$chosen" ]; then
            # Don't overwrite a relocated pointer with the YAML canonical path when
            # the real target is only temporarily offline (unmounted disk). The GUI
            # falls back to canonical for that run; the pointer must survive.
            if [ -f "$canonical/data_root.path" ]; then
                existing="$(tr -d '\r\n' <"$canonical/data_root.path" 2>/dev/null || true)"
                existing="$(paths_expand "${existing:-}")"
                if [ -n "$existing" ] && [ "$existing" != "$chosen" ] \
                    && [ "$chosen" = "$canonical" ]; then
                    persist=0
                fi
            fi
            if [ "$persist" -eq 1 ]; then
                printf '%s\n' "$chosen" >"$canonical/data_root.path"
            fi
        fi
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
    case "$rt" in
        ""|proton-ge) rt="proton-ge" ;;
        *)
            # Legacy recipe.yml mit runtime: system → Proton-GE erzwingen
            rt="proton-ge"
            ;;
    esac
    export WINE_METHOD="$rt"
    export RECIPE_RUNTIME="$rt"
    local wow64
    wow64="$(recipe_get "$yml" disable_wow64 2>/dev/null || true)"
    export RECIPE_DISABLE_WOW64="$wow64"
    # Optional per-recipe Proton-GE pin (default = core/runtime.lock).
    # Medizin/options.env may still override PROTON_GE_TAG afterwards.
    local ptag purl psha
    ptag="$(recipe_get "$yml" proton_ge_tag 2>/dev/null || true)"
    if [ -n "$ptag" ]; then
        export PROTON_GE_TAG="$ptag"
        purl="$(recipe_get "$yml" proton_ge_url 2>/dev/null || true)"
        psha="$(recipe_get "$yml" proton_ge_sha256 2>/dev/null || true)"
        [ -n "$purl" ] && export PROTON_GE_URL="$purl"
        [ -n "$psha" ] && export PROTON_GE_SHA256="$psha"
    fi
    recipe_export_yaml_env "$yml"
}

# env:-Block aus recipe.yml (flache key: value unter env:)
recipe_export_yaml_env() {
    local yml="${1:?recipe.yml}"
    local in_env=0 line key val
    [ -f "$yml" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%$'\r'}"
        if [ "$in_env" -eq 0 ]; then
            [[ "$line" =~ ^env:[[:space:]]*$ ]] && in_env=1
            continue
        fi
        if [[ "$line" =~ ^[^[:space:]#] ]]; then
            break
        fi
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([^#:]+):[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            key="${key//[[:space:]]/}"
            val="${BASH_REMATCH[2]}"
            val="${val%%#*}"
            val="${val%"${val##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val#\"}"
            val="${val%\"}"
            [ -n "$key" ] && export "${key}=${val}"
        fi
    done <"$yml"
}
