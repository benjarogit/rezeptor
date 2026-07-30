#!/usr/bin/env bats
# recipe-updates discovery / sort / skip

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/env-file.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-updates.sh"
    TMP="$(mktemp -d)"
    export DATA_ROOT="$TMP/data"
    mkdir -p "$DATA_ROOT"
    recipe_hooks::state_file() { echo "${DATA_ROOT}/recipe.env"; }
    recipe_hooks::state_set() { env_file_set "$(recipe_hooks::state_file)" "$1" "$2"; }
    recipe_hooks::state_get() { env_file_get "$(recipe_hooks::state_file)" "$1"; }
}

teardown() {
    rm -rf "$TMP"
}

@test "discover sorts numbered updates numerically (1,2,10)" {
    root="$TMP/pack/updates"
    mkdir -p "$root/1 - first" "$root/10 - tenth" "$root/2 - second"
    touch "$root/1 - first/a.exe" "$root/10 - tenth/b.exe" "$root/2 - second/c.exe"
    run recipe_updates::discover "$TMP/pack"
    [ "$status" -eq 0 ]
    ids="$(printf '%s\n' "$output" | cut -d'|' -f1 | tr '\n' ',')"
    [[ "$ids" == "1,2,10," ]]
}

@test "discover uses updates/ subdirectory" {
    mkdir -p "$TMP/game/updates/1 - patch"
    touch "$TMP/game/updates/1 - patch/u.exe"
    run recipe_updates::discover "$TMP/game"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1|"* ]]
    [[ "$output" == *"/1 - patch"* ]]
}

@test "discover finds numbered unit under named wrapper in updates/" {
    # ElAmigos layout: updates/<title>/1 - <title>/
    wrap="$TMP/halo/updates/Halo Campaign Evolved update 29.07.2026"
    mkdir -p "$wrap/1 - Halo Campaign Evolved update 29.07.2026"
    touch "$wrap/1 - Halo Campaign Evolved update 29.07.2026/patch.exe"
    touch "$wrap/1 - Halo Campaign Evolved update 29.07.2026/elamigos-1.bin"
    run recipe_updates::discover "$TMP/halo"
    [ "$status" -eq 0 ]
    [[ "$output" == 1\|* ]]
    [[ "$output" == *"/1 - Halo Campaign Evolved update 29.07.2026"* ]]
}

@test "discover accepts update parent with numbered child" {
    mkdir -p "$TMP/upd/1 - Halo update"
    touch "$TMP/upd/1 - Halo update/patch.exe" "$TMP/upd/1 - Halo update/elamigos-1.bin"
    run recipe_updates::discover "$TMP/upd"
    [ "$status" -eq 0 ]
    [[ "$output" == 1\|* ]]
}

@test "apply_all skips already applied IDs" {
    mkdir -p "$TMP/upd/1 - one" "$TMP/upd/2 - two"
    touch "$TMP/upd/1 - one/a.exe" "$TMP/upd/2 - two/b.exe"
    export RECIPE_UPDATE_ROOT="$TMP/upd"
    unset RECIPE_SOURCE_ROOT RECIPE_WORK_ROOT RECIPE_FIX_ROOT || true
    recipe_hooks::state_set APPLIED_UPDATES "1"

    fake_wine() { return 0; }

    run recipe_updates::apply_all /dev/null fake_wine
    [ "$status" -eq 0 ]
    [[ "$output" == *"bereits angewandt"* ]] || [[ "$output" == *"skip"* ]]
    applied="$(recipe_hooks::state_get APPLIED_UPDATES)"
    [[ "$applied" == *"1"* ]]
    [[ "$applied" == *"2"* ]]
}

@test "roots_from_env prefers UPDATE and FIX aliases" {
    mkdir -p "$TMP/u" "$TMP/f"
    export RECIPE_UPDATE_ROOT="$TMP/u"
    export RECIPE_FIX_ROOT="$TMP/f"
    unset RECIPE_SOURCE_ROOT RECIPE_WORK_ROOT || true
    run recipe_updates::roots_from_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TMP/u"* ]]
    [[ "$output" == *"$TMP/f"* ]]
}
