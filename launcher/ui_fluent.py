"""Fluent Design — Standard ist immer Dark + Kupfer (Brand).

Quellen:
- docs/BRAND.md (Anthrazit/Kupfer/Pergament)
- qfluentwidgets Theme.DARK (zhiyiYo) — Lib nicht mit PyQtDarkTheme mischen
- Material Dark: Elevation + hoher Textkontrast; System-Light ignorieren
"""

from __future__ import annotations

from ui_styles import (
    ACCENT_COPPER,
    COLOR_EXPERIMENTAL,
    COLOR_PARCHMENT,
    COLOR_TESTED,
    MUTED,
    get_host_stylesheet,
)

ACCENT = ACCENT_COPPER

FLUENT_AVAILABLE = False
Pivot = None  # type: ignore[misc, assignment]
IconWidget = None  # type: ignore[misc, assignment]
BodyLabel = None  # type: ignore[misc, assignment]
StrongBodyLabel = None  # type: ignore[misc, assignment]
FluentIcon = None  # type: ignore[misc, assignment]
Theme = None  # type: ignore[misc, assignment]
RoundMenu = None  # type: ignore[misc, assignment]
_qconfig = None  # type: ignore[misc, assignment]
_setTheme = None  # type: ignore[misc, assignment]
_setThemeColor = None  # type: ignore[misc, assignment]

try:
    from qfluentwidgets import (  # type: ignore[import-untyped]
        BodyLabel,
        CaptionLabel,
        CardWidget,
        FluentIcon,
        IconWidget,
        Pivot,
        PrimaryPushButton,
        PushButton,
        RoundMenu,
        StrongBodyLabel,
        SubtitleLabel,
        Theme,
        TitleLabel,
        qconfig,
        setTheme,
        setThemeColor,
    )

    FLUENT_AVAILABLE = True
    _qconfig = qconfig
    _setTheme = setTheme
    _setThemeColor = setThemeColor
except ImportError:
    from PyQt6.QtGui import QIcon
    from PyQt6.QtWidgets import QLabel, QMenu, QPushButton, QWidget

    class IconWidget(QLabel):  # type: ignore[no-redef]
        """Fluent-less fallback: show recipe icon in sidebar cards."""

        def __init__(self, icon: QIcon, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            if icon is not None and not icon.isNull():
                self.setPixmap(icon.pixmap(20, 20))

    PrimaryPushButton = QPushButton  # type: ignore[misc, assignment]
    PushButton = QPushButton  # type: ignore[misc, assignment]
    RoundMenu = QMenu  # type: ignore[misc, assignment]
    CardWidget = QWidget  # type: ignore[misc, assignment]
    TitleLabel = QLabel  # type: ignore[misc, assignment]
    SubtitleLabel = QLabel  # type: ignore[misc, assignment]
    CaptionLabel = QLabel  # type: ignore[misc, assignment]
    BodyLabel = QLabel  # type: ignore[misc, assignment]
    StrongBodyLabel = QLabel  # type: ignore[misc, assignment]

    def setThemeColor(_color: str) -> None:
        return


def apply_rezeptor_theme() -> str:
    """Ein Look: Fluent Dark + Kupfer. System Light/Dark egal.

    Returns:
        Stylesheet für die App (Host-Chrome + später Segment-Tabs).
    """
    try:
        from PyQt6.QtCore import Qt
        from PyQt6.QtGui import QColor, QGuiApplication, QPalette
        from PyQt6.QtWidgets import QApplication

        app = QApplication.instance()
        if app is not None:
            hints = QGuiApplication.styleHints()
            if hasattr(hints, "setColorScheme"):
                hints.setColorScheme(Qt.ColorScheme.Dark)

            # Dunkle Palette — sonst System-Light → helles Chrome + Fluent-Weißschrift
            bg = QColor("#1C1C1A")
            fg = QColor(COLOR_PARCHMENT)
            muted = QColor(MUTED)
            panel = QColor("#252526")
            base = QColor("#2B2B2B")
            accent = QColor(ACCENT_COPPER)
            pal = QPalette()
            for group in (
                QPalette.ColorGroup.Active,
                QPalette.ColorGroup.Inactive,
                QPalette.ColorGroup.Disabled,
            ):
                pal.setColor(group, QPalette.ColorRole.Window, bg)
                pal.setColor(group, QPalette.ColorRole.WindowText, fg)
                pal.setColor(group, QPalette.ColorRole.Base, base)
                pal.setColor(group, QPalette.ColorRole.AlternateBase, panel)
                pal.setColor(group, QPalette.ColorRole.Text, fg)
                pal.setColor(group, QPalette.ColorRole.Button, panel)
                pal.setColor(group, QPalette.ColorRole.ButtonText, fg)
                pal.setColor(group, QPalette.ColorRole.ToolTipBase, panel)
                pal.setColor(group, QPalette.ColorRole.ToolTipText, fg)
                pal.setColor(group, QPalette.ColorRole.PlaceholderText, muted)
                pal.setColor(group, QPalette.ColorRole.BrightText, fg)
                pal.setColor(group, QPalette.ColorRole.Highlight, accent)
                pal.setColor(group, QPalette.ColorRole.HighlightedText, QColor("#1C1C1A"))
                pal.setColor(group, QPalette.ColorRole.Link, accent)
            # Disabled etwas gedämpft, aber noch lesbar
            pal.setColor(
                QPalette.ColorGroup.Disabled, QPalette.ColorRole.WindowText, muted
            )
            pal.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.Text, muted)
            pal.setColor(
                QPalette.ColorGroup.Disabled, QPalette.ColorRole.ButtonText, muted
            )
            app.setPalette(pal)
    except Exception:
        pass

    if FLUENT_AVAILABLE and Theme is not None and _setTheme is not None:
        _setTheme(Theme.DARK, save=True)
        if _setThemeColor is not None:
            _setThemeColor(ACCENT_COPPER, save=True)
        if _qconfig is not None:
            try:
                _qconfig.theme = Theme.DARK
            except Exception:
                pass

    return get_host_stylesheet()


# Aliase
ignore_system_light_theme = apply_rezeptor_theme
enforce_standard_design = apply_rezeptor_theme
apply_app_theme = apply_rezeptor_theme


def app_stylesheet() -> str:
    """Host-QSS (Fluent Dark Surfaces + Brand). Immer — auch mit Fluent."""
    return get_host_stylesheet()
