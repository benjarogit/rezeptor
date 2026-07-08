#!/usr/bin/env bats
################################################################################
# Photoshop CC Linux - i18n Module Tests
#
# Description:
#   Unit tests for i18n.sh module functions using bats-core
#
# Author:       benjarogit
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-3.0
# Copyright:    (c) 2024 benjarogit
################################################################################

# Load test helper
load test_helper

# Load i18n module
setup() {
    # Source the i18n module
    source "$BATS_TEST_DIRNAME/../scripts/i18n.sh"
}

# ============================================================================
# Tests for i18n::get
# ============================================================================

@test "i18n::get returns German text when LANG_CODE is de" {
    export LANG_CODE="de"
    run i18n::get "install_photoshop"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Installiere" ]] || [[ "$output" =~ "Photoshop" ]]
}

@test "i18n::get returns English text when LANG_CODE is en" {
    export LANG_CODE="en"
    run i18n::get "install_photoshop"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Install" ]] || [[ "$output" =~ "Photoshop" ]]
}

@test "i18n::get returns key when translation not found" {
    export LANG_CODE="de"
    run i18n::get "nonexistent_key"
    [ "$status" -eq 0 ]
    [ "$output" = "nonexistent_key" ]
}

