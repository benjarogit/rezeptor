"""Recipe catalog: local index, GitHub fetch, and community recipe install.

Official recipes live under ``recipes/<id>``; community recipes under
``recipes/community/<id>``. The launcher discovers both trees.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_GITHUB_REPO = "benjarogit/rezeptor"
DEFAULT_GITHUB_REF = "main"
CATALOG_FILENAME = "catalog.json"
COMMUNITY_DIR = "community"
_HTTP_TIMEOUT = 30
_USER_AGENT = "Rezeptor-recipe-catalog/1.0"
_HTTP_OPENER = urllib.request.build_opener()


class CatalogError(Exception):
    """Raised when catalog load or parse fails."""


class RecipeInstallError(Exception):
    """Raised when a remote recipe cannot be installed."""


@dataclass
class CatalogEntry:
    id: str
    name: str
    category: str
    trust: str
    path: str
    summary: dict[str, str] = field(default_factory=dict)
    files: list[str] = field(default_factory=list)

    @property
    def is_official(self) -> bool:
        return self.trust == "official"

    @property
    def is_community(self) -> bool:
        return self.trust == "community"


def _request_json(url: str) -> Any:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": _USER_AGENT,
        },
    )
    try:
        with _HTTP_OPENER.open(req, timeout=_HTTP_TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode("utf-8", errors="replace")[:200]
        except OSError:
            pass
        raise CatalogError(f"HTTP {exc.code} for {url}: {body or exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise CatalogError(f"Network error for {url}: {exc.reason}") from exc
    except (TimeoutError, json.JSONDecodeError, OSError) as exc:
        raise CatalogError(f"Failed to read {url}: {exc}") from exc


def _download_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    try:
        with _HTTP_OPENER.open(req, timeout=_HTTP_TIMEOUT) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        raise RecipeInstallError(f"HTTP {exc.code} downloading {url}: {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise RecipeInstallError(f"Network error downloading {url}: {exc.reason}") from exc
    except (TimeoutError, OSError) as exc:
        raise RecipeInstallError(f"Failed to download {url}: {exc}") from exc


def _parse_recipe_yml(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise CatalogError(f"Cannot read {path}: {exc}") from exc
    for line in lines:
        if not line or line[0] in " \t#" or ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        if not key or key.startswith("-"):
            continue
        data[key] = val.strip().strip('"')
    return data


def _entry_from_dict(raw: dict[str, Any]) -> CatalogEntry:
    rid = str(raw.get("id", "")).strip()
    if not rid:
        raise CatalogError("Catalog entry missing id")
    summary = raw.get("summary")
    summary_map: dict[str, str] = {}
    if isinstance(summary, dict):
        for lang, text in summary.items():
            s = str(text).strip()
            if s:
                summary_map[str(lang).strip().lower()] = s
    files_raw = raw.get("files")
    files: list[str] = []
    if isinstance(files_raw, list):
        files = [str(f).strip() for f in files_raw if str(f).strip()]
    return CatalogEntry(
        id=rid,
        name=str(raw.get("name", rid)).strip() or rid,
        category=str(raw.get("category", "Sonstige")).strip() or "Sonstige",
        trust=str(raw.get("trust", "official")).strip() or "official",
        path=str(raw.get("path", rid)).strip() or rid,
        summary=summary_map,
        files=files,
    )


def _entries_from_catalog_data(data: Any) -> list[CatalogEntry]:
    if not isinstance(data, dict):
        raise CatalogError("Catalog root must be a JSON object")
    recipes_raw = data.get("recipes")
    if recipes_raw is None:
        raise CatalogError("Catalog missing 'recipes'")
    entries: list[CatalogEntry] = []
    if isinstance(recipes_raw, list):
        for item in recipes_raw:
            if isinstance(item, dict):
                entries.append(_entry_from_dict(item))
    elif isinstance(recipes_raw, dict):
        for rid, item in recipes_raw.items():
            if isinstance(item, dict):
                merged = dict(item)
                merged.setdefault("id", rid)
                entries.append(_entry_from_dict(merged))
    else:
        raise CatalogError("'recipes' must be a list or object")
    if not entries:
        raise CatalogError("Catalog contains no recipes")
    return entries


def _scan_recipes_dir(recipes_dir: Path) -> list[CatalogEntry]:
    entries: list[CatalogEntry] = []
    if not recipes_dir.is_dir():
        return entries

    def scan_one(yml: Path, trust: str, rel_parent: str) -> None:
        if yml.parent.name.startswith("_"):
            return
        meta = _parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        entries.append(
            CatalogEntry(
                id=rid,
                name=meta.get("name", rid),
                category=meta.get("category", "Sonstige"),
                trust=trust,
                path=rel_parent or yml.parent.name,
            )
        )

    for yml in sorted(recipes_dir.glob("*/recipe.yml")):
        scan_one(yml, "official", yml.parent.name)

    community_root = recipes_dir / COMMUNITY_DIR
    if community_root.is_dir():
        for yml in sorted(community_root.glob("*/recipe.yml")):
            scan_one(yml, "community", f"{COMMUNITY_DIR}/{yml.parent.name}")

    return entries


def load_local_catalog(recipes_dir: Path) -> list[CatalogEntry]:
    """Load ``recipes/catalog.json`` when present, else scan the recipe tree."""
    catalog_path = recipes_dir / CATALOG_FILENAME
    if catalog_path.is_file():
        try:
            data = json.loads(catalog_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise CatalogError(f"Cannot parse {catalog_path}: {exc}") from exc
        return _entries_from_catalog_data(data)
    return _scan_recipes_dir(recipes_dir)


def fetch_catalog_from_github(
    repo: str = DEFAULT_GITHUB_REPO,
    ref: str = DEFAULT_GITHUB_REF,
) -> list[CatalogEntry]:
    """Fetch ``recipes/catalog.json`` from GitHub (raw.githubusercontent.com)."""
    url = f"https://raw.githubusercontent.com/{repo}/{ref}/recipes/{CATALOG_FILENAME}"
    data = _request_json(url)
    return _entries_from_catalog_data(data)


def _github_raw_url(repo: str, ref: str, repo_path: str) -> str:
    return f"https://raw.githubusercontent.com/{repo}/{ref}/{repo_path}"


def _contained_recipe_target(dest_dir: Path, rel: str) -> tuple[Path, str]:
    """Return ``(target, safe_rel)`` under *dest_dir*, or raise on traversal."""
    raw = (rel or "").replace("\\", "/")
    # Reject absolute paths before any strip — ``lstrip("/")`` would turn
    # ``/etc/passwd`` into a false relative ``etc/passwd``.
    if not raw or raw.endswith("/") or raw.startswith("/") or Path(raw).is_absolute():
        raise RecipeInstallError(f"Invalid or absolute recipe path: {rel!r}")
    while raw.startswith("./"):
        raw = raw[2:]
    if not raw or raw.startswith("/") or Path(raw).is_absolute():
        raise RecipeInstallError(f"Invalid recipe path: {rel!r}")
    parts = tuple(p for p in Path(raw).parts if p not in ("", "."))
    if not parts or any(p == ".." for p in parts):
        raise RecipeInstallError(f"Path traversal rejected: {rel!r}")
    safe_rel = "/".join(parts)
    dest_resolved = dest_dir.resolve()
    target = (dest_dir / safe_rel).resolve()
    try:
        target.relative_to(dest_resolved)
    except ValueError as exc:
        raise RecipeInstallError(
            f"Path escapes recipe directory: {rel!r}"
        ) from exc
    return target, safe_rel


def _list_github_tree(repo: str, ref: str, repo_path: str) -> list[str]:
    """Return repo-relative file paths under *repo_path* via the Contents API."""
    api_url = f"https://api.github.com/repos/{repo}/contents/{repo_path}?ref={ref}"
    payload = _request_json(api_url)
    if not isinstance(payload, list):
        raise RecipeInstallError(f"Expected directory listing for {repo_path}, got object")
    files: list[str] = []

    def walk(items: list[dict[str, Any]], prefix: str) -> None:
        for item in items:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", "")).strip()
            item_type = str(item.get("type", "")).strip()
            rel = f"{prefix}/{name}" if prefix else name
            if item_type == "file":
                files.append(rel)
            elif item_type == "dir":
                sub_url = str(item.get("url", "")).strip()
                if sub_url:
                    sub_payload = _request_json(sub_url)
                    if isinstance(sub_payload, list):
                        walk(sub_payload, rel)

    walk(payload, repo_path)
    return sorted(files)


def _catalog_entry_for(
    entries: list[CatalogEntry],
    recipe_id: str,
) -> CatalogEntry:
    for entry in entries:
        if entry.id == recipe_id:
            return entry
    raise RecipeInstallError(f"Recipe '{recipe_id}' not found in catalog")


def install_recipe_from_github(
    repo: str,
    recipe_id: str,
    dest_recipes_dir: Path,
    community: bool = False,
    ref: str = DEFAULT_GITHUB_REF,
    catalog: list[CatalogEntry] | None = None,
) -> Path:
    """Download a recipe folder from GitHub into *dest_recipes_dir*.

  Official recipes install to ``recipes/<id>``; community to
  ``recipes/community/<id>``.
  """
    entries = catalog if catalog is not None else fetch_catalog_from_github(repo, ref)
    entry = _catalog_entry_for(entries, recipe_id)

    use_community = community or entry.is_community
    folder_name = entry.path.split("/")[-1] if entry.path else recipe_id
    if use_community:
        dest_dir = dest_recipes_dir / COMMUNITY_DIR / folder_name
        repo_prefix = f"recipes/{COMMUNITY_DIR}/{folder_name}"
    else:
        dest_dir = dest_recipes_dir / folder_name
        repo_prefix = f"recipes/{entry.path or folder_name}"

    if entry.files:
        rel_files = entry.files
    else:
        rel_files = [
            p[len(repo_prefix) + 1 :]
            for p in _list_github_tree(repo, ref, repo_prefix)
            if p.startswith(repo_prefix + "/")
        ]
        if not rel_files:
            raise RecipeInstallError(f"No files found under {repo_prefix} in {repo}")

    dest_dir.mkdir(parents=True, exist_ok=True)
    for rel in rel_files:
        try:
            target, safe_rel = _contained_recipe_target(dest_dir, rel)
        except RecipeInstallError as exc:
            raise RecipeInstallError(
                f"Failed to install '{recipe_id}' file '{rel}': {exc}"
            ) from exc
        raw_url = _github_raw_url(repo, ref, f"{repo_prefix}/{safe_rel}")
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            target.write_bytes(_download_bytes(raw_url))
        except RecipeInstallError as exc:
            raise RecipeInstallError(
                f"Failed to install '{recipe_id}' file '{rel}': {exc}"
            ) from exc

    recipe_yml = dest_dir / "recipe.yml"
    if not recipe_yml.is_file():
        raise RecipeInstallError(
            f"Install of '{recipe_id}' finished without recipe.yml in {dest_dir}"
        )
    return dest_dir
