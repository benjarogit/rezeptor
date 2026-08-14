#!/usr/bin/env bats
# source_hints parsing + URL lint policy


_require_pyqt6() {
    python3 -c "import PyQt6" 2>/dev/null || skip "PyQt6 not installed on host"
}

load test_helper

@test "minimal YAML parser reads source_hints string list" {
    run python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, str(Path("launcher").resolve()))
from version_detect import _load_recipe_mapping_minimal, source_hints_list

text = '''
id: demo
version_guaranteed: "1.0"
source_hints:
  - "Pack Title Here"
  - "rutracker"
  - m0nkrus
name: Demo
'''
data = _load_recipe_mapping_minimal(text)
hints = source_hints_list(data)
assert hints == ["Pack Title Here", "rutracker", "m0nkrus"], hints
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "photoshop-m0nkrus recipe has source_hints and version 22.1.1.138" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    yml="$ROOT/recipes/photoshop-m0nkrus/recipe.yml"
    [ -f "$yml" ]
    grep -q 'version_guaranteed: "22.1.1.138"' "$yml"
    grep -q '^source_hints:' "$yml"
    grep -q 'm0nkrus' "$yml"
    ! grep -E 'https?://|magnet:\?' "$yml"
}

@test "sidebar_card_texts uses short title plus small subtitle" {
    run python3 - <<'PY'
import sys
sys.path.insert(0, "launcher")
from recipe_discovery import sidebar_card_texts

items = [
    ("photoshop", {"name": "Adobe Photoshop CC 2021", "version_guaranteed": "22.0.0.35", "sidebar_label": "Photoshop"}),
    ("photoshop-m0nkrus", {
        "name": "Adobe Photoshop CC 2021 (m0nkrus 22.1.1.138)",
        "version_guaranteed": "22.1.1.138",
        "sidebar_label": "Photoshop",
    }),
]
texts = sidebar_card_texts(items)
assert texts["photoshop"][0] == "Photoshop", texts
assert texts["photoshop"][1] == "22.0.0.35", texts
assert texts["photoshop-m0nkrus"][0] == "Photoshop", texts
assert "22.1.1.138" in texts["photoshop-m0nkrus"][1], texts
print("OK", texts)
PY
    if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
    [ "$status" -eq 0 ]
}

@test "m0nkrus pack folder normalizes to ISO with matching version" {
    _require_pyqt6

    PACK="/home/benny/Downloads/Adobe Photoshop 2021 22.1.1.138 Multilingual"
    if [ ! -d "$PACK" ]; then
        skip "pack folder not present"
    fi
    run python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "launcher")
from ui_source import normalize_folder_source, adobe_pack_root_for_source
pack = Path("$PACK")
got = normalize_folder_source("photoshop-m0nkrus", str(pack), version_hint="22.1.1.138")
assert got.endswith(".iso"), got
assert "22.1.1.138" in Path(got).name
root = adobe_pack_root_for_source(got)
assert root == str(pack.resolve()), (root, pack)
print("OK", got, root)
PY
    if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
    [ "$status" -eq 0 ]
}

@test "adobe pack root heuristic and RECIPE_PACK_ROOT env" {
    _require_pyqt6

    run python3 - <<'PY'
import tempfile
from pathlib import Path
import sys
sys.path.insert(0, "launcher")
from ui_source import (
    _looks_like_adobe_pack_root,
    adobe_pack_root_for_source,
    normalize_folder_source,
)

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    (root / "Adobe Photoshop 2021 22.1.1.138 Multilingual.iso").write_bytes(b"iso")
    (root / "Neural Filters All 22.10.2020.exe").write_bytes(b"sfx")
    (root / "ps2021_missing_libs.7z").write_bytes(b"7z")
    assert _looks_like_adobe_pack_root(root)
    iso = normalize_folder_source(
        "photoshop-m0nkrus", str(root), version_hint="22.1.1.138"
    )
    assert iso.endswith(".iso")
    assert adobe_pack_root_for_source(iso) == str(root.resolve())
    assert adobe_pack_root_for_source(str(root)) == str(root.resolve())
print("OK")
PY
    if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
    [ "$status" -eq 0 ]
}

@test "adobe pack folder survives accept path (not forced to ISO-as-dir)" {
    _require_pyqt6

    PACK="/home/benny/Downloads/Adobe Photoshop 2021 22.1.1.138 Multilingual"
    if [ ! -d "$PACK" ]; then
        skip "pack folder not present"
    fi
    run python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "launcher")
from ui_source import (
    _looks_like_adobe_pack_root,
    adobe_pack_root_for_source,
    is_adobe_offline_recipe,
    normalize_folder_source,
)

pack = Path("$PACK")
assert _looks_like_adobe_pack_root(pack)
# Accept darf Pack-Root als Ordner behalten
assert pack.is_dir()
# ISO-Pfad allein ist Datei — Accept muss is_file().iso erlauben
iso = normalize_folder_source("photoshop-m0nkrus", str(pack), version_hint="22.1.1.138")
assert Path(iso).is_file() and iso.endswith(".iso")
assert is_adobe_offline_recipe("photoshop-m0nkrus")
ok_dir = pack.is_dir()
ok_iso = Path(iso).is_file() and Path(iso).suffix.lower() == ".iso"
assert ok_dir and ok_iso
assert adobe_pack_root_for_source(str(pack)) == str(pack.resolve())
assert adobe_pack_root_for_source(iso) == str(pack.resolve())
print("OK")
PY
    if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
    [ "$status" -eq 0 ]
}

@test "photoshop-m0nkrus loads recipe_photoshop::install via wrapper" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run bash -c "
set -euo pipefail
export PROJECT_ROOT='$ROOT'
export RECIPE_DIR='$ROOT/recipes/photoshop-m0nkrus'
export RECIPE_ID=photoshop-m0nkrus
export RECIPE_YML=\"\$RECIPE_DIR/recipe.yml\"
export DATA_ROOT=/tmp/rezeptor-m0nkrus-test-\$\$
export CORE_DIR=\"\$PROJECT_ROOT/core\"
mkdir -p \"\$DATA_ROOT\"
# shellcheck source=/dev/null
source \"\$CORE_DIR/recipe-hooks.sh\"
recipe_hooks::load install
type recipe_photoshop::install >/dev/null
echo OK
"
    [ "$status" -eq 0 ]
    [[ "$output" == *OK* ]]
}

@test "lightroom-classic loads recipe_lightroom::install via wrapper" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run bash -c "
set -euo pipefail
export PROJECT_ROOT='$ROOT'
export RECIPE_DIR='$ROOT/recipes/lightroom-classic'
export RECIPE_ID=lightroom-classic
export RECIPE_YML=\"\$RECIPE_DIR/recipe.yml\"
export DATA_ROOT=/tmp/rezeptor-lrc-test-\$\$
export CORE_DIR=\"\$PROJECT_ROOT/core\"
mkdir -p \"\$DATA_ROOT\"
# shellcheck source=/dev/null
source \"\$CORE_DIR/recipe-hooks.sh\"
recipe_hooks::load install
recipe_install_steps::_ensure_module recipe_lightroom::install
type recipe_lightroom::install >/dev/null
type lr_stubs::ensure_patched_d2d1 >/dev/null
echo OK
"
    [ "$status" -eq 0 ]
    [[ "$output" == *OK* ]]
}

@test "lightroom find_exe accepts versioned Adobe folder names" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    prefix="$BATS_TEST_TMPDIR/pfx-lrc"
    app="$prefix/drive_c/Program Files/Adobe/Adobe Lightroom Classic 15.4"
    mkdir -p "$app"
    printf 'MZ' > "$app/Lightroom.exe"
    run bash -c "
set -euo pipefail
export PROJECT_ROOT='$ROOT'
# shellcheck source=/dev/null
source '$ROOT/core/sharedFuncs.sh'
lightroom::find_exe '$prefix'
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Adobe Lightroom Classic 15.4/Lightroom.exe"* ]]
}

@test "ISO-only pack heuristic still distinguishes extras-less packs" {
    _require_pyqt6

    run python3 - <<'PY'
import tempfile
from pathlib import Path
import sys
sys.path.insert(0, "launcher")
from ui_source import (
    _looks_like_adobe_iso_only_pack,
    _looks_like_adobe_pack_root,
    _matches_m0nkrus_220_pack,
)
from recipe_discovery import is_adobe_offline_recipe

assert not is_adobe_offline_recipe("photoshop-m0nkrus-220")
assert is_adobe_offline_recipe("photoshop-m0nkrus")

with tempfile.TemporaryDirectory() as td:
    root = Path(td) / "Photoshop.2021"
    root.mkdir()
    iso = root / "Adobe.Photoshop.2021.Multilingual.iso"
    iso.write_bytes(b"iso")
    (root / "m0nkrus.nfo").write_text("nfo")
    assert _looks_like_adobe_iso_only_pack(root)
    assert not _looks_like_adobe_pack_root(root)
    assert _matches_m0nkrus_220_pack(root)
    assert _matches_m0nkrus_220_pack(iso)
print("OK")
PY
    if [ "$status" -ne 0 ]; then echo "$output" >&2; fi
    [ "$status" -eq 0 ]
}

@test "pack _find_in_pack finds files when path has spaces" {
    PACK="/home/benny/Downloads/Adobe Photoshop 2021 22.1.1.138 Multilingual"
    if [ ! -d "$PACK" ]; then
        skip "pack folder not present"
    fi
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck disable=SC1091
    source "$ROOT/core/output.sh"
    # shellcheck disable=SC1091
    source "$ROOT/core/recipe-photoshop-pack.sh"
    libs="$(recipe_photoshop_pack::_find_in_pack "$PACK" "ps2021_missing_libs.7z")"
    [ -n "$libs" ]
    [ -f "$libs" ]
    sfx="$(recipe_photoshop_pack::_find_in_pack "$PACK" "*Neural*Filters*.exe")"
    [ -n "$sfx" ]
    [ -f "$sfx" ]
}

@test "photoshop_app_version reads ProductVersion from AdobeSetup json" {
    PREFIX="/home/benny/.local/share/wine-software/photoshop-m0nkrus/prefix"
    EXE="$PREFIX/drive_c/Program Files/Adobe/Adobe Photoshop 2021/Photoshop.exe"
    JSON="$PREFIX/drive_c/AdobeSetup/products/PHSP/application.json"
    if [ ! -f "$EXE" ] || [ ! -f "$JSON" ]; then
        skip "m0nkrus install not present"
    fi
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck disable=SC1091
    source "$ROOT/core/recipe-validate.sh"
    export WINEPREFIX="$PREFIX"
    ver="$(recipe_validate::photoshop_app_version "$EXE")"
    [ "$ver" = "22.1.1.138" ]
}



