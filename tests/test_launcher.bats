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
    format_tested_on_display,
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
set_locale('en')
assert format_tested_on_display('2026-08-11') == '11 Aug 2026'
assert format_tested_on_display('') is None
assert format_tested_on_display('nope') is None
set_locale('de')
assert format_tested_on_display('2026-08-11') == '11.08.2026'
body_de = build_issue_body('wiso-steuer', p, 'abc123')
for s in ['## 🐛 Problem', 'Rezept:', 'Schritte zum Reproduzieren', 'Support-Session']:
    assert s in body_de, s
assert bug_report_template_name() == 'bug_report_de.md'
print('ok')
"
    [ "$status" -eq 0 ]
}

@test "status.progress_pct stays for a11y, not the left step label" {
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from i18n import set_locale, clear_cache, t
clear_cache()
set_locale('de')
assert t('status.progress_pct', pct='45') == 'Fortschritt — 45%'
set_locale('en')
assert t('status.progress_pct', pct='45') == 'Progress — 45%'
src = Path('$PROJECT_ROOT/launcher/launcher.py').read_text(encoding='utf-8')
assert 'status.progress_pct' in src
assert 't(\"status.progress_pct\", pct=str(self._progress_pct))' not in src
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
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

@test "info markdown headings get extra space after the first block" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from launcher import format_recipe_info_html
html = format_recipe_info_html('Intro line\\n\\n# Installation\\n\\nGo')
assert \"margin:16px 0 6px\" in html, html
html2 = format_recipe_info_html('Intro\\n\\nKurzbeschreibung:\\nHi')
assert \"margin:16px 0 4px\" in html2, html2
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "each recipe has repair and validate in recipe.yml" {
    for yml in "$PROJECT_ROOT"/recipes/*/recipe.yml; do
        grep -q '^repair:' "$yml"
        grep -q '^validate:' "$yml"
    done
}

@test "launch_wait long uses a 4-minute alive window" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from recipe_process import (
    LAUNCH_ALIVE_ATTEMPTS_DEFAULT,
    LAUNCH_ALIVE_ATTEMPTS_LONG,
    launch_alive_max_attempts,
    launch_tips_key_for_meta,
)
assert launch_alive_max_attempts({}) == LAUNCH_ALIVE_ATTEMPTS_DEFAULT
assert launch_alive_max_attempts({'launch_wait': 'long'}) == LAUNCH_ALIVE_ATTEMPTS_LONG
assert launch_alive_max_attempts({'launch_wait': 'long'}) >= 100
assert launch_alive_max_attempts({}, 'warte auf Halo unter Steam') == LAUNCH_ALIVE_ATTEMPTS_LONG
assert launch_tips_key_for_meta({'launch_wait': 'long'}) == 'dialog.launch_tips_portable'
assert launch_tips_key_for_meta({'launch_tips_key': 'dialog.launch_tips_wiso'}) == 'dialog.launch_tips_wiso'
assert launch_tips_key_for_meta({}) == 'dialog.launch_tips_default'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "exe_patterns_match treats wine wrap as Lightroom.exe" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from launcher import exe_patterns_match
pats = ['lightroom.exe']
assert exe_patterns_match(pats, argv0=r'C:\\\\Program Files\\\\Adobe\\\\Lightroom.exe', comm='Lightroom.exe')
assert exe_patterns_match(pats, argv0='wine64', comm='wine64', arg_basenames=['wine64', 'Lightroom.exe'])
assert exe_patterns_match(pats, argv0='/opt/proton/bin/wine64', comm='Lightroom.exe')
assert not exe_patterns_match(pats, argv0='AdobeIPCBroker.exe', comm='AdobeIPCBroker.exe', arg_basenames=['AdobeIPCBroker.exe', 'Lightroom.exe'])
assert not exe_patterns_match(['photoshop.exe'], argv0='wine64', comm='wine64', arg_basenames=['wine64', 'Lightroom.exe'])
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "recipe_guard cmdline_has_exe matches wrapped Lightroom.exe" {
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/core/recipe-guard.sh"
    recipe_guard::_cmdline_has_exe \
        "wine64 /mnt/app/Adobe Lightroom Classic/Lightroom.exe" \
        "Lightroom.exe"
    ! recipe_guard::_cmdline_has_exe \
        "wine64 /mnt/app/Photoshop.exe" \
        "Lightroom.exe"
}

@test "header watermark is right-aligned and clipped to card radius" {
    run env QT_QPA_PLATFORM=offscreen python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from PyQt6.QtCore import QSize, Qt
from PyQt6.QtGui import QColor, QPainter, QPixmap
from PyQt6.QtWidgets import QApplication
from launcher import _HEADER_CARD_RADIUS, faded_header_watermark

app = QApplication.instance() or QApplication([])

def _make(w, h, color):
    pm = QPixmap(w, h)
    pm.fill(color)
    return pm

square = faded_header_watermark(_make(256, 256, QColor('#B87333')), QSize(400, 80), radius=_HEADER_CARD_RADIUS)
wide = faded_header_watermark(_make(800, 120, QColor('#F5C518')), QSize(400, 80), radius=_HEADER_CARD_RADIUS)
assert square.width() == 400 and square.height() == 80
assert wide.width() == 400 and wide.height() == 80
sq = square.toImage()
wd = wide.toImage()
# Far-right column has ink; far-left does not (same path for square and banner).
assert sq.pixelColor(395, 40).alpha() > 0
assert wd.pixelColor(395, 40).alpha() > 0
assert sq.pixelColor(8, 40).alpha() == 0
assert wd.pixelColor(8, 40).alpha() == 0
# Expand-crop fills header height (not a contained mid-band strip).
assert sq.pixelColor(360, 2).alpha() > 0
assert sq.pixelColor(360, 77).alpha() > 0
assert wd.pixelColor(360, 2).alpha() > 0
assert wd.pixelColor(360, 77).alpha() > 0
# Outer corner of the 8px radius is transparent (no square bleed).
assert sq.pixelColor(399, 0).alpha() == 0
assert wd.pixelColor(399, 0).alpha() == 0
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "medizin uninstalled saves options without fake update CTA" {
    run env QT_QPA_PLATFORM=offscreen python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from i18n import set_locale, clear_cache, t
from launcher import pending_repair_overrides_cta
from ui_medizin import medizin_save_followup

clear_cache()
set_locale('de')
assert medizin_save_followup(installed=False, needs_overlay_apply=True) == (
    'medizin.apply_install_hint', 'ok', False,
)
assert medizin_save_followup(installed=True, needs_overlay_apply=True) == (
    'medizin.apply_repair_hint', 'warn', True,
)
assert medizin_save_followup(installed=False, needs_overlay_apply=False) == (
    'medizin.saved_ok', 'ok', False,
)
hint_install = t('medizin.apply_install_hint')
hint_repair = t('medizin.apply_repair_hint')
assert 'Installieren' in hint_install
assert 'Aktualisieren' not in hint_install
assert 'Aktualisieren' not in hint_repair
assert t('btn.install') == 'Installieren'
set_locale('en')
assert 'install' in t('medizin.apply_install_hint').lower()
assert 'update now' not in t('medizin.apply_install_hint').lower()
assert 'update now' not in t('medizin.apply_repair_hint').lower()

assert pending_repair_overrides_cta(
    pending_rid='prototype',
    recipe_rid='prototype',
    has_repair_sh=True,
    checking=False,
    installed_ish=False,
) is False
assert pending_repair_overrides_cta(
    pending_rid='prototype',
    recipe_rid='prototype',
    has_repair_sh=True,
    checking=False,
    installed_ish=True,
) is True

src = Path('$PROJECT_ROOT/launcher/launcher.py').read_text(encoding='utf-8')
assert 'medizin.apply_install_hint' in src
assert 'pending_repair_overrides_cta' in src
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
