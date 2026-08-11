#!/usr/bin/env bats
# version_detect signal kinds + recipe.yml integration (no PE / no real packs)

load test_helper

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURE="$BATS_TEST_TMPDIR/pack"
    mkdir -p "$FIXTURE/products/PHSP"
}

@test "json_key reads ProductVersion from application.json" {
    cat >"$FIXTURE/products/PHSP/application.json" <<'EOF'
{"ProductVersion": "22.0.0.35", "Name": "Photoshop"}
EOF
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_with_rules
root = Path('$FIXTURE')
rules = [{'kind': 'json_key', 'glob': 'products/PHSP/application.json', 'key': 'ProductVersion'}]
assert detect_with_rules(str(root), rules) == '22.0.0.35'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "text_regex extracts first capture group" {
    printf 'BuildId=7575778\nother=1\n' >"$FIXTURE/build.ini"
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_with_rules
root = Path('$FIXTURE')
rules = [{'kind': 'text_regex', 'glob': 'build.ini', 'regex': r'BuildId=([0-9]+)'}]
assert detect_with_rules(str(root), rules) == '7575778'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "filename_regex returns capture or label" {
    touch "$FIXTURE/AdobePhotoshop_22.1.1.138.exe"
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_with_rules
root = Path('$FIXTURE')
rules = [{
    'kind': 'filename_regex',
    'regex': r'AdobePhotoshop_([0-9.]+)\\.exe',
}]
assert detect_with_rules(str(root), rules) == '22.1.1.138'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "stack returns ok_label when files and ini match" {
    mkdir -p "$FIXTURE/bin"
    touch "$FIXTURE/bin/game.exe" "$FIXTURE/identity.flag"
    cat >"$FIXTURE/steam_appid.ini" <<'EOF'
appid=12345
build=9
EOF
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_with_rules
root = Path('$FIXTURE')
rules = [{
    'kind': 'stack',
    'identity_file': 'identity.flag',
    'require_files': ['bin/game.exe'],
    'ini': 'steam_appid.ini',
    'require_ini': {'appid': '12345'},
    'build_key': 'build',
    'ok_label': 'Halo CE',
}]
assert detect_with_rules(str(root), rules, guaranteed='Halo CE') == 'Halo CE (Build 9)'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "stack returns partial_label when required file missing" {
    touch "$FIXTURE/identity.flag"
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_with_rules
root = Path('$FIXTURE')
rules = [{
    'kind': 'stack',
    'identity_file': 'identity.flag',
    'require_files': ['bin/missing.exe'],
    'ok_label': 'Full',
    'partial_label': 'Partial pack',
}]
hit = detect_with_rules(str(root), rules)
assert hit.startswith('Partial pack'), hit
assert 'unvollständig' in hit
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "first matching rule wins; empty path returns empty" {
    cat >"$FIXTURE/products/PHSP/application.json" <<'EOF'
{"ProductVersion": "22.0.0.35"}
EOF
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_with_rules
root = Path('$FIXTURE')
rules = [
    {'kind': 'json_key', 'glob': 'products/PHSP/application.json', 'key': 'ProductVersion'},
    {'kind': 'filename_regex', 'regex': r'never', 'label': 'nope'},
]
assert detect_with_rules(str(root), rules) == '22.0.0.35'
assert detect_with_rules('', rules) == ''
assert detect_with_rules('/no/such/path', rules) == ''
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "detect_recipe_version uses photoshop recipe.yml against fixture" {
    cat >"$FIXTURE/products/PHSP/application.json" <<'EOF'
{"ProductVersion": "22.0.0.35"}
EOF
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import detect_recipe_version
yml = Path('$PROJECT_ROOT/recipes/photoshop/recipe.yml')
hit = detect_recipe_version(str(Path('$FIXTURE')), yml)
assert hit == '22.0.0.35', hit
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "minimal parser keeps version_detect list of mappings" {
    run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/launcher')
from version_detect import _load_recipe_mapping_minimal
text = '''
id: demo
version_guaranteed: \"1.2.3\"
version_detect:
  - kind: json_key
    glob: \"products/X/application.json\"
    key: ProductVersion
  - kind: text_regex
    file: build.ini
    regex: \"BuildId=([0-9]+)\"
'''
data = _load_recipe_mapping_minimal(text)
assert data['version_guaranteed'] == '1.2.3'
vd = data['version_detect']
assert isinstance(vd, list) and len(vd) == 2, vd
assert vd[0]['kind'] == 'json_key'
assert vd[0]['key'] == 'ProductVersion'
assert vd[1]['kind'] == 'text_regex'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
