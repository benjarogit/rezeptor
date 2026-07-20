#!/usr/bin/env bats
# env-file safe read/write (no eval injection)

load test_helper

setup() {
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../core/env-file.sh"
    ENVF="$BATS_TEST_TMPDIR/test.env"
}

@test "env_file round-trip preserves path with spaces" {
    env_file_set "$ENVF" PORTABLE_ROOT "/tmp/my portable/root"
    run env_file_get "$ENVF" PORTABLE_ROOT
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/my portable/root" ]
}

@test "env_file_get rejects command-substitution injection" {
    printf '%s\n' 'EVIL=$(touch '"$BATS_TEST_TMPDIR"'/pwned-rezeptor-injection)' > "$ENVF"
    run env_file_get "$ENVF" EVIL
    [ "$status" -ne 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/pwned-rezeptor-injection" ]
}

@test "env_file_load_export rejects unquoted injection" {
    printf '%s\n' 'EVIL=$(touch '"$BATS_TEST_TMPDIR"'/pwned-load-export)' > "$ENVF"
    run env_file_load_export "$ENVF"
    [ ! -f "$BATS_TEST_TMPDIR/pwned-load-export" ]
}

@test "env_file_load_export exports safe %q values" {
    env_file_write "$ENVF" WISO_PORTABLE_ROOT "/tmp/wiso root" WISO_PORTABLE_VERSION "2024"
    unset WISO_PORTABLE_ROOT WISO_PORTABLE_VERSION || true
    env_file_load_export "$ENVF"
    [ "$WISO_PORTABLE_ROOT" = "/tmp/wiso root" ]
    [ "$WISO_PORTABLE_VERSION" = "2024" ]
}