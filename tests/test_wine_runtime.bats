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

@test "wine_runtime _find_proton_dir prefers exact lock tag only" {
    export HOME="$BATS_TEST_TMPDIR/wine-home-exact"
    mkdir -p "$HOME"
    wine_runtime::reset
    wine_runtime::_load_lock
    base="$(wine_runtime::_user_runtime_base)"
    wrong="$base/GE-Proton9-0"
    right="$base/${PROTON_GE_TAG}"
    mkdir -p "$wrong/files/bin" "$right/files/bin"
    touch "$wrong/files/bin/wine" "$right/files/bin/wine"
    chmod +x "$wrong/files/bin/wine" "$right/files/bin/wine"
    run wine_runtime::_find_proton_dir
    [ "$status" -eq 0 ]
    [[ "$output" == "$right" ]]
}

@test "wine_runtime _find_proton_dir does not pick wrong tag via glob" {
    export HOME="$BATS_TEST_TMPDIR/wine-home-wrong"
    mkdir -p "$HOME"
    wine_runtime::reset
    wine_runtime::_load_lock
    base="$(wine_runtime::_user_runtime_base)"
    wrong="$base/GE-Proton9-0"
    mkdir -p "$wrong/files/bin"
    touch "$wrong/files/bin/wine"
    chmod +x "$wrong/files/bin/wine"
    run wine_runtime::_find_proton_dir
    [ "$status" -ne 0 ]
}

@test "wine_runtime _load_lock preserves recipe PROTON_GE_TAG override" {
    export HOME="$BATS_TEST_TMPDIR/wine-home-pin"
    mkdir -p "$HOME"
    wine_runtime::reset
    export PROTON_GE_TAG="GE-Proton11-3"
    unset PROTON_GE_URL PROTON_GE_SHA256
    wine_runtime::_load_lock
    [ "$PROTON_GE_TAG" = "GE-Proton11-3" ]
    [[ "$PROTON_GE_URL" == *GE-Proton11-3* ]]
    [ -n "$PROTON_GE_SHA256" ]
    [ "${#PROTON_GE_SHA256}" -eq 64 ]
}

@test "wine_runtime _load_lock default tag is GE-Proton10-28" {
    export HOME="$BATS_TEST_TMPDIR/wine-home-default"
    mkdir -p "$HOME"
    wine_runtime::reset
    unset PROTON_GE_TAG PROTON_GE_URL PROTON_GE_SHA256
    wine_runtime::_load_lock
    [ "$PROTON_GE_TAG" = "GE-Proton10-28" ]
    [[ "$PROTON_GE_URL" == *GE-Proton10-28* ]]
}
