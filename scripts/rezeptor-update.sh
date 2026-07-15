#!/usr/bin/env bash
# Rezeptor self-update with backup + rollback (git clone or AppImage).
# Usage:
#   rezeptor-update.sh detect
#   rezeptor-update.sh apply [tag]
#   rezeptor-update.sh list
#   rezeptor-update.sh rollback <backup_id>
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="${REZEPTOR_GITHUB_REPO:-benjarogit/rezeptor}"
BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/wine-software/rezeptor/backups"
MAX_BACKUPS=3
VERSION_FILE="$ROOT/VERSION"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

current_version() {
    if [ -f "$VERSION_FILE" ]; then
        tr -d '\n' < "$VERSION_FILE"
    else
        echo "dev"
    fi
}

detect_mode() {
    # Nur echte Rezeptor-AppImage — nicht Cursor/andere APPIMAGE-Env
    if [ -n "${APPIMAGE:-}" ] && [ -f "$APPIMAGE" ]; then
        case "${APPIMAGE,,}" in
            *photoshopcclinux*|*rezeptor*)
                echo "appimage"
                return
                ;;
        esac
    fi
    case "$ROOT" in
        *.AppImage) echo "appimage"; return ;;
    esac
    if [ -d "$ROOT/.git" ]; then
        echo "git"
        return
    fi
    echo "tarball"
}

# Remote für Tags/Releases: bevorzugt „rezeptor“, sonst origin (Clone von benjarogit/rezeptor).
git_update_remote() {
    if git -C "$ROOT" remote get-url rezeptor >/dev/null 2>&1; then
        echo "rezeptor"
    else
        echo "origin"
    fi
}

latest_release_tag() {
    local json tag
    json="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)"
    tag="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tag_name",""))' 2>/dev/null || true)"
    [ -n "$tag" ] || die "Konnte neuestes Release nicht ermitteln"
    echo "$tag"
}

prune_backups() {
    [ -d "$BACKUP_ROOT" ] || return 0
    local dirs
    mapfile -t dirs < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r)
    local i=0
    for d in "${dirs[@]}"; do
        i=$((i + 1))
        if [ "$i" -gt "$MAX_BACKUPS" ]; then
            info "Lösche altes Backup: $d"
            rm -rf "$BACKUP_ROOT/$d"
        fi
    done
}

write_meta() {
    local dest="$1" mode="$2" from_v="$3" to_v="$4" path="$5"
    python3 - "$dest/meta.json" "$mode" "$from_v" "$to_v" "$path" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
meta = {
    "mode": sys.argv[2],
    "version_from": sys.argv[3],
    "version_to": sys.argv[4],
    "path": sys.argv[5],
}
path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
PY
}

backup_git_or_tree() {
    local ts mode from_v to_v dest
    ts="$(date +%Y%m%d-%H%M%S)"
    mode="$(detect_mode)"
    from_v="$(current_version)"
    to_v="${1:-unknown}"
    dest="$BACKUP_ROOT/$ts"
    mkdir -p "$dest"
    info "Backup → $dest"
    tar -C "$ROOT" \
        --exclude='.git' \
        --exclude='photoshop/packages' \
        --exclude='photoshop/Set-up.exe' \
        --exclude='AppDir-build' \
        --exclude='.cache' \
        --exclude='logs' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        -czf "$dest/tree.tar.gz" .
    write_meta "$dest" "$mode" "$from_v" "$to_v" "$ROOT"
    prune_backups
    echo "$ts"
}

backup_appimage() {
    local ts from_v to_v dest src
    ts="$(date +%Y%m%d-%H%M%S)"
    from_v="$(current_version)"
    to_v="${1:-unknown}"
    src="${APPIMAGE:-}"
    [ -n "$src" ] && [ -f "$src" ] || die "APPIMAGE nicht gesetzt / nicht gefunden"
    dest="$BACKUP_ROOT/$ts"
    mkdir -p "$dest"
    info "Backup AppImage → $dest"
    cp -a "$src" "$dest/rezeptor.AppImage"
    write_meta "$dest" "appimage" "$from_v" "$to_v" "$src"
    prune_backups
    echo "$ts"
}

apply_git() {
    local tag="${1:-}" remote
    [ -n "$tag" ] || tag="$(latest_release_tag)"
    local ver="${tag#v}"
    backup_git_or_tree "$ver" >/dev/null
    remote="$(git_update_remote)"
    info "git fetch + checkout $tag (remote: $remote)"
    git -C "$ROOT" fetch --tags --force "$remote"
    if git -C "$ROOT" rev-parse "$tag" >/dev/null 2>&1; then
        git -C "$ROOT" checkout --force "$tag"
    elif git -C "$ROOT" rev-parse "tags/$tag" >/dev/null 2>&1; then
        git -C "$ROOT" checkout --force "tags/$tag"
    else
        die "Tag $tag nicht gefunden (remote $remote)"
    fi
    echo "$ver" > "$VERSION_FILE"
    info "Update auf $ver abgeschlossen"
}

apply_tarball() {
    local tag="${1:-}"
    [ -n "$tag" ] || tag="$(latest_release_tag)"
    local ver="${tag#v}"
    local url staging
    backup_git_or_tree "$ver" >/dev/null
    url="https://github.com/${GITHUB_REPO}/archive/refs/tags/${tag}.tar.gz"
    staging="$(mktemp -d)"
    info "Lade $url"
    curl -fsSL "$url" -o "$staging/src.tar.gz"
    mkdir -p "$staging/extract"
    tar -xzf "$staging/src.tar.gz" -C "$staging/extract"
    local src_dir
    src_dir="$(find "$staging/extract" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [ -n "$src_dir" ] || die "Tarball leer"
    rsync -a --delete \
        --exclude='.git' \
        --exclude='photoshop/packages' \
        --exclude='photoshop/Set-up.exe' \
        --exclude='AppDir-build' \
        --exclude='.cache' \
        "$src_dir/" "$ROOT/"
    echo "$ver" > "$VERSION_FILE"
    rm -rf "$staging"
    info "Update auf $ver abgeschlossen (tarball)"
}

apply_appimage() {
    local tag="${1:-}"
    [ -n "$tag" ] || tag="$(latest_release_tag)"
    local ver="${tag#v}"
    local json asset_url dest
    backup_appimage "$ver" >/dev/null
    json="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${tag}" 2>/dev/null \
        || curl -fsSL -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")"
    asset_url="$(printf '%s' "$json" | python3 -c '
import json,sys,re
d=json.load(sys.stdin)
assets=d.get("assets") or []
# Prefer rezeptor-*.AppImage; fall back to any AppImage (legacy photoshopCClinux-*)
picked=""
for a in assets:
    name=a.get("name") or ""
    if re.search(r"(?i)^rezeptor-.*\.AppImage$", name):
        picked=a.get("browser_download_url","")
        break
if not picked:
    for a in assets:
        name=a.get("name") or ""
        if re.search(r"AppImage$", name, re.I):
            picked=a.get("browser_download_url","")
            break
print(picked)
')"
    [ -n "$asset_url" ] || die "Kein AppImage-Asset in Release $tag"
    dest="${APPIMAGE}"
    info "Lade AppImage → $dest"
    curl -fsSL "$asset_url" -o "${dest}.new"
    chmod +x "${dest}.new"
    mv -f "${dest}.new" "$dest"
    info "AppImage Update auf $ver abgeschlossen"
}

cmd_apply() {
    local tag="${1:-}" mode
    mode="$(detect_mode)"
    info "Modus: $mode"
    case "$mode" in
        git) apply_git "$tag" ;;
        appimage) apply_appimage "$tag" ;;
        tarball) apply_tarball "$tag" ;;
        *) die "Unbekannter Modus: $mode" ;;
    esac
}

cmd_list() {
    [ -d "$BACKUP_ROOT" ] || { echo "[]"; return 0; }
    python3 - "$BACKUP_ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
items = []
for d in sorted(root.iterdir(), reverse=True):
    if not d.is_dir():
        continue
    meta = {}
    mp = d / "meta.json"
    if mp.is_file():
        try:
            meta = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            meta = {}
    items.append({"id": d.name, **meta})
print(json.dumps(items, indent=2))
PY
}

cmd_rollback() {
    local bid="${1:-}" dest mode path
    [ -n "$bid" ] || die "Usage: rollback <backup_id>"
    dest="$BACKUP_ROOT/$bid"
    [ -d "$dest" ] || die "Backup nicht gefunden: $bid"
    mode="$(python3 -c "import json; print(json.load(open('$dest/meta.json')).get('mode',''))" 2>/dev/null || true)"
    path="$(python3 -c "import json; print(json.load(open('$dest/meta.json')).get('path',''))" 2>/dev/null || true)"
    case "$mode" in
        appimage)
            [ -f "$dest/rezeptor.AppImage" ] || die "AppImage-Backup fehlt"
            target="${path:-$APPIMAGE}"
            [ -n "$target" ] || die "Ziel-AppImage unbekannt"
            cp -a "$dest/rezeptor.AppImage" "$target"
            chmod +x "$target"
            info "AppImage Rollback → $target"
            ;;
        git|tarball|"")
            [ -f "$dest/tree.tar.gz" ] || die "tree.tar.gz fehlt"
            tar -xzf "$dest/tree.tar.gz" -C "$ROOT"
            info "Tree Rollback → $ROOT"
            ;;
        *) die "Unbekannter Backup-Modus: $mode" ;;
    esac
}

cmd="${1:-}"
case "$cmd" in
    detect) detect_mode ;;
    apply) shift; cmd_apply "${1:-}" ;;
    list) cmd_list ;;
    rollback) shift; cmd_rollback "${1:-}" ;;
    *)
        echo "Usage: $0 {detect|apply [tag]|list|rollback <id>}" >&2
        exit 2
        ;;
esac
