"""Rezeptor UI themes: standard (brand), dracula, alucard.

Official Dracula / Alucard hex from https://draculatheme.com/spec
(and https://github.com/dracula/dracula-theme). Do not invent variants.
"""

from __future__ import annotations

THEME_STANDARD = "standard"
THEME_DRACULA = "dracula"
THEME_ALUCARD = "alucard"
THEME_IDS = (THEME_STANDARD, THEME_DRACULA, THEME_ALUCARD)

# Brand (docs/BRAND.md) — anthracite / copper / parchment
_STANDARD = {
    "id": THEME_STANDARD,
    "bg": "#1C1C1A",
    "surface1": "#232321",
    "surface2": "#292926",
    "surface3": "#333330",
    "border": "#3A3A36",
    "fg": "#EDE6D6",
    "muted": "#A9A296",
    "accent": "#B87333",
    "accent_soft": "rgba(184,115,51,0.14)",
    "tested": "#7fb144",
    "experimental": "#e0af52",
    "danger": "#e07070",
    "fluent_dark": True,
}

# Dracula Classic — https://draculatheme.com/spec
_DRACULA = {
    "id": THEME_DRACULA,
    "bg": "#282A36",
    "surface1": "#21222C",
    "surface2": "#343746",
    "surface3": "#44475A",
    "border": "#6272A4",
    "fg": "#F8F8F2",
    # Comment (#6272A4) fails AA as body/secondary text; slightly lighter for UI.
    "muted": "#9CA4C4",
    "accent": "#BD93F9",
    "accent_soft": "rgba(189,147,249,0.18)",
    "tested": "#50FA7B",
    "experimental": "#F1FA8C",
    "danger": "#FF5555",
    "fluent_dark": True,
}

# Alucard Classic — https://draculatheme.com/spec (+ UI Background Lighter/Light)
_ALUCARD = {
    "id": THEME_ALUCARD,
    "bg": "#FFFBEB",
    "surface1": "#ECE9DF",
    "surface2": "#EFEDDC",
    "surface3": "#DEDCCF",
    "border": "#BCBAB3",
    "fg": "#1F1F1F",
    "muted": "#6C664B",
    "accent": "#644AC9",
    "accent_soft": "rgba(100,74,201,0.16)",
    "tested": "#14710A",
    "experimental": "#846E15",
    "danger": "#CB3A2A",
    "fluent_dark": False,
}

THEMES: dict[str, dict[str, object]] = {
    THEME_STANDARD: _STANDARD,
    THEME_DRACULA: _DRACULA,
    THEME_ALUCARD: _ALUCARD,
}

_ACTIVE_THEME: str = THEME_STANDARD


def set_active_theme(theme_id: str | None) -> str:
    """Remember the UI theme so theme_tokens() works without an explicit id."""
    global _ACTIVE_THEME
    _ACTIVE_THEME = normalize_theme(theme_id)
    return _ACTIVE_THEME


def active_theme() -> str:
    return _ACTIVE_THEME


def normalize_theme(raw: str | None) -> str:
    """Map settings / legacy values → canonical theme id."""
    t = (raw or "").strip().lower()
    if t in ("dark", "system", ""):
        return THEME_STANDARD
    if t in ("light",):
        return THEME_ALUCARD
    if t in THEME_IDS:
        return t
    return THEME_STANDARD


def theme_tokens(theme_id: str | None = None) -> dict[str, str]:
    """String-only CSS/QSS token map for the active theme."""
    tid = normalize_theme(theme_id if theme_id is not None else _ACTIVE_THEME)
    src = THEMES[tid]
    return {k: str(v) for k, v in src.items() if k != "fluent_dark"}


def theme_is_dark(theme_id: str | None = None) -> bool:
    tid = normalize_theme(theme_id if theme_id is not None else _ACTIVE_THEME)
    return bool(THEMES[tid].get("fluent_dark", True))


def next_theme(current: str | None) -> str:
    tid = normalize_theme(current)
    idx = THEME_IDS.index(tid)
    return THEME_IDS[(idx + 1) % len(THEME_IDS)]


def theme_label_key(theme_id: str | None = None) -> str:
    return f"theme.{normalize_theme(theme_id)}"
