"""Verify recipe files against recipes/manifest.json."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

# Process-local digest cache: (resolved path, mtime_ns, size) → "sha256:…"
_DIGEST_CACHE: dict[tuple[str, int, int], str] = {}


def rezeptor_dev_mode() -> bool:
    return os.environ.get("REZEPTOR_DEV", "").lower() in ("1", "true", "yes")


def manifest_auto_sync_enabled(project_root: Path) -> bool:
    """Auto-sync hashes only with explicit REZEPTOR_DEV — never on mere ``.git``.

    Git checkouts used to regenerate ``manifest.json`` on discover, which made
    local recipe tampering look trusted. Packaged trees and normal git clones
    stay fail-closed via ``verify_recipe_trust``.
    """
    del project_root  # API kept for callers; sync is env-gated only
    return rezeptor_dev_mode()


def friendly_trust_reason(reason: str) -> str:
    """Map technical hash errors to a short user-facing phrase (i18n key suffix)."""
    r = (reason or "").strip()
    if not r:
        return "changed"
    rl = r.lower()
    if "prüft" in rl or "checking" in rl or "integrität" in rl:
        return "checking"
    if r.startswith("Hash mismatch:") or r.startswith("Nicht im Manifest:") or r.startswith("Fehlt:"):
        return "changed"
    if "fehlt" in rl or "missing" in rl or "unlesbar" in rl:
        return "missing"
    return "changed"


def _recipe_id(recipe_dir: Path) -> str:
    rid = recipe_dir.name
    yml = recipe_dir / "recipe.yml"
    if yml.is_file():
        for line in yml.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("id:"):
                return line.split(":", 1)[1].strip().strip('"')
    return rid


def _file_digest(path: Path) -> str:
    """SHA-256 of *path*, cached by mtime/size so refresh/discover do not re-hash."""
    try:
        st = path.stat()
        key = (str(path.resolve()), int(st.st_mtime_ns), int(st.st_size))
    except OSError:
        return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
    cached = _DIGEST_CACHE.get(key)
    if cached is not None:
        return cached
    digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
    _DIGEST_CACHE[key] = digest
    # Bound cache growth (recipe trees are small; still avoid unbounded growth)
    if len(_DIGEST_CACHE) > 4000:
        for old in list(_DIGEST_CACHE.keys())[:1000]:
            _DIGEST_CACHE.pop(old, None)
    return digest


def clear_digest_cache() -> None:
    """Test helper / after external tree rewrite."""
    _DIGEST_CACHE.clear()


def generate_manifest(recipes_dir: Path, manifest_path: Path) -> int:
    """Write manifest.json from recipe tree. Returns recipe count."""
    clear_digest_cache()
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
            files[rel] = _file_digest(path)
        recipes[rid] = {"files": files}

    manifest["recipes"] = recipes
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return len(recipes)


def _iter_recipe_ymls(recipes_dir: Path) -> list[Path]:
    """recipe.yml paths under official and community trees (mirrors discover_recipes)."""
    yml_paths: list[Path] = []
    for yml in sorted(recipes_dir.glob("*/recipe.yml")):
        if yml.parent.name.startswith("_"):
            continue
        if yml.parent.name == "community":
            continue
        yml_paths.append(yml)
    community = recipes_dir / "community"
    if community.is_dir():
        for yml in sorted(community.glob("*/recipe.yml")):
            if yml.parent.name.startswith("_"):
                continue
            yml_paths.append(yml)
    return yml_paths


def _recipe_dir_stale_vs_manifest(
    recipe_dir: Path,
    manifest_path: Path,
    manifest: dict[str, object],
    manifest_mtime_ns: int,
) -> bool:
    """True when the recipe tree may differ from manifest (mtime or membership)."""
    rid = _recipe_id(recipe_dir)
    entry = manifest.get("recipes", {}).get(rid)
    if not isinstance(entry, dict):
        return True
    expected: set[str] = set(entry.get("files", {}))
    actual: set[str] = set()
    needs_hash_check = False
    for path in recipe_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(recipe_dir).as_posix()
        actual.add(rel)
        if rel not in expected:
            return True
        try:
            if path.stat().st_mtime_ns > manifest_mtime_ns:
                needs_hash_check = True
        except OSError:
            return True
    if actual != expected:
        return True
    if needs_hash_check:
        ok, _ = verify_recipe_trust(recipe_dir, manifest_path, strict=True)
        return not ok
    return False


def manifest_needs_sync(recipes_dir: Path, manifest_path: Path) -> bool:
    if not manifest_path.is_file():
        return True
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest_mtime_ns = int(manifest_path.stat().st_mtime_ns)
    except (OSError, json.JSONDecodeError):
        return True
    for yml in _iter_recipe_ymls(recipes_dir):
        if _recipe_dir_stale_vs_manifest(
            yml.parent, manifest_path, manifest, manifest_mtime_ns
        ):
            return True
    return False


def sync_manifest_if_stale(
    recipes_dir: Path, manifest_path: Path, project_root: Path
) -> tuple[bool, str]:
    """Regenerate manifest when recipe files changed (REZEPTOR_DEV only).

    Callers must treat a successful sync as *not* user approval: force
    ``trust_ok=False`` until the user explicitly re-confirms (Approve files).
    """
    if not manifest_auto_sync_enabled(project_root):
        return False, ""
    if not manifest_needs_sync(recipes_dir, manifest_path):
        return False, ""
    count = generate_manifest(recipes_dir, manifest_path)
    return True, f"Rezept-Manifest aktualisiert ({count} Rezepte) — Freigabe nötig"


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
    actual: dict[str, str] = {}
    for path in recipe_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(recipe_dir).as_posix()
        actual[rel] = _file_digest(path)

    for rel, want in sorted(expected.items()):
        if rel not in actual:
            return False, f"Fehlt: {rel}"
        if actual[rel] != want:
            return False, f"Hash mismatch: {rel}"

    for rel in sorted(actual):
        if rel not in expected:
            return False, f"Nicht im Manifest: {rel}"

    return True, ""
