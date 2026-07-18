#!/usr/bin/env bash
# Portable-Quelle → Zielordner (copy/move/link). Installer-Erkennung im Ordner.

recipe_deploy::sync_portable() {
    local src="$1" dst="$2" mode="${3:-copy}"
    local src_real dst_real

    [ -n "$src" ] && [ -d "$src" ] || return 1
    [ -n "$dst" ] || return 1

    src_real="$(cd "$src" && pwd)"
    mkdir -p "$dst" || return 1
    dst_real="$(cd "$dst" && pwd)"

    if [ "$src_real" = "$dst_real" ]; then
        echo "$dst_real"
        return 0
    fi

    case "$mode" in
        link|inplace)
            # inplace: legacy schema alias — use source in place (no copy)
            echo "$src_real"
            return 0
            ;;
        move)
            if [ -n "$(ls -A "$dst_real" 2>/dev/null)" ]; then
                rm -rf "${dst_real:?}/"* "${dst_real:?}/".[!.]* 2>/dev/null || true
            fi
            if command -v rsync >/dev/null 2>&1; then
                rsync -a "$src_real/" "$dst_real/" || return 1
                rm -rf "$src_real"
            else
                cp -a "$src_real/." "$dst_real/" || return 1
                rm -rf "$src_real"
            fi
            ;;
        copy|*)
            if command -v rsync >/dev/null 2>&1; then
                rsync -a "$src_real/" "$dst_real/" || return 1
            else
                cp -a "$src_real/." "$dst_real/" || return 1
            fi
            ;;
    esac
    echo "$dst_real"
}

recipe_deploy::detect_installer() {
    local dir="$1"
    local f base lc size best="" best_size=0
    [ -d "$dir" ] || return 1
    shopt -s nullglob 2>/dev/null || true
    for f in "$dir"/*.exe "$dir"/*.msi "$dir"/*/*.exe "$dir"/*/*.msi; do
        [ -f "$f" ] || continue
        base="${f##*/}"
        lc="${base,,}"
        [[ "$lc" == *uninstall* ]] && continue
        [[ "$lc" == set-up.exe || "$lc" == setup*.exe || "$lc" == install*.exe || "$lc" == *setup*.msi ]] && {
            echo "$f"
            return 0
        }
        size="$(stat -c%s "$f" 2>/dev/null || echo 0)"
        if [ "$size" -gt "$best_size" ]; then
            best="$f"
            best_size="$size"
        fi
    done
    shopt -u nullglob 2>/dev/null || true
    [ -n "$best" ] || return 1
    echo "$best"
}
