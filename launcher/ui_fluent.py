"""Fluent Design — Standard ist immer Dark + Kupfer (Brand).

Quellen:
- docs/BRAND.md (Anthrazit/Kupfer/Pergament)
- qfluentwidgets Theme.DARK (zhiyiYo) — Lib nicht mit PyQtDarkTheme mischen
- Material Dark: Elevation + hoher Textkontrast; System-Light ignorieren
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from ui_styles import (
    ACCENT_COPPER,
    COLOR_EXPERIMENTAL,
    COLOR_PARCHMENT,
    COLOR_TESTED,
    MUTED,
    get_host_stylesheet,
)

FLUENT_AVAILABLE = False
Pivot = None  # type: ignore[misc, assignment]
IconWidget = None  # type: ignore[misc, assignment]
BodyLabel = None  # type: ignore[misc, assignment]
StrongBodyLabel = None  # type: ignore[misc, assignment]
FluentIcon = None  # type: ignore[misc, assignment]
Theme = None  # type: ignore[misc, assignment]
RoundMenu = None  # type: ignore[misc, assignment]
MenuAnimationType = None  # type: ignore[misc, assignment]
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
    from qfluentwidgets.components.widgets.menu import (  # type: ignore[import-untyped]
        MenuAnimationType,
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
    MenuAnimationType = None  # type: ignore[misc, assignment]
    CardWidget = QWidget  # type: ignore[misc, assignment]
    TitleLabel = QLabel  # type: ignore[misc, assignment]
    SubtitleLabel = QLabel  # type: ignore[misc, assignment]
    CaptionLabel = QLabel  # type: ignore[misc, assignment]
    BodyLabel = QLabel  # type: ignore[misc, assignment]
    StrongBodyLabel = QLabel  # type: ignore[misc, assignment]

    def setThemeColor(_color: str) -> None:
        return


def apply_rezeptor_theme(theme: str | None = None) -> str:
    """Apply palette + Fluent theme for standard / dracula / alucard.

    Returns:
        Host stylesheet for the app chrome.
    """
    from themes import normalize_theme, set_active_theme, theme_is_dark, theme_tokens

    tid = set_active_theme(theme)
    tok = theme_tokens(tid)
    try:
        from PyQt6.QtCore import Qt
        from PyQt6.QtGui import QColor, QGuiApplication, QPalette
        from PyQt6.QtWidgets import QApplication

        app = QApplication.instance()
        if app is not None:
            hints = QGuiApplication.styleHints()
            if hasattr(hints, "setColorScheme"):
                scheme = (
                    Qt.ColorScheme.Dark
                    if theme_is_dark(tid)
                    else Qt.ColorScheme.Light
                )
                hints.setColorScheme(scheme)

            bg = QColor(tok["bg"])
            fg = QColor(tok["fg"])
            muted = QColor(tok["muted"])
            panel = QColor(tok["surface1"])
            base = QColor(tok["surface2"])
            accent = QColor(tok["accent"])
            hi_text = QColor("#1C1C1A" if theme_is_dark(tid) else "#FFFBEB")
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
                pal.setColor(group, QPalette.ColorRole.HighlightedText, hi_text)
                pal.setColor(group, QPalette.ColorRole.Link, accent)
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
        # AppImage/FUSE mounts are read-only. qfluentwidgets defaults to
        # writing ./config next to cwd — that crashes startup (Errno 30).
        try:
            if _qconfig is not None:
                xdg = Path(
                    os.environ.get("XDG_CONFIG_HOME")
                    or (Path.home() / ".config")
                )
                cfg = xdg / "rezeptor" / "qfluentwidgets.json"
                cfg.parent.mkdir(parents=True, exist_ok=True)
                try:
                    _qconfig.file = cfg
                except Exception:
                    pass
            fluent_theme = Theme.DARK if theme_is_dark(tid) else Theme.LIGHT
            _setTheme(fluent_theme, save=False)
            if _setThemeColor is not None:
                # Always re-apply accent so Standard/Alucard never keep Dracula purple.
                _setThemeColor(str(tok["accent"]), save=False)
            if _qconfig is not None:
                try:
                    _qconfig.theme = fluent_theme
                except Exception:
                    pass
                try:
                    # Drop cached purple from a previous session if present.
                    if hasattr(_qconfig, "set"):
                        _qconfig.set(_qconfig.themeColor, tok["accent"], save=False)
                except Exception:
                    pass
        except OSError as exc:
            print(f"rezeptor: fluent theme skipped ({exc})", file=sys.stderr)

    return get_host_stylesheet(tid)
