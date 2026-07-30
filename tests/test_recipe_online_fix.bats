#!/usr/bin/env bats
# Online-Fix-Merge aus separatem Ordner in den Spielordner.

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-online-fix.sh"

    GAME="$TMP/game"
    FIX="$TMP/fix"
    MERGE="SMG025/Binaries/Win64"
    mkdir -p "$GAME/$MERGE" "$FIX"
    printf 'dll' >"$FIX/OnlineFix64.dll"
    printf 'ini' >"$FIX/OnlineFix.ini"
}

teardown() {
    rm -rf "$TMP"
}

@test "merge kopiert dll/ini in Ziel-Unterordner" {
    run recipe_online_fix::merge "$GAME" "$FIX" "SMG025/Binaries/Win64"
    [ "$status" -eq 0 ]
    [ -f "$GAME/$MERGE/OnlineFix64.dll" ]
    [ -f "$GAME/$MERGE/OnlineFix.ini" ]
}

@test "merge akzeptiert Unterordner mit gleichem Namen" {
    mkdir -p "$FIX/Win64"
    mv "$FIX/OnlineFix64.dll" "$FIX/Win64/"
    mv "$FIX/OnlineFix.ini" "$FIX/Win64/"
    run recipe_online_fix::merge "$GAME" "$FIX" "Binaries/Win64"
    [ "$status" -eq 0 ]
    [ -f "$GAME/Binaries/Win64/OnlineFix64.dll" ]
}

@test "merge schlägt fehl ohne dll/ini" {
    rm -f "$FIX"/*
    run recipe_online_fix::merge "$GAME" "$FIX" "$MERGE"
    [ "$status" -ne 0 ]
}
