#!/usr/bin/env bats
# recipe_export_env must not rewrite data_root.path when DATA_ROOT and
# RECIPE_DATA_ROOT disagree (stale parent env from another selected recipe).

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    export PROJECT_ROOT="$ROOT"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    # shellcheck source=/dev/null
    source "$ROOT/core/paths.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe.sh"

    CANON="$TMP/canon-ps"
    PS_ROOT="$TMP/photoshop-real"
    HALO_ROOT="$TMP/halo-wrong"
    mkdir -p "$CANON" "$PS_ROOT/prefix" "$HALO_ROOT/prefix"
    printf '%s\n' "$PS_ROOT" >"$CANON/data_root.path"

    RDIR="$TMP/recipes/photoshop-fake"
    mkdir -p "$RDIR"
    cat >"$RDIR/recipe.yml" <<EOF
id: photoshop-fake
name: Photoshop Fake
data_root: "$CANON"
prefix: "{data_root}/prefix"
runtime: proton-ge
EOF
    YML="$RDIR/recipe.yml"
}

teardown() {
    rm -rf "$TMP"
}

@test "mismatched RECIPE_DATA_ROOT does not overwrite data_root.path" {
    export DATA_ROOT="$PS_ROOT"
    export RECIPE_DATA_ROOT="$HALO_ROOT"
    recipe_export_env "$YML"
    ptr="$(tr -d '\r\n' <"$CANON/data_root.path")"
    [ "$ptr" = "$PS_ROOT" ]
    [ "$DATA_ROOT" = "$PS_ROOT" ]
}

@test "matching RECIPE_DATA_ROOT persists data_root.path" {
    NEW="$TMP/photoshop-moved"
    mkdir -p "$NEW/prefix"
    unset DATA_ROOT || true
    export RECIPE_DATA_ROOT="$NEW"
    recipe_export_env "$YML"
    ptr="$(tr -d '\r\n' <"$CANON/data_root.path")"
    [ "$ptr" = "$NEW" ]
    [ "$DATA_ROOT" = "$NEW" ]
}
