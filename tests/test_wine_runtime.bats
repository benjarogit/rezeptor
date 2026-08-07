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

@test "wine_runtime _resolve_dxvk_root uses PROTON_GE_DXVK_TAG overlay" {
    export HOME="$BATS_TEST_TMPDIR/wine-home-dxvk"
    mkdir -p "$HOME"
    wine_runtime::reset
    base="$(wine_runtime::_user_runtime_base)"
    wine11="$base/GE-Proton11-3"
    wine10="$base/GE-Proton10-28"
    mkdir -p "$wine11/files/bin" "$wine11/files/lib/wine/dxvk/x86_64-windows"
    mkdir -p "$wine10/files/bin" "$wine10/files/lib/wine/dxvk/x86_64-windows"
    touch "$wine11/files/bin/wine" "$wine10/files/bin/wine"
    chmod +x "$wine11/files/bin/wine" "$wine10/files/bin/wine"
    export PROTON_GE_TAG="GE-Proton11-3"
    export PROTON_GE_DXVK_TAG="GE-Proton10-28"
    _WINE_RUNTIME_ROOT="$wine11"
    run wine_runtime::_resolve_dxvk_root "$wine11"
    [ "$status" -eq 0 ]
    [[ "$output" == "$wine10" ]]
}

@test "wine_runtime _resolve_dxvk_root falls back to wine root without overlay" {
    export HOME="$BATS_TEST_TMPDIR/wine-home-dxvk-off"
    mkdir -p "$HOME"
    wine_runtime::reset
    unset PROTON_GE_DXVK_TAG
    export PROTON_GE_TAG="GE-Proton11-3"
    wine11="$BATS_TEST_TMPDIR/fake-ge11"
    mkdir -p "$wine11/files/lib/wine/dxvk"
    run wine_runtime::_resolve_dxvk_root "$wine11"
    [ "$status" -eq 0 ]
    [[ "$output" == "$wine11" ]]
}

@test "recipe_photoshop apply_proton_pin sets GE-11 DXVK overlay and X11 flags" {
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-photoshop-install.sh"
    unset PROTON_GE_TAG PROTON_GE_URL PROTON_GE_SHA256 PROTON_GE_DXVK_TAG
    unset PHOTOSHOP_GE11_WINED3D PHOTOSHOP_GE11_FORCE_X11 WAYLAND_DISPLAY
    export WAYLAND_DISPLAY=wayland-0
    export PHOTOSHOP_PROTON_GE_11=1
    recipe_photoshop::apply_proton_pin
    [ "$PROTON_GE_TAG" = "GE-Proton11-3" ]
    [ "$PROTON_GE_DXVK_TAG" = "GE-Proton10-28" ]
    [ "$PHOTOSHOP_GE11_FORCE_X11" = "1" ]
    [ "${PROTON_ENABLE_WAYLAND:-}" = "0" ]
    [ -z "${WAYLAND_DISPLAY:-}" ]
    export PHOTOSHOP_PROTON_GE_11=0
    recipe_photoshop::apply_proton_pin
    [ -z "${PROTON_GE_DXVK_TAG:-}" ]
    [ -z "${PHOTOSHOP_GE11_FORCE_X11:-}" ]
    [ -z "${PROTON_GE_TAG:-}" ]
}

@test "recipe_photoshop GE-11 launch overrides disable d2d1" {
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-photoshop-install.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-photoshop-launch.sh"
    export PHOTOSHOP_PROTON_GE_11=1
    unset WINEDLLOVERRIDES
    recipe_photoshop::_export_launch_env
    [[ "$WINEDLLOVERRIDES" == *"d2d1=n"* ]]
    [[ "$WINEDLLOVERRIDES" != *"d2d1=builtin"* ]]
    export PHOTOSHOP_PROTON_GE_11=0
    unset WINEDLLOVERRIDES
    recipe_photoshop::_export_launch_env
    [[ "$WINEDLLOVERRIDES" == *"d2d1=builtin"* ]]
}
