#!/usr/bin/env bats
# Regression: AppImage FUSE is read-only; Fluent must not mkdir ./config there.

load test_helper

@test "apply_rezeptor_theme works with read-only cwd" {
    ro_cwd="$BATS_TEST_TMPDIR/ro-cwd"
    smoke_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$ro_cwd" "$smoke_home/.config"
    chmod 555 "$ro_cwd"

    run env \
        HOME="$smoke_home" \
        XDG_CONFIG_HOME="$smoke_home/.config" \
        QT_QPA_PLATFORM=offscreen \
        PYTHONPATH="$REZEPTOR_ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}" \
        bash -c "cd \"$ro_cwd\" && python3 - <<'PY'
import sys
from pathlib import Path
from PyQt6.QtWidgets import QApplication
app = QApplication(sys.argv)
import ui_fluent
ui_fluent.apply_rezeptor_theme()
assert not Path('config').exists(), 'wrote ./config into cwd'
print('ok')
PY"

    chmod 755 "$ro_cwd" || true
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
