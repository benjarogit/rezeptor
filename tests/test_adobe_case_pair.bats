#!/usr/bin/env bats
# adobe_setup case-pair: Driver.xml ↔ driver.xml (bidirectional)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-adobe-setup.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "case pair creates Driver.xml when only driver.xml exists" {
    mkdir -p "$TMP/products"
    echo "driver" >"$TMP/products/driver.xml"
    adobe_setup::_ensure_case_pair "$TMP/products" "Driver.xml" "driver.xml"
    [ -e "$TMP/products/Driver.xml" ]
    [ -e "$TMP/products/driver.xml" ]
}

@test "case pair creates driver.xml when only Driver.xml exists" {
    mkdir -p "$TMP/products"
    echo "Driver" >"$TMP/products/Driver.xml"
    adobe_setup::_ensure_case_pair "$TMP/products" "Driver.xml" "driver.xml"
    [ -e "$TMP/products/driver.xml" ]
    [ -e "$TMP/products/Driver.xml" ]
}

@test "case pair creates config.xml when only Config.xml exists" {
    mkdir -p "$TMP/resources"
    echo "cfg" >"$TMP/resources/Config.xml"
    adobe_setup::_ensure_case_pair "$TMP/resources" "Config.xml" "config.xml"
    [ -e "$TMP/resources/config.xml" ]
}

@test "fix_installer_case_symlinks is bidirectional under AdobeSetup" {
    export WINEPREFIX="$TMP/prefix"
    mkdir -p "$WINEPREFIX/drive_c/AdobeSetup/products" \
        "$WINEPREFIX/drive_c/AdobeSetup/resources"
    echo "d" >"$WINEPREFIX/drive_c/AdobeSetup/products/driver.xml"
    echo "c" >"$WINEPREFIX/drive_c/AdobeSetup/resources/Config.xml"
    adobe_setup::fix_installer_case_symlinks
    [ -e "$WINEPREFIX/drive_c/AdobeSetup/products/Driver.xml" ]
    [ -e "$WINEPREFIX/drive_c/AdobeSetup/resources/config.xml" ]
}
