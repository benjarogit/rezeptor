"""Verify recipe files against recipes/manifest.json."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


def rezeptor_dev_mode() -> bool:
    return os.environ.get("REZEPTOR_DEV", "").lower() in ("1", "true", "yes")


def verify_recipe_trust(recipe_dir: Path, manifest_path: Path) -> tuple[bool, str]:
    if rezeptor_dev_mode():
        return True, ""
    if not manifest_path.is_file():
        return False, "manifest.json fehlt"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return False, f"Manifest unlesbar: {exc}"

    rid = recipe_dir.name
    yml = recipe_dir / "recipe.yml"
    if yml.is_file():
        for line in yml.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("id:"):
                rid = line.split(":", 1)[1].strip().strip('"')
                break

    entry = manifest.get("recipes", {}).get(rid)
    if not entry:
        return False, f"Kein Manifest-Eintrag für {rid}"

    expected: dict[str, str] = entry.get("files", {})
    for rel, want in sorted(expected.items()):
        path = recipe_dir / rel
        if not path.is_file():
            return False, f"Fehlt: {rel}"
        got = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        if got != want:
            return False, f"Hash mismatch: {rel}"

    for path in recipe_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(recipe_dir).as_posix()
        if rel not in expected:
            return False, f"Nicht im Manifest: {rel}"

    return True, ""
