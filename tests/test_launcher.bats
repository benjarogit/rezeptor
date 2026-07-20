#!/usr/bin/env bats
load test_helper

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "humanize_log_line converts @step tags" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from app_support import humanize_log_line
assert humanize_log_line('@step:Proton-GE initialisieren') == '→ Proton-GE initialisieren'
assert humanize_log_line('@ok:Prefix bereit') == '✓ Prefix bereit'
assert humanize_log_line('Speicherzugriffsfehler') is None
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "build_issue_body contains bug report sections" {
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from app_support import build_issue_body
p = Path('/tmp/bats-report-test.txt')
p.write_text('sample log', encoding='utf-8')
body = build_issue_body('wiso-steuer', p, 'abc123')
for s in ['## 🐛 Problem', '## 📋 System', '## 📸 Logs', 'pre-check.sh']:
    assert s in body, s
print('ok')
"
    [ "$status" -eq 0 ]
}

@test "each recipe has repair and validate in recipe.yml" {
    for yml in "$PROJECT_ROOT"/recipes/*/recipe.yml; do
        grep -q '^repair:' "$yml"
        grep -q '^validate:' "$yml"
    done
}
