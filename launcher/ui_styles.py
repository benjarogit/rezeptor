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

# Material-ähnliche Elevation auf Dark (heller = höher)
SURFACE_1 = "#252526"  # sidebar / menubar
SURFACE_2 = "#2B2B2B"  # cards (Fluent-Dialog-nah)
SURFACE_3 = "#323232"  # hover / elevierter
BORDER = "#3A3A3A"
MUTED = "#D4CDC3"  # secondary text — hell genug auf Surface 2 (AA)

STATE_COLORS = {
    "not_installed": (MUTED, SURFACE_1),
    "partial": (COLOR_EXPERIMENTAL, "#3d3200"),
    "installed": (COLOR_TESTED, "#0d3320"),
    "unknown": (MUTED, SURFACE_1),
}

DARK = {
    "bg": COLOR_ANTHRACITE,
    "fg": COLOR_PARCHMENT,
    "muted": MUTED,
    "accent": ACCENT_COPPER,
    "border": BORDER,
}


def palette(theme: str | None = None) -> dict[str, str]:
    _ = theme
    return DARK


def host_stylesheet() -> str:
    """Host-Chrome QSS — Combo/Spin brauchen echte Arrow-Images (sonst leere Kästen)."""
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
QMenu::item:selected {{ background-color: rgba(184, 115, 51, 0.28); }}
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
    background-color: rgba(184, 115, 51, 0.16);
}}
QFrame#homeStatCard {{
    background-color: {COLOR_ANTHRACITE};
    border: 1px solid {BORDER};
    border-radius: 8px;
}}
QLabel#homeStatValue {{
    color: {ACCENT_COPPER};
    font-size: 22px;
    font-weight: 700;
    background: transparent;
}}
QLabel#homeStatLabel {{
    color: {MUTED};
    font-size: 11px;
    font-weight: 600;
    background: transparent;
}}
QLabel#homeIntro {{
    color: {COLOR_PARCHMENT};
    font-size: 13px;
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
    background-color: {COLOR_ANTHRACITE};
    border: 1px solid {BORDER};
    border-radius: 6px;
    color: {COLOR_PARCHMENT};
    font-family: "JetBrains Mono", "Fira Code", monospace;
    font-size: 12px;
}}
QListWidget#activityList::item {{ padding: 4px 8px; border: none; }}
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
/* Dropdowns: ein Design mit Kupfer — kein System-Blau */
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
    border-color: rgba(184, 115, 51, 0.55);
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
    selection-background-color: rgba(184, 115, 51, 0.35);
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
    background-color: rgba(184, 115, 51, 0.22);
    color: {COLOR_PARCHMENT};
}}
QComboBox QAbstractItemView::item:selected {{
    background-color: rgba(184, 115, 51, 0.35);
    color: {COLOR_PARCHMENT};
}}
QListWidget::item:selected {{
    background-color: rgba(184, 115, 51, 0.35);
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
    border-color: rgba(184, 115, 51, 0.45);
}}
QPushButton:pressed {{
    background-color: rgba(184, 115, 51, 0.22);
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
    background-color: rgba(184, 115, 51, 0.18);
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
    border-color: rgba(184, 115, 51, 0.45);
}}
/* Kompakte Header-Chips — globales ToolButton-Padding würgt 22px-Icons sonst leer */
QToolButton#versionInfoBtn,
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
    background: rgba(237, 230, 214, 0.35);
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
    background: rgba(237, 230, 214, 0.35);
}}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
    width: 0;
}}
QSplitter::handle {{ background-color: {BORDER}; width: 1px; }}
"""


_HOST_CACHE: str | None = None


def get_host_stylesheet() -> str:
    """Cached Host-QSS (erst nach QApplication sicher für QPainter-Arrows)."""
    global _HOST_CACHE
    if _HOST_CACHE is None:
        _HOST_CACHE = host_stylesheet()
    return _HOST_CACHE


def __getattr__(name: str) -> str:
    if name in ("HOST_STYLESHEET", "APP_STYLESHEET"):
        return get_host_stylesheet()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
