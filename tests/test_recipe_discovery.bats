#!/usr/bin/env bats
# recipe_discovery parse + discover (no PyQt)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
}

@test "parse_recipe_yml defaults schema_version" {
    run python3 - "$ROOT/recipes/photoshop/recipe.yml" "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[2])
sys.path.insert(0, str(root / "launcher"))
from recipe_discovery import parse_recipe_yml

meta = parse_recipe_yml(Path(sys.argv[1]))
assert meta.get("schema_version") == "1"
assert meta.get("id") == "photoshop"
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "discover_recipes without trust verify marks CHECKING" {
    run python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_discovery import RecipeState, discover_recipes

out = discover_recipes(
    recipes_dir=root / "recipes",
    manifest_path=root / "recipes" / "manifest.json",
    project_root=root,
    verify_trust=False,
)
assert out.recipes, "expected recipes"
assert any(r.state == RecipeState.CHECKING for r in out.recipes)
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "launch_process_patterns_from_meta reads yaml list" {
    run python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_discovery import launch_process_patterns_from_meta

meta = {"launch_process_patterns": "foo.exe, bar.exe"}
assert launch_process_patterns_from_meta(meta) == ["foo.exe", "bar.exe"]
meta = {"exe_glob": "Game/sub.exe"}
assert launch_process_patterns_from_meta(meta) == ["sub.exe"]
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "source_hints_sidebar_adobe_and_maintainer helpers" {
    run python3 - "$ROOT" "$BATS_TEST_TMPDIR" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
tmp = Path(sys.argv[2])
sys.path.insert(0, str(root / "launcher"))
from recipe_discovery import (
    is_adobe_offline_recipe,
    is_maintainer_only,
    merge_recipe_yml_paths,
    sidebar_label_for_meta,
    source_hints_from_meta,
)

assert source_hints_from_meta({"source_hints": "a; b, c"}) == ["a", "b", "c"]
assert source_hints_from_meta({}) == []
assert sidebar_label_for_meta({"sidebar_label": "PS"}, "photoshop") == "PS"
assert sidebar_label_for_meta({"name": "WISO"}, "wiso-steuer") == "WISO"
assert is_adobe_offline_recipe("photoshop") is True
assert is_adobe_offline_recipe("wiso-steuer") is False
assert is_maintainer_only({"maintainer_only": "true"}) is True
assert is_maintainer_only({"maintainer_only": "no"}) is False

bundled = tmp / "bundled"
wip = bundled / "wip-demo"
wip.mkdir(parents=True)
(wip / "recipe.yml").write_text(
    "id: wip-demo\nname: WIP\nmaintainer_only: true\n",
    encoding="utf-8",
)
import recipe_discovery as rd

rd._dev_recipes_visible = lambda: False  # type: ignore[assignment]
hidden = {p.parent.name for p in merge_recipe_yml_paths(bundled)}
assert "wip-demo" not in hidden, hidden
rd._dev_recipes_visible = lambda: True  # type: ignore[assignment]
shown = {p.parent.name for p in merge_recipe_yml_paths(bundled)}
assert "wip-demo" in shown, shown
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
