#!/usr/bin/env bats
# Shell i18n (RECIPE_UI_LANG)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/i18n.sh"
}

@test "msg::t returns German for RECIPE_UI_LANG=de" {
    RECIPE_UI_LANG=de
    run msg::t step.wine_init
    [ "$status" -eq 0 ]
    [[ "$output" == "Wine initialisieren" ]]
}

@test "msg::t returns English for RECIPE_UI_LANG=en" {
    RECIPE_UI_LANG=en
    run msg::t step.wine_init
    [ "$status" -eq 0 ]
    [[ "$output" == "Initializing Wine" ]]
}

@test "msg::t formats printf args" {
    RECIPE_UI_LANG=en
    run msg::t step.installer "Setup.exe"
    [ "$status" -eq 0 ]
    [[ "$output" == "Installer: Setup.exe" ]]
}
