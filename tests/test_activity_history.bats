#!/usr/bin/env bats
# Activity history: append/cap, corrupt JSON → empty, tracked ops only.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    HIST="$(mktemp)"
    export REZEPTOR_TEST_HIST="$HIST"
}

teardown() {
    rm -f "$REZEPTOR_TEST_HIST"
}

@test "activity_history append prune corrupt and track filter" {
    run python3 -c "
import json
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from activity_history import (
    HISTORY_CAP,
    TRACKED_OPS,
    append_activity,
    format_activity_ago,
    format_activity_line,
    is_tracked_op,
    load_activity_history,
)
from i18n import clear_cache, set_locale

hist = Path('$REZEPTOR_TEST_HIST')

assert load_activity_history(hist) == []
assert not is_tracked_op('launch')
assert is_tracked_op('install')
assert 'launch' not in TRACKED_OPS

# Corrupt JSON must not raise — empty list.
hist.write_text('{not json', encoding='utf-8')
assert load_activity_history(hist) == []

# Append beyond cap keeps newest HISTORY_CAP.
for i in range(HISTORY_CAP + 5):
    append_activity(
        rid=f'r{i}',
        name=f'Recipe {i}',
        op='install',
        ok=True,
        path=hist,
        ts=1000.0 + i,
    )
items = load_activity_history(hist)
assert len(items) == HISTORY_CAP
assert items[0].rid == f'r{HISTORY_CAP + 4}'
assert items[-1].rid == f'r{5}'

# Untracked op ignored.
before = len(load_activity_history(hist))
append_activity(rid='x', name='X', op='launch', ok=True, path=hist, ts=9999.0)
assert len(load_activity_history(hist)) == before

# Permissions when parent is the settings-style dir (atomic write on path).
mode = hist.stat().st_mode & 0o777
assert mode == 0o600, oct(mode)

clear_cache()
set_locale('de')
line = format_activity_line(items[0], now=items[0].ts + 30)
assert 'Gerade eben' in line or 'Recipe' in line
assert format_activity_ago(items[0].ts, now=items[0].ts + 30) == 'Gerade eben'
set_locale('en')
assert format_activity_ago(items[0].ts, now=items[0].ts + 120) == '2 min ago'

# Failed line key
append_activity(
    rid='bad', name='Bad', op='repair', ok=False, path=hist, ts=20000.0
)
fail = load_activity_history(hist)[0]
set_locale('en')
assert 'failed' in format_activity_line(fail, now=fail.ts + 10)

print('ok')
"
    [ "$status" -eq 0 ]
    echo "$output"
}
