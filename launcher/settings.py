"""Rezeptor user settings (~/.local/share/wine-software/rezeptor/settings.json)."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

SETTINGS_DIR = Path.home() / ".local/share/wine-software/rezeptor"
SETTINGS_FILE = SETTINGS_DIR / "settings.json"


def _default_locale() -> str:
    try:
        from i18n import detect_system_locale

        return detect_system_locale()
    except Exception:
        return "en"


@dataclass
class RezeptorSettings:
    log_retention_days: int = 14
    log_max_files: int = 50
    prune_logs_on_startup: bool = True
    # Beim Start validate.sh für alle Rezepte (mit Hinweisdialog)
    validate_on_startup: bool = True
    locale: str = ""
    theme: str = "dark"  # nur dark — Light war unbrauchbar, kein Parallel-Theme
    last_recipe_id: str = ""
    developer_mode: bool = False
    hidden_recipe_ids: list[str] = field(default_factory=list)
    recipe_order: list[str] = field(default_factory=list)  # drag order of recipe ids
    custom_category_order: list[str] = field(default_factory=list)  # DnD order for non-standard categories
    # User sidebar category override (rid → category). Default remains recipe.yml.
    recipe_category_overrides: dict[str, str] = field(default_factory=dict)
    recipe_sources: list[dict] = field(default_factory=list)  # [{id, url, label, trusted: bool}]
    # Archive passwords (one entry per line in UI; tried in order when extracting)
    archive_passwords: list[str] = field(default_factory=list)
    # Pending install env per recipe id (source/target from dialog — not yet installed)
    recipe_install_env: dict[str, dict[str, str]] = field(default_factory=dict)
    # First-start host tool prompt (System prüfen) already shown
    host_deps_prompt_done: bool = False
    # UI-Persistenz (Base64 von QWidget.saveGeometry / QSplitter.saveState)
    window_geometry: str = ""
    window_maximized: bool = False
    splitter_state: str = ""
    content_tab: str = "overview"
    recipe_view_geometry: str = ""
    docs_geometry: str = ""
    settings_geometry: str = ""


def _parse_str_list(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for item in raw:
        s = str(item).strip()
        if s:
            out.append(s)
    return out


def _parse_str_dict(raw: object) -> dict[str, str]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, str] = {}
    for key, val in raw.items():
        k = str(key).strip()
        v = str(val).strip()
        if k and v:
            out[k] = v
    return out


_SOURCE_ENV_KEYS = (
    "RECIPE_SOURCE_ROOT",
    "RECIPE_ARCHIVE_PATH",
    "RECIPE_INSTALLER_PATH",
)
_EPHEMERAL_ENV_KEYS = (
    "RECIPE_ARCHIVE_PASSWORD_FILE",
    "RECIPE_ARCHIVE_PASSWORD_USED_FILE",
)
# User cleared Quelle/Ziel in the dialog — do not re-apply heuristics on reopen.
_CLEARED_KEY = "__cleared__"


def _parse_recipe_install_env(raw: object) -> dict[str, dict[str, str]]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, dict[str, str]] = {}
    for rid, env in raw.items():
        key = str(rid).strip()
        if not key or not isinstance(env, dict):
            continue
        cleaned = _sanitize_install_env({str(k): str(v) for k, v in env.items()})
        if cleaned and (
            has_recipe_install_source(cleaned) or is_recipe_install_cleared(cleaned)
        ):
            out[key] = cleaned
    return out


def _sanitize_install_env(env: dict[str, str]) -> dict[str, str]:
    """Drop empty values and ephemeral password temp-file paths."""
    out: dict[str, str] = {}
    for k, v in env.items():
        key = str(k).strip()
        val = str(v).strip()
        if not key or not val or key in _EPHEMERAL_ENV_KEYS:
            continue
        out[key] = val
    return out


def has_recipe_install_source(env: dict[str, str] | None) -> bool:
    if not env or is_recipe_install_cleared(env):
        return False
    return any((env.get(k) or "").strip() for k in _SOURCE_ENV_KEYS)


def is_recipe_install_cleared(env: dict[str, str] | None) -> bool:
    return bool(env and (env.get(_CLEARED_KEY) or "").strip() == "1")


def load_recipe_install_env(
    settings: RezeptorSettings, rid: str
) -> dict[str, str] | None:
    env = settings.recipe_install_env.get(rid)
    if not env:
        return None
    if is_recipe_install_cleared(env):
        return {_CLEARED_KEY: "1"}
    if not has_recipe_install_source(env):
        return None
    return dict(env)


def save_recipe_install_env(
    settings: RezeptorSettings, rid: str, env: dict[str, str]
) -> None:
    cleaned = _sanitize_install_env(env)
    if not has_recipe_install_source(cleaned):
        clear_recipe_install_env(settings, rid)
        return
    settings.recipe_install_env[rid] = cleaned
    save_settings(settings)


def clear_recipe_install_env(settings: RezeptorSettings, rid: str) -> None:
    """Remember that the user cleared paths — heuristics must not refill them."""
    settings.recipe_install_env[rid] = {_CLEARED_KEY: "1"}
    save_settings(settings)


def _parse_recipe_sources(raw: object) -> list[dict]:
    if not isinstance(raw, list):
        return []
    out: list[dict] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        rid = str(item.get("id", "")).strip()
        url = str(item.get("url", "")).strip()
        label = str(item.get("label", "")).strip()
        if not rid or not url:
            continue
        out.append(
            {
                "id": rid,
                "url": url,
                "label": label or rid,
                "trusted": bool(item.get("trusted", False)),
            }
        )
    return out


def prepend_archive_password(settings: RezeptorSettings, password: str) -> bool:
    """Prepend a working password to the global list (JDownloader-style). Returns True if changed."""
    pw = (password or "").strip()
    if not pw:
        return False
    existing = [p for p in settings.archive_passwords if p != pw]
    new_list = [pw, *existing]
    if new_list == settings.archive_passwords:
        return False
    settings.archive_passwords = new_list
    return True


def recipe_edit_allowed(settings: RezeptorSettings | None = None) -> bool:
    """True when REZEPTOR_DEV=1 or settings.developer_mode (recipe view save)."""
    import os

    if os.environ.get("REZEPTOR_DEV", "").lower() in ("1", "true", "yes"):
        return True
    return bool(settings and settings.developer_mode)


def load_settings() -> RezeptorSettings:
    if not SETTINGS_FILE.is_file():
        s = RezeptorSettings(locale=_default_locale())
        return s
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return RezeptorSettings(locale=_default_locale())
    locale = str(data.get("locale", "")).strip() or _default_locale()
    # Früher system/light → immer Standard (dark)
    theme = str(data.get("theme", "dark")).strip().lower()
    if theme != "dark":
        theme = "dark"
    tab = str(data.get("content_tab", "overview") or "overview").strip()
    if tab not in ("overview", "progress", "logs"):
        tab = "overview"
    return RezeptorSettings(
        log_retention_days=max(1, min(365, int(data.get("log_retention_days", 14)))),
        log_max_files=max(5, min(500, int(data.get("log_max_files", 50)))),
        prune_logs_on_startup=bool(data.get("prune_logs_on_startup", True)),
        validate_on_startup=bool(data.get("validate_on_startup", True)),
        locale=locale,
        theme=theme,
        last_recipe_id=str(data.get("last_recipe_id", "") or "").strip(),
        developer_mode=bool(data.get("developer_mode", False)),
        hidden_recipe_ids=_parse_str_list(data.get("hidden_recipe_ids")),
        recipe_order=_parse_str_list(data.get("recipe_order")),
        custom_category_order=_parse_str_list(data.get("custom_category_order")),
        recipe_category_overrides=_parse_str_dict(data.get("recipe_category_overrides")),
        recipe_sources=_parse_recipe_sources(data.get("recipe_sources")),
        archive_passwords=_parse_str_list(data.get("archive_passwords")),
        recipe_install_env=_parse_recipe_install_env(data.get("recipe_install_env")),
        host_deps_prompt_done=bool(data.get("host_deps_prompt_done", False)),
        window_geometry=str(data.get("window_geometry", "") or ""),
        window_maximized=bool(data.get("window_maximized", False)),
        splitter_state=str(data.get("splitter_state", "") or ""),
        content_tab=tab,
        recipe_view_geometry=str(data.get("recipe_view_geometry", "") or ""),
        docs_geometry=str(data.get("docs_geometry", "") or ""),
        settings_geometry=str(data.get("settings_geometry", "") or ""),
    )


def save_settings(settings: RezeptorSettings) -> None:
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    if not settings.locale:
        settings.locale = _default_locale()
    SETTINGS_FILE.write_text(
        json.dumps(asdict(settings), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
