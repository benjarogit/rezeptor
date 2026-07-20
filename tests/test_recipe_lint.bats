#!/usr/bin/env bats
# Recipe lint tests

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "recipe-lint passes on official recipes" {
    run bash "$ROOT/scripts/recipe-lint.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "recipe-lint includes template directory" {
    [ -f "$ROOT/recipes/_template/recipe.yml" ]
    run bash "$ROOT/scripts/recipe-lint.sh"
    [ "$status" -eq 0 ]
}
