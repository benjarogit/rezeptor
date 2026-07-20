#!/usr/bin/env bats
# Proton-GE fetch / wine-runtime error paths

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/proton-ge-fetch.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/wine-runtime.sh"
}

@test "proton_ge_fetch verify rejects bad checksum when SHA256 set" {
    archive="$BATS_TEST_TMPDIR/fake-proton.tar.gz"
    printf 'not-proton' >"$archive"
    PROTON_GE_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
    run proton_ge_fetch::verify_tarball "$archive"
    [ "$status" -ne 0 ]
}

@test "proton_ge_fetch verify skips checksum when SHA256 empty" {
    archive="$BATS_TEST_TMPDIR/open.tar.gz"
    printf 'payload' >"$archive"
    PROTON_GE_TAG=x PROTON_GE_URL=file:/// PROTON_GE_SHA256="" \
        run proton_ge_fetch::verify_tarball "$archive"
    [ "$status" -eq 0 ]
}

@test "proton_ge_fetch verify accepts matching checksum" {
    archive="$BATS_TEST_TMPDIR/match.tar.gz"
    printf 'payload' >"$archive"
    hash="$(sha256sum "$archive" | awk '{print $1}')"
    PROTON_GE_TAG=x PROTON_GE_URL=file:/// PROTON_GE_SHA256="$hash" \
        run proton_ge_fetch::verify_tarball "$archive"
    [ "$status" -eq 0 ]
}

@test "wine_runtime ensure_proton_ge fails on bad checksum archive" {
    export HOME="$BATS_TEST_TMPDIR/wine-home"
    mkdir -p "$HOME"
    wine_runtime::reset
    wine_runtime::_load_lock
    base="$(wine_runtime::_user_runtime_base)"
    mkdir -p "$base"
    archive="$base/${PROTON_GE_TAG}.tar.gz"
    printf 'bad-archive' >"$archive"
    run wine_runtime::ensure_proton_ge
    [ "$status" -ne 0 ]
    [[ "$output" == *ERROR:* ]]
}

@test "wine_runtime _fail prints ERROR" {
    run wine_runtime::_fail "synthetic failure"
    [ "$status" -ne 0 ]
    [[ "$output" == *ERROR:* ]]
    [[ "$output" == *"synthetic failure"* ]]
}
