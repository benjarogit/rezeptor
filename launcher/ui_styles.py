"""Rezeptor-Farben & Host-QSS — Fluent Dark + Brand (docs/BRAND.md).

Kein PyQtDarkTheme: würde gegen qfluentwidgets kämpfen.
Kontrast nach Material Dark (Elevation, hoher Textkontrast auf dunklen Flächen).
"""

from __future__ import annotations

from ui_icons import ensure_chevron_png

# Brand (docs/BRAND.md)
ACCENT_COPPER = "#B87333"
COLOR_TESTED = "#639922"
COLOR_EXPERIMENTAL = "#d9a441"
COLOR_PARCHMENT = "#EDE6D6"  # high-emphasis text (Material ~87%)
COLOR_ANTHRACITE = "#1C1C1A"  # surface 0
# Semantic error (not in brand table — soft red for dark surfaces)
COLOR_ERROR = "#E07070"

# Material-ähnliche Elevation auf Dark (heller = höher)
SURFACE_1 = "#252526"  # sidebar / menubar
SURFACE_2 = "#2B2B2B"  # cards (Fluent-Dialog-nah)
SURFACE_3 = "#323232"  # hover / elevierter
BORDER = "#3A3A3A"
MUTED = "#D4CDC3"  # secondary text — hell genug auf Surface 2 (AA)

# Status text on dark UI (ok / warn / error / info)
STATUS_FG = {
    "ok": COLOR_TESTED,
    "warn": COLOR_EXPERIMENTAL,
    "error": COLOR_ERROR,
    "info": MUTED,
}

DARK = {
    "bg": COLOR_ANTHRACITE,
    "fg": COLOR_PARCHMENT,
    "muted": MUTED,
    "accent": ACCENT_COPPER,
    "border": BORDER,
}


def palette(theme: str | None = None) -> dict[str, str]:
    """Active theme color map (standard / dracula / alucard)."""
    from themes import theme_tokens

    return theme_tokens(theme)


def _hex_rgba(hex_color: str, alpha: float) -> str:
    h = hex_color.lstrip("#")
    if len(h) != 6:
        return f"rgba(184, 115, 51, {alpha})"
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r}, {g}, {b}, {alpha})"


def style_status_label(label, kind: str = "info", *, size_px: int = 12) -> None:
    """Brand status colors for feedback lines (Gespeichert / Warnung / Fehler)."""
    from themes import theme_tokens

    tok = theme_tokens()
    color = {
        "ok": tok["tested"],
        "warn": tok["experimental"],
        "error": tok["danger"],
        "info": tok["muted"],
    }.get(kind, tok["muted"])
    weight = "600" if kind in ("ok", "warn", "error") else "500"
    label.setStyleSheet(
        f"color: {color}; font-size: {size_px}px; font-weight: {weight}; "
        "background: transparent;"
    )


def host_stylesheet(theme: str | None = None) -> str:
    """Host-Chrome QSS — Combo/Spin brauchen echte Arrow-Images (sonst leere Kästen)."""
    tok = palette(theme)
    COLOR_ANTHRACITE = tok["bg"]
    COLOR_PARCHMENT = tok["fg"]
    MUTED = tok["muted"]
    ACCENT_COPPER = tok["accent"]
    BORDER = tok["border"]
    SURFACE_1 = tok["surface1"]
    SURFACE_2 = tok["surface2"]
    SURFACE_3 = tok["surface3"]
    ACCENT_SOFT = tok.get("accent_soft") or _hex_rgba(ACCENT_COPPER, 0.14)
    ACCENT_16 = _hex_rgba(ACCENT_COPPER, 0.16)
    ACCENT_18 = _hex_rgba(ACCENT_COPPER, 0.18)
    ACCENT_22 = _hex_rgba(ACCENT_COPPER, 0.22)
    ACCENT_28 = _hex_rgba(ACCENT_COPPER, 0.28)
    ACCENT_35 = _hex_rgba(ACCENT_COPPER, 0.35)
    ACCENT_45 = _hex_rgba(ACCENT_COPPER, 0.45)
    ACCENT_55 = _hex_rgba(ACCENT_COPPER, 0.55)
    SCROLL_HOVER = _hex_rgba(COLOR_PARCHMENT, 0.35)
    arrow_down = ensure_chevron_png("down", COLOR_PARCHMENT).as_posix()
    arrow_up = ensure_chevron_png("up", COLOR_PARCHMENT).as_posix()
    return f"""
QMainWindow {{
    background-color: {COLOR_ANTHRACITE};
    color: {COLOR_PARCHMENT};
    font-size: 13px;
}}
QMenuBar {{
    background-color: {SURFACE_1};
    color: {COLOR_PARCHMENT};
    border-bottom: 1px solid {BORDER};
    padding: 2px 0;
}}
QMenuBar::item {{
    color: {COLOR_PARCHMENT};
    padding: 4px 10px;
}}
QMenuBar::item:selected {{ background-color: {SURFACE_3}; }}
QMenu {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    color: {COLOR_PARCHMENT};
}}
QMenu::item:selected {{ background-color: {ACCENT_28}; }}
QStatusBar {{
    background-color: {SURFACE_1};
    border-top: 1px solid {BORDER};
    color: {MUTED};
    font-size: 11px;
    padding: 0 8px;
}}
QLabel#statusFooter {{
    color: {MUTED};
    padding: 0 4px;
}}
QFrame#sidebar {{
    background-color: {SURFACE_1};
    border-right: 1px solid {BORDER};
}}
/* ScrollArea must not paint Base (#2B2B2B) — looked like stacked card blocks */
QScrollArea#recipeCardsScroll {{
    background-color: transparent;
    border: none;
}}
QScrollArea#recipeCardsScroll > QWidget {{
    background-color: transparent;
}}
QWidget#recipeCardsHost {{
    background-color: transparent;
}}
QLabel#sidebarCategory {{
    color: {MUTED};
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.08em;
    padding: 8px 4px 2px 4px;
    background-color: transparent;
}}
QLabel#sidebarCardTitle {{
    background-color: transparent;
    color: {COLOR_PARCHMENT};
}}
QLabel#sidebarCardSub {{
    background-color: transparent;
    color: {MUTED};
    font-size: 8pt;
    font-family: monospace;
}}
QLabel#sidebarSearchEmpty {{
    color: {MUTED};
    font-size: 12px;
    padding: 8px 4px;
    background-color: transparent;
}}
QFrame#headerCard, QFrame#contentShell {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 8px;
}}
QFrame#actionBar {{
    background-color: transparent;
    border: none;
}}
QStackedWidget {{ background-color: transparent; }}
QLabel#sidebarTitle {{
    color: {MUTED};
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
    background-color: transparent;
}}
QPushButton#homeSidebarBtn {{
    text-align: left;
    padding: 8px 10px;
    border: 1px solid {BORDER};
    border-radius: 6px;
    background-color: {SURFACE_2};
    color: {COLOR_PARCHMENT};
    font-weight: 600;
}}
QPushButton#homeSidebarBtn:hover {{
    border-color: {ACCENT_COPPER};
}}
QPushButton#homeSidebarBtn[homeActive="true"] {{
    border-color: {ACCENT_COPPER};
    background-color: {ACCENT_16};
}}
QFrame#homeStatCard {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 6px;
}}
QLabel#homeStatValue {{
    color: {ACCENT_COPPER};
    font-size: 16px;
    font-weight: 700;
    background: transparent;
}}
QLabel#homeStatLabel {{
    color: {MUTED};
    font-size: 10px;
    font-weight: 600;
    background: transparent;
}}
QLabel#homeIntro {{
    color: {COLOR_PARCHMENT};
    font-size: 12px;
    background: transparent;
}}
QLabel#homeLinksHint {{
    color: {MUTED};
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.04em;
    background: transparent;
}}
QLabel#homeActivityTitle {{
    color: {MUTED};
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.04em;
    background: transparent;
}}
QListWidget#homeActivityList {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 6px;
    color: {COLOR_PARCHMENT};
    font-size: 12px;
}}
QListWidget#homeActivityList::item {{ padding: 2px 6px; border: none; }}
/* Home community links — read as buttons (fill + accent edge), not flat cards */
QFrame#homeLinkCard {{
    background-color: {SURFACE_2};
    border: 1px solid {ACCENT_COPPER};
    border-radius: 6px;
}}
QFrame#homeLinkCard:hover {{
    background-color: {ACCENT_22};
    border-color: {ACCENT_COPPER};
}}
QFrame#homeLinkCard:focus {{
    background-color: {ACCENT_18};
    border: 2px solid {ACCENT_COPPER};
}}
QLabel#homeLinkIcon {{
    background: transparent;
    border: none;
    padding: 0px;
    margin: 0px;
}}
QLabel#homeLinkTitle {{
    color: {COLOR_PARCHMENT};
    font-size: 12px;
    font-weight: 600;
    background: transparent;
}}
QLabel#homeLinkSub {{
    color: {MUTED};
    font-size: 10px;
    background: transparent;
}}
QLabel#appTitle {{
    font-size: 20px;
    font-weight: 600;
    color: {COLOR_PARCHMENT};
    background: transparent;
}}
QLabel#appPath {{
    color: {MUTED};
    font-size: 11px;
    background: transparent;
}}
QLabel#stepLabel {{
    font-weight: 600;
    color: {COLOR_PARCHMENT};
}}
QLabel#muted, QLabel#statusDetail {{
    color: {MUTED};
    font-size: 12px;
    background: transparent;
}}
QListWidget#activityList {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 6px;
    color: {COLOR_PARCHMENT};
    font-family: "JetBrains Mono", "Fira Code", monospace;
    font-size: 12px;
}}
QListWidget#activityList::item {{ padding: 4px 8px; border: none; }}
QTextEdit#rawLog {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 6px;
    color: {COLOR_PARCHMENT};
    padding: 6px 8px;
}}
QTextBrowser#infoBrowser {{
    background-color: transparent;
    border: none;
    color: {COLOR_PARCHMENT};
    padding: 4px 0;
}}
QLineEdit#sidebarSearch {{
    background-color: rgba(255, 255, 255, 0.06);
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 8px 10px;
    color: {COLOR_PARCHMENT};
    font-size: 13px;
    min-height: 20px;
}}
QLineEdit#sidebarSearch:focus {{
    border-color: {ACCENT_COPPER};
}}
QLineEdit#sidebarSearch::placeholder {{
    color: {MUTED};
}}
QTextEdit, QPlainTextEdit, QSpinBox {{
    background-color: rgba(255, 255, 255, 0.06);
    border: 1px solid {BORDER};
    border-radius: 4px;
    color: {COLOR_PARCHMENT};
    selection-background-color: {ACCENT_COPPER};
    selection-color: #1a1a1a;
}}
QSpinBox:focus {{
    border-color: {ACCENT_COPPER};
}}
QSpinBox::up-button, QSpinBox::down-button {{
    background: transparent;
    border: none;
    width: 18px;
}}
QSpinBox::up-arrow {{
    image: url({arrow_up});
    width: 10px;
    height: 10px;
}}
QSpinBox::down-arrow {{
    image: url({arrow_down});
    width: 10px;
    height: 10px;
}}
/* Dropdowns: ein Design mit Akzent — kein System-Blau */
QComboBox {{
    background-color: rgba(255, 255, 255, 0.06);
    border: 1px solid {BORDER};
    border-radius: 4px;
    padding: 6px 10px;
    padding-right: 28px;
    color: {COLOR_PARCHMENT};
    min-height: 20px;
    selection-background-color: {ACCENT_COPPER};
    selection-color: #1a1a1a;
}}
QComboBox:hover {{
    border-color: {ACCENT_55};
}}
QComboBox:focus, QComboBox:on {{
    border-color: {ACCENT_COPPER};
}}
QComboBox::drop-down {{
    border: none;
    width: 28px;
    background: transparent;
}}
QComboBox::down-arrow {{
    image: url({arrow_down});
    width: 10px;
    height: 10px;
}}
QComboBox QAbstractItemView {{
    background-color: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 4px;
    color: {COLOR_PARCHMENT};
    outline: none;
    padding: 4px;
    selection-background-color: {ACCENT_35};
    selection-color: {COLOR_PARCHMENT};
}}
QComboBox QAbstractItemView::item {{
    min-height: 28px;
    padding: 4px 8px;
    border: none;
    border-radius: 4px;
    color: {COLOR_PARCHMENT};
}}
QComboBox QAbstractItemView::item:hover {{
    background-color: {ACCENT_22};
    color: {COLOR_PARCHMENT};
}}
QComboBox QAbstractItemView::item:selected {{
    background-color: {ACCENT_35};
    color: {COLOR_PARCHMENT};
}}
QListWidget::item:selected {{
    background-color: {ACCENT_35};
    color: {COLOR_PARCHMENT};
}}
QListWidget::item:hover:!selected {{
    background-color: rgba(255, 255, 255, 0.06);
}}
QProgressBar, QProgressBar#rezeptorProgress {{
    border: 1px solid {BORDER};
    border-radius: 4px;
    background-color: {SURFACE_1};
    text-align: center;
    min-height: 8px;
    color: {COLOR_PARCHMENT};
}}
QProgressBar::chunk, QProgressBar#rezeptorProgress::chunk {{
    background-color: {ACCENT_COPPER};
    border-radius: 3px;
}}
QPushButton {{
    background-color: rgba(255, 255, 255, 0.0605);
    border: 1px solid {BORDER};
    border-radius: 4px;
    padding: 7px 14px;
    color: {COLOR_PARCHMENT};
    min-height: 18px;
}}
QPushButton:hover {{
    background-color: rgba(255, 255, 255, 0.09);
    border-color: {ACCENT_45};
}}
QPushButton:pressed {{
    background-color: {ACCENT_22};
}}
QPushButton:disabled {{
    color: {MUTED};
    background-color: {SURFACE_1};
    border-color: {BORDER};
}}
QPushButton#ghostBtn {{
    background-color: transparent;
    border-color: {BORDER};
    color: {COLOR_PARCHMENT};
}}
QPushButton#ghostBtn:hover {{
    background-color: {ACCENT_18};
    border-color: {ACCENT_COPPER};
}}
QToolButton {{
    background-color: rgba(255, 255, 255, 0.0605);
    border: 1px solid {BORDER};
    border-radius: 4px;
    padding: 6px 12px;
    color: {COLOR_PARCHMENT};
}}
QToolButton:hover {{
    background-color: rgba(255, 255, 255, 0.09);
    border-color: {ACCENT_45};
}}
/* Kompakte Header-Chips — globales ToolButton-Padding würgt 22px-Icons sonst leer */
QToolButton#versionInfoBtn,
QToolButton#sourceInfoBtn,
QToolButton#openPathBtn,
QToolButton#healthChip {{
    padding: 2px;
    margin: 0;
    min-width: 26px;
    max-width: 28px;
    min-height: 26px;
    max-height: 28px;
    background-color: rgba(255, 255, 255, 0.08);
}}
/* Menubar corner: flag + theme — compact, no chrome */
QToolButton#langToggle,
QToolButton#themeToggle {{
    background: transparent;
    border: none;
    padding: 0;
    margin: 0;
    min-width: 0;
    max-width: 36px;
    min-height: 28px;
    max-height: 28px;
    color: {COLOR_PARCHMENT};
}}
QToolButton#langToggle:hover,
QToolButton#langToggle:pressed,
QToolButton#langToggle:focus,
QToolButton#themeToggle:hover,
QToolButton#themeToggle:pressed,
QToolButton#themeToggle:focus {{
    background: transparent;
    border: none;
}}
QToolButton::menu-indicator {{ image: none; width: 0; }}
/* Scrollbars dezent — kein Kupfer-Signalstreifen (Akzent bleibt bei CTA/Auswahl) */
QScrollBar:vertical {{
    background: transparent;
    width: 8px;
    margin: 0;
}}
QScrollBar::handle:vertical {{
    background: {BORDER};
    border-radius: 4px;
    min-height: 24px;
}}
QScrollBar::handle:vertical:hover {{
    background: {SCROLL_HOVER};
}}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
    height: 0;
}}
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{
    background: transparent;
}}
QScrollBar:horizontal {{
    background: transparent;
    height: 8px;
    margin: 0;
}}
QScrollBar::handle:horizontal {{
    background: {BORDER};
    border-radius: 4px;
    min-width: 24px;
}}
QScrollBar::handle:horizontal:hover {{
    background: {SCROLL_HOVER};
}}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
    width: 0;
}}
QSplitter::handle {{ background-color: {BORDER}; width: 1px; }}
"""


_HOST_CACHE: str | None = None
_HOST_CACHE_THEME: str | None = None


def get_host_stylesheet(theme: str | None = None) -> str:
    """Cached Host-QSS (erst nach QApplication sicher für QPainter-Arrows)."""
    global _HOST_CACHE, _HOST_CACHE_THEME
    from themes import normalize_theme

    tid = normalize_theme(theme)
    if _HOST_CACHE is None or _HOST_CACHE_THEME != tid:
        _HOST_CACHE = host_stylesheet(tid)
        _HOST_CACHE_THEME = tid
    return _HOST_CACHE


def __getattr__(name: str) -> str:
    if name in ("HOST_STYLESHEET", "APP_STYLESHEET"):
        return get_host_stylesheet()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
