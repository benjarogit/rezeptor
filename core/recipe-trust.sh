#!/usr/bin/env bash
# Verify recipe files against recipes/manifest.json
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT/core"

recipe_trust_dev_mode() {
    [ "${REZEPTOR_DEV:-}" = "1" ] || [ "${REZEPTOR_DEV:-}" = "true" ]
}

recipe_trust_verify() {
    local recipe_dir="${1:?recipe dir required}"
    if recipe_trust_dev_mode; then
        return 0
    fi
    python3 - "$recipe_dir" "$ROOT/recipes/manifest.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

recipe_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])

if not manifest_path.is_file():
    print("manifest.json fehlt", file=sys.stderr)
    sys.exit(1)

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
recipes = manifest.get("recipes", {})

rid = recipe_dir.name
yml = recipe_dir / "recipe.yml"
if yml.is_file():
    for line in yml.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("id:"):
            rid = line.split(":", 1)[1].strip().strip('"')
            break

entry = recipes.get(rid)
if not entry:
    print(f"Kein Manifest-Eintrag für {rid}", file=sys.stderr)
    sys.exit(1)

expected = entry.get("files", {})
for rel, want in sorted(expected.items()):
    path = recipe_dir / rel
    if not path.is_file():
        print(f"Fehlt: {rel}", file=sys.stderr)
        sys.exit(1)
    got = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
    if got != want:
        print(f"Hash mismatch: {rel}", file=sys.stderr)
        sys.exit(1)

for path in recipe_dir.rglob("*"):
    if not path.is_file():
        continue
    rel = path.relative_to(recipe_dir).as_posix()
    if rel not in expected:
        print(f"Nicht im Manifest: {rel}", file=sys.stderr)
        sys.exit(1)

sys.exit(0)
PY
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    recipe_trust_verify "${1:?usage: recipe-trust.sh <recipe_dir>}"
fi
