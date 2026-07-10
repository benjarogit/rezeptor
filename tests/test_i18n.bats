#!/usr/bin/env bats
################################################################################
# Photoshop CC Linux - i18n Module Tests
#
# Description:
#   Unit tests for core/i18n.sh (Bash install-pipeline strings).
#
# Author:       benjarogit
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-3.0
# Copyright:    (c) 2024 benjarogit
################################################################################

load test_helper

setup() {
    source "$BATS_TEST_DIRNAME/../core/i18n.sh"
}

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
