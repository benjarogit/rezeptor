"""Rezeptor user settings (~/.local/share/wine-software/rezeptor/settings.json)."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
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


def load_settings() -> RezeptorSettings:
    if not SETTINGS_FILE.is_file():
        s = RezeptorSettings(locale=_default_locale())
        return s
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return RezeptorSettings(locale=_default_locale())
    locale = str(data.get("locale", "")).strip() or _default_locale()
    return RezeptorSettings(
        log_retention_days=max(1, min(365, int(data.get("log_retention_days", 14)))),
        log_max_files=max(5, min(500, int(data.get("log_max_files", 50)))),
        prune_logs_on_startup=bool(data.get("prune_logs_on_startup", True)),
        locale=locale,
    )


def save_settings(settings: RezeptorSettings) -> None:
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    if not settings.locale:
        settings.locale = _default_locale()
    SETTINGS_FILE.write_text(
        json.dumps(asdict(settings), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
