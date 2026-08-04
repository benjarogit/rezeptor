#!/usr/bin/env bats
# winetricks cache guards for IE8 / win7sp1

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/wt-cache.XXXXXX")"
    export WINETRICKS_CACHE="$TMP_CACHE"
    export WINETRICKS_WIN7SP1_MIN_BYTES=100
    # Dummy-Dateien sind keine echten Cabinets — Größen-Tests ohne cabextract-Smoke.
    export WINETRICKS_WIN7SP1_CAB_CHECK=0
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-winetricks.sh"
}

teardown() {
    rm -rf "${TMP_CACHE:-}"
}

@test "sanitize_win7sp1_cache removes undersized canonical file" {
    d="$WINETRICKS_CACHE/win7sp1"
    mkdir -p "$d"
    printf 'tiny' > "$d/windows6.1-KB976932-X64.exe"

    run recipe_winetricks::sanitize_win7sp1_cache
    [ "$status" -eq 0 ]
    [ ! -f "$d/windows6.1-KB976932-X64.exe" ]
}

@test "sanitize_win7sp1_cache promotes hashed file to canonical" {
    d="$WINETRICKS_CACHE/win7sp1"
    mkdir -p "$d"
    python3 - <<'PY'
from pathlib import Path
import os
d = Path(os.environ["WINETRICKS_CACHE"]) / "win7sp1"
p = d / "windows6.1-kb976932-x64_74865ef2562006e51d7f9333b4a8d45b7a749dab.exe"
p.write_bytes(b"x" * 120)
PY

    run recipe_winetricks::sanitize_win7sp1_cache
    [ "$status" -eq 0 ]
    [ -f "$d/windows6.1-KB976932-X64.exe" ]
}

@test "sanitize_win7sp1_cache removes large file with no valid cabinets" {
    command -v cabextract >/dev/null 2>&1 || skip "cabextract not installed"
    export WINETRICKS_WIN7SP1_CAB_CHECK=1
    d="$WINETRICKS_CACHE/win7sp1"
    mkdir -p "$d"
    # Groß genug für MIN_BYTES, aber kein Cabinet-Archiv (Issue #7).
    python3 - <<'PY'
from pathlib import Path
import os
d = Path(os.environ["WINETRICKS_CACHE"]) / "win7sp1"
(d / "windows6.1-KB976932-X64.exe").write_bytes(b"NOT_A_CABINET" * 20)
PY

    run recipe_winetricks::sanitize_win7sp1_cache
    [ "$status" -eq 0 ]
    [ ! -f "$d/windows6.1-KB976932-X64.exe" ]
}

@test "purge_win7sp1_cache removes both file names" {
    d="$WINETRICKS_CACHE/win7sp1"
    mkdir -p "$d"
    printf 'a' > "$d/windows6.1-KB976932-X64.exe"
    printf 'b' > "$d/windows6.1-kb976932-x64_74865ef2562006e51d7f9333b4a8d45b7a749dab.exe"

    run recipe_winetricks::purge_win7sp1_cache
    [ "$status" -eq 0 ]
    [ ! -f "$d/windows6.1-KB976932-X64.exe" ]
    [ ! -f "$d/windows6.1-kb976932-x64_74865ef2562006e51d7f9333b4a8d45b7a749dab.exe" ]
}
