#!/usr/bin/env bash
################################################################################
# Photoshop CC Linux - Test Helper Functions
#
# Description:
#   Helper functions for bats-core tests
#
# Author:       benjarogit
# Repository:   https://github.com/benjarogit/photoshopCClinux
# License:      GPL-3.0
# Copyright:    (c) 2024 benjarogit
################################################################################

# Get the directory where this script is located
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Set up test environment
setup_test_environment() {
    # Create temporary directory for tests
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    
    # Cleanup function
    teardown_test_environment() {
        rm -rf "$TEST_TMPDIR"
    }
}

# Resolve repository root from tests/ (works when sourced from any tests/*.bats).
rezeptor_root() {
    local d="${BATS_TEST_DIRNAME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        if [ -f "$d/launcher/launcher.py" ] || [ -f "$d/core/recipe-source.sh" ]; then
            echo "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done
    echo "${BATS_TEST_DIRNAME:-.}/.."
}

REZEPTOR_ROOT="$(rezeptor_root)"
export REZEPTOR_ROOT

