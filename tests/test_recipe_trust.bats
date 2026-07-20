#!/usr/bin/env bats
# Recipe manifest trust tests (launcher/recipe_trust.py — replaces core/recipe-trust.sh)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
    MANIFEST="$ROOT/recipes/manifest.json"
}

_verify() {
    local recipe_dir="$1"
    local strict="${2:-0}"
    python3 - "$ROOT" "$recipe_dir" "$strict" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
recipe_dir = Path(sys.argv[2])
strict = sys.argv[3] == "1"
sys.path.insert(0, str(root / "launcher"))
from recipe_trust import verify_recipe_trust

ok, reason = verify_recipe_trust(recipe_dir, root / "recipes" / "manifest.json", strict=strict)
if not ok:
    print(reason, file=sys.stderr)
    sys.exit(1)
PY
}

@test "recipe trust verifies photoshop" {
    run _verify "$ROOT/recipes/photoshop" 1
    [ "$status" -eq 0 ]
}

@test "recipe trust verifies wiso-steuer" {
    run _verify "$ROOT/recipes/wiso-steuer" 1
    [ "$status" -eq 0 ]
}

@test "recipe trust fails on tampered file" {
    copy="$BATS_TEST_TMPDIR/wiso-copy"
    cp -a "$ROOT/recipes/wiso-steuer" "$copy"
    echo "# tamper" >> "$copy/launch.sh"
    run _verify "$copy" 1
    [ "$status" -ne 0 ]
}

@test "recipe trust dev mode bypasses failure" {
    copy="$BATS_TEST_TMPDIR/wiso-copy2"
    cp -a "$ROOT/recipes/wiso-steuer" "$copy"
    echo "# tamper" >> "$copy/launch.sh"
    REZEPTOR_DEV=1 run _verify "$copy" 0
    [ "$status" -eq 0 ]
}

@test "manifest auto-sync disabled for mere .git without REZEPTOR_DEV" {
    run python3 - "$ROOT" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
os.environ.pop("REZEPTOR_DEV", None)
from recipe_trust import manifest_auto_sync_enabled

assert (root / ".git").is_dir(), "expected git checkout"
assert manifest_auto_sync_enabled(root) is False
os.environ["REZEPTOR_DEV"] = "1"
assert manifest_auto_sync_enabled(root) is True
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "manifest_needs_sync skips full hash when tree matches manifest mtime" {
    run python3 - "$ROOT" "$BATS_TEST_TMPDIR" <<'PY'
import sys
import shutil
from pathlib import Path

root = Path(sys.argv[1])
tmpdir = Path(sys.argv[2])
sys.path.insert(0, str(root / "launcher"))
from recipe_trust import clear_digest_cache, generate_manifest, manifest_needs_sync

work = tmpdir / "recipes"
shutil.copytree(root / "recipes" / "photoshop", work / "photoshop")
manifest_path = work / "manifest.json"
clear_digest_cache()
generate_manifest(work, manifest_path)
clear_digest_cache()
assert manifest_needs_sync(work, manifest_path) is False
(work / "photoshop" / "launch.sh").touch()
clear_digest_cache()
assert manifest_needs_sync(work, manifest_path) is False
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
