"""Official recipe sync via GitHub Release asset (rezeptor-recipes-*.tar.gz)."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import tarfile
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from app_support import GITHUB_REPO, read_version, version_compare
from recipe_paths import (
    ensure_overlay_dirs,
    overlay_catalog_path,
    overlay_manifest_path,
    overlay_recipes_dir,
    sync_state_path,
)
from recipe_trust import clear_digest_cache, verify_recipe_trust

_HTTP_TIMEOUT = 45
_USER_AGENT = "Rezeptor-recipe-sync/1.0"
_RECIPES_ASSET_RE = re.compile(r"^rezeptor-recipes-([0-9][0-9A-Za-z.\-]*)\.tar\.gz$")
DownloadFn = Callable[[str], bytes]


class RecipeSyncError(Exception):
    """Raised when recipe bundle fetch/apply fails."""


@dataclass
class RecipeChange:
    id: str
    kind: str  # added | updated | removed | blocked | deprecated
    detail: str = ""


@dataclass
class RecipeSyncPlan:
    bundle_version: str
    asset_name: str
    asset_url: str
    sha256_expected: str
    release_url: str
    changes: list[RecipeChange] = field(default_factory=list)
    app_version: str = ""

    @property
    def actionable(self) -> list[RecipeChange]:
        return [c for c in self.changes if c.kind in ("added", "updated", "removed")]

    @property
    def has_actionable(self) -> bool:
        return bool(self.actionable)

    @property
    def pending_count(self) -> int:
        return len(self.actionable) + sum(
            1 for c in self.changes if c.kind in ("blocked", "deprecated")
        )


def _http_get(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/octet-stream, application/json, */*",
            "User-Agent": _USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        raise RecipeSyncError(f"HTTP {exc.code} for {url}: {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise RecipeSyncError(f"Network error for {url}: {exc.reason}") from exc
    except (TimeoutError, OSError) as exc:
        raise RecipeSyncError(f"Failed to download {url}: {exc}") from exc


def _http_get_json(url: str) -> Any:
    data = _http_get(url)
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RecipeSyncError(f"Invalid JSON from {url}: {exc}") from exc


def parse_sha256sums(text: str) -> dict[str, str]:
    """Parse ``sha256sum`` output: ``<hex>  <filename>``."""
    out: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        digest, name = parts[0], parts[-1]
        name = name.lstrip("*")
        if re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            out[Path(name).name] = digest.lower()
    return out


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _safe_tar_members(tf: tarfile.TarFile, dest: Path) -> list[tarfile.TarInfo]:
    dest_res = dest.resolve()
    safe: list[tarfile.TarInfo] = []
    for member in tf.getmembers():
        name = (member.name or "").replace("\\", "/")
        if not name or name.startswith("/") or Path(name).is_absolute():
            raise RecipeSyncError(f"Unsafe archive path: {member.name!r}")
        parts = tuple(p for p in Path(name).parts if p not in ("", "."))
        if any(p == ".." for p in parts):
            raise RecipeSyncError(f"Path traversal rejected: {member.name!r}")
        # GNU tar often stores archive root as "." / "./" — skip, not traversal
        if not parts:
            continue
        target = (dest / Path(*parts)).resolve()
        try:
            target.relative_to(dest_res)
        except ValueError as exc:
            raise RecipeSyncError(f"Path escapes extract dir: {member.name!r}") from exc
        # Rewrite member name to normalized relative path
        member.name = "/".join(parts)
        safe.append(member)
    return safe


def safe_extract_tar_gz(archive: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "r:gz") as tf:
        members = _safe_tar_members(tf, dest)
        for member in members:
            tf.extract(member, path=dest, set_attrs=False)


def _norm_version(v: str) -> str:
    return (v or "").strip().lstrip("v")


def app_version_satisfies(min_app_version: str, app_version: str) -> bool:
    """True when *app_version* >= *min_app_version* (empty min = always ok)."""
    need = _norm_version(min_app_version)
    have = _norm_version(app_version)
    if not need:
        return True
    if not have:
        return False
    # version_compare(a, b) is True when b > a — need have >= need
    if have == need:
        return True
    return version_compare(need, have)  # True if have > need


def _recipe_ids_from_tree(recipes_root: Path) -> dict[str, Path]:
    found: dict[str, Path] = {}
    if not recipes_root.is_dir():
        return found
    for yml in sorted(recipes_root.glob("*/recipe.yml")):
        if yml.parent.name.startswith("_") or yml.parent.name == "community":
            continue
        rid = yml.parent.name
        for line in yml.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("id:"):
                rid = line.split(":", 1)[1].strip().strip('"')
                break
        found[rid] = yml.parent
    return found


def _load_catalog_meta(catalog_path: Path) -> dict[str, dict[str, Any]]:
    if not catalog_path.is_file():
        return {}
    try:
        data = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    recipes = data.get("recipes")
    out: dict[str, dict[str, Any]] = {}
    if isinstance(recipes, list):
        for item in recipes:
            if isinstance(item, dict) and item.get("id"):
                out[str(item["id"])] = item
    elif isinstance(recipes, dict):
        for rid, item in recipes.items():
            if isinstance(item, dict):
                merged = dict(item)
                merged.setdefault("id", rid)
                out[str(rid)] = merged
    return out


def _manifest_files_for(manifest_path: Path, rid: str) -> dict[str, str] | None:
    if not manifest_path.is_file():
        return None
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    entry = data.get("recipes", {}).get(rid)
    if not isinstance(entry, dict):
        return None
    files = entry.get("files")
    return files if isinstance(files, dict) else None


def _local_effective_ids(
    bundled_recipes: Path,
    overlay_recipes: Path,
) -> dict[str, Path]:
    """Overlay overrides bundled for the same id."""
    merged = _recipe_ids_from_tree(bundled_recipes)
    overlay = _recipe_ids_from_tree(overlay_recipes)
    merged.update(overlay)
    return merged


def fetch_latest_release_json(
    *,
    repo: str = GITHUB_REPO,
    getter: Callable[[str], Any] | None = None,
) -> dict[str, Any]:
    get = getter or _http_get_json
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    data = get(url)
    if not isinstance(data, dict):
        raise RecipeSyncError("GitHub releases/latest returned non-object")
    return data


def pick_recipes_asset(release: dict[str, Any]) -> tuple[str, str, str]:
    """Return (asset_name, download_url, bundle_version)."""
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise RecipeSyncError("Release has no assets")
    candidates: list[tuple[str, str, str]] = []
    for asset in assets:
        if not isinstance(asset, dict):
            continue
        name = str(asset.get("name", ""))
        m = _RECIPES_ASSET_RE.match(name)
        if not m:
            continue
        url = str(asset.get("browser_download_url", "")).strip()
        if url:
            candidates.append((name, url, m.group(1)))
    if not candidates:
        raise RecipeSyncError("No rezeptor-recipes-*.tar.gz asset on latest release")
    # Prefer asset whose version matches release tag when possible
    tag = _norm_version(str(release.get("tag_name", "")))
    for name, url, ver in candidates:
        if ver == tag:
            return name, url, ver
    return candidates[0]


def fetch_sha256_for_asset(
    release: dict[str, Any],
    asset_name: str,
    *,
    download: DownloadFn | None = None,
) -> str:
    dl = download or _http_get
    assets = release.get("assets") or []
    sums_url = ""
    for asset in assets:
        if isinstance(asset, dict) and asset.get("name") == "SHA256SUMS":
            sums_url = str(asset.get("browser_download_url", "")).strip()
            break
    if not sums_url:
        raise RecipeSyncError("SHA256SUMS missing from release")
    sums = parse_sha256sums(dl(sums_url).decode("utf-8", errors="replace"))
    digest = sums.get(asset_name)
    if not digest:
        raise RecipeSyncError(f"{asset_name} not listed in SHA256SUMS")
    return digest


def load_sync_state() -> dict[str, Any]:
    path = sync_state_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_sync_state(state: dict[str, Any]) -> None:
    ensure_overlay_dirs()
    path = sync_state_path()
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def pending_attention_count(state: dict[str, Any] | None = None) -> int:
    st = state if state is not None else load_sync_state()
    pending = st.get("pending")
    if not isinstance(pending, dict):
        return 0
    n = 0
    for key in ("added", "updated", "removed", "blocked", "deprecated"):
        items = pending.get(key)
        if isinstance(items, list):
            n += len(items)
    return n


def build_diff_plan(
    *,
    extract_dir: Path,
    bundled_recipes: Path,
    overlay_recipes: Path,
    bundled_manifest: Path,
    app_version: str,
    bundle_version: str,
    asset_name: str,
    asset_url: str,
    sha256_expected: str,
    release_url: str,
) -> RecipeSyncPlan:
    remote_catalog = extract_dir / "catalog.json"
    remote_manifest = extract_dir / "manifest.json"
    if not remote_catalog.is_file() or not remote_manifest.is_file():
        raise RecipeSyncError("Bundle missing catalog.json or manifest.json")

    # Bundle may store recipes at archive root or under recipes/
    remote_root = extract_dir / "recipes"
    if not remote_root.is_dir():
        remote_root = extract_dir

    remote_ids = _recipe_ids_from_tree(remote_root)
    # If recipes live next to catalog at root, filter non-recipe dirs
    if remote_root == extract_dir:
        remote_ids = {
            rid: path
            for rid, path in remote_ids.items()
            if rid not in ("community",)
        }

    catalog_meta = _load_catalog_meta(remote_catalog)
    local_ids = _local_effective_ids(bundled_recipes, overlay_recipes)
    local_manifest_overlay = overlay_manifest_path()

    changes: list[RecipeChange] = []

    for rid, rdir in sorted(remote_ids.items()):
        meta = catalog_meta.get(rid, {})
        min_ver = str(meta.get("min_app_version") or "").strip()
        # Also allow recipe.yml min_app_version
        yml = rdir / "recipe.yml"
        if yml.is_file() and not min_ver:
            for line in yml.read_text(encoding="utf-8").splitlines():
                if line.strip().startswith("min_app_version:"):
                    min_ver = line.split(":", 1)[1].strip().strip('"')
                    break
        deprecated = bool(meta.get("deprecated"))
        if deprecated:
            changes.append(
                RecipeChange(id=rid, kind="deprecated", detail="catalog deprecated")
            )
            continue
        if not app_version_satisfies(min_ver, app_version):
            changes.append(
                RecipeChange(
                    id=rid,
                    kind="blocked",
                    detail=f"needs app >= {min_ver} (have {app_version})",
                )
            )
            continue

        remote_files = _manifest_files_for(remote_manifest, rid)
        if remote_files is None:
            raise RecipeSyncError(f"Bundle manifest missing recipe {rid}")

        if rid not in local_ids:
            changes.append(RecipeChange(id=rid, kind="added"))
            continue

        # Compare against overlay manifest first, else bundled
        local_files = _manifest_files_for(local_manifest_overlay, rid)
        if local_files is None:
            local_files = _manifest_files_for(bundled_manifest, rid)
        if local_files != remote_files:
            changes.append(RecipeChange(id=rid, kind="updated"))

    remote_official = {
        rid
        for rid, meta in catalog_meta.items()
        if str(meta.get("trust", "official")) == "official"
        and not bool(meta.get("deprecated"))
    }
    # If catalog empty of trust field, treat all remote tree ids as official
    if not remote_official:
        remote_official = set(remote_ids)

    for rid in sorted(local_ids):
        if rid.startswith("_"):
            continue
        if rid not in remote_ids and rid not in remote_official:
            # Present locally but gone from remote catalog/tree
            if rid not in remote_ids:
                changes.append(
                    RecipeChange(
                        id=rid,
                        kind="removed",
                        detail="not in remote catalog — hide/update overlay",
                    )
                )

    return RecipeSyncPlan(
        bundle_version=bundle_version,
        asset_name=asset_name,
        asset_url=asset_url,
        sha256_expected=sha256_expected,
        release_url=release_url,
        changes=changes,
        app_version=app_version,
    )


def check_recipe_updates(
    *,
    bundled_recipes: Path,
    bundled_manifest: Path,
    app_version: str | None = None,
    repo: str = GITHUB_REPO,
    download: DownloadFn | None = None,
    release_json: dict[str, Any] | None = None,
) -> RecipeSyncPlan:
    """Fetch latest recipes bundle metadata, download, verify, return diff plan."""
    dl = download or _http_get
    release = release_json or fetch_latest_release_json(repo=repo)
    asset_name, asset_url, bundle_ver = pick_recipes_asset(release)
    sha_expected = fetch_sha256_for_asset(release, asset_name, download=dl)
    release_url = str(
        release.get("html_url") or f"https://github.com/{repo}/releases"
    )
    app_ver = app_version if app_version is not None else read_version()

    ensure_overlay_dirs()
    cache = overlay_root_cache()
    archive = cache / asset_name
    raw = dl(asset_url)
    archive.write_bytes(raw)
    got = file_sha256(archive)
    if got != sha_expected:
        archive.unlink(missing_ok=True)
        raise RecipeSyncError(
            f"SHA256 mismatch for {asset_name}: expected {sha_expected}, got {got}"
        )

    extract_dir = cache / f"extract-{bundle_ver}"
    if extract_dir.exists():
        shutil.rmtree(extract_dir)
    extract_dir.mkdir(parents=True)
    safe_extract_tar_gz(archive, extract_dir)

    plan = build_diff_plan(
        extract_dir=extract_dir,
        bundled_recipes=bundled_recipes,
        overlay_recipes=overlay_recipes_dir(),
        bundled_manifest=bundled_manifest,
        app_version=app_ver,
        bundle_version=bundle_ver,
        asset_name=asset_name,
        asset_url=asset_url,
        sha256_expected=sha_expected,
        release_url=release_url,
    )

    # Persist pending for UI
    pending = {
        "added": [c.id for c in plan.changes if c.kind == "added"],
        "updated": [c.id for c in plan.changes if c.kind == "updated"],
        "removed": [c.id for c in plan.changes if c.kind == "removed"],
        "blocked": [
            {"id": c.id, "detail": c.detail}
            for c in plan.changes
            if c.kind == "blocked"
        ],
        "deprecated": [c.id for c in plan.changes if c.kind == "deprecated"],
    }
    state = load_sync_state()
    state.update(
        {
            "bundle_version": plan.bundle_version,
            "asset_name": plan.asset_name,
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "release_url": plan.release_url,
            "pending": pending,
            "extract_dir": str(extract_dir),
            "sha256": plan.sha256_expected,
        }
    )
    save_sync_state(state)
    return plan


def overlay_root_cache() -> Path:
    return ensure_overlay_dirs() / "cache"


def apply_recipe_sync(
    plan: RecipeSyncPlan,
    *,
    bundled_recipes: Path,
    extract_dir: Path | None = None,
) -> list[str]:
    """Apply actionable changes from a verified extract into the overlay.

    Returns list of applied recipe ids. Blocked recipes are skipped.
    Removed recipes are marked deprecated in state (overlay copy deleted if present);
    user data under wine-software is never touched.
    """
    state = load_sync_state()
    extract = Path(extract_dir or state.get("extract_dir") or "")
    if not extract.is_dir():
        raise RecipeSyncError("No extracted bundle — run check first")

    remote_root = extract / "recipes"
    if not remote_root.is_dir():
        remote_root = extract
    remote_manifest = extract / "manifest.json"
    remote_catalog = extract / "catalog.json"
    if not remote_manifest.is_file():
        raise RecipeSyncError("Bundle manifest missing")

    try:
        full_manifest = json.loads(remote_manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RecipeSyncError(f"Cannot read bundle manifest: {exc}") from exc

    overlay_recipes = overlay_recipes_dir()
    overlay_recipes.mkdir(parents=True, exist_ok=True)

    # Load or start overlay manifest
    omani_path = overlay_manifest_path()
    if omani_path.is_file():
        try:
            overlay_manifest: dict[str, Any] = json.loads(
                omani_path.read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError):
            overlay_manifest = {"version": 1, "recipes": {}}
    else:
        overlay_manifest = {"version": 1, "recipes": {}}
    recipes_map = overlay_manifest.setdefault("recipes", {})
    if not isinstance(recipes_map, dict):
        recipes_map = {}
        overlay_manifest["recipes"] = recipes_map

    applied: list[str] = []
    deprecated_ids: list[str] = list(state.get("deprecated_ids") or [])

    for change in plan.changes:
        if change.kind in ("blocked", "deprecated"):
            if change.kind == "deprecated" and change.id not in deprecated_ids:
                deprecated_ids.append(change.id)
            continue

        if change.kind == "removed":
            if change.id not in deprecated_ids:
                deprecated_ids.append(change.id)
            target = overlay_recipes / change.id
            if target.is_dir():
                shutil.rmtree(target)
            recipes_map.pop(change.id, None)
            applied.append(change.id)
            continue

        if change.kind not in ("added", "updated"):
            continue

        src = remote_root / change.id
        if not (src / "recipe.yml").is_file():
            # try path from catalog
            cat = _load_catalog_meta(remote_catalog)
            path_name = str(cat.get(change.id, {}).get("path") or change.id)
            src = remote_root / path_name
        if not (src / "recipe.yml").is_file():
            raise RecipeSyncError(f"Bundle missing recipe folder for {change.id}")

        dest = overlay_recipes / change.id
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(src, dest)

        entry = full_manifest.get("recipes", {}).get(change.id)
        if not isinstance(entry, dict):
            raise RecipeSyncError(f"No manifest entry for {change.id}")
        recipes_map[change.id] = entry
        applied.append(change.id)

    clear_digest_cache()
    omani_path.parent.mkdir(parents=True, exist_ok=True)
    omani_path.write_text(
        json.dumps(overlay_manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    for rid in applied:
        if rid in deprecated_ids:
            continue
        rdir = overlay_recipes / rid
        if not rdir.is_dir():
            continue
        ok, reason = verify_recipe_trust(rdir, omani_path, strict=True)
        if not ok:
            raise RecipeSyncError(f"Trust failed after apply for {rid}: {reason}")

    if remote_catalog.is_file():
        shutil.copy2(remote_catalog, overlay_catalog_path())

    state["deprecated_ids"] = sorted(set(deprecated_ids))
    state["applied_bundle_version"] = plan.bundle_version
    state["applied_at"] = datetime.now(timezone.utc).isoformat()
    state["pending"] = {
        "added": [],
        "updated": [],
        "removed": [],
        "blocked": [
            {"id": c.id, "detail": c.detail}
            for c in plan.changes
            if c.kind == "blocked"
        ],
        "deprecated": sorted(set(deprecated_ids)),
    }
    save_sync_state(state)
    del bundled_recipes  # overlay never mutates the packaged tree
    return applied


def format_plan_summary(plan: RecipeSyncPlan) -> str:
    lines: list[str] = []
    for c in plan.changes:
        if c.detail:
            lines.append(f"{c.kind}: {c.id} ({c.detail})")
        else:
            lines.append(f"{c.kind}: {c.id}")
    return "\n".join(lines)
