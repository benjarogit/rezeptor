#!/usr/bin/env bats
# Shared remote-asset fetch: public shares only, SHA-256, no /fm/.

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-assets.sh"
}

@test "is_public_share_url accepts MEGA file/folder with key and rejects /fm/" {
    recipe_assets::is_public_share_url "https://mega.nz/file/AbCd#keyKEY"
    recipe_assets::is_public_share_url "https://mega.nz/folder/AbCd#keyKEY"
    ! recipe_assets::is_public_share_url "https://mega.nz/fm/4BhCRArI"
    ! recipe_assets::is_public_share_url ""
    ! recipe_assets::is_public_share_url "http://mega.nz/file/AbCd#keyKEY"
}

@test "verify_sha256 accepts a matching file and rejects a mismatch" {
    tmp="$(mktemp)"
    printf 'rezeptor-asset\n' >"$tmp"
    want="$(sha256sum "$tmp" | awk '{print $1}')"
    recipe_assets::verify_sha256 "$tmp" "$want"
    ! recipe_assets::verify_sha256 "$tmp" "0000000000000000000000000000000000000000000000000000000000000000"
    rm -f "$tmp"
}

@test "ensure refuses a File-Manager URL even if dest is missing" {
    dest="$(mktemp -u)"
    ! recipe_assets::ensure "$dest" "https://mega.nz/fm/4BhCRArI" "abc"
    [ ! -e "$dest" ]
}

@test "ensure keeps a dest whose sha256 already matches" {
    dest="$(mktemp)"
    printf 'keep-me\n' >"$dest"
    want="$(sha256sum "$dest" | awk '{print $1}')"
    recipe_assets::ensure "$dest" "" "$want"
    grep -q keep-me "$dest"
    rm -f "$dest"
}

@test "lock file has a public MEGA folder share and a remote dir" {
    grep -q '^MEGA_ASSETS_REMOTE_DIR=' "$ROOT/core/recipe-assets.lock"
    ! grep -E '^MEGA_ASSETS_BASE_URL=.*/fm/' "$ROOT/core/recipe-assets.lock"
    line="$(grep -E '^MEGA_ASSETS_BASE_URL=' "$ROOT/core/recipe-assets.lock" | tail -n1)"
    url="${line#MEGA_ASSETS_BASE_URL=}"
    url="${url#\"}"
    url="${url%\"}"
    recipe_assets::is_public_share_url "$url"
}

@test "recipe-assets.sh has no official recipe-id literals" {
    ! grep -E "['\"]prototype['\"]" "$ROOT/core/recipe-assets.sh"
}

@test "join_mega_folder_url appends the path after the key" {
    got="$(recipe_assets::join_mega_folder_url "https://mega.nz/folder/AbCd#keyKEY" "demo/pack.zip")"
    [ "$got" = "https://mega.nz/folder/AbCd#keyKEY/demo/pack.zip" ]
}

@test "resolve_pack_url prefers a public pack url" {
    got="$(recipe_assets::resolve_pack_url "https://mega.nz/file/Ff#kk" "pack.zip" "demo")"
    [ "$got" = "https://mega.nz/file/Ff#kk" ]
}

@test "resolve_pack_url uses folder base plus recipe id and file" {
    got="$(REZEPTOR_MEGA_ASSETS_URL="https://mega.nz/folder/AbCd#keyKEY" \
        recipe_assets::resolve_pack_url "" "pack.zip" "demo")"
    [ "$got" = "https://mega.nz/folder/AbCd#keyKEY/demo/pack.zip" ]
}

@test "resolve_pack_url rejects a File-Manager base" {
    ! REZEPTOR_MEGA_ASSETS_URL="https://mega.nz/fm/4BhCRArI" \
        recipe_assets::resolve_pack_url "" "pack.zip" "demo"
}

@test "fetch_pack keeps dest when sha256 already matches" {
    dest="$(mktemp)"
    yml="$(mktemp)"
    printf 'keep-pack\n' >"$dest"
    want="$(sha256sum "$dest" | awk '{print $1}')"
    cat >"$yml" <<EOF
version: 1
packs:
  - id: demo-pack
    file: keep.txt
    sha256: $want
    url: ""
EOF
    recipe_assets::fetch_pack "$yml" demo-pack "$dest" demo
    grep -q keep-pack "$dest"
    rm -f "$dest" "$yml"
}

@test "pack_dest is cache/<recipe-id>/file and never Downloads" {
    export WINE_SOFTWARE_BASE="$BATS_TEST_TMPDIR/wine-software"
    got="$(recipe_assets::pack_dest demo pack.zip)"
    [ "$got" = "$WINE_SOFTWARE_BASE/cache/demo/pack.zip" ]
    [[ "$got" != *"/Downloads/"* ]]
}

@test "is_archive is true for zip/rar/7z and false for tpf" {
    recipe_assets::is_archive "Prototype_DeuPatchBEP.zip"
    recipe_assets::is_archive "/tmp/mods/skin.rar"
    recipe_assets::is_archive "pack.7z"
    ! recipe_assets::is_archive "Venom Symbiote.tpf"
    ! recipe_assets::is_archive "overlay/art/hud/fe_textbible.p3d"
}

@test "discard_consumed_archive deletes a zip and leaves a tpf" {
    zipf="$BATS_TEST_TMPDIR/keep-or-not.zip"
    tpff="$BATS_TEST_TMPDIR/keep.tpf"
    printf 'arc\n' >"$zipf"
    printf 'loose\n' >"$tpff"
    recipe_assets::discard_consumed_archive "$zipf"
    recipe_assets::discard_consumed_archive "$tpff"
    [ ! -f "$zipf" ]
    [ -f "$tpff" ]
}

@test "stage_pack uses a Downloads seed once and does not copy it as store" {
    export HOME="$BATS_TEST_TMPDIR/home"
    export WINE_SOFTWARE_BASE="$BATS_TEST_TMPDIR/wine-software"
    mkdir -p "$HOME/Downloads"
    yml="$BATS_TEST_TMPDIR/remote.yml"
    printf 'seed-bytes\n' >"$HOME/Downloads/demo-pack.zip"
    want="$(sha256sum "$HOME/Downloads/demo-pack.zip" | awk '{print $1}')"
    cat >"$yml" <<EOF
version: 1
packs:
  - id: demo-pack
    file: demo-pack.zip
    sha256: $want
    url: ""
EOF
    staged=""
    recipe_assets::stage_pack "$yml" demo-pack "" demo staged
    [ "$staged" = "$HOME/Downloads/demo-pack.zip" ]
    [ ! -f "$WINE_SOFTWARE_BASE/cache/demo/demo-pack.zip" ]
}

@test "discard_yml_archives drops leftover zips after success and keeps tpf" {
    export HOME="$BATS_TEST_TMPDIR/home"
    export WINE_SOFTWARE_BASE="$BATS_TEST_TMPDIR/wine-software"
    mkdir -p "$HOME/Downloads" "$WINE_SOFTWARE_BASE/cache/demo" \
        "$WINE_SOFTWARE_BASE/cache/demo-mod-bundle"
    yml="$BATS_TEST_TMPDIR/remote.yml"
    printf 'z\n' >"$HOME/Downloads/demo-pack.zip"
    printf 'z\n' >"$WINE_SOFTWARE_BASE/cache/demo/demo-pack.zip"
    printf 'z\n' >"$WINE_SOFTWARE_BASE/cache/demo-mod-bundle/demo-pack.zip"
    printf 't\n' >"$WINE_SOFTWARE_BASE/cache/demo/skin.tpf"
    printf 't\n' >"$HOME/Downloads/skin.tpf"
    cat >"$yml" <<EOF
version: 1
packs:
  - id: demo-pack
    file: demo-pack.zip
    cache_rel: demo-mod-bundle/demo-pack.zip
    sha256: unused
    url: ""
  - id: demo-skin
    file: skin.tpf
    cache_rel: demo/skin.tpf
    sha256: unused
    url: ""
EOF
    recipe_assets::discard_yml_archives "$yml" demo
    [ ! -f "$HOME/Downloads/demo-pack.zip" ]
    [ ! -f "$WINE_SOFTWARE_BASE/cache/demo/demo-pack.zip" ]
    [ ! -f "$WINE_SOFTWARE_BASE/cache/demo-mod-bundle/demo-pack.zip" ]
    [ -f "$WINE_SOFTWARE_BASE/cache/demo/skin.tpf" ]
    [ -f "$HOME/Downloads/skin.tpf" ]
}

@test "stage_pack refuses ~/Downloads as dest and writes cache/<recipe-id>/" {
    export HOME="$BATS_TEST_TMPDIR/home"
    export WINE_SOFTWARE_BASE="$BATS_TEST_TMPDIR/wine-software"
    mkdir -p "$HOME/Downloads" "$WINE_SOFTWARE_BASE/cache/demo"
    yml="$BATS_TEST_TMPDIR/remote.yml"
    printf 'cached\n' >"$WINE_SOFTWARE_BASE/cache/demo/demo-pack.zip"
    want="$(sha256sum "$WINE_SOFTWARE_BASE/cache/demo/demo-pack.zip" | awk '{print $1}')"
    cat >"$yml" <<EOF
version: 1
packs:
  - id: demo-pack
    file: demo-pack.zip
    sha256: $want
    url: ""
EOF
    staged=""
    recipe_assets::stage_pack "$yml" demo-pack "$HOME/Downloads/demo-pack.zip" demo staged
    [ "$staged" = "$WINE_SOFTWARE_BASE/cache/demo/demo-pack.zip" ]
    [ ! -e "$HOME/Downloads/demo-pack.zip" ]
}

@test "recipe_id_from_remote_yml walks assets or assets/bundle" {
    [ "$(recipe_assets::recipe_id_from_remote_yml "$ROOT/recipes/prototype/assets/mod-bundle/remote.yml")" = "prototype" ]
}

@test "purge_recipe_cache drops id and id-mod-bundle and keeps shared cache" {
    export WINE_SOFTWARE_BASE="$BATS_TEST_TMPDIR/wine-software"
    mkdir -p "$WINE_SOFTWARE_BASE/cache/demo" \
        "$WINE_SOFTWARE_BASE/cache/demo-mod-bundle/deu-overlay" \
        "$WINE_SOFTWARE_BASE/cache/demo-legacy" \
        "$WINE_SOFTWARE_BASE/cache/winetricks"
    printf 'z\n' >"$WINE_SOFTWARE_BASE/cache/demo/pack.zip"
    printf 'o\n' >"$WINE_SOFTWARE_BASE/cache/demo-mod-bundle/deu-overlay/.rezeptor-deu-stamp"
    printf 't\n' >"$WINE_SOFTWARE_BASE/cache/demo-mod-bundle/skin.tpf"
    printf 'w\n' >"$WINE_SOFTWARE_BASE/cache/winetricks/keep.bin"
    recipe_assets::purge_recipe_cache demo
    [ ! -e "$WINE_SOFTWARE_BASE/cache/demo" ]
    [ ! -e "$WINE_SOFTWARE_BASE/cache/demo-mod-bundle" ]
    [ ! -e "$WINE_SOFTWARE_BASE/cache/demo-legacy" ]
    [ -f "$WINE_SOFTWARE_BASE/cache/winetricks/keep.bin" ]
}
