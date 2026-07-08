#!/usr/bin/env bats
################################################################################
# Photoshop CC Linux - Security Module Tests
#
# Description:
#   Unit tests for security.sh module functions using bats-core
#
# Author:       benjarogit
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-3.0
# Copyright:    (c) 2024 benjarogit
################################################################################

# Load test helper
load test_helper

# Load security module
setup() {
    # Source the security module
    source "$BATS_TEST_DIRNAME/../scripts/security.sh"
}

# ============================================================================
# Tests for security::validate_path
# ============================================================================

@test "security::validate_path accepts valid user paths" {
    run security::validate_path "$HOME/test"
    [ "$status" -eq 0 ]
}

@test "security::validate_path rejects system directories" {
    run security::validate_path "/etc"
    [ "$status" -eq 1 ]
    
    run security::validate_path "/usr/bin"
    [ "$status" -eq 1 ]
    
    run security::validate_path "/bin"
    [ "$status" -eq 1 ]
}

@test "security::validate_path rejects unsafe temp directories" {
    run security::validate_path "/etc/shadow"
    [ "$status" -eq 1 ]
}

@test "security::validate_path rejects empty path" {
    run security::validate_path ""
    [ "$status" -eq 1 ]
}

# ============================================================================
# Tests for security::sanitize_input
# ============================================================================

@test "security::sanitize_input removes dangerous characters" {
    run security::sanitize_input "test<script>alert('xss')</script>"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "<script>" ]]
}

@test "security::sanitize_input allows safe characters" {
    run security::sanitize_input "test-path_123"
    [ "$status" -eq 0 ]
    [ "$output" = "test-path_123" ]
}

