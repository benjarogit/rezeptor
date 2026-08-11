#!/usr/bin/env bats
# adobe_setup helpers testable without winetricks / live Proton

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-validate.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-adobe-setup.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "export_adobe_installer_dll_overrides sets msxml and mshtml native" {
    unset WINEDLLOVERRIDES
    adobe_setup::export_adobe_installer_dll_overrides
    [[ "$WINEDLLOVERRIDES" == *msxml3=native,builtin* ]]
    [[ "$WINEDLLOVERRIDES" == *mshtml=native,builtin* ]]
}

@test "resolve_setup_exe prefers ADOBE_INSTALLER_DIR then AdobeSetup" {
    export WINEPREFIX="$TMP/prefix"
    mkdir -p "$WINEPREFIX/drive_c/AdobeSetup"
    touch "$WINEPREFIX/drive_c/AdobeSetup/Set-up.exe"
    run adobe_setup::resolve_setup_exe
    [ "$status" -eq 0 ]
    [[ "$output" == *"/drive_c/AdobeSetup/Set-up.exe" ]]

    mkdir -p "$TMP/custom"
    touch "$TMP/custom/Set-up.exe"
    export ADOBE_INSTALLER_DIR="$TMP/custom"
    run adobe_setup::resolve_setup_exe
    [ "$status" -eq 0 ]
    [[ "$output" == "$TMP/custom/Set-up.exe" ]]
}

@test "deploy_installer_to_c_drive copies Set-up tree and case aliases" {
    export WINEPREFIX="$TMP/prefix"
    SRC="$TMP/src"
    mkdir -p "$SRC/products" "$SRC/resources"
    touch "$SRC/Set-up.exe"
    echo d >"$SRC/products/driver.xml"
    echo c >"$SRC/resources/Config.xml"
    adobe_setup::deploy_installer_to_c_drive "$SRC"
    [ -f "$WINEPREFIX/drive_c/AdobeSetup/Set-up.exe" ]
    [ -e "$WINEPREFIX/drive_c/AdobeSetup/products/Driver.xml" ]
    [ -e "$WINEPREFIX/drive_c/AdobeSetup/resources/config.xml" ]
    [ "$ADOBE_INSTALLER_DIR" = "$WINEPREFIX/drive_c/AdobeSetup" ]
}

@test "ensure_msxml3r_system32 copies from wow64 when missing" {
    export WINEPREFIX="$TMP/prefix"
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64" \
        "$WINEPREFIX/drive_c/windows/system32"
    echo rsrc >"$WINEPREFIX/drive_c/windows/syswow64/msxml3r.dll"
    adobe_setup::ensure_msxml3r_system32
    [ -f "$WINEPREFIX/drive_c/windows/system32/msxml3r.dll" ]
    # already present → no fail
    adobe_setup::ensure_msxml3r_system32
}

@test "ie8_present requires native mshtml PE not just iexplore.exe" {
    export WINEPREFIX="$TMP/prefix"
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    # empty / non-PE → not native
    echo notape >"$WINEPREFIX/drive_c/windows/syswow64/mshtml.dll"
    run adobe_setup::ie8_present
    [ "$status" -ne 0 ]
}

@test "diagnose_failed_install writes section without wineserver" {
    export WINEPREFIX="$TMP/prefix"
    export RECIPE_ID=photoshop
    export DATA_ROOT="$TMP/data"
    export ERROR_LOG="$TMP/err.log"
    export LOG_FILE="$TMP/install.log"
    mkdir -p "$WINEPREFIX/drive_c/AdobeSetup" "$DATA_ROOT"
    : >"$LOG_FILE"
    adobe_setup::diagnose_failed_install 42
    grep -q 'Adobe-Install Diagnose' "$ERROR_LOG"
    grep -q 'exit=42' "$ERROR_LOG"
    grep -q 'RECIPE_ID=photoshop' "$ERROR_LOG"
}

# Prefix-bound / winetricks paths (ensure_native_msxml, install_ie8, run_silent_setup):
# need Proton + network — covered by install/repair E2E and test_recipe_winetricks_cache.bats
# for the win7sp1 sanitize/retry piece. Not unit-faked here.
