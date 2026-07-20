"""Recipe discovery and trust-aware listing (extracted from launcher UI)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from i18n import t
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


def discover_recipes(
    *,
    recipes_dir: Path,
    manifest_path: Path,
    project_root: Path,
    verify_trust: bool = True,
) -> DiscoverOutcome:
    """List recipes. If *verify_trust* is False, skip hashing (first paint / async)."""
    found: list[RecipeInfo] = []
    trust_failures: list[str] = []
    manifest_sync = ""
    if not recipes_dir.is_dir():
        return DiscoverOutcome(recipes=found)
    synced = False
    sync_msg = ""
    if verify_trust:
        synced, sync_msg = sync_manifest_if_stale(
            recipes_dir, manifest_path, project_root
        )
        if synced and sync_msg:
            manifest_sync = sync_msg

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

    for yml in yml_paths:
        meta = parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        meta["_dir"] = str(yml.parent)
        if "community" in yml.parent.parts and meta.get("origin", "") != "official":
            meta.setdefault("origin", "community")
        if not verify_trust:
            # Pending trust — scripts still blocked until async verify completes
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
        # After an auto-regenerated manifest, hashes match disk but are not
        # user-approved — force re-confirm (Approve / regen) before scripts run.
        if synced:
            ok, reason = False, sync_msg or t("trust.reason_changed")
        else:
            ok, reason = verify_recipe_trust(yml.parent, manifest_path)
        info = RecipeInfo(rid=rid, meta=meta, trust_ok=ok, trust_reason=reason or "")
        if not ok:
            info.state = RecipeState.UNTRUSTED
            info.status_detail = reason or t("trust.manifest_failed")
            trust_failures.append(f"{rid}: {reason}")
        found.append(info)
    trust_log = ""
    if trust_failures and not rezeptor_dev_mode():
        trust_log = "\n".join(trust_failures)
    return DiscoverOutcome(
        recipes=found,
        manifest_sync=manifest_sync,
        trust_log=trust_log,
    )
