"""Sidebar category storage keys vs locale labels."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "launcher"))

from i18n import set_locale  # noqa: E402
from recipe_categories import (  # noqa: E402
    STANDARD_CATEGORIES,
    category_label,
    is_standard,
)


def test_standard_keys_stable() -> None:
    assert "Spiele" in STANDARD_CATEGORIES
    assert is_standard("Spiele")
    assert not is_standard("Games")


def test_category_label_follows_locale() -> None:
    set_locale("de")
    assert category_label("Spiele") == "Spiele"
    assert category_label("Sonstige") == "Sonstige"
    set_locale("en")
    assert category_label("Spiele") == "Games"
    assert category_label("Sonstige") == "Other"
    assert category_label("Custom Pack") == "Custom Pack"


if __name__ == "__main__":
    test_standard_keys_stable()
    test_category_label_follows_locale()
    print("ok")
