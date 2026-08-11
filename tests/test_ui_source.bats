#!/usr/bin/env bats
# ui_source hotspots: path normalize, Adobe pack helpers, RecipeSourceDialog.build_env

load test_helper

_require_pyqt6() {
    python3 -c "import PyQt6" 2>/dev/null || skip "PyQt6 not installed on host"
}

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "normalize_user_path expands ~ file:// and //Dokumente" {
    run python3 -c "
import sys, os
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from ui_source import normalize_user_path
home = str(Path.home())
assert normalize_user_path('~/foo') == os.path.normpath(home + '/foo')
assert normalize_user_path('file:///tmp/bar') == '/tmp/bar'
assert normalize_user_path('{repo}/x', Path('/repo')) == '/repo/x'
# //Dokumente → \$HOME/Dokumente (KDE hand entry)
got = normalize_user_path('//Dokumente/Pack')
assert got == os.path.normpath(home + '/Dokumente/Pack'), got
# //mnt stays absolute
assert normalize_user_path('//mnt/data/x') == '/mnt/data/x'
assert normalize_user_path('') == ''
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "needs_target_dir and fix_kind_category helpers" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from ui_source import needs_target_dir, fix_kind_category, shows_fix_field, needs_source_dialog
assert needs_target_dir({'deploy_mode': 'link'}) is False
assert needs_target_dir({'target_default': '~/.local/share/x'}) is True
assert needs_target_dir({'install_type': 'portable_launch'}) is True
assert fix_kind_category('optional') == 'updates'
assert fix_kind_category('online_fix_required') == 'online_fix'
assert fix_kind_category('none') == 'none'
assert shows_fix_field({'fix_kind': 'optional'}) is True
assert needs_source_dialog({'source_kind': 'folder'}) is True
assert needs_source_dialog({'source_kind': 'fixed_path'}) is False
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "adobe pack root and folder normalize pick ISO" {
    PACK="$BATS_TEST_TMPDIR/Adobe.Photoshop.2021.Multilingual"
    mkdir -p "$PACK/Neural Filters"
    touch "$PACK/Photoshop.iso"
    touch "$PACK/other.iso"
    # newer mtime wins without version hint — touch order
    sleep 0.05
    touch "$PACK/Photoshop.2021.iso"
    SETUP="$BATS_TEST_TMPDIR/offline/Setup"
    mkdir -p "$SETUP"
    touch "$SETUP/Set-up.exe"

    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from ui_source import (
    adobe_pack_root_for_source,
    normalize_folder_source,
    _looks_like_adobe_pack_root,
    _matches_m0nkrus_220_pack,
)
pack = Path('$PACK')
assert _looks_like_adobe_pack_root(pack)
assert _matches_m0nkrus_220_pack(pack)
assert adobe_pack_root_for_source(str(pack)) == str(pack.resolve())
iso = Path(normalize_folder_source('photoshop', str(pack)))
assert iso.suffix.lower() == '.iso'
assert iso.is_file()
# Set-up tree
setup = Path('$SETUP')
assert normalize_folder_source('photoshop', str(setup)) == str(setup.resolve())
# ISO file returns itself
assert normalize_folder_source('photoshop', str(iso)) == str(iso.resolve())
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "RecipeSourceDialog.build_env sets DATA_ROOT and ISO installer path" {
    _require_pyqt6
    PACK="$BATS_TEST_TMPDIR/pack-root"
    mkdir -p "$PACK/Neural"
    touch "$PACK/PS.iso"
    DATA="$BATS_TEST_TMPDIR/data-root"

    run python3 -c "
import os, sys
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from PyQt6.QtWidgets import QApplication
from ui_source import RecipeSourceDialog

app = QApplication.instance() or QApplication([])
meta = {
    'source_kind': 'folder',
    'install_type': 'installer_offline',
    'target_default': str(Path('$DATA')),
    'target_label': 'Datenordner',
    'version_guaranteed': '22.0.0.35',
    'fix_kind': 'none',
}
dlg = RecipeSourceDialog(None, rid='photoshop', meta=meta, root=Path('$PROJECT_ROOT'))
dlg.primary_edit.setText('$PACK')
dlg.target_edit.setText('$DATA')
env = dlg.build_env(Path('$DATA'))
assert env.get('RECIPE_DATA_ROOT') == '$DATA' or env.get('DATA_ROOT') == '$DATA', env
assert env.get('WINEPREFIX', '').endswith('/prefix'), env
assert env.get('RECIPE_PACK_ROOT'), env
assert env.get('RECIPE_INSTALLER_PATH', '').lower().endswith('.iso'), env
print('ok', sorted(env))
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "RecipeSourceDialog.build_env installer kind sets RECIPE_INSTALLER_PATH" {
    _require_pyqt6
    EXE="$BATS_TEST_TMPDIR/Set-up.exe"
    touch "$EXE"

    run python3 -c "
import os, sys
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from PyQt6.QtWidgets import QApplication
from ui_source import RecipeSourceDialog

app = QApplication.instance() or QApplication([])
meta = {
    'source_kind': 'installer',
    'install_type': 'installer_offline',
    'fix_kind': 'none',
}
dlg = RecipeSourceDialog(None, rid='photoshop', meta=meta, root=Path('$PROJECT_ROOT'))
dlg.primary_edit.setText('$EXE')
env = dlg.build_env(Path('$BATS_TEST_TMPDIR'))
assert env.get('RECIPE_INSTALLER_PATH') == str(Path('$EXE').resolve()) or env.get('RECIPE_INSTALLER_PATH') == '$EXE'
print('ok', env)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
