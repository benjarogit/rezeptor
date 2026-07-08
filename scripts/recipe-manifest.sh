#!/usr/bin/env bash
# Generate recipes/manifest.json with SHA256 hashes (deterministic).
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES="$ROOT/recipes"
OUT="$RECIPES/manifest.json"

python3 - "$RECIPES" "$OUT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

recipes_dir = Path(sys.argv[1])
out_path = Path(sys.argv[2])
manifest = {"version": 1, "recipes": {}}

for recipe_dir in sorted(recipes_dir.iterdir()):
    if not recipe_dir.is_dir():
        continue
    if recipe_dir.name.startswith("_"):
        continue
    yml = recipe_dir / "recipe.yml"
    if not yml.is_file():
        continue
    rid = recipe_dir.name
    for line in yml.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("id:"):
            rid = line.split(":", 1)[1].strip().strip('"')
            break
    files: dict[str, str] = {}
    for path in sorted(recipe_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(recipe_dir).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        files[rel] = f"sha256:{digest}"
    manifest["recipes"][rid] = {"files": files}

out_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"Wrote {out_path} ({len(manifest['recipes'])} recipes)")
PY
