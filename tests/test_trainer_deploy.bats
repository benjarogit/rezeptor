#!/usr/bin/env bats
# trainer_deploy: EXE vs folder pack heuristics

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PYTHONPATH="$ROOT/launcher${PYTHONPATH:+:$PYTHONPATH}"
}

@test "lone exe in busy folder copies only the exe" {
    run python3 - "$ROOT" <<'PY'
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from trainer_deploy import deploy_trainer_source, trainer_dir

td = Path(tempfile.mkdtemp())
downloads = td / "Downloads"
downloads.mkdir()
# Simulate busy Downloads
for i in range(30):
    (downloads / f"noise_{i}.txt").write_text("x", encoding="utf-8")
exe = downloads / "Halo Campaign Evolved v1.0 Plus 16 Trainer.exe"
exe.write_bytes(b"MZ-fake")
(downloads / "unrelated.dll").write_bytes(b"dll")

data = td / "data"
deployed = deploy_trainer_source(data, exe)
dest = trainer_dir(data)
assert deployed.name == exe.name
assert deployed.is_file()
names = {p.name for p in dest.iterdir()}
assert names == {exe.name}, names
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "folder pack copies exe and dll" {
    run python3 - "$ROOT" <<'PY'
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from trainer_deploy import deploy_trainer_source, trainer_dir

td = Path(tempfile.mkdtemp())
pack = td / "FLiNG-Trainer-Pack"
pack.mkdir()
exe = pack / "Game Plus 16 Trainer.exe"
exe.write_bytes(b"MZ")
(pack / "TrSpeedHack_x64.dll").write_bytes(b"dll")
(pack / "notes.ini").write_text("x", encoding="utf-8")

data = td / "data"
deployed = deploy_trainer_source(data, pack)
dest = trainer_dir(data)
assert deployed.name == exe.name
names = {p.name for p in dest.iterdir()}
assert "Game Plus 16 Trainer.exe" in names
assert "TrSpeedHack_x64.dll" in names
assert "notes.ini" in names
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "exe with sidecars in named trainer folder copies companions" {
    run python3 - "$ROOT" <<'PY'
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from trainer_deploy import deploy_trainer_source, trainer_dir

td = Path(tempfile.mkdtemp())
pack = td / "MyTrainer"
pack.mkdir()
exe = pack / "Foo Trainer.exe"
exe.write_bytes(b"MZ")
(pack / "TrSpeedHack_x64.dll").write_bytes(b"dll")
(pack / "Foo Trainer.ini").write_text("cfg", encoding="utf-8")

data = td / "data"
# Keep README across replace
dest = trainer_dir(data)
dest.mkdir(parents=True)
(dest / "README.txt").write_text("keep", encoding="utf-8")
(dest / "OldTrainer.exe").write_bytes(b"old")

deployed = deploy_trainer_source(data, exe)
names = {p.name for p in dest.iterdir()}
assert "README.txt" in names
assert "OldTrainer.exe" not in names
assert "Foo Trainer.exe" in names
assert "TrSpeedHack_x64.dll" in names
assert "Foo Trainer.ini" in names
assert deployed.name == "Foo Trainer.exe"
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "halo launch_trainer option parses pick metadata" {
    run python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "launcher"))
from recipe_options import parse_recipe_options

opts = parse_recipe_options(root / "recipes" / "halo-campaign-evolved" / "recipe.yml")
tr = next(o for o in opts if o.id == "launch_trainer")
assert tr.pick is not None
assert tr.pick.kind == "file_or_folder"
assert tr.pick.dest_rel == "trainer"
assert tr.pick.source_env == "HALO_TRAINER_SOURCE"
# Minimal parser path (no PyYAML dependency for this assert)
from version_detect import _load_recipe_mapping_minimal

text = (root / "recipes" / "halo-campaign-evolved" / "recipe.yml").read_text(
    encoding="utf-8"
)
data = _load_recipe_mapping_minimal(text)
opts2 = parse_recipe_options(data)
tr2 = next(o for o in opts2 if o.id == "launch_trainer")
assert tr2.pick is not None, tr2
assert tr2.pick.dest_rel == "trainer"
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}
