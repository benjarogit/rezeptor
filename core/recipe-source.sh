#!/usr/bin/env bash
# Archive extraction for recipes (used by recipe-install.sh).
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_source::validate_path() {
    local path="$1"
    if type security::validate_path >/dev/null 2>&1; then
        security::validate_path "$path" || return 1
    fi
    [ -n "$path" ] || return 1
    [[ "$path" != *".."* ]] || return 1
    return 0
}

recipe_source::staging_dir() {
    local data_root="$1" recipe_id="$2"
    echo "${data_root%/}/staging/${recipe_id}"
}

# Reject zip-slip / absolute members before extract (archive path alone is not enough).
recipe_source::_members_safe() {
    local member
    while IFS= read -r member; do
        [ -n "$member" ] || continue
        case "$member" in
            /* | \\* | *../* | */.. | */../* | .. | ../*)
                echo "ERROR: archive member escapes destination: $member" >&2
                return 1
                ;;
        esac
    done
    return 0
}

recipe_source::extract_archive() {
    local archive="$1" dest="$2"
    [ -f "$archive" ] || return 1
    recipe_source::validate_path "$archive" || return 1
    recipe_source::validate_path "$dest" || return 1
    mkdir -p "$dest"
    local lower="${archive,,}" dest_abs
    dest_abs="$(cd "$dest" && pwd)" || return 1
    case "$lower" in
        *.zip)
            command -v unzip >/dev/null 2>&1 || return 1
            unzip -Z1 "$archive" | recipe_source::_members_safe || return 1
            unzip -o -q "$archive" -d "$dest" || return 1
            ;;
        *.tar.gz|*.tgz)
            tar -tzf "$archive" | recipe_source::_members_safe || return 1
            tar --no-same-owner -xzf "$archive" -C "$dest" || return 1
            ;;
        *)
            return 1
            ;;
    esac
    # Post-check: nothing resolved outside dest (symlink / odd unzip edge cases).
    local f resolved
    while IFS= read -r -d '' f; do
        resolved="$(readlink -f "$f" 2>/dev/null || true)"
        [ -n "$resolved" ] || continue
        case "$resolved" in
            "$dest_abs"|"$dest_abs"/*) ;;
            *)
                echo "ERROR: extracted path outside destination: $f -> $resolved" >&2
                return 1
                ;;
        esac
    done < <(find "$dest_abs" -print0 2>/dev/null)
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/security.sh" 2>/dev/null || true
    case "${1:-}" in
        extract)
            recipe_source::extract_archive "${2:?archive}" "${3:?dest}"
            ;;
        *)
            echo "usage: recipe-source.sh extract <archive> <dest>" >&2
            exit 1
            ;;
    esac
fi
