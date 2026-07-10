"""Load JSON locale packs with fallback chain: locale → en → key."""

from __future__ import annotations

import json
import os
from pathlib import Path

LOCALES_DIR = Path(__file__).resolve().parent.parent / "locales"
_FALLBACK = "en"
_cache: dict[str, dict[str, str]] = {}
_current = "en"


def detect_system_locale() -> str:
    for key in ("LC_ALL", "LC_MESSAGES", "LANG"):
        raw = os.environ.get(key, "")
        if raw and raw not in ("C", "POSIX"):
            code = raw.split(".", 1)[0].split("_", 1)[0].lower()
            if code:
                return "de" if code.startswith("de") else "en"
    return "en"


def available_locales() -> list[tuple[str, str]]:
    manifest = LOCALES_DIR / "manifest.json"
    if manifest.is_file():
        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
            out: list[tuple[str, str]] = []
            for entry in data.get("locales", []):
                lid = str(entry.get("id", "")).strip()
                name = str(entry.get("name", lid)).strip()
                if lid:
                    out.append((lid, name))
            if out:
                return out
        except (OSError, json.JSONDecodeError, TypeError):
            pass
    found: list[tuple[str, str]] = []
    for path in sorted(LOCALES_DIR.glob("*.json")):
        if path.name == "manifest.json":
            continue
        found.append((path.stem, path.stem))
    return found or [("en", "English"), ("de", "Deutsch")]


def _flatten(obj: object, prefix: str = "") -> dict[str, str]:
    out: dict[str, str] = {}
    if isinstance(obj, dict):
        for key, val in obj.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            if isinstance(val, dict):
                out.update(_flatten(val, path))
            else:
                out[path] = str(val)
    return out


def _load_locale(code: str) -> dict[str, str]:
    if code in _cache:
        return _cache[code]
    path = LOCALES_DIR / f"{code}.json"
    data: dict[str, str] = {}
    if path.is_file():
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            data = _flatten(raw)
        except (OSError, json.JSONDecodeError):
            data = {}
    _cache[code] = data
    return data


def set_locale(code: str) -> str:
    global _current
    available = {lid for lid, _ in available_locales()}
    if code not in available:
        code = detect_system_locale() if code == "auto" else _FALLBACK
    if code not in available:
        code = _FALLBACK
    _current = code
    _load_locale(code)
    if code != _FALLBACK:
        _load_locale(_FALLBACK)
    return _current


def get_locale() -> str:
    return _current


def t(key: str, **kwargs: object) -> str:
    packs = (_load_locale(_current),)
    if _current != _FALLBACK:
        packs = (_load_locale(_current), _load_locale(_FALLBACK))
    text = key
    for pack in packs:
        if key in pack:
            text = pack[key]
            break
    if kwargs:
        try:
            return text.format(**kwargs)
        except (KeyError, ValueError):
            return text
    return text


def clear_cache() -> None:
    _cache.clear()
