#!/usr/bin/env bash
# Archive extraction and source.env helpers for recipes.
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

recipe_source::extract_archive() {
    local archive="$1" dest="$2"
    [ -f "$archive" ] || return 1
    recipe_source::validate_path "$archive" || return 1
    recipe_source::validate_path "$dest" || return 1
    mkdir -p "$dest"
    local lower="${archive,,}"
    case "$lower" in
        *.zip)
            command -v unzip >/dev/null 2>&1 || return 1
            unzip -o -q "$archive" -d "$dest"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$dest"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

recipe_source::detect_installer() {
    local root="$1" glob="${2:-**/*.exe}"
    [ -d "$root" ] || return 1
    find "$root" -type f -iname '*.exe' 2>/dev/null | head -1
}

recipe_source::write_source_env() {
    local file="$1"
    shift
    # shellcheck source=/dev/null
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env-file.sh"
    env_file_write "$file" "$@"
}

recipe_source::cli_extract() {
    local archive="$1" dest="$2"
    recipe_source::extract_archive "$archive" "$dest"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/security.sh" 2>/dev/null || true
    case "${1:-}" in
        extract)
            recipe_source::cli_extract "${2:?archive}" "${3:?dest}"
            ;;
        *)
            echo "usage: recipe-source.sh extract <archive> <dest>" >&2
            exit 1
            ;;
    esac
fi
