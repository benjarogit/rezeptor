#!/usr/bin/env bats
# Guard: Deinstallation muss Rezeptor-State vollständig entfernen (kein GUI-Geisterstatus).

setup() {
  export ROOT
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_BASE="$(mktemp -d "${TMPDIR:-/tmp}/rezeptor-uninstall.XXXXXX")"
  export TEST_BASE
  export WINE_SOFTWARE_BASE="$TEST_BASE/wine-software"
  mkdir -p "$WINE_SOFTWARE_BASE"
}

teardown() {
  rm -rf "$TEST_BASE"
}

@test "purge_recipe_data removes chosen DATA_ROOT and canonical dir" {
  canonical="$WINE_SOFTWARE_BASE/fake-recipe"
  chosen="$TEST_BASE/custom-target"
  mkdir -p "$canonical" "$chosen/prefix"
  echo "$chosen" >"$canonical/data_root.path"
  echo "FOO=1" >"$chosen/recipe.env"

  tmp_yml="$TEST_BASE/recipe.yml"
  cat >"$tmp_yml" <<EOF
id: fake-recipe
data_root: "$canonical"
name: Fake
EOF

  (
    set -eu
    export RECIPE_DIR="$ROOT/recipes/photoshop"
    export PROJECT_ROOT="$ROOT"
    export CORE_DIR="$ROOT/core"
    export RECIPE_YML="$tmp_yml"
    export RECIPE_ID="fake-recipe"
    export DATA_ROOT="$chosen"
    # shellcheck source=/dev/null
    source "$ROOT/core/paths.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-hooks.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-desktop.sh"
    recipe_hooks::purge_recipe_data
  )

  [ ! -e "$chosen" ]
  [ ! -e "$canonical" ]
}

@test "every product recipe uninstall.sh calls purge_recipe_data" {
  missing=0
  for f in "$ROOT"/recipes/*/uninstall.sh; do
    case "$f" in
      */_template/*|*/_template-installer/*) ;;
      *)
        if ! grep -q 'recipe_hooks::purge_recipe_data' "$f"; then
          echo "missing purge: $f" >&2
          missing=1
        fi
        ;;
    esac
  done
  # templates too
  for f in "$ROOT"/recipes/_template/uninstall.sh \
           "$ROOT"/recipes/_template-installer/uninstall.sh; do
    [ -f "$f" ] || continue
    if ! grep -q 'recipe_hooks::purge_recipe_data' "$f"; then
      echo "missing purge: $f" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "recipe-lint enforces uninstall + purge" {
  run bash "$ROOT/scripts/recipe-lint.sh"
  [ "$status" -eq 0 ]
}

@test "purge_recipe_data removes desktop shortcut files" {
  canonical="$WINE_SOFTWARE_BASE/photoshop"
  chosen="$TEST_BASE/custom-target"
  mkdir -p "$canonical" "$chosen/prefix"
  echo "$chosen" >"$canonical/data_root.path"

  desk="$TEST_BASE/Desktop"
  apps="$TEST_BASE/applications"
  mkdir -p "$desk" "$apps"
  touch "$desk/rezeptor-photoshop.desktop"
  touch "$apps/rezeptor-photoshop.desktop"
  touch "$desk/Adobe Photoshop 2021.desktop"

  tmp_yml="$TEST_BASE/recipe.yml"
  cat >"$tmp_yml" <<EOF
id: photoshop
data_root: "$canonical"
name: Photoshop
EOF

  (
    set -eu
    export RECIPE_DIR="$ROOT/recipes/photoshop"
    export PROJECT_ROOT="$ROOT"
    export CORE_DIR="$ROOT/core"
    export RECIPE_YML="$tmp_yml"
    export RECIPE_ID="photoshop"
    export RECIPE_NAME="Photoshop"
    export DATA_ROOT="$chosen"
    export HOME="$TEST_BASE"
    export XDG_DATA_HOME="$TEST_BASE"
    export XDG_DESKTOP_DIR="$desk"
    # shellcheck source=/dev/null
    source "$ROOT/core/paths.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-hooks.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-desktop.sh"
    recipe_hooks::purge_recipe_data
  )

  [ ! -e "$desk/rezeptor-photoshop.desktop" ]
  [ ! -e "$apps/rezeptor-photoshop.desktop" ]
  [ ! -e "$desk/Adobe Photoshop 2021.desktop" ]
}
