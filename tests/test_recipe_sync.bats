#!/usr/bin/env bats
# recipe_sync + overlay discovery (no network)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
    OVERLAY="$(mktemp -d "${TMPDIR:-/tmp}/rezeptor-overlay.XXXXXX")"
    export REZEPTOR_OVERLAY_ROOT="$OVERLAY"
}

teardown() {
    rm -rf "${OVERLAY:-}"
}

@test "merge_recipe_yml_paths: overlay wins same id" {
    run python3 - "$ROOT" "$OVERLAY" <<'PY'
import json
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
overlay = Path(sys.argv[2])
sys.path.insert(0, str(root / "launcher"))
from recipe_discovery import merge_recipe_yml_paths, parse_recipe_yml

bundled = root / "recipes"
ov_recipes = overlay / "recipes"
ov_recipes.mkdir(parents=True)
# Copy photoshop to overlay and tweak name
src = bundled / "photoshop"
dst = ov_recipes / "photoshop"
shutil.copytree(src, dst)
yml = dst / "recipe.yml"
text = yml.read_text(encoding="utf-8")
text = text.replace('name: "Adobe Photoshop CC 2021"', 'name: "Overlay Photoshop"')
yml.write_text(text, encoding="utf-8")

paths = merge_recipe_yml_paths(bundled, ov_recipes)
by_id = {}
for p in paths:
    meta = parse_recipe_yml(p)
    by_id[meta["id"]] = meta
assert by_id["photoshop"]["name"] == "Overlay Photoshop"
assert "premiere" in by_id
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "safe_extract rejects zip-slip" {
    run python3 - "$ROOT" "$OVERLAY" <<'PY'
import io
import sys
import tarfile
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_sync import RecipeSyncError, safe_extract_tar_gz

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as tf:
    info = tarfile.TarInfo(name="../evil.txt")
    data = b"nope"
    info.size = len(data)
    tf.addfile(info, io.BytesIO(data))
archive = Path(sys.argv[2]) / "bad.tar.gz"
archive.write_bytes(buf.getvalue())
dest = Path(sys.argv[2]) / "extract"
try:
    safe_extract_tar_gz(archive, dest)
except RecipeSyncError as exc:
    assert "traversal" in str(exc).lower() or "unsafe" in str(exc).lower() or "escape" in str(exc).lower()
    print("ok")
else:
    raise SystemExit("expected RecipeSyncError")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "app_version_satisfies and build_diff blocked" {
    run python3 - "$ROOT" "$OVERLAY" <<'PY'
import json
import shutil
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])
overlay = Path(sys.argv[2])
sys.path.insert(0, str(root / "launcher"))
from recipe_sync import app_version_satisfies, build_diff_plan, safe_extract_tar_gz
from recipe_trust import generate_manifest

assert app_version_satisfies("", "1.0.0")
assert app_version_satisfies("1.1.0", "1.1.0")
assert app_version_satisfies("1.1.0", "1.2.0")
assert not app_version_satisfies("1.1.0", "1.0.14")

# Minimal fake extract: catalog wants future min for photoshop
extract = overlay / "extract"
extract.mkdir()
cat = {
    "version": 1,
    "recipes": [
        {
            "id": "photoshop",
            "name": "PS",
            "category": "x",
            "trust": "official",
            "path": "photoshop",
            "min_app_version": "9.9.9",
        }
    ],
}
(extract / "catalog.json").write_text(json.dumps(cat), encoding="utf-8")
shutil.copytree(root / "recipes" / "photoshop", extract / "photoshop")
# manifest for extract tree
generate_manifest(extract, extract / "manifest.json")
# generate_manifest scans dirs with recipe.yml — also wrote catalog? catalog has no yml — ok
# But generate_manifest iterates extract/* dirs — catalog.json is file; photoshop is dir.
# It will also pick up nothing else.

plan = build_diff_plan(
    extract_dir=extract,
    bundled_recipes=root / "recipes",
    overlay_recipes=overlay / "recipes",
    bundled_manifest=root / "recipes" / "manifest.json",
    app_version="1.0.14",
    bundle_version="1.1.0",
    asset_name="rezeptor-recipes-1.1.0.tar.gz",
    asset_url="https://example.invalid/x",
    sha256_expected="0" * 64,
    release_url="https://example.invalid/r",
)
kinds = {c.id: c.kind for c in plan.changes}
assert kinds.get("photoshop") == "blocked", kinds
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "parse_sha256sums and SHA mismatch" {
    run python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_sync import parse_sha256sums

text = "01e8bb6368d088e22d8e8f1d02497214e8db436476021725ef0c0707b7cb1738  rezeptor-recipes-1.1.0.tar.gz\n"
m = parse_sha256sums(text)
assert m["rezeptor-recipes-1.1.0.tar.gz"].startswith("01e8")
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "apply_recipe_sync writes overlay and verifies trust" {
    run python3 - "$ROOT" "$OVERLAY" <<'PY'
import json
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
overlay = Path(sys.argv[2])
sys.path.insert(0, str(root / "launcher"))
from recipe_discovery import discover_recipes
from recipe_sync import RecipeChange, RecipeSyncPlan, apply_recipe_sync, save_sync_state
from recipe_trust import generate_manifest

extract = overlay / "extract"
extract.mkdir()
# Bundle only contains a tiny fake recipe "demo"
demo = extract / "demo"
demo.mkdir()
(demo / "recipe.yml").write_text(
    'id: demo\nname: "Demo"\ncategory: "Test"\nschema_version: 1\n',
    encoding="utf-8",
)
(demo / "install.sh").write_text("#!/bin/true\n", encoding="utf-8")
generate_manifest(extract, extract / "manifest.json")
# Fix: generate_manifest hashed extract including only demo
cat = {
    "version": 1,
    "recipes": [
        {
            "id": "demo",
            "name": "Demo",
            "category": "Test",
            "trust": "official",
            "path": "demo",
        }
    ],
}
(extract / "catalog.json").write_text(json.dumps(cat), encoding="utf-8")
# regenerate manifest cleanly (catalog.json is not a recipe dir)
generate_manifest(extract, extract / "manifest.json")

save_sync_state({"extract_dir": str(extract)})
plan = RecipeSyncPlan(
    bundle_version="1.1.0",
    asset_name="rezeptor-recipes-1.1.0.tar.gz",
    asset_url="https://example.invalid/x",
    sha256_expected="0" * 64,
    release_url="https://example.invalid/r",
    changes=[RecipeChange(id="demo", kind="added")],
    app_version="1.1.0",
)
applied = apply_recipe_sync(plan, bundled_recipes=root / "recipes", extract_dir=extract)
assert applied == ["demo"]
assert (overlay / "recipes" / "demo" / "recipe.yml").is_file()
assert (overlay / "manifest.overlay.json").is_file()

out = discover_recipes(
    recipes_dir=root / "recipes",
    manifest_path=root / "recipes" / "manifest.json",
    project_root=root,
    verify_trust=True,
    overlay_recipes=overlay / "recipes",
    overlay_manifest=overlay / "manifest.overlay.json",
)
ids = {r.rid for r in out.recipes}
assert "demo" in ids
demo_info = next(r for r in out.recipes if r.rid == "demo")
assert demo_info.trust_ok, demo_info.trust_reason
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
