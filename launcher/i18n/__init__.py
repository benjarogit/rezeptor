"""Rezeptor launcher internationalization."""

from __future__ import annotations

from .loader import (
    available_locales,
    clear_cache,
    detect_system_locale,
    get_locale,
    set_locale,
    t,
)

__all__ = [
    "available_locales",
    "clear_cache",
    "detect_system_locale",
    "get_locale",
    "set_locale",
    "t",
]
