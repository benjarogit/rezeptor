#!/usr/bin/env bats
# recipe-install enum validation (install_type / source_kind)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-install.sh"
}

@test "recipe_install rejects unknown install_type" {
    run recipe_install::_validate_install_type "not_a_real_type"
    [ "$status" -ne 0 ]
    [[ "$output" == *install_type* ]]
}

@test "recipe_install accepts portable_launch install_type" {
    run recipe_install::_validate_install_type "portable_launch"
    [ "$status" -eq 0 ]
}

@test "recipe_install rejects unknown source_kind" {
    run recipe_install::_validate_source_kind "magic"
    [ "$status" -ne 0 ]
    [[ "$output" == *source_kind* ]]
}

@test "recipe_install accepts folder source_kind" {
    run recipe_install::_validate_source_kind "folder"
    [ "$status" -eq 0 ]
}
