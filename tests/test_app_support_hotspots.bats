#!/usr/bin/env bats
# app_support hotspots: version mismatch, report bundle, proton tag from options

load test_helper

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "version_guarantee_mismatch allows build suffix only" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from app_support import version_guarantee_mismatch
assert version_guarantee_mismatch('', '1') is False
assert version_guarantee_mismatch('22.0.0.35', '') is False
assert version_guarantee_mismatch('22.0.0.35', '22.0.0.35') is False
assert version_guarantee_mismatch('Halo CE', 'Halo CE (Build 9)') is False
assert version_guarantee_mismatch('22.0.0.35', '22.1.1.138') is True
assert version_guarantee_mismatch('22.0', '22.0.0.35') is True
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "parse_validate_version_fields reads OK and WARN lines" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from app_support import parse_validate_version_fields
out = '''
OK: prefix: vorhanden
OK: Photoshop: 22.0.0.35 (getestet & garantiert)
WARN: Quelle weicht von garantiert ab
noise
'''
det, warn = parse_validate_version_fields(out)
assert det == '22.0.0.35', det
assert 'garantiert' in warn
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "effective_proton_ge_tag prefers Photoshop Medizin bool" {
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from app_support import effective_proton_ge_tag, read_proton_ge_tag
dr = Path('$BATS_TEST_TMPDIR/data')
dr.mkdir()
(dr / 'options.env').write_text('PHOTOSHOP_PROTON_GE_11=1\n', encoding='utf-8')
assert effective_proton_ge_tag(data_root=dr) == 'GE-Proton11-3'
(dr / 'options.env').write_text('PHOTOSHOP_PROTON_GE_11=0\n', encoding='utf-8')
# false → fall through to lock
lock = read_proton_ge_tag()
assert effective_proton_ge_tag(data_root=dr) == lock
(dr / 'options.env').write_text('PROTON_GE_TAG=GE-Proton10-20\n', encoding='utf-8')
assert effective_proton_ge_tag(data_root=dr) == 'GE-Proton10-20'
assert effective_proton_ge_tag(recipe_tag='GE-Proton10-28') == 'GE-Proton10-28'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "collect_report_bundle writes sanitized report with session and data logs" {
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
import app_support
from i18n import set_locale, clear_cache

tmp = Path('$BATS_TEST_TMPDIR/logs')
tmp.mkdir()
app_support.LOG_ROOT = tmp

data = Path('$BATS_TEST_TMPDIR/recipe-data')
data.mkdir()
(data / 'photoshop_Install_errors.log').write_text(
    'ERROR: fail at /home/elsarraf/secret\n', encoding='utf-8'
)
(data / 'install.log').write_text('@step:Prefix\nOK\n', encoding='utf-8')

clear_cache()
set_locale('en')
out = app_support.collect_report_bundle(
    'photoshop',
    'sessdeadbeef',
    data_root=data,
    recipe_name='Adobe Photoshop CC 2021',
    version_guaranteed='22.0.0.35',
    version_detected='22.0.0.35',
)
assert out.is_file(), out
text = out.read_text(encoding='utf-8')
assert 'sessdeadbeef' in text
assert '22.0.0.35' in text
assert 'photoshop_Install_errors.log' in text or 'Install_errors' in text
assert '/home/elsarraf' not in text
assert '/home/<USER>' in text
assert 'Proton-GE' in text
print('ok', out.name)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "build_diagnose_zip allowlists logs, tails bytes, sanitizes, skips secrets files" {
    run python3 -c "
import sys
from pathlib import Path
import zipfile
sys.path.insert(0, '$PROJECT_ROOT/launcher')
import app_support
from i18n import set_locale, clear_cache

tmp = Path('$BATS_TEST_TMPDIR/logs')
tmp.mkdir()
app_support.LOG_ROOT = tmp

# Allowlisted
(tmp / 'launch_photoshop_deadbeef.log').write_text(
    'x' * 4000 + '\nERROR at /home/elsarraf/secret\nOK\n', encoding='utf-8'
)
(tmp / 'winetricks_foo.log').write_text('winetricks ok\n', encoding='utf-8')
(tmp / 'rezeptor-exit-diagnostics.log').write_text('diag\n', encoding='utf-8')
# Must NOT be packed
(tmp / 'archive-passwords.json').write_text('{\"p\":\"x\"}\n', encoding='utf-8')
(tmp / 'random.txt').write_text('nope\n', encoding='utf-8')
(tmp / 'diagnose_old.zip').write_bytes(b'PK\x03\x04')

data = Path('$BATS_TEST_TMPDIR/recipe-data')
data.mkdir()
(data / 'install.log').write_text('@step:Prefix\npath=/home/benny/x\n', encoding='utf-8')
(data / 'options.env').write_text('SECRET=1\n', encoding='utf-8')

clear_cache()
set_locale('en')
built = app_support.build_diagnose_zip(
    'photoshop',
    'sessdeadbeef',
    data_root=data,
    recipe_name='Adobe Photoshop CC 2021',
    per_file_bytes=512,
)
assert built is not None, built
out, count = built
assert out.is_file() and out.name.startswith('diagnose_photoshop_')
assert count >= 2
with zipfile.ZipFile(out, 'r') as zf:
    names = set(zf.namelist())
assert 'README.txt' in names
assert 'logs/launch_photoshop_deadbeef.log' in names
assert 'data_logs/install.log' in names
assert 'logs/archive-passwords.json' not in names
assert 'data_logs/options.env' not in names
assert not any(n.endswith('random.txt') for n in names)
launch = zipfile.ZipFile(out).read('logs/launch_photoshop_deadbeef.log').decode()
assert '/home/elsarraf' not in launch
assert '/home/<USER>' in launch
assert len(launch.encode()) <= 512 + 80  # tail + sanitize slack
print('ok', out.name, count)
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "sanitize_log_text redacts home paths and secrets" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from app_support import sanitize_log_text
s = sanitize_log_text('path=/home/benny/x token=abc123 7z -pSECRET file.zip')
assert '/home/<USER>' in s
assert 'token=<REDACTED>' in s or 'token=abc123' not in s
assert 'SECRET' not in s
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
