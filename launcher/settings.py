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
    locale: str = ""
    theme: str = "dark"  # nur dark — Light war unbrauchbar, kein Parallel-Theme
    last_recipe_id: str = ""
    developer_mode: bool = False
    hidden_recipe_ids: list[str] = field(default_factory=list)
    recipe_order: list[str] = field(default_factory=list)  # drag order of recipe ids
    custom_category_order: list[str] = field(default_factory=list)  # DnD order for non-standard categories
    recipe_sources: list[dict] = field(default_factory=list)  # [{id, url, label, trusted: bool}]
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
        locale=locale,
        theme=theme,
        last_recipe_id=str(data.get("last_recipe_id", "") or "").strip(),
        developer_mode=bool(data.get("developer_mode", False)),
        hidden_recipe_ids=_parse_str_list(data.get("hidden_recipe_ids")),
        recipe_order=_parse_str_list(data.get("recipe_order")),
        custom_category_order=_parse_str_list(data.get("custom_category_order")),
        recipe_sources=_parse_recipe_sources(data.get("recipe_sources")),
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
