#!/usr/bin/env bash
# Online-Fix aus separatem Ordner in den Spielordner mergen (Steam-Link-Rezepte).
# Env: RECIPE_FIX_ROOT, RECIPE_FIX_MERGE_PATH (relativ zum Spielordner)

recipe_online_fix::merge() {
    local game_root="${1:?game root}"
    local fix_src="${2:?fix source}"
    local merge_rel="${3:?merge path relative to game}"

    [ -d "$game_root" ] || return 1
    [ -d "$fix_src" ] || {
        type recipe_hooks::log_err >/dev/null 2>&1 \
            && recipe_hooks::log_err "Online-Fix-Ordner fehlt: $fix_src"
        return 1
    }

    local dest="$game_root/$merge_rel"
    local from="$fix_src" base

    mkdir -p "$dest"

    # Fix-Paket enthält oft direkt die DLLs oder einen Unterordner Win64.
    if ! compgen -G "$from"/*.dll >/dev/null 2>&1; then
        base="$(basename "$merge_rel")"
        if [ -d "$from/$base" ] && compgen -G "$from/$base"/*.dll >/dev/null 2>&1; then
            from="$from/$base"
        fi
    fi

    if ! compgen -G "$from"/*.dll >/dev/null 2>&1 \
        && ! compgen -G "$from"/*.ini >/dev/null 2>&1; then
        type recipe_hooks::log_err >/dev/null 2>&1 \
            && recipe_hooks::log_err "Online-Fix-Ordner enthält keine .dll/.ini: $fix_src"
        return 1
    fi

    local f
    shopt -s nullglob
    for f in "$from"/*; do
        [ -f "$f" ] || continue
        cp -f "$f" "$dest/$(basename "$f")"
    done
    shopt -u nullglob

    type output::success >/dev/null 2>&1 \
        && output::success "Online-Fix nach $merge_rel kopiert"
    return 0
}
