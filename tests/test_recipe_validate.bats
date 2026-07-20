#!/usr/bin/env bats
load test_helper

setup() {
    setup_test_environment
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../core/recipe-validate.sh"
    TEST_PREFIX="$TEST_TMPDIR/prefix"
    mkdir -p "$TEST_PREFIX/drive_c/windows/syswow64"
}

teardown() {
    teardown_test_environment
}

@test "prefix_initialized requires user.reg" {
    run recipe_validate::prefix_initialized "$TEST_PREFIX"
    [ "$status" -eq 1 ]
    echo 'dummy' > "$TEST_PREFIX/user.reg"
    run recipe_validate::prefix_initialized "$TEST_PREFIX"
    [ "$status" -eq 0 ]
}

@test "windows_version reads registry files" {
    echo '"CurrentVersion"="10.0"' > "$TEST_PREFIX/system.reg"
    run recipe_validate::windows_version "$TEST_PREFIX" "win10"
    [ "$status" -eq 0 ]
    echo '"Version"="win10"' > "$TEST_PREFIX/user.reg"
    rm -f "$TEST_PREFIX/system.reg"
    run recipe_validate::windows_version "$TEST_PREFIX" "win10"
    [ "$status" -eq 0 ]
}

@test "dll_exists checks file presence" {
    run recipe_validate::dll_exists "$TEST_PREFIX/nope.dll"
    [ "$status" -eq 1 ]
    touch "$TEST_PREFIX/drive_c/windows/syswow64/gdiplus.dll"
    run recipe_validate::dll_exists "$TEST_PREFIX/drive_c/windows/syswow64/gdiplus.dll"
    [ "$status" -eq 0 ]
}
