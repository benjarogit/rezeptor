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
