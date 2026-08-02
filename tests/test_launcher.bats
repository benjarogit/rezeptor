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
from i18n import set_locale, clear_cache
from app_support import (
    build_issue_body,
    bug_report_template_name,
    describe_runtime_for_report,
    proton_ge_badge_label,
)
clear_cache()
p = Path('/tmp/bats-report-test.txt')
p.write_text('sample log', encoding='utf-8')
set_locale('en')
body_en = build_issue_body('wiso-steuer', p, 'abc123')
for s in ['## 🐛 Problem', '## 📋 System', '## 📸 Logs', 'pre-check.sh', 'Recipe:', 'Steps to reproduce', 'Proton-GE']:
    assert s in body_en, s
assert 'Support session' in body_en
assert bug_report_template_name() == 'bug_report.md'
assert 'Proton-GE' in describe_runtime_for_report()
assert 'Proton-GE' in proton_ge_badge_label()
set_locale('de')
body_de = build_issue_body('wiso-steuer', p, 'abc123')
for s in ['## 🐛 Problem', 'Rezept:', 'Schritte zum Reproduzieren', 'Support-Session']:
    assert s in body_de, s
assert bug_report_template_name() == 'bug_report_de.md'
print('ok')
"
    [ "$status" -eq 0 ]
}

@test "status.window_soon includes recipe name placeholder" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from i18n import set_locale, clear_cache, t
clear_cache()
set_locale('de')
assert 'Halo' in t('status.window_soon', name='Halo')
assert 'Geduld' in t('status.window_soon', name='Halo')
set_locale('en')
assert 'Halo' in t('status.window_soon', name='Halo')
assert 'Please wait' in t('status.window_soon', name='Halo')
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
