#!/usr/bin/env bats
# recipe_options parse + persist

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
}

@test "premiere recipe declares nvidia_libs option" {
    run python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_options import parse_recipe_options

opts = parse_recipe_options(root / "recipes" / "premiere" / "recipe.yml")
assert len(opts) == 1
o = opts[0]
assert o.id == "nvidia_libs"
assert o.env == "PREMIERE_NVIDIA_LIBS"
assert o.default is True
assert o.when == "nvidia"
assert "CUDA" in o.label_for("de")
assert o.tip_for("en")
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "minimal yaml parser loads photoshop Medizin options without PyYAML" {
    run python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_options import parse_recipe_options
from version_detect import _load_recipe_mapping_minimal

text = (root / "recipes" / "photoshop" / "recipe.yml").read_text(encoding="utf-8")
data = _load_recipe_mapping_minimal(text)
opts = parse_recipe_options(data)
assert len(opts) == 3, opts
ids = {o.id for o in opts}
assert ids == {
    "ui_home_screen",
    "ui_rich_tooltips",
    "ui_modern_new",
}
home = next(o for o in opts if o.id == "ui_home_screen")
assert home.env == "PHOTOSHOP_UI_HOME_SCREEN"
assert home.default is False
assert "Home" in home.label_for("en") or "Startbildschirm" in home.label_for("de")
assert "Repair" in home.tip_for("en") or "Reparieren" in home.tip_for("de")
# tip must not leak into label
assert "Default off" not in home.label_for("en")
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "write_option_value persists 0/1" {
    run python3 - "$ROOT" <<'PY'
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_options import (
    env_overrides_for_options,
    parse_recipe_options,
    read_option_values,
    write_option_value,
)

opts = parse_recipe_options(root / "recipes" / "premiere" / "recipe.yml")
td = Path(tempfile.mkdtemp())
write_option_value(td, opts[0], False)
assert (td / "options.env").is_file()
assert read_option_values(td, opts)["nvidia_libs"] is False
text = (td / "options.env").read_text(encoding="utf-8")
assert "PREMIERE_NVIDIA_LIBS" in text
write_option_value(td, opts[0], True)
assert read_option_values(td, opts)["nvidia_libs"] is True
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
