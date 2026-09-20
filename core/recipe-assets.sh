#!/usr/bin/env bash
# Shared remote-asset fetch: cache/<recipe-id>/ (never ~/Downloads as dest),
# SHA-256 verify, then discard archives after a successful consume.
# Same checksum idea as proton-ge-fetch / nvidia-libs. No recipe-id literals.
#
# MEGA: only public /file/ or /folder/ shares with a key. /fm/ is rejected.
# mega-get (mega-cmd) is required for mega.nz links; curl cannot decrypt them.
# A leftover file in ~/Downloads may seed once; it is not copied as a store.

recipe_assets::_lock_file() {
    local root="${PROJECT_ROOT:-}"
    if [ -z "$root" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
        root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    fi
    echo "${root}/core/recipe-assets.lock"
}

recipe_assets::_load_lock() {
    local lock line key val
    lock="$(recipe_assets::_lock_file)"
    [ -f "$lock" ] || return 0
    # Do not source the lock: an unquoted MEGA #key is a shell comment.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            MEGA_ASSETS_BASE_URL=*|MEGA_ASSETS_REMOTE_DIR=*)
                key="${line%%=*}"
                val="${line#*=}"
                val="${val#\"}"
                val="${val%\"}"
                printf -v "$key" '%s' "$val"
                ;;
        esac
    done <"$lock"
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

# mega-get accepts exportedfolderurl#key/remotepath (path after the key).
recipe_assets::join_mega_folder_url() {
    local base="${1:-}" rel="${2:-}"
    [ -n "$base" ] && [ -n "$rel" ] || return 1
    printf '%s/%s' "${base%/}" "${rel#/}"
}

# recipes/<id>/assets/remote.yml or recipes/<id>/assets/<bundle>/remote.yml
recipe_assets::recipe_id_from_remote_yml() {
    python3 - "${1:?}" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
print(p.parents[2].name if p.parent.name != "assets" else p.parents[1].name)
PY
}

# Pack url if public; else MEGA folder base + <recipe_id>/<file>. Never /fm/.
recipe_assets::resolve_pack_url() {
    local pack_url="${1:-}" file="${2:-}" recipe_id="${3:-}"
    local base
    if [ -n "$pack_url" ] && recipe_assets::is_public_share_url "$pack_url"; then
        printf '%s' "$pack_url"
        return 0
    fi
    base="$(recipe_assets::mega_base_url)"
    [ -n "$base" ] || return 1
    recipe_assets::is_public_share_url "$base" || return 1
    case "$base" in
        https://mega.nz/file/*#*|https://mega.io/file/*#*)
            printf '%s' "$base"
            return 0
            ;;
        https://mega.nz/folder/*#*|https://mega.io/folder/*#*)
            if [ -n "$recipe_id" ] && [ -n "$file" ]; then
                recipe_assets::join_mega_folder_url "$base" "${recipe_id}/${file}"
                return 0
            fi
            if [ -n "$file" ]; then
                recipe_assets::join_mega_folder_url "$base" "$file"
                return 0
            fi
            printf '%s' "$base"
            return 0
            ;;
        *)
            printf '%s' "$base"
            return 0
            ;;
    esac
}

recipe_assets::_pack_meta() {
    python3 - "${1:?}" "${2:?}" <<'PY'
from pathlib import Path
import sys
want = sys.argv[2]
cur = None
hit = None
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    s = line.strip()
    if s.startswith("- id:"):
        if cur and cur.get("id") == want:
            hit = cur
        cur = {"id": s.split(":", 1)[1].strip().strip('"')}
        continue
    if cur and ":" in s and not s.startswith("- "):
        key, val = s.split(":", 1)
        cur[key.strip()] = val.strip().strip('"')
if cur and cur.get("id") == want:
    hit = cur
if not hit:
    raise SystemExit(1)
print(hit.get("file", ""))
print(hit.get("sha256", ""))
print(hit.get("url", ""))
print(hit.get("cache_rel", ""))
PY
}

recipe_assets::_cache_base() {
    if type wine_software_base >/dev/null 2>&1; then
        echo "$(wine_software_base)/cache"
    else
        echo "${WINE_SOFTWARE_BASE:-$HOME/.local/share/wine-software}/cache"
    fi
}

recipe_assets::_downloads_dir() {
    echo "${HOME}/Downloads"
}

# True for a consumed archive (deleted after a successful extract/overlay).
recipe_assets::is_archive() {
    local name="${1:-}"
    name="${name##*/}"
    case "${name,,}" in
        *.zip|*.rar|*.7z|*.tar|*.tgz|*.tbz2|*.txz|*.tar.gz|*.tar.bz2|*.tar.xz)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

recipe_assets::_safe_basename() {
    local f="${1:-}"
    f="${f##*/}"
    case "$f" in
        ""|.|..|*/*|*\\*) return 1 ;;
    esac
    printf '%s' "$f"
}

recipe_assets::_is_downloads_path() {
    local p="${1:-}" dl
    [ -n "$p" ] || return 1
    dl="$(recipe_assets::_downloads_dir)"
    case "$p" in
        "$dl"|"$dl"/*) return 0 ;;
    esac
    return 1
}

# Uninstall: drop cache/<recipe-id>/ and cache/<recipe-id>-mod-bundle/.
# Overlay, leftover zips, and loose .tpf live there. Shared caches stay
# (winetricks, vcredist, nvidia-libs). Never touches ~/Downloads.
recipe_assets::purge_recipe_cache() {
    local recipe_id="${1:-${RECIPE_ID:-}}"
    local cache_base dest name yml _id file cache_rel first
    recipe_id="$(recipe_assets::_safe_basename "$recipe_id")" || return 0
    cache_base="$(recipe_assets::_cache_base)"
    [ -n "$cache_base" ] || return 0

    recipe_assets::_purge_named_cache_dir() {
        local n="${1:-}" d
        n="$(recipe_assets::_safe_basename "$n")" || return 0
        d="${cache_base}/${n}"
        [ -e "$d" ] || return 0
        rm -rf "$d"
    }

    recipe_assets::_purge_named_cache_dir "$recipe_id"
    recipe_assets::_purge_named_cache_dir "${recipe_id}-mod-bundle"

    if [ -n "${RECIPE_DIR:-}" ] && [ -d "${RECIPE_DIR}/assets" ]; then
        while IFS= read -r -d '' yml; do
            [ -f "$yml" ] || continue
            while IFS=$'\t' read -r _id file cache_rel; do
                [ -n "$cache_rel" ] || continue
                cache_rel="${cache_rel#/}"
                case "$cache_rel" in
                    cache/*) cache_rel="${cache_rel#cache/}" ;;
                esac
                first="${cache_rel%%/*}"
                [ -n "$first" ] || continue
                # Recipe-owned names only. Never winetricks / vcredist / nvidia-libs.
                if [ "$first" = "$recipe_id" ] || [ "$first" = "${recipe_id}-mod-bundle" ]; then
                    recipe_assets::_purge_named_cache_dir "$first"
                fi
            done < <(recipe_assets::_each_pack "$yml")
        done < <(find "${RECIPE_DIR}/assets" -name remote.yml -print0 2>/dev/null)
    fi

    # Empty leftover dirs from older cache names (<id>-*). Non-empty stays.
    if [ -d "$cache_base" ]; then
        for dest in "$cache_base/${recipe_id}-"*; do
            [ -d "$dest" ] || continue
            [ -z "$(ls -A "$dest" 2>/dev/null)" ] || continue
            rm -rf "$dest"
        done
    fi
    return 0
}

# Staging dest: cache/<recipe-id>/<file>. Never ~/Downloads.
recipe_assets::pack_dest() {
    local recipe_id="${1:?}" file="${2:?}"
    file="$(recipe_assets::_safe_basename "$file")" || return 1
    echo "$(recipe_assets::_cache_base)/${recipe_id}/${file}"
}

# Optional one-shot seed in ~/Downloads/<file>. Never required. Never copied.
recipe_assets::optional_downloads_seed() {
    local file sha cand
    file="$(recipe_assets::_safe_basename "${1:-}")" || return 1
    sha="${2:-}"
    cand="$(recipe_assets::_downloads_dir)/${file}"
    [ -f "$cand" ] || return 1
    if [ -n "$sha" ]; then
        recipe_assets::verify_sha256 "$cand" "$sha" || return 1
    fi
    printf '%s' "$cand"
}

# Delete one consumed archive. Loose files (tpf, dll, …) stay. Missing path is OK.
recipe_assets::discard_consumed_archive() {
    local path="${1:-}"
    [ -n "$path" ] && [ -f "$path" ] || return 0
    recipe_assets::is_archive "$path" || return 0
    rm -f "$path"
}

recipe_assets::_each_pack() {
    python3 - "${1:?}" <<'PY'
from pathlib import Path
import sys
cur = None
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    s = line.strip()
    if s.startswith("- id:"):
        if cur and cur.get("file"):
            print("\t".join([cur.get("id", ""), cur.get("file", ""), cur.get("cache_rel", "")]))
        cur = {"id": s.split(":", 1)[1].strip().strip('"')}
        continue
    if cur and ":" in s and not s.startswith("- "):
        key, val = s.split(":", 1)
        cur[key.strip()] = val.strip().strip('"')
if cur and cur.get("file"):
    print("\t".join([cur.get("id", ""), cur.get("file", ""), cur.get("cache_rel", "")]))
PY
}

# After a successful consume: drop archive dests + leftover Downloads seeds.
# Overlay / used loose files are not archives and stay.
recipe_assets::discard_yml_archives() {
    local yml="${1:?}" recipe_id="${2:-}" file dest cache_rel
    [ -f "$yml" ] || return 0
    if [ -z "$recipe_id" ]; then
        recipe_id="$(recipe_assets::recipe_id_from_remote_yml "$yml")" || return 0
    fi
    while IFS=$'\t' read -r _id file cache_rel; do
        [ -n "$file" ] || continue
        recipe_assets::is_archive "$file" || continue
        dest="$(recipe_assets::pack_dest "$recipe_id" "$file")" || continue
        recipe_assets::discard_consumed_archive "$dest"
        if [ -n "$cache_rel" ]; then
            recipe_assets::discard_consumed_archive "$(recipe_assets::_cache_base)/${cache_rel}"
        fi
        recipe_assets::discard_consumed_archive "$(recipe_assets::_cache_base)/${recipe_id}-mod-bundle/${file}"
        recipe_assets::discard_consumed_archive "$(recipe_assets::_downloads_dir)/${file}"
    done < <(recipe_assets::_each_pack "$yml")
}

# Resolve a usable pack path (cache dest or Downloads seed). Sets RECIPE_ASSETS_STAGED.
# Optional 5th arg: nameref target for the path.
recipe_assets::stage_pack() {
    local yml="${1:?}" pack_id="${2:?}" dest="${3:-}" recipe_id="${4:-}" outvar="${5:-}"
    local meta file sha url cache_rel seed usable
    RECIPE_ASSETS_STAGED=""
    [ -f "$yml" ] || return 1
    if [ -z "$recipe_id" ]; then
        recipe_id="$(recipe_assets::recipe_id_from_remote_yml "$yml")" || return 1
    fi
    meta="$(recipe_assets::_pack_meta "$yml" "$pack_id")" || return 1
    file="$(printf '%s\n' "$meta" | sed -n '1p')"
    sha="$(printf '%s\n' "$meta" | sed -n '2p')"
    url="$(printf '%s\n' "$meta" | sed -n '3p')"
    cache_rel="$(printf '%s\n' "$meta" | sed -n '4p')"
    [ -n "$file" ] || return 1
    if [ -z "$dest" ] || recipe_assets::_is_downloads_path "$dest"; then
        dest="$(recipe_assets::pack_dest "$recipe_id" "$file")" || return 1
    fi
    usable=""
    if [ -f "$dest" ] && [ -n "$sha" ] && recipe_assets::verify_sha256 "$dest" "$sha"; then
        usable="$dest"
    elif seed="$(recipe_assets::optional_downloads_seed "$file" "$sha")"; then
        usable="$seed"
    elif [ -n "$cache_rel" ] && [ -f "$(recipe_assets::_cache_base)/${cache_rel}" ] \
        && [ -n "$sha" ] \
        && recipe_assets::verify_sha256 "$(recipe_assets::_cache_base)/${cache_rel}" "$sha"; then
        usable="$(recipe_assets::_cache_base)/${cache_rel}"
    elif [ -f "$(recipe_assets::_cache_base)/${recipe_id}-mod-bundle/${file}" ] \
        && [ -n "$sha" ] \
        && recipe_assets::verify_sha256 "$(recipe_assets::_cache_base)/${recipe_id}-mod-bundle/${file}" "$sha"; then
        usable="$(recipe_assets::_cache_base)/${recipe_id}-mod-bundle/${file}"
    else
        url="$(recipe_assets::resolve_pack_url "$url" "$file" "$recipe_id")" || return 1
        recipe_assets::ensure "$dest" "$url" "$sha" || return 1
        usable="$dest"
    fi
    RECIPE_ASSETS_STAGED="$usable"
    if [ -n "$outvar" ]; then
        local -n _recipe_assets_out="$outvar"
        _recipe_assets_out="$usable"
    fi
    return 0
}

# Fetch any recipes/*/assets/**/remote.yml pack. dest optional (cache/<recipe-id>/<file>).
# ~/Downloads is never the dest. A matching Downloads file may seed once (no copy).
recipe_assets::fetch_pack() {
    local yml="${1:?}" pack_id="${2:?}" dest="${3:-}" recipe_id="${4:-}"
    recipe_assets::stage_pack "$yml" "$pack_id" "$dest" "$recipe_id" || return 1
    # Loose files stay at dest. Archives are deleted by discard_* after consume.
    if [ -n "$dest" ] && ! recipe_assets::_is_downloads_path "$dest" \
        && [ -n "${RECIPE_ASSETS_STAGED:-}" ] \
        && [ "$RECIPE_ASSETS_STAGED" != "$dest" ] \
        && [ -f "$RECIPE_ASSETS_STAGED" ] \
        && ! recipe_assets::is_archive "$RECIPE_ASSETS_STAGED"; then
        mkdir -p "$(dirname "$dest")"
        cp -f "$RECIPE_ASSETS_STAGED" "$dest" || return 1
    fi
    return 0
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
