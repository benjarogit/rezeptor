#!/usr/bin/env bats
# recipe-relocate: move DATA_ROOT + update data_root.path

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    export PROJECT_ROOT="$ROOT"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    CANON="$TMP/canon"
    OLD="$TMP/old_target"
    NEW="$TMP/new_target"
    mkdir -p "$CANON" "$OLD/prefix/drive_c/Games/Demo" "$OLD/prefix/dosdevices"
    echo "hello" >"$OLD/prefix/drive_c/Games/Demo/game.exe"
    echo "MARK=1" >"$OLD/recipe.env"
    echo "OLD_PATH=$OLD" >>"$OLD/recipe.env"
    ln -sfn "../drive_c" "$OLD/prefix/dosdevices/c:"
    printf '%s\n' "$OLD" >"$CANON/data_root.path"

    # Minimal fake recipe
    RDIR="$TMP/recipes/demo-relocate"
    mkdir -p "$RDIR"
    cat >"$RDIR/recipe.yml" <<EOF
id: demo-relocate
name: Demo Relocate
data_root: "$CANON"
prefix: "{data_root}/prefix"
runtime: proton-ge
install_type: installer_offline
EOF
    cat >"$RDIR/launch.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$RDIR/launch.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "recipe_relocate::move moves tree and updates pointer" {
    export RECIPE_DIR="$RDIR"
    export RECIPE_YML="$RDIR/recipe.yml"
    export RECIPE_ID="demo-relocate"
    export DATA_ROOT="$OLD"
    export RECIPE_RELOCATE_TO="$NEW"
    # shellcheck source=/dev/null
    source "$ROOT/core/paths.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/env-file.sh"
    # stub desktop
    recipe_desktop::refresh_if_present() { return 0; }
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-relocate.sh"

    run recipe_relocate::move
    echo "$output"
    [ "$status" -eq 0 ]
    [ -f "$NEW/prefix/drive_c/Games/Demo/game.exe" ]
    [ ! -d "$OLD/prefix" ]
    ptr="$(tr -d '\r\n' <"$CANON/data_root.path")"
    [ "$ptr" = "$NEW" ]
    grep -q "OLD_PATH=$NEW" "$NEW/recipe.env"
    [ -L "$NEW/prefix/dosdevices/c:" ]
}

@test "discover_update_units finds updates/ numbered dirs" {
    pack="$TMP/pack"
    mkdir -p "$pack/updates/1 - first" "$pack/updates/2 - second"
    touch "$pack/updates/1 - first/a.exe" "$pack/updates/2 - second/b.exe"
    run env PYTHONPATH="$ROOT/launcher" python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "$ROOT/launcher")
from ui_source import discover_update_units
u = discover_update_units("$pack")
assert len(u) == 2, u
assert u[0][0] == "1"
assert u[1][0] == "2"
print("ok", len(u))
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok 2"* ]]
}

@test "default_target_dir returns empty without saved path" {
    run env PYTHONPATH="$ROOT/launcher" python3 - <<PY
import sys
sys.path.insert(0, "$ROOT/launcher")
from ui_source import default_target_dir
meta = {
    "target_default": "~/.local/share/wine-software/demo",
    "target_label": "Install",
    "data_root": "~/.local/share/wine-software/demo",
    "install_type": "installer_offline",
}
assert default_target_dir(meta, "demo", None) == ""
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}
