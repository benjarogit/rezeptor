#!/usr/bin/env bats
# Silent offline installer helpers (Inno /LANG)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-hooks.sh"
}

@test "installer_lang maps de_DE to german" {
    LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 LC_MESSAGES=de_DE.UTF-8 \
        run recipe_hooks::installer_lang
    [ "$status" -eq 0 ]
    [ "$output" = "german" ]
}

@test "installer_lang maps en_US to english" {
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_MESSAGES=en_US.UTF-8 \
        run recipe_hooks::installer_lang
    [ "$status" -eq 0 ]
    [ "$output" = "english" ]
}
