#!/usr/bin/env bash
# Installationsziel umziehen (DATA_ROOT / Portable-Root) inkl. Prefix-Verdrahtung.
#
# Env: RECIPE_RELOCATE_TO = neuer Zielordner (absolut oder expandierbar)
# Voraussetzung: recipe_hooks::load minimal (+ dieses Modul); DATA_ROOT gesetzt.
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_relocate::_log() {
    type output::step >/dev/null 2>&1 && output::step "$1" || echo "→ $1"
}

recipe_relocate::_ok() {
    type output::success >/dev/null 2>&1 && output::success "$1" || echo "OK: $1"
}

recipe_relocate::_err() {
    echo "ERROR: $*" >&2
    type recipe_hooks::log_err >/dev/null 2>&1 && recipe_hooks::log_err "$*"
}

recipe_relocate::_info() {
    type output::info >/dev/null 2>&1 && output::info "$1" || echo "$1"
}

recipe_relocate::_canonical() {
    local yml="${RECIPE_YML:?}"
    paths_expand "$(recipe_get "$yml" data_root)"
}

recipe_relocate::_same_path() {
    local a b
    a="$(cd "$1" 2>/dev/null && pwd -P)" || a="$1"
    b="$(cd "$2" 2>/dev/null && pwd -P)" || b="$2"
    [ "$a" = "$b" ]
}

recipe_relocate::_is_subpath() {
    # true if $2 is under $1
    local parent child
    parent="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
    child="$(cd "$2" 2>/dev/null && pwd -P)" || {
        # child may not exist yet — use dirname resolve + basename
        local pdir
        pdir="$(cd "$(dirname "$2")" 2>/dev/null && pwd -P)" || return 1
        child="${pdir}/$(basename "$2")"
    }
    case "$child" in
        "$parent"|"$parent"/*) return 0 ;;
        *) return 1 ;;
    esac
}

recipe_relocate::_disk_free_bytes() {
    local dir="$1"
    df -PB1 --output=avail "$dir" 2>/dev/null | tail -1 | tr -d ' ' || echo 0
}

recipe_relocate::_dir_size_bytes() {
    local dir="$1"
    du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0
}

# Rewrite absolute old→new in text files under root (env, soft links handled separately).
recipe_relocate::_rewrite_text_paths() {
    local root="$1" old="$2" new="$3" f
    [ -d "$root" ] || return 0
    while IFS= read -r -d '' f; do
        grep -Fq "$old" "$f" 2>/dev/null || continue
        if command -v python3 >/dev/null 2>&1; then
            OLD="$old" NEW="$new" FILE="$f" python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["FILE"])
old, new = os.environ["OLD"], os.environ["NEW"]
text = p.read_text(encoding="utf-8", errors="replace")
if old in text:
    p.write_text(text.replace(old, new), encoding="utf-8")
PY
        else
            # Fallback: only simple paths without sed metacharacters
            case "$old" in
                *'/'*) sed -i "s|${old}|${new}|g" "$f" 2>/dev/null || true ;;
            esac
        fi
    done < <(find "$root" -maxdepth 2 -type f \( \
        -name 'recipe.env' -o -name 'portable.env' -o -name 'options.env' -o -name '*.path' \
        \) -print0 2>/dev/null)
}

recipe_relocate::_fix_dosdevices() {
    local prefix="$1" old_prefix="$2"
    local dd="${prefix}/dosdevices"
    [ -d "$dd" ] || return 0
    if [ -e "${dd}/c:" ] || [ -L "${dd}/c:" ]; then
        rm -f "${dd}/c:" 2>/dev/null || true
        ln -sfn "../drive_c" "${dd}/c:" 2>/dev/null || true
    fi
    if [ -L "${dd}/z:" ]; then
        ln -sfn "/" "${dd}/z:" 2>/dev/null || true
    fi
    local link target
    for link in "$dd"/*; do
        [ -L "$link" ] || continue
        target="$(readlink "$link" 2>/dev/null || true)"
        [ -n "$target" ] || continue
        case "$target" in
            "$old_prefix"*)
                ln -sfn "${prefix}${target#"$old_prefix"}" "$link" 2>/dev/null || true
                ;;
        esac
    done
}

recipe_relocate::_move_tree() {
    local src="$1" dst="$2"
    local parent
    parent="$(dirname "$dst")"
    mkdir -p "$parent" || {
        recipe_relocate::_err "Kann Ziel-Elternordner nicht anlegen: $parent"
        return 1
    }
    if [ -e "$dst" ] && [ "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]; then
        recipe_relocate::_err "Zielordner ist nicht leer: $dst"
        return 1
    fi
    mkdir -p "$dst" 2>/dev/null || true

    # Same device → rename; else copy+verify+remove
    local src_dev dst_dev
    src_dev="$(stat -c '%d' "$src" 2>/dev/null || echo x)"
    dst_dev="$(stat -c '%d' "$parent" 2>/dev/null || echo y)"
    if [ "$src_dev" = "$dst_dev" ]; then
        recipe_relocate::_log "Verschiebe (gleiche Partition)…"
        # dst may exist empty — remove then mv
        rmdir "$dst" 2>/dev/null || true
        if mv "$src" "$dst"; then
            return 0
        fi
        recipe_relocate::_info "mv fehlgeschlagen — kopiere…"
    else
        recipe_relocate::_log "Kopiere auf andere Partition…"
    fi
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --info=progress2 "$src"/ "$dst"/ || {
            recipe_relocate::_err "rsync fehlgeschlagen"
            return 1
        }
    else
        cp -a "$src"/. "$dst"/ || {
            recipe_relocate::_err "cp fehlgeschlagen"
            return 1
        }
    fi
    # crude size check
    local s1 s2
    s1="$(recipe_relocate::_dir_size_bytes "$src")"
    s2="$(recipe_relocate::_dir_size_bytes "$dst")"
    if [ "$s1" -gt 0 ] && [ "$s2" -lt $((s1 * 9 / 10)) ]; then
        recipe_relocate::_err "Kopie unvollständig (Größe $s2 < $s1)"
        return 1
    fi
    recipe_relocate::_log "Entferne alten Ort…"
    rm -rf "$src"
    return 0
}

recipe_relocate::_move_canonical_contents() {
    # old == canonical: Inhalt nach dst, data_root.path bleibt im Canonical
    local src="$1" dst="$2" item base
    mkdir -p "$dst" || return 1
    shopt -s dotglob nullglob
    for item in "$src"/*; do
        base="$(basename "$item")"
        [ "$base" = "data_root.path" ] && continue
        if [ -e "${dst}/${base}" ]; then
            recipe_relocate::_err "Konflikt am Ziel: ${dst}/${base}"
            shopt -u dotglob nullglob
            return 1
        fi
        mv "$item" "$dst/" || {
            shopt -u dotglob nullglob
            return 1
        }
    done
    shopt -u dotglob nullglob
    return 0
}

recipe_relocate::_update_portable_env() {
    local root="$1" old="$2" new="$3"
    local pe="${root}/portable.env"
    [ -f "$pe" ] || return 0
    if grep -q 'WISO_PORTABLE_ROOT=' "$pe" 2>/dev/null; then
        # shellcheck source=/dev/null
        type env_file_set >/dev/null 2>&1 || recipe_hooks::_source env-file.sh 2>/dev/null || true
        if type env_file_set >/dev/null 2>&1; then
            local cur
            cur="$(env_file_get "$pe" WISO_PORTABLE_ROOT 2>/dev/null || true)"
            if [ -n "$cur" ] && [ "$cur" = "$old" ]; then
                env_file_set "$pe" WISO_PORTABLE_ROOT "$new"
            elif [ -n "$cur" ]; then
                # portable root may equal old portable path stored elsewhere
                case "$cur" in
                    "$old"|"$old"/*) env_file_set "$pe" WISO_PORTABLE_ROOT "$new" ;;
                esac
            fi
        fi
    fi
    recipe_relocate::_rewrite_text_paths "$root" "$old" "$new"
}

# Main: move current DATA_ROOT (and optional portable root) to RECIPE_RELOCATE_TO.
recipe_relocate::move() {
    local dest="${RECIPE_RELOCATE_TO:-${1:-}}"
    local old canonical old_prefix new_prefix portable_old

    [ -n "${DATA_ROOT:-}" ] || {
        recipe_relocate::_err "DATA_ROOT fehlt"
        return 1
    }
    [ -n "$dest" ] || {
        recipe_relocate::_err "RECIPE_RELOCATE_TO fehlt"
        return 1
    }
    type paths_expand >/dev/null 2>&1 || {
        recipe_relocate::_err "paths_expand fehlt"
        return 1
    }
    dest="$(paths_expand "$dest")"
    old="$(cd "$DATA_ROOT" 2>/dev/null && pwd)" || old="$DATA_ROOT"
    [ -d "$old" ] || {
        recipe_relocate::_err "Aktuelles Ziel fehlt: $old"
        return 1
    }
    if recipe_relocate::_same_path "$old" "$dest"; then
        recipe_relocate::_err "Neues Ziel ist identisch mit dem aktuellen"
        return 1
    fi
    if recipe_relocate::_is_subpath "$old" "$dest"; then
        recipe_relocate::_err "Neues Ziel darf nicht unter dem alten Ziel liegen"
        return 1
    fi
    if recipe_relocate::_is_subpath "$dest" "$old" && [ -d "$dest" ]; then
        recipe_relocate::_err "Altes Ziel liegt unter dem neuen — ungültig"
        return 1
    fi

    canonical="$(recipe_relocate::_canonical)"
    portable_old=""
    if [ -f "${old}/portable.env" ]; then
        # shellcheck source=/dev/null
        type env_file_get >/dev/null 2>&1 || recipe_hooks::_source env-file.sh 2>/dev/null || true
        if type env_file_get >/dev/null 2>&1; then
            portable_old="$(env_file_get "${old}/portable.env" WISO_PORTABLE_ROOT 2>/dev/null || true)"
        fi
    fi
    # Auch RECIPE_TARGET_DIR / pending
    if [ -z "$portable_old" ] && [ -n "${RECIPE_TARGET_DIR:-}" ] && [ -d "${RECIPE_TARGET_DIR}" ]; then
        case "$(recipe_get "${RECIPE_YML}" install_type 2>/dev/null || true)" in
            portable_*|game_portable) portable_old="$(paths_expand "$RECIPE_TARGET_DIR")" ;;
        esac
    fi

    recipe_relocate::_log "Prüfe Speicherplatz…"
    local need free parent_for_df
    need="$(recipe_relocate::_dir_size_bytes "$old")"
    parent_for_df="$(dirname "$dest")"
    mkdir -p "$parent_for_df" 2>/dev/null || true
    free="$(recipe_relocate::_disk_free_bytes "$parent_for_df")"
    # Extra headroom ~5%
    if [ "$need" -gt 0 ] && [ "$free" -gt 0 ] && [ "$free" -lt $((need + need / 20)) ]; then
        recipe_relocate::_err "Zu wenig Speicher am Ziel (frei=$free, nötig≈$need)"
        return 1
    fi

    echo "@step:relocate_move"
    echo "@progress:10"
    recipe_relocate::_log "Von: $old"
    recipe_relocate::_log "Nach: $dest"

    old_prefix="${old}/prefix"
    if [ -d "$canonical" ] && recipe_relocate::_same_path "$old" "$canonical"; then
        recipe_relocate::_move_canonical_contents "$old" "$dest" || return 1
    else
        recipe_relocate::_move_tree "$old" "$dest" || return 1
    fi
    echo "@progress:70"

    printf '%s\n' "$dest" >"${canonical}/data_root.path"
    export DATA_ROOT="$dest"
    export WINEPREFIX="${dest}/prefix"
    export WINE_PREFIX="$WINEPREFIX"
    new_prefix="$WINEPREFIX"

    recipe_relocate::_rewrite_text_paths "$dest" "$old" "$dest"
    if [ -d "$old_prefix" ] || [ -d "$new_prefix" ]; then
        recipe_relocate::_fix_dosdevices "$new_prefix" "$old_prefix"
    fi

    # Portable-App separat, wenn außerhalb von DATA_ROOT
    if [ -n "$portable_old" ] && [ -d "$portable_old" ] \
        && ! recipe_relocate::_same_path "$portable_old" "$old" \
        && ! recipe_relocate::_is_subpath "$old" "$portable_old"; then
        local portable_new
        portable_new="${dest}/$(basename "$portable_old")"
        # If user chose dest as the new portable home, prefer dest itself when empty of prefix-only move
        # Convention: when relocating portable, RECIPE_RELOCATE_TO is the new portable root;
        # DATA_ROOT may stay — but our move already moved DATA_ROOT. For WISO, DATA_ROOT holds
        # state and portable is separate: if we only moved DATA_ROOT, also move portable next to dest
        # when RECIPE_RELOCATE_PORTABLE_TO is set; else nest under dest.
        if [ -n "${RECIPE_RELOCATE_PORTABLE_TO:-}" ]; then
            portable_new="$(paths_expand "$RECIPE_RELOCATE_PORTABLE_TO")"
        fi
        recipe_relocate::_log "Portable-Root: $portable_old → $portable_new"
        recipe_relocate::_move_tree "$portable_old" "$portable_new" || return 1
        recipe_relocate::_update_portable_env "$dest" "$portable_old" "$portable_new"
    else
        recipe_relocate::_update_portable_env "$dest" "$old" "$dest"
    fi

    echo "@progress:90"
    # Desktop-Verknüpfungen aktualisieren falls vorhanden
    if type recipe_desktop::refresh_if_present >/dev/null 2>&1; then
        recipe_desktop::refresh_if_present || true
    elif [ -f "${RECIPE_DIR}/../../core/recipe-desktop.sh" ]; then
        # shellcheck source=/dev/null
        source "${RECIPE_DIR}/../../core/recipe-desktop.sh"
        recipe_desktop::refresh_if_present || true
    fi

    echo "@progress:100"
    recipe_relocate::_ok "Ziel verschoben nach $dest"
    echo "@step:relocate_done"
    return 0
}
