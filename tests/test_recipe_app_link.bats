#!/usr/bin/env bats
# recipe_app_link: absolute symlink under DATA_ROOT → app/game folder

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    export PROJECT_ROOT="$ROOT"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    DATA="$TMP/data"
    APP="$TMP/real_app"
    mkdir -p "$DATA" "$APP"
    echo "ok" >"$APP/game.exe"

    RDIR="$TMP/recipes/demo-app-link"
    mkdir -p "$RDIR"
    cat >"$RDIR/recipe.yml" <<EOF
id: demo-app-link
name: Demo App Link
data_root: "$DATA"
runtime: proton-ge
EOF
    export RECIPE_DIR="$RDIR"
    export RECIPE_YML="$RDIR/recipe.yml"
    export RECIPE_ID="demo-app-link"
    export DATA_ROOT="$DATA"
    export CORE_DIR="$ROOT/core"

    # shellcheck source=/dev/null
    source "$ROOT/core/paths.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/env-file.sh"
    # Minimal stubs for state_* without full recipe_hooks::load
    recipe_hooks::state_file() { echo "${DATA_ROOT}/recipe.env"; }
    recipe_hooks::state_set() { env_file_set "$(recipe_hooks::state_file)" "$1" "$2"; }
    recipe_hooks::state_get() { env_file_get "$(recipe_hooks::state_file)" "$1"; }
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-validate.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-app-link.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "recipe_app_link::ensure creates absolute symlink" {
    recipe_hooks::state_set WORK_ROOT "$APP"
    run recipe_app_link::ensure
    [ "$status" -eq 0 ]
    link="$DATA/demo-app-link"
    [ -L "$link" ]
    target="$(readlink -f "$link")"
    want="$(readlink -f "$APP")"
    [ "$target" = "$want" ]
    # Target must be absolute in the link itself
    raw="$(readlink "$link")"
    [[ "$raw" == /* ]]
}

@test "recipe_app_link::ensure replaces relative stale symlink" {
    recipe_hooks::state_set GAME_ROOT "$APP"
    ln -sfn "prefix/drive_c/Games/Broken" "$DATA/demo-app-link"
    run recipe_app_link::ensure
    [ "$status" -eq 0 ]
    [ -L "$DATA/demo-app-link" ]
    [ "$(readlink -f "$DATA/demo-app-link")" = "$(readlink -f "$APP")" ]
    raw="$(readlink "$DATA/demo-app-link")"
    [[ "$raw" == /* ]]
}

@test "recipe_app_link::ensure does not clobber real directory" {
    recipe_hooks::state_set WORK_ROOT "$APP"
    mkdir -p "$DATA/demo-app-link"
    echo keep >"$DATA/demo-app-link/user.txt"
    run recipe_app_link::ensure
    [ "$status" -eq 0 ]
    [ -d "$DATA/demo-app-link" ]
    [ ! -L "$DATA/demo-app-link" ]
    [ -f "$DATA/demo-app-link/user.txt" ]
}

@test "recipe_app_link::validate WARNs when target missing" {
    ln -sfn "$TMP/missing_app" "$DATA/demo-app-link"
    run recipe_app_link::validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "recipe_app_link::link_name respects app_link_name" {
    cat >"$RDIR/recipe.yml" <<EOF
id: demo-app-link
name: Demo
app_link_name: HaloCampaignEvolved
data_root: "$DATA"
runtime: proton-ge
EOF
    run recipe_app_link::link_name
    [ "$status" -eq 0 ]
    [ "$output" = "HaloCampaignEvolved" ]
}

@test "recipe_app_link priority GAME_ROOT over WORK_ROOT" {
    other="$TMP/other"
    mkdir -p "$other"
    recipe_hooks::state_set WORK_ROOT "$other"
    recipe_hooks::state_set GAME_ROOT "$APP"
    run recipe_app_link::resolve_target
    [ "$status" -eq 0 ]
    [ "$(readlink -f "$output")" = "$(readlink -f "$APP")" ]
}
