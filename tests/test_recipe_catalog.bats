#!/usr/bin/env bats
# Catalog install path containment

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
}

@test "catalog reject path traversal relative segments" {
    run python3 - <<'PY'
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.environ["PYTHONPATH"].split(":")[0])
from recipe_catalog import RecipeInstallError, _contained_recipe_target

dest = Path(tempfile.mkdtemp()) / "recipes" / "evil"
dest.mkdir(parents=True)

for bad in ("../../pwned.txt", "../sibling.sh", "/etc/passwd", "foo/../../outside"):
    try:
        _contained_recipe_target(dest, bad)
    except RecipeInstallError:
        pass
    else:
        raise SystemExit(f"expected reject for {bad!r}")

target, safe = _contained_recipe_target(dest, "sub/ok.sh")
assert safe == "sub/ok.sh"
assert target == (dest / "sub/ok.sh").resolve()
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
