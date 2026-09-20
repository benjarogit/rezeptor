#!/usr/bin/env bash
# Shared remote-asset fetch: HTTPS download + SHA-256 verify.
# Same checksum idea as proton-ge-fetch / nvidia-libs. No recipe-id literals.
#
# MEGA: only public /file/ or /folder/ shares with a key. /fm/ is rejected.
# mega-get (mega-cmd) is required for mega.nz links; curl cannot decrypt them.

recipe_assets::_lock_file() {
    local root="${PROJECT_ROOT:-}"
    if [ -z "$root" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
        root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    fi
    echo "${root}/core/recipe-assets.lock"
}

recipe_assets::_load_lock() {
    local lock
    lock="$(recipe_assets::_lock_file)"
    [ -f "$lock" ] || return 0
    # shellcheck source=/dev/null
    source "$lock"
}

recipe_assets::_settings_json() {
    local base=""
    if type wine_software_base >/dev/null 2>&1; then
        base="$(wine_software_base)"
    else
        base="${WINE_SOFTWARE_BASE:-$HOME/.local/share/wine-software}"
    fi
    echo "${base}/rezeptor/settings.json"
}

recipe_assets::mega_base_url() {
    local url="" sj lock_url=""
    if [ -n "${REZEPTOR_MEGA_ASSETS_URL:-}" ]; then
        url="${REZEPTOR_MEGA_ASSETS_URL}"
    else
        sj="$(recipe_assets::_settings_json)"
        if [ -f "$sj" ]; then
            url="$(python3 - "$sj" <<'PY'
import json, sys
try:
    data = json.loads(open(sys.argv[1], encoding="utf-8").read())
except (OSError, json.JSONDecodeError):
    data = {}
print((data.get("mega_assets_base_url") or "").strip() if isinstance(data, dict) else "")
PY
)"
        fi
        if [ -z "$url" ]; then
            recipe_assets::_load_lock
            url="${MEGA_ASSETS_BASE_URL:-}"
        fi
    fi
    printf '%s' "$url"
}

recipe_assets::mega_remote_dir() {
    if [ -n "${REZEPTOR_MEGA_REMOTE_DIR:-}" ]; then
        printf '%s' "${REZEPTOR_MEGA_REMOTE_DIR}"
        return 0
    fi
    recipe_assets::_load_lock
    printf '%s' "${MEGA_ASSETS_REMOTE_DIR:-/Rezeptor-assets}"
}

# True for a usable public download URL. File-Manager /fm/ is never a share.
recipe_assets::is_public_share_url() {
    local url="${1:-}"
    [ -n "$url" ] || return 1
    case "$url" in
        http://*) return 1 ;;
        https://mega.nz/fm/*|https://mega.io/fm/*) return 1 ;;
        https://mega.nz/file/*#*|https://mega.nz/folder/*#*|https://mega.io/file/*#*|https://mega.io/folder/*#*)
            return 0
            ;;
        https://mega.nz/file/*!*|https://mega.nz/folder/*!*|https://mega.io/file/*!*|https://mega.io/folder/*!*)
            return 0
            ;;
        https://github.com/*|https://*.githubusercontent.com/*|https://objects.githubusercontent.com/*)
            return 0
            ;;
        https://*)
            return 0
            ;;
        *) return 1 ;;
    esac
}

recipe_assets::_validate_download_url() {
    local url="${1:-}"
    recipe_assets::is_public_share_url "$url" || return 1
    case "$url" in
        https://mega.nz/fm/*|https://mega.io/fm/*) return 1 ;;
    esac
    if type security::validate_url >/dev/null 2>&1; then
        security::validate_url "$url" \
            "github.com" "githubusercontent.com" "mega.nz" "mega.io" \
            || return 1
    fi
    return 0
}

recipe_assets::verify_sha256() {
    local file="${1:-}" expected="${2:-}"
    [ -f "$file" ] && [ -n "$expected" ] || return 1
    echo "${expected}  ${file}" | /usr/bin/sha256sum -c --status 2>/dev/null \
        || echo "${expected}  ${file}" | sha256sum -c --status 2>/dev/null
}

recipe_assets::_download_https() {
    local url="${1:?}" dest="${2:?}"
    local dir
    dir="$(dirname "$dest")"
    mkdir -p "$dir"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --retry-connrefused "$url" -O "$dest"
    else
        return 1
    fi
}

recipe_assets::_download_mega() {
    local url="${1:?}" dest="${2:?}"
    local dir tmp
    dir="$(dirname "$dest")"
    mkdir -p "$dir"
    if command -v mega-get >/dev/null 2>&1; then
        tmp="$(mktemp -d "${dir}/.mega-get.XXXXXX")"
        mega-get "$url" "$tmp" || { rm -rf "$tmp"; return 1; }
        if [ -f "$tmp/$(basename "$dest")" ]; then
            mv -f "$tmp/$(basename "$dest")" "$dest"
        else
            # mega-get may write the remote name; take the only regular file.
            set -- "$tmp"/*
            if [ "$#" -eq 1 ] && [ -f "$1" ]; then
                mv -f "$1" "$dest"
            else
                rm -rf "$tmp"
                return 1
            fi
        fi
        rm -rf "$tmp"
        return 0
    fi
    if command -v megadl >/dev/null 2>&1; then
        megadl --path "$dest" "$url"
        return $?
    fi
    echo "ERROR: MEGA public share needs mega-cmd (mega-get) or megatools (megadl)" >&2
    return 1
}

# Download url to dest and require sha256. Skip when dest already matches.
recipe_assets::ensure() {
    local dest="${1:?}" url="${2:-}" sha="${3:-}"
    if [ -f "$dest" ] && [ -n "$sha" ]; then
        recipe_assets::verify_sha256 "$dest" "$sha" && return 0
        rm -f "$dest"
    fi
    [ -n "$url" ] || return 1
    recipe_assets::_validate_download_url "$url" || {
        echo "ERROR: Not a public HTTPS share URL (mega.nz /fm/ is the file manager): $url" >&2
        return 1
    }
    type output::step >/dev/null 2>&1 && output::step "Remote-Asset laden" || true
    case "$url" in
        https://mega.nz/*|https://mega.io/*)
            recipe_assets::_download_mega "$url" "$dest" || return 1
            ;;
        *)
            recipe_assets::_download_https "$url" "$dest" || return 1
            ;;
    esac
    if [ -n "$sha" ]; then
        recipe_assets::verify_sha256 "$dest" "$sha" || {
            rm -f "$dest"
            echo "ERROR: SHA-256 mismatch: $dest" >&2
            return 1
        }
    fi
    return 0
}
