#!/usr/bin/env bats
# Silent offline installer: family detect, one-shot (no || cascade)

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

@test "installer_family detects Inno from PE string" {
    local exe="$BATS_TEST_TMPDIR/setup.exe"
    # Minimal stub with Inno marker in first 512 KiB
    printf 'MZ%sInno Setup Setup Data (5.5.0)' "$(head -c 100 </dev/zero | tr '\0' 'x')" >"$exe"
    run recipe_hooks::installer_family "$exe"
    [ "$status" -eq 0 ]
    [ "$output" = "inno" ]
}

@test "installer_family detects msi by extension" {
    local msi="$BATS_TEST_TMPDIR/setup.msi"
    : >"$msi"
    run recipe_hooks::installer_family "$msi"
    [ "$output" = "msi" ]
}

@test "run_exe_silent invokes wine exactly once even on failure" {
    local bindir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bindir"
    local countf="$BATS_TEST_TMPDIR/wine_count"
    : >"$countf"
    cat >"$bindir/wine" <<EOF
#!/usr/bin/env bash
echo 1 >>"$countf"
exit 1
EOF
    chmod +x "$bindir/wine"
    export PATH="$bindir:$PATH"

    local exe="$BATS_TEST_TMPDIR/setup.exe"
    printf 'MZ%sInno Setup Setup Data' "$(head -c 50 </dev/zero | tr '\0' 'x')" >"$exe"

    run recipe_hooks::run_exe_silent "$exe" /dev/null wine
    [ "$status" -ne 0 ]
    # Genau ein Aufruf — kein ||-Stapel
    [ "$(wc -l <"$countf" | tr -d ' ')" = "1" ]
}

@test "installer_wine_dir for halo recipe" {
    RECIPE_ID=halo-campaign-evolved run recipe_hooks::installer_wine_dir
    [ "$status" -eq 0 ]
    [[ "$output" == *HaloCampaignEvolved* ]]
}
