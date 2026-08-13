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
    sort_categories,
)


def test_standard_keys_stable() -> None:
    assert STANDARD_CATEGORIES[:5] == [
        "Finanzen & Steuer",
        "Grafik & Design",
        "Video & Schnitt",
        "Dokumente & PDF",
        "Spiele",
    ]
    assert is_standard("Spiele")
    assert is_standard("Video & Schnitt")
    assert is_standard("Dokumente & PDF")
    assert not is_standard("Games")


def test_category_label_follows_locale() -> None:
    set_locale("de")
    assert category_label("Spiele") == "Spiele"
    assert category_label("Video & Schnitt") == "Video & Schnitt"
    assert category_label("Dokumente & PDF") == "Dokumente & PDF"
    assert category_label("Sonstige") == "Sonstige"
    set_locale("en")
    assert category_label("Spiele") == "Games"
    assert category_label("Video & Schnitt") == "Video & editing"
    assert category_label("Dokumente & PDF") == "Documents & PDF"
    assert category_label("Sonstige") == "Other"
    assert category_label("Custom Pack") == "Custom Pack"


def test_sort_categories_follows_sidebar_order() -> None:
    got = sort_categories(
        ["Spiele", "Dokumente & PDF", "Grafik & Design", "Video & Schnitt", "Finanzen & Steuer"],
        [],
    )
    assert got == [
        "Finanzen & Steuer",
        "Grafik & Design",
        "Video & Schnitt",
        "Dokumente & PDF",
        "Spiele",
    ]


if __name__ == "__main__":
    test_standard_keys_stable()
    test_category_label_follows_locale()
    test_sort_categories_follows_sidebar_order()
    print("ok")
