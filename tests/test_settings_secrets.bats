#!/usr/bin/env bats
# Archive password secrets store + settings.json permissions

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
}

@test "archive_passwords leave settings.json and land in 0600 secrets file" {
    run python3 - <<'PY'
import json
import os
import stat
import sys
from pathlib import Path

sys.path.insert(0, os.environ["PYTHONPATH"].split(":")[0])
import importlib
import settings

importlib.reload(settings)

s = settings.RezeptorSettings(locale="en", archive_passwords=["secret-one", "secret-two"])
settings.save_settings(s)

assert settings.SETTINGS_DIR.is_dir()
mode_dir = settings.SETTINGS_DIR.stat().st_mode & 0o777
assert mode_dir == 0o700, oct(mode_dir)

mode_settings = settings.SETTINGS_FILE.stat().st_mode & 0o777
assert mode_settings == 0o600, oct(mode_settings)

data = json.loads(settings.SETTINGS_FILE.read_text(encoding="utf-8"))
assert "archive_passwords" not in data, data
assert data.get("schema_version") == settings.SETTINGS_SCHEMA_VERSION, data

assert settings.ARCHIVE_PASSWORDS_FILE.is_file()
mode_secrets = settings.ARCHIVE_PASSWORDS_FILE.stat().st_mode & 0o777
assert mode_secrets == 0o600, oct(mode_secrets)

loaded = settings.load_settings()
assert loaded.archive_passwords == ["secret-one", "secret-two"]
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "plaintext archive_passwords migrate out of settings.json" {
    run python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ["PYTHONPATH"].split(":")[0])
import importlib
import settings

importlib.reload(settings)

settings.SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
settings.SETTINGS_FILE.write_text(
    json.dumps({"locale": "en", "archive_passwords": ["legacy-pw"]}, indent=2) + "\n",
    encoding="utf-8",
)

loaded = settings.load_settings()
assert loaded.archive_passwords == ["legacy-pw"]

data = json.loads(settings.SETTINGS_FILE.read_text(encoding="utf-8"))
assert "archive_passwords" not in data, data
assert settings.ARCHIVE_PASSWORDS_FILE.is_file()
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "prepend_archive_password API still works with secrets file" {
    run python3 - <<'PY'
import os
import sys

sys.path.insert(0, os.environ["PYTHONPATH"].split(":")[0])
import importlib
import settings

importlib.reload(settings)

s = settings.load_settings()
assert settings.prepend_archive_password(s, "alpha")
assert settings.prepend_archive_password(s, "beta")
assert not settings.prepend_archive_password(s, "beta")
settings.save_settings(s)
again = settings.load_settings()
assert again.archive_passwords[:2] == ["beta", "alpha"]
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
