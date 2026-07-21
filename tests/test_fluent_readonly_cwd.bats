#!/usr/bin/env bats
# Regression: AppImage FUSE is read-only; Fluent must not mkdir ./config there.
# Full gate runs in scripts/verify-appimage-bundle.sh (bundled python + Fluent).
# This bats test runs when host PyQt6 is available; otherwise skip.

load test_helper

@test "apply_rezeptor_theme works with read-only cwd" {
    if ! python3 -c "import PyQt6.QtWidgets" 2>/dev/null; then
        skip "PyQt6 not installed on host (AppImage verify covers this)"
    fi

    ro_cwd="$BATS_TEST_TMPDIR/ro-cwd"
    smoke_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$ro_cwd" "$smoke_home/.config" "$smoke_home/.cache"
    chmod 555 "$ro_cwd"

    run env \
        HOME="$smoke_home" \
        XDG_CONFIG_HOME="$smoke_home/.config" \
        XDG_CACHE_HOME="$smoke_home/.cache" \
        QT_QPA_PLATFORM=offscreen \
        PYTHONPATH="$REZEPTOR_ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}" \
        bash -c "cd \"$ro_cwd\" && python3 - <<'PY'
import os
import sys
from pathlib import Path
from PyQt6.QtWidgets import QApplication
app = QApplication(sys.argv)
import ui_fluent
import ui_icons
ui_fluent.apply_rezeptor_theme()
assert not Path('config').exists(), 'wrote ./config into cwd'
chev = ui_icons.ensure_chevron_png('down')
cache = Path(os.environ['XDG_CACHE_HOME']).resolve()
assert cache in chev.resolve().parents, chev
print('ok')
PY"

    chmod 755 "$ro_cwd" || true
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
