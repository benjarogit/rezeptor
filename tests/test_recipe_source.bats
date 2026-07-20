#!/usr/bin/env bats
# Recipe source archive extraction tests

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/security.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-source.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-deploy.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/env-file.sh"
    STAGING="$BATS_TEST_TMPDIR/staging"
    mkdir -p "$STAGING"
}

@test "extract zip archive" {
    zipfile="$BATS_TEST_TMPDIR/test.zip"
    mkdir -p "$BATS_TEST_TMPDIR/inner"
    echo "hello" > "$BATS_TEST_TMPDIR/inner/readme.txt"
    (cd "$BATS_TEST_TMPDIR/inner" && zip -q "$zipfile" readme.txt)
    dest="$STAGING/zip-out"
    run recipe_source::extract_archive "$zipfile" "$dest"
    [ "$status" -eq 0 ]
    [ -f "$dest/readme.txt" ]
}

@test "extract tar.gz archive" {
    tg="$BATS_TEST_TMPDIR/test.tar.gz"
    mkdir -p "$BATS_TEST_TMPDIR/tinner"
    echo "data" > "$BATS_TEST_TMPDIR/tinner/file.txt"
    tar -czf "$tg" -C "$BATS_TEST_TMPDIR/tinner" file.txt
    dest="$STAGING/tar-out"
    run recipe_source::extract_archive "$tg" "$dest"
    [ "$status" -eq 0 ]
    [ -f "$dest/file.txt" ]
}

_require_7z() {
    if command -v 7z >/dev/null 2>&1; then
        return 0
    fi
    if [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "7z required in CI (install p7zip-full)" >&2
        return 1
    fi
    skip "7z not installed"
}

@test "extract 7z archive when 7z available" {
    _require_7z
    arch="$BATS_TEST_TMPDIR/test.7z"
    mkdir -p "$BATS_TEST_TMPDIR/s7"
    echo "seven" > "$BATS_TEST_TMPDIR/s7/note.txt"
    (cd "$BATS_TEST_TMPDIR/s7" && 7z a -bd -y "$arch" note.txt >/dev/null)
    dest="$STAGING/7z-out"
    run recipe_source::extract_archive "$arch" "$dest"
    [ "$status" -eq 0 ]
    [ -f "$dest/note.txt" ]
}

@test "extract password-protected 7z with password file" {
    _require_7z
    arch="$BATS_TEST_TMPDIR/secret.7z"
    mkdir -p "$BATS_TEST_TMPDIR/sec"
    echo "secret" > "$BATS_TEST_TMPDIR/sec/secret.txt"
    (cd "$BATS_TEST_TMPDIR/sec" && 7z a -bd -y -pcorrect "$arch" secret.txt >/dev/null)
    pwfile="$BATS_TEST_TMPDIR/passwords.txt"
    printf '%s\n' "wrong" "correct" > "$pwfile"
    used="$BATS_TEST_TMPDIR/used.txt"
    : > "$used"
    export RECIPE_ARCHIVE_PASSWORD_FILE="$pwfile"
    export RECIPE_ARCHIVE_PASSWORD_USED_FILE="$used"
    dest="$STAGING/pw-out"
    run recipe_source::extract_archive "$arch" "$dest"
    unset RECIPE_ARCHIVE_PASSWORD_FILE RECIPE_ARCHIVE_PASSWORD_USED_FILE
    [ "$status" -eq 0 ]
    [ -f "$dest/secret.txt" ]
    [ "$(cat "$used")" = "correct" ]
}

@test "resolve multipart 7z to first volume" {
    _require_7z
    mkdir -p "$BATS_TEST_TMPDIR/parts"
    # >1 MiB so -v512k creates at least two volumes
    dd if=/dev/urandom of="$BATS_TEST_TMPDIR/parts/data.bin" bs=1024 count=1200 status=none
    (cd "$BATS_TEST_TMPDIR/parts" && 7z a -bd -y -v512k "$BATS_TEST_TMPDIR/vol.7z" data.bin >/dev/null)
    [ -f "$BATS_TEST_TMPDIR/vol.7z.001" ]
    second=""
    for f in "$BATS_TEST_TMPDIR"/vol.7z.00*; do
        case "$f" in
            *.001) ;;
            *) second="$f"; break ;;
        esac
    done
    [ -n "$second" ]
    run recipe_source::resolve_archive "$second"
    [ "$status" -eq 0 ]
    [[ "$output" == *vol.7z.001 ]]
    dest="$STAGING/multi-out"
    run recipe_source::extract_archive "$second" "$dest"
    [ "$status" -eq 0 ]
    [ -f "$dest/data.bin" ]
}

@test "detect installer exe" {
    mkdir -p "$STAGING/app"
    touch "$STAGING/app/setup.exe"
    run recipe_deploy::detect_installer "$STAGING/app"
    [ "$status" -eq 0 ]
    [[ "$output" == *setup.exe ]]
}

@test "write source env file" {
    envf="$STAGING/source.env"
    env_file_write "$envf" SOURCE_ROOT "/tmp/foo" INSTALLER_PATH "/tmp/bar.exe"
    grep -q 'SOURCE_ROOT=' "$envf"
    grep -q 'INSTALLER_PATH=' "$envf"
}

@test "extract missing archive fails" {
    run recipe_source::extract_archive /no/such/archive.zip "$STAGING/out-miss"
    [ "$status" -ne 0 ]
}

@test "corrupt zip fails" {
    bad="$STAGING/bad.zip"
    printf 'not-a-zip' >"$bad"
    run recipe_source::extract_archive "$bad" "$STAGING/out-bad"
    [ "$status" -ne 0 ]
}

@test "unknown archive extension fails without 7z" {
  if command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1; then
    skip "7z installed — unknown extension would be attempted via 7z"
  fi
  blob="$STAGING/weird.blob"
  printf 'data' >"$blob"
  run recipe_source::extract_archive "$blob" "$STAGING/out-weird"
  [ "$status" -ne 0 ]
}

@test "archive_zip extract corrupt zip fails" {
    bad="$STAGING/bad-zip2.zip"
    printf 'not-a-zip' >"$bad"
    run python3 "$ROOT/core/archive_zip.py" extract "$bad" "$STAGING/zipfail"
    [ "$status" -ne 0 ]
}

@test "archive_zip missing archive fails" {
    run python3 "$ROOT/core/archive_zip.py" extract /no/such/file.zip "$STAGING/miss"
    [ "$status" -ne 0 ]
}
