"""Font Awesome Free icons for Rezeptor activity / status UI."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import QPointF, Qt
from PyQt6.QtGui import (
    QColor,
    QFont,
    QFontDatabase,
    QIcon,
    QPainter,
    QPixmap,
    QPolygonF,
)

_FA_FONT: QFont | None = None
_FA_FAMILY: str = ""
_FA_BRANDS_FONT: QFont | None = None
_FA_BRANDS_FAMILY: str = ""

FA_CHECK = "\uf00c"
FA_XMARK = "\uf00d"
FA_ARROW_RIGHT = "\uf061"
FA_TRIANGLE_EXCLAMATION = "\uf071"
FA_CIRCLE_INFO = "\uf05a"
FA_CIRCLE = "\uf111"
FA_SPINNER = "\uf110"
FA_PLAY = "\uf04b"
FA_DOWNLOAD = "\uf019"
FA_ROTATE = "\uf2f1"
FA_CLIPBOARD_CHECK = "\uf46c"
FA_STOP = "\uf04d"
FA_ELLIPSIS = "\uf141"
FA_FOLDER_OPEN = "\uf07c"
FA_BOOK = "\uf02d"
FA_BOOK_OPEN = "\uf518"
FA_GITHUB = "\uf09b"  # Font Awesome Brands

_KIND_GLYPH = {
    "ok": FA_CHECK,
    "error": FA_XMARK,
    "warn": FA_TRIANGLE_EXCLAMATION,
    "step": FA_ARROW_RIGHT,
    "info": FA_CIRCLE_INFO,
    "log": FA_CIRCLE,
    "progress": FA_SPINNER,
    "launch": FA_PLAY,
    "install": FA_DOWNLOAD,
    "repair": FA_ROTATE,
    "validate": FA_CLIPBOARD_CHECK,
    "kill": FA_STOP,
    "more": FA_ELLIPSIS,
    "folder": FA_FOLDER_OPEN,
    "book": FA_BOOK,
    "book_open": FA_BOOK_OPEN,
    "github": FA_GITHUB,
}

_BRAND_KINDS = frozenset({"github"})

# Farben wie vor Dracula (Kupfer / Grün / Amber)
_KIND_COLOR = {
    "ok": "#3ddc84",
    "error": "#f85149",
    "warn": "#e6a700",
    "step": "#58a6ff",
    "info": "#a1a1aa",
    "log": "#c9d1d9",
    "progress": "#58a6ff",
    "launch": "#e4e4e7",
    "install": "#e4e4e7",
    "repair": "#e4e4e7",
    "validate": "#e4e4e7",
    "kill": "#f85149",
    "more": "#a1a1aa",
    "folder": "#a1a1aa",
}


def _font_path() -> Path:
    return Path(__file__).resolve().parent / "assets" / "fonts" / "fa-solid-900.otf"


def _brands_font_path() -> Path:
    return Path(__file__).resolve().parent / "assets" / "fonts" / "fa-brands-400.ttf"


def _load_fa_font(path: Path) -> QFont | None:
    if not path.is_file():
        return None
    font_id = QFontDatabase.addApplicationFont(str(path))
    if font_id < 0:
        return None
    families = QFontDatabase.applicationFontFamilies(font_id)
    if not families:
        return None
    font = QFont(families[0], 11)
    font.setStyleStrategy(QFont.StyleStrategy.PreferQuality)
    return font


def ensure_fa_font() -> QFont | None:
    global _FA_FONT, _FA_FAMILY
    if _FA_FONT is not None:
        return _FA_FONT
    font = _load_fa_font(_font_path())
    if font is None:
        return None
    _FA_FAMILY = font.family()
    _FA_FONT = font
    return _FA_FONT


def ensure_fa_brands_font() -> QFont | None:
    global _FA_BRANDS_FONT, _FA_BRANDS_FAMILY
    if _FA_BRANDS_FONT is not None:
        return _FA_BRANDS_FONT
    font = _load_fa_font(_brands_font_path())
    if font is None:
        return None
    _FA_BRANDS_FAMILY = font.family()
    _FA_BRANDS_FONT = font
    return _FA_BRANDS_FONT


def fa_glyph(kind: str) -> str:
    return _KIND_GLYPH.get(kind, FA_CIRCLE)


def fa_color(kind: str) -> str:
    return _KIND_COLOR.get(kind, "#c9d1d9")


def fa_icon(kind: str, pixel: int = 16, *, color: str | None = None) -> QIcon | None:
    font = ensure_fa_brands_font() if kind in _BRAND_KINDS else ensure_fa_font()
    if font is None:
        return None
    glyph = fa_glyph(kind)
    paint = QColor(color or fa_color(kind))
    size = max(12, pixel)
    pix = QPixmap(size + 4, size + 4)
    pix.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pix)
    f = QFont(font)
    f.setPixelSize(size)
    painter.setFont(f)
    painter.setPen(paint)
    painter.drawText(pix.rect(), int(Qt.AlignmentFlag.AlignCenter), glyph)
    painter.end()
    return QIcon(pix)


def _ui_asset_dir() -> Path:
    d = Path(__file__).resolve().parent / "assets" / "ui"
    d.mkdir(parents=True, exist_ok=True)
    return d


def ensure_chevron_png(direction: str, color: str = "#EDE6D6") -> Path:
    """Tiny up/down chevron for QSS (Combo/Spin) — empty ::down-arrow otherwise."""
    out = _ui_asset_dir() / f"chevron-{direction}-{color.lstrip('#')}-v2.png"
    if out.is_file():
        return out
    size = 16
    pix = QPixmap(size, size)
    pix.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pix)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(QColor(color))
    cx, cy = size / 2, size / 2
    if direction == "up":
        points = [
            (cx, cy - 4),
            (cx + 5, cy + 3),
            (cx - 5, cy + 3),
        ]
    else:
        points = [
            (cx, cy + 4),
            (cx + 5, cy - 3),
            (cx - 5, cy - 3),
        ]
    painter.drawPolygon(QPolygonF([QPointF(x, y) for x, y in points]))
    painter.end()
    pix.save(str(out), "PNG")
    return out
