"""Bundled vs user overlay recipe paths."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

_OVERLAY_ENV = "REZEPTOR_OVERLAY_ROOT"


def overlay_root() -> Path:
    """Writable user overlay (recipes sync). Override with REZEPTOR_OVERLAY_ROOT."""
    env = (os.environ.get(_OVERLAY_ENV) or "").strip()
    if env:
        return Path(env).expanduser()
    return Path.home() / ".local/share/rezeptor"


def overlay_recipes_dir() -> Path:
    return overlay_root() / "recipes"


def overlay_manifest_path() -> Path:
    return overlay_root() / "manifest.overlay.json"


def overlay_catalog_path() -> Path:
    return overlay_root() / "catalog.remote.json"


def sync_state_path() -> Path:
    return overlay_root() / "sync-state.json"


def ensure_overlay_dirs() -> Path:
    root = overlay_root()
    (root / "recipes").mkdir(parents=True, exist_ok=True)
    (root / "cache").mkdir(parents=True, exist_ok=True)
    return root


def recipe_is_under(recipe_dir: Path, root: Path) -> bool:
    try:
        recipe_dir.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False


def manifest_for_recipe_dir(
    recipe_dir: Path,
    *,
    bundled_manifest: Path,
    overlay_manifest: Path | None = None,
) -> Path:
    """Pick manifest that owns *recipe_dir* (overlay wins when path is under overlay)."""
    omani = overlay_manifest if overlay_manifest is not None else overlay_manifest_path()
    if recipe_is_under(recipe_dir, overlay_recipes_dir()) and omani.is_file():
        return omani
    return bundled_manifest


def load_sync_state_safe() -> dict[str, Any]:
    """Read sync-state.json without importing recipe_sync (discovery/UI)."""
    path = sync_state_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}
