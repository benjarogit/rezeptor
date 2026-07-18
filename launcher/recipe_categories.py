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


def default_category(meta: dict | None) -> str:
    """Category from recipe.yml (shipping default)."""
    if not isinstance(meta, dict):
        return "Sonstige"
    return (meta.get("category") or "Sonstige").strip() or "Sonstige"


def effective_category(rid: str, meta: dict | None, overrides: dict[str, str] | None) -> str:
    """Sidebar category: user override wins, else recipe.yml."""
    ov = (overrides or {}).get(rid, "").strip()
    if ov:
        return ov
    return default_category(meta)


def sort_categories(categories: list[str], custom_order: list[str]) -> list[str]:
    """Standard categories first (alphabetical), then custom (DnD order), then rest."""
    seen: set[str] = set()
    ordered: list[str] = []

    present_standard = sorted(c for c in categories if is_standard(c))
    for cat in present_standard:
        ordered.append(cat)
        seen.add(cat)

    for cat in custom_order:
        if cat in categories and cat not in seen and not is_standard(cat):
            ordered.append(cat)
            seen.add(cat)

    for cat in sorted(c for c in categories if c not in seen):
        ordered.append(cat)
        seen.add(cat)

    return ordered


def sort_recipes_in_category(
    recipes: list[tuple[int, object]],
    recipe_order: list[str],
    *,
    rid_attr: str = "rid",
) -> list[tuple[int, object]]:
    """Stable sort by settings recipe_order, then by name."""
    order_index = {rid: i for i, rid in enumerate(recipe_order)}

    def key(item: tuple[int, object]) -> tuple[int, str]:
        _i, info = item
        rid = str(getattr(info, rid_attr, "") or "")
        name = ""
        meta = getattr(info, "meta", None)
        if isinstance(meta, dict):
            name = str(meta.get("name") or rid)
        else:
            name = rid
        return (order_index.get(rid, 10_000), name.lower())

    return sorted(recipes, key=key)
