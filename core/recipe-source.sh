#!/usr/bin/env bash
# Archive extraction for recipes (used by recipe-install.sh).
# Formats: zip/tar.gz via unzip|tar; broader set (7z/rar/multipart) via 7z when available.
# Passwords: RECIPE_ARCHIVE_PASSWORD (single) and/or RECIPE_ARCHIVE_PASSWORD_FILE
# (one candidate per line; empty lines and # comments ignored). Successful password
# may be written to RECIPE_ARCHIVE_PASSWORD_USED_FILE (mode 0600) for the launcher.
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_source::validate_path() {
    local path="$1"
    local label="${2:-path}"
    if type security::validate_path >/dev/null 2>&1; then
        if ! security::validate_path "$path"; then
            echo "ERROR: Unsafe $label (blocked by security policy): $path" >&2
            return 1
        fi
    fi
    if [ -z "$path" ]; then
        echo "ERROR: Missing $label" >&2
        return 1
    fi
    if [[ "$path" == *".."* ]]; then
        echo "ERROR: Unsafe $label (path traversal): $path" >&2
        return 1
    fi
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

recipe_source::_find_7z() {
    if command -v 7z >/dev/null 2>&1; then
        command -v 7z
        return 0
    fi
    if command -v 7za >/dev/null 2>&1; then
        command -v 7za
        return 0
    fi
    return 1
}

# Prefer first volume for common multipart schemes (7z/zip/rar).
recipe_source::resolve_archive() {
    local archive="$1" base dir name
    [ -f "$archive" ] || {
        echo "$archive"
        return 0
    }
    dir="$(cd "$(dirname "$archive")" && pwd)" || {
        echo "$archive"
        return 0
    }
    name="$(basename "$archive")"
    case "${name,,}" in
        *.7z.[0-9][0-9][0-9])
            base="${name%.7z.*}.7z.001"
            if [ -f "$dir/$base" ]; then
                echo "$dir/$base"
                return 0
            fi
            ;;
        *.zip.[0-9][0-9][0-9])
            base="${name%.zip.*}.zip.001"
            if [ -f "$dir/$base" ]; then
                echo "$dir/$base"
                return 0
            fi
            ;;
        *.z[0-9][0-9])
            base="$(printf '%s' "$name" | sed -E 's/\.z[0-9]{2}$/.zip/')"
            if [ -f "$dir/$base" ]; then
                echo "$dir/$base"
                return 0
            fi
            ;;
        *.part[0-9]*.rar)
            for cand in \
                "$(printf '%s' "$name" | sed -E 's/\.part[0-9]+\.rar$/.part01.rar/')" \
                "$(printf '%s' "$name" | sed -E 's/\.part[0-9]+\.rar$/.part1.rar/')"; do
                if [ -n "$cand" ] && [ -f "$dir/$cand" ]; then
                    echo "$dir/$cand"
                    return 0
                fi
            done
            ;;
        *.p[0-9][0-9].rar)
            base="$(printf '%s' "$name" | sed -E 's/\.p[0-9]{2}\.rar$/.p01.rar/')"
            if [ -f "$dir/$base" ]; then
                echo "$dir/$base"
                return 0
            fi
            ;;
        *.[0-9][0-9][0-9])
            # Bare split volumes: rewrite .002+ → .001 when present.
            if [[ "$name" =~ ^(.*)\.([0-9]{3})$ ]]; then
                local stem="${BASH_REMATCH[1]}" n="${BASH_REMATCH[2]}"
                if [ "$n" != "001" ] && [ -f "$dir/${stem}.001" ]; then
                    echo "$dir/${stem}.001"
                    return 0
                fi
            fi
            ;;
    esac
    echo "$archive"
}

recipe_source::_password_candidates() {
    # Yield password candidates: empty (unprotected) first, then file, then single env.
    printf '\0'
    if [ -n "${RECIPE_ARCHIVE_PASSWORD_FILE:-}" ] && [ -f "${RECIPE_ARCHIVE_PASSWORD_FILE}" ]; then
        local line
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "" | \#*) continue ;;
            esac
            printf '%s\0' "$line"
        done < "${RECIPE_ARCHIVE_PASSWORD_FILE}"
    fi
    if [ -n "${RECIPE_ARCHIVE_PASSWORD:-}" ]; then
        printf '%s\0' "${RECIPE_ARCHIVE_PASSWORD}"
    fi
}

recipe_source::_record_used_password() {
    local pw="$1"
    [ -n "${RECIPE_ARCHIVE_PASSWORD_USED_FILE:-}" ] || return 0
    [ -n "$pw" ] || return 0
    umask 077
    printf '%s' "$pw" > "${RECIPE_ARCHIVE_PASSWORD_USED_FILE}" || true
    chmod 600 "${RECIPE_ARCHIVE_PASSWORD_USED_FILE}" 2>/dev/null || true
}

recipe_source::_postcheck_dest() {
    local dest_abs="$1"
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

recipe_source::_extract_7z_once() {
    local seven="$1" archive="$2" dest="$3" pw="$4"
    local core_dir pwfile="" rc=1
    if [ -n "$pw" ]; then
        core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if command -v python3 >/dev/null 2>&1 && [ -f "$core_dir/archive_7z.py" ]; then
            pwfile="$(mktemp)"
            printf '%s' "$pw" > "$pwfile"
            chmod 600 "$pwfile" 2>/dev/null || true
            python3 "$core_dir/archive_7z.py" extract "$seven" "$archive" "$dest" "$pwfile"
            rc=$?
            rm -f "$pwfile"
            return "$rc"
        fi
        # Fallback when Python helper unavailable (password briefly on 7z argv).
        "$seven" x -y "-o${dest}" "-p${pw}" -- "$archive" </dev/null >/dev/null 2>&1
        return $?
    fi
    "$seven" x -y "-o${dest}" -- "$archive" </dev/null >/dev/null 2>&1
}

recipe_source::_extract_via_7z() {
    local archive="$1" dest="$2"
    local seven pw
    seven="$(recipe_source::_find_7z)" || return 1
    # Member pre-check (zip-slip / absolute paths) before any extract attempt.
    if ! "$seven" l -ba -- "$archive" </dev/null 2>/dev/null \
        | awk '{print $NF}' \
        | recipe_source::_members_safe; then
        return 1
    fi
    # Clear dest contents between password attempts (caller creates dest).
    while IFS= read -r -d '' pw; do
        find "$dest" -mindepth 1 -delete 2>/dev/null || true
        if recipe_source::_extract_7z_once "$seven" "$archive" "$dest" "$pw"; then
            # Empty extract = likely wrong password / wrong volume accepted as "ok"
            if [ -z "$(find "$dest" -mindepth 1 -print -quit 2>/dev/null)" ]; then
                continue
            fi
            dest_abs="$(cd "$dest" && pwd)" || return 1
            if ! recipe_source::_postcheck_dest "$dest_abs"; then
                find "$dest" -mindepth 1 -delete 2>/dev/null || true
                return 1
            fi
            recipe_source::_record_used_password "$pw"
            return 0
        fi
    done < <(recipe_source::_password_candidates)
    return 1
}

recipe_source::_zip_py() {
    # Prefer in-process zip (no password on argv). Fallback: host unzip without -P.
    local core_dir
    core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if command -v python3 >/dev/null 2>&1 && [ -f "$core_dir/archive_zip.py" ]; then
        python3 "$core_dir/archive_zip.py" "$@"
        return $?
    fi
    return 127
}

recipe_source::_extract_zip_native() {
    local archive="$1" dest="$2"
    local pw pwfile rc
    # Member pre-check when unzip is available
    if command -v unzip >/dev/null 2>&1; then
        unzip -Z1 "$archive" | recipe_source::_members_safe || return 1
    fi
    if [ -n "${RECIPE_ARCHIVE_PASSWORD:-}" ] || [ -n "${RECIPE_ARCHIVE_PASSWORD_FILE:-}" ]; then
        while IFS= read -r -d '' pw; do
            find "$dest" -mindepth 1 -delete 2>/dev/null || true
            pwfile=""
            if [ -n "$pw" ]; then
                pwfile="$(mktemp)"
                printf '%s' "$pw" > "$pwfile"
                chmod 600 "$pwfile" 2>/dev/null || true
            fi
            if recipe_source::_zip_py extract "$archive" "$dest" ${pwfile:+"$pwfile"}; then
                rc=0
            else
                rc=$?
            fi
            [ -n "$pwfile" ] && rm -f "$pwfile"
            if [ "$rc" -eq 0 ]; then
                [ -n "$pw" ] && recipe_source::_record_used_password "$pw"
                return 0
            fi
            # Fallback: unzip without password only (never -P — argv leak).
            if [ -z "$pw" ] && command -v unzip >/dev/null 2>&1; then
                if unzip -o -q "$archive" -d "$dest" </dev/null 2>/dev/null; then
                    return 0
                fi
            fi
        done < <(recipe_source::_password_candidates)
        return 1
    fi
    if recipe_source::_zip_py extract "$archive" "$dest"; then
        return 0
    fi
    command -v unzip >/dev/null 2>&1 || return 1
    unzip -o -q "$archive" -d "$dest" </dev/null || return 1
}

recipe_source::_extract_targz_native() {
    local archive="$1" dest="$2"
    tar -tzf "$archive" | recipe_source::_members_safe || return 1
    tar --no-same-owner -xzf "$archive" -C "$dest" || return 1
}

recipe_source::extract_archive() {
    local archive="$1" dest="$2"
    local lower dest_abs resolved
    [ -f "$archive" ] || return 1
    recipe_source::validate_path "$archive" || return 1
    recipe_source::validate_path "$dest" || return 1
    resolved="$(recipe_source::resolve_archive "$archive")"
    archive="$resolved"
    [ -f "$archive" ] || return 1
    mkdir -p "$dest"
    dest_abs="$(cd "$dest" && pwd)" || return 1
    lower="${archive,,}"

    case "$lower" in
        *.tar.gz|*.tgz)
            # Prefer tar for gzip tarballs (7z also works, but tar is enough).
            recipe_source::_extract_targz_native "$archive" "$dest" || {
                recipe_source::_find_7z >/dev/null 2>&1 && recipe_source::_extract_via_7z "$archive" "$dest"
            } || return 1
            ;;
        *.zip)
            # Prefer 7z when available (password + multipart .zip.001 / .z01).
            if recipe_source::_find_7z >/dev/null 2>&1; then
                recipe_source::_extract_via_7z "$archive" "$dest" || \
                    recipe_source::_extract_zip_native "$archive" "$dest" || return 1
            else
                recipe_source::_extract_zip_native "$archive" "$dest" || return 1
            fi
            ;;
        *.7z|*.rar|*.7z.[0-9][0-9][0-9]|*.zip.[0-9][0-9][0-9]|*.z[0-9][0-9]|*.part[0-9]*.rar|*.p[0-9][0-9].rar|*.[0-9][0-9][0-9])
            recipe_source::_extract_via_7z "$archive" "$dest" || return 1
            ;;
        *)
            # Unknown extension: try 7z (covers many formats), else fail.
            if recipe_source::_find_7z >/dev/null 2>&1; then
                recipe_source::_extract_via_7z "$archive" "$dest" || return 1
            else
                return 1
            fi
            ;;
    esac
    recipe_source::_postcheck_dest "$dest_abs" || return 1
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
        resolve)
            recipe_source::resolve_archive "${2:?archive}"
            ;;
        *)
            echo "usage: recipe-source.sh extract <archive> <dest>" >&2
            echo "       recipe-source.sh resolve <archive>" >&2
            exit 1
            ;;
    esac
fi
