"""Recipe discovery and trust-aware listing (extracted from launcher UI)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from i18n import t
from recipe_paths import (
    load_sync_state_safe,
    manifest_for_recipe_dir,
    overlay_manifest_path,
    overlay_recipes_dir,
)
from recipe_trust import (
    rezeptor_dev_mode,
    sync_manifest_if_stale,
    verify_recipe_trust,
)
from version_detect import load_recipe_mapping

# Nested / complex YAML keys — not flattened into GUI meta strings.
_SKIP_COMPLEX_KEYS = frozenset(
    {
        "version_detect",
        "install_steps",
        "env",
        "desktop",
        "shortcuts",
    }
)


class RecipeState(str, Enum):
    NOT_INSTALLED = "not_installed"
    PARTIAL = "partial"
    INSTALLED = "installed"
    UNKNOWN = "unknown"
    UNTRUSTED = "untrusted"
    CHECKING = "checking"  # first paint — trust verify still running


STATE_LABEL = {
    RecipeState.NOT_INSTALLED: "state.not_installed",
    RecipeState.PARTIAL: "state.partial",
    RecipeState.INSTALLED: "state.installed",
    RecipeState.UNKNOWN: "state.unknown",
    RecipeState.UNTRUSTED: "state.untrusted",
    RecipeState.CHECKING: "state.checking",
}


@dataclass
class RecipeInfo:
    rid: str
    meta: dict[str, str]
    state: RecipeState = RecipeState.UNKNOWN
    status_detail: str = ""
    version_detected: str = ""
    version_warning: str = ""
    trust_ok: bool = True
    trust_reason: str = ""
    validate_fails: list[str] | None = None


@dataclass
class DiscoverOutcome:
    """Recipe list plus trust/sync messages (no os.environ side channel)."""

    recipes: list[RecipeInfo]
    manifest_sync: str = ""
    trust_log: str = ""


def _flatten_scalar(value: Any) -> str | None:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return value
    return None


def parse_recipe_yml(path: Path) -> dict[str, str]:
    """GUI metadata from recipe.yml via PyYAML (or minimal mapping).

    Complex blocks (version_detect, install_steps, env, …) are skipped.
    String lists (winetricks, launch_process_patterns, source_formats) become
    comma-separated strings for existing callers.
    """
    raw = load_recipe_mapping(path)
    data: dict[str, str] = {}
    for key, val in raw.items():
        if not isinstance(key, str) or key in _SKIP_COMPLEX_KEYS:
            continue
        flat = _flatten_scalar(val)
        if flat is not None:
            data[key] = flat
            continue
        if isinstance(val, list) and all(isinstance(x, str) for x in val):
            data[key] = ",".join(x.strip() for x in val if str(x).strip())
            continue
        # Inline list like source_formats already a string from minimal parser
    data.setdefault("schema_version", "1")
    return data


def launch_process_patterns_from_meta(meta: dict[str, str], rid: str = "") -> list[str]:
    """Patterns for alive-check: recipe.yml ``launch_process_patterns`` or exe basename."""
    raw = (meta.get("launch_process_patterns") or "").strip()
    if raw:
        return [p.strip() for p in raw.replace(";", ",").split(",") if p.strip()]
    # Derive from exe_glob last path segment when it looks like a filename
    eg = (meta.get("exe_glob") or "").strip().replace("\\", "/")
    if eg:
        base = eg.rsplit("/", 1)[-1]
        if base and "*" not in base and "?" not in base and base.lower().endswith(
            (".exe", ".bin")
        ):
            return [base]
    del rid
    return []


def _collect_yml_paths(recipes_dir: Path) -> list[Path]:
    yml_paths: list[Path] = []
    if not recipes_dir.is_dir():
        return yml_paths
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


def merge_recipe_yml_paths(
    bundled_recipes: Path,
    overlay_recipes: Path | None = None,
) -> list[Path]:
    """Official/community ymls; overlay path wins on the same recipe id."""
    by_id: dict[str, Path] = {}
    for yml in _collect_yml_paths(bundled_recipes):
        meta = parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        by_id[rid] = yml
    if overlay_recipes is not None and overlay_recipes.is_dir():
        for yml in _collect_yml_paths(overlay_recipes):
            meta = parse_recipe_yml(yml)
            rid = meta.get("id", yml.parent.name)
            by_id[rid] = yml
    return [by_id[k] for k in sorted(by_id)]


def discover_recipes(
    *,
    recipes_dir: Path,
    manifest_path: Path,
    project_root: Path,
    verify_trust: bool = True,
    overlay_recipes: Path | None = None,
    overlay_manifest: Path | None = None,
) -> DiscoverOutcome:
    """List recipes. If *verify_trust* is False, skip hashing (first paint / async).

    When *overlay_recipes* is set (default: user overlay), those trees override
    bundled recipes with the same id.
    """
    found: list[RecipeInfo] = []
    trust_failures: list[str] = []
    manifest_sync = ""
    ov_recipes = (
        overlay_recipes if overlay_recipes is not None else overlay_recipes_dir()
    )
    ov_manifest = (
        overlay_manifest if overlay_manifest is not None else overlay_manifest_path()
    )

    if not recipes_dir.is_dir() and not ov_recipes.is_dir():
        return DiscoverOutcome(recipes=found)

    synced = False
    sync_msg = ""
    if verify_trust and recipes_dir.is_dir():
        synced, sync_msg = sync_manifest_if_stale(
            recipes_dir, manifest_path, project_root
        )
        if synced and sync_msg:
            manifest_sync = sync_msg

    yml_paths = merge_recipe_yml_paths(recipes_dir, ov_recipes)
    deprecated_ids = set(load_sync_state_safe().get("deprecated_ids") or [])

    for yml in yml_paths:
        meta = parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        meta["_dir"] = str(yml.parent)
        if recipe_is_overlay := _is_under(yml.parent, ov_recipes):
            meta["_source"] = "overlay"
        else:
            meta["_source"] = "bundled"
        if "community" in yml.parent.parts and meta.get("origin", "") != "official":
            meta.setdefault("origin", "community")
        if rid in deprecated_ids:
            meta["deprecated"] = "true"

        if not verify_trust:
            info = RecipeInfo(
                rid=rid,
                meta=meta,
                trust_ok=False,
                trust_reason=t("trust.reason_checking"),
                state=RecipeState.CHECKING,
                status_detail=t("trust.reason_checking"),
            )
            found.append(info)
            continue

        use_manifest = manifest_for_recipe_dir(
            yml.parent,
            bundled_manifest=manifest_path,
            overlay_manifest=ov_manifest,
        )
        # Bundled auto-sync forces re-confirm only for bundled recipes
        if synced and not recipe_is_overlay:
            ok, reason = False, sync_msg or t("trust.reason_changed")
        else:
            ok, reason = verify_recipe_trust(yml.parent, use_manifest)

        info = RecipeInfo(rid=rid, meta=meta, trust_ok=ok, trust_reason=reason or "")
        if not ok:
            info.state = RecipeState.UNTRUSTED
            info.status_detail = reason or t("trust.manifest_failed")
            trust_failures.append(f"{rid}: {reason}")
        elif rid in deprecated_ids:
            info.status_detail = t("recipe_sync.deprecated_detail")
        found.append(info)

    trust_log = ""
    if trust_failures and not rezeptor_dev_mode():
        trust_log = "\n".join(trust_failures)
    return DiscoverOutcome(
        recipes=found,
        manifest_sync=manifest_sync,
        trust_log=trust_log,
    )


def _is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False
