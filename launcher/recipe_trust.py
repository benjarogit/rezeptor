"""Verify recipe files against recipes/manifest.json."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


def rezeptor_dev_mode() -> bool:
    return os.environ.get("REZEPTOR_DEV", "").lower() in ("1", "true", "yes")


def manifest_auto_sync_enabled(project_root: Path) -> bool:
    """Only explicit REZEPTOR_DEV — never auto-rewrite hashes just because .git exists."""
    _ = project_root  # kept for call-site compatibility
    return rezeptor_dev_mode()


def _recipe_id(recipe_dir: Path) -> str:
    rid = recipe_dir.name
    yml = recipe_dir / "recipe.yml"
    if yml.is_file():
        for line in yml.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("id:"):
                return line.split(":", 1)[1].strip().strip('"')
    return rid


def generate_manifest(recipes_dir: Path, manifest_path: Path) -> int:
    """Write manifest.json from recipe tree. Returns recipe count."""
    manifest: dict[str, object] = {"version": 1, "recipes": {}}
    recipes: dict[str, dict[str, dict[str, str]]] = {}

    for recipe_dir in sorted(recipes_dir.iterdir()):
        if not recipe_dir.is_dir() or recipe_dir.name.startswith("_"):
            continue
        yml = recipe_dir / "recipe.yml"
        if not yml.is_file():
            continue
        rid = _recipe_id(recipe_dir)
        files: dict[str, str] = {}
        for path in sorted(recipe_dir.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(recipe_dir).as_posix()
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            files[rel] = f"sha256:{digest}"
        recipes[rid] = {"files": files}

    manifest["recipes"] = recipes
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return len(recipes)


def manifest_needs_sync(recipes_dir: Path, manifest_path: Path) -> bool:
    if not manifest_path.is_file():
        return True
    for yml in sorted(recipes_dir.glob("*/recipe.yml")):
        if yml.parent.name.startswith("_"):
            continue
        ok, _ = verify_recipe_trust(yml.parent, manifest_path, strict=True)
        if not ok:
            return True
    return False


def sync_manifest_if_stale(
    recipes_dir: Path, manifest_path: Path, project_root: Path
) -> tuple[bool, str]:
    """Regenerate manifest when recipe files changed (REZEPTOR_DEV only)."""
    if not manifest_auto_sync_enabled(project_root):
        return False, ""
    if not manifest_needs_sync(recipes_dir, manifest_path):
        return False, ""
    count = generate_manifest(recipes_dir, manifest_path)
    return True, f"Rezept-Manifest aktualisiert ({count} Rezepte)"


def verify_recipe_trust(
    recipe_dir: Path, manifest_path: Path, *, strict: bool = False
) -> tuple[bool, str]:
    if not strict and rezeptor_dev_mode():
        return True, ""
    if not manifest_path.is_file():
        return False, "manifest.json fehlt"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return False, f"Manifest unlesbar: {exc}"

    rid = _recipe_id(recipe_dir)

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
