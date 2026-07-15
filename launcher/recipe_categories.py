"""Standard recipe categories and sort helpers for the launcher sidebar."""

from __future__ import annotations

STANDARD_CATEGORIES = [
    "Finanzen & Steuer",
    "Grafik & Design",
    "Spiele",
    "Sonstige",
]


def is_standard(category: str) -> bool:
    """True when *category* is one of the built-in sidebar groups."""
    return category in STANDARD_CATEGORIES


def sort_categories(categories: list[str], custom_order: list[str]) -> list[str]:
    """Order categories: standard slots first, then custom_order, then remainder."""
    seen: set[str] = set()
    ordered: list[str] = []

    for cat in STANDARD_CATEGORIES:
        if cat in categories and cat not in seen:
            ordered.append(cat)
            seen.add(cat)

    for cat in custom_order:
        if cat in categories and cat not in seen:
            ordered.append(cat)
            seen.add(cat)

    for cat in sorted(categories):
        if cat not in seen:
            ordered.append(cat)
            seen.add(cat)

    return ordered
