#!/usr/bin/env bash
# Hash large remote packs and, if mega-cmd is logged in, upload + public-export.
# Writes sha256 (and url when a public share is created) into each remote.yml.
# Never writes /fm/ File-Manager URLs. Never stores MEGA passwords.
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/core/recipe-assets.sh"

CACHE_DEFAULT="${WINE_SOFTWARE_BASE:-$HOME/.local/share/wine-software}/cache"

mega_logged_in() {
    command -v mega-whoami >/dev/null 2>&1 && mega-whoami >/dev/null 2>&1
}

mega_put_export() {
    local local_file="${1:?}" dest_dir="${2:?}"
    local name remote_path link
    name="$(basename "$local_file")"
    remote_path="${dest_dir%/}/${name}"
    command -v mega-put >/dev/null 2>&1 || return 1
    command -v mega-mkdir >/dev/null 2>&1 && mega-mkdir -p "$dest_dir" >/dev/null 2>&1 || true
    mega-put "$local_file" "${dest_dir}/" >/dev/null || return 1
    command -v mega-export >/dev/null 2>&1 || return 1
    link="$(mega-export -a "$remote_path" 2>/dev/null | tr -d '\r' | awk '/https:\/\//{print $NF; exit}')"
    recipe_assets::is_public_share_url "$link" || return 1
    printf '%s' "$link"
}

update_remote_yaml() {
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import sys
from pathlib import Path

path, pack_id, sha, size, url = sys.argv[1:6]
lines = Path(path).read_text(encoding="utf-8").splitlines(keepends=True)
out = []
in_pack = False
id_hit = False
wrote_sha = wrote_size = wrote_url = False
indent = "    "

def flush_missing():
    extra = []
    if id_hit:
        if not wrote_sha:
            extra.append(f"{indent}sha256: {sha}\n")
        if not wrote_size:
            extra.append(f"{indent}size: {size}\n")
        if url and not wrote_url:
            extra.append(f'{indent}url: "{url}"\n')
    return extra

for line in lines:
    stripped = line.lstrip()
    if stripped.startswith("- id:"):
        out.extend(flush_missing())
        in_pack = True
        id_hit = pack_id in stripped
        wrote_sha = wrote_size = wrote_url = False
        out.append(line)
        continue
    if in_pack and id_hit:
        if stripped.startswith("sha256:"):
            out.append(f"{indent}sha256: {sha}\n")
            wrote_sha = True
            continue
        if stripped.startswith("size:"):
            out.append(f"{indent}size: {size}\n")
            wrote_size = True
            continue
        if stripped.startswith("url:"):
            out.append(f'{indent}url: "{url}"\n' if url else line)
            wrote_url = True
            continue
    out.append(line)
out.extend(flush_missing())
Path(path).write_text("".join(out), encoding="utf-8")
PY
}

find_local_file() {
    local file="${1:?}" cache_rel="${2:-}" recipe_cache="${3:-}"
    local cand
    for cand in \
        "${recipe_cache}/${file}" \
        "${CACHE_DEFAULT}/${cache_rel}" \
        "${CACHE_DEFAULT}/${file}" \
        "${HOME}/Downloads/${file}"
    do
        [ -n "$cand" ] && [ -f "$cand" ] && echo "$cand" && return 0
    done
    return 1
}

list_packs() {
    python3 - "$1" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
cur = None
for line in text.splitlines():
    s = line.strip()
    if s.startswith("- id:"):
        if cur:
            print("\t".join([
                cur.get("id", ""),
                cur.get("file", ""),
                cur.get("cache_rel", ""),
                cur.get("url", ""),
            ]))
        cur = {"id": s.split(":", 1)[1].strip().strip('"')}
        continue
    if cur and ":" in s and not s.startswith("- "):
        key, val = s.split(":", 1)
        cur[key.strip()] = val.strip().strip('"')
if cur:
    print("\t".join([
        cur.get("id", ""),
        cur.get("file", ""),
        cur.get("cache_rel", ""),
        cur.get("url", ""),
    ]))
PY
}

logged=0
if mega_logged_in; then
    logged=1
    echo "mega-cmd session: OK"
else
    echo "mega-cmd is not logged in (or not installed)."
    echo "Install MEGA-CLI, run mega-login, then: make recipe-assets-publish"
    echo "Hashes will still be written from local files."
fi

remote_dir="$(recipe_assets::mega_remote_dir)"
found=0
shopt -s nullglob
for remote in "$ROOT"/recipes/*/assets/*/remote.yml "$ROOT"/recipes/*/assets/remote.yml; do
    [ -f "$remote" ] || continue
    found=1
    rid="$(python3 -c 'from pathlib import Path; p=Path("'"$remote"'"); print(p.parents[2].name if p.parent.name!="assets" else p.parents[1].name)')"
    echo "→ $rid $(realpath --relative-to="$ROOT" "$remote")"
    recipe_cache="${CACHE_DEFAULT}/${rid}-mod-bundle"
    while IFS=$'\t' read -r pid file cache_rel url; do
        [ -n "$pid" ] || continue
        local=""
        local="$(find_local_file "$file" "$cache_rel" "$recipe_cache" || true)"
        if [ -z "$local" ]; then
            echo "  $pid: no local file ($file)"
            continue
        fi
        sha="$(sha256sum "$local" | awk '{print $1}')"
        size="$(wc -c <"$local" | tr -d ' ')"
        new_url=""
        case "$url" in
            *"/fm/"*) url="" ;;
        esac
        if [ "$logged" -eq 1 ] && [ -z "$url" ]; then
            dest="${remote_dir%/}/${rid}"
            if new_url="$(mega_put_export "$local" "$dest")"; then
                echo "  $pid: uploaded public share"
            else
                echo "  $pid: hashed, upload/export failed (public /file/ or /folder/ + key still needed)"
            fi
        elif [ -n "$url" ] && recipe_assets::is_public_share_url "$url"; then
            new_url="$url"
            echo "  $pid: keep public URL, sha256 updated"
        else
            echo "  $pid: sha256=$sha (no public URL yet)"
        fi
        update_remote_yaml "$remote" "$pid" "$sha" "$size" "$new_url"
    done < <(list_packs "$remote")
done
shopt -u nullglob

if [ "$found" -eq 0 ]; then
    echo "No recipes/*/assets/**/remote.yml found."
    exit 0
fi

if [ "$logged" -eq 0 ]; then
    echo
    echo "Next: install mega-cmd, mega-login, then make recipe-assets-publish"
    echo "A public /folder/ or /file/ + key is required before recipes can download."
fi
