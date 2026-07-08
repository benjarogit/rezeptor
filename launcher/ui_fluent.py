"""Fluent Design (PyQt6-Fluent-Widgets) mit Fallback auf Standard-Qt."""

from __future__ import annotations

ACCENT_COPPER = "#B87333"
COLOR_TESTED = "#639922"
COLOR_EXPERIMENTAL = "#d9a441"

FLUENT_AVAILABLE = False
Pivot = None  # type: ignore[misc, assignment]
IconWidget = None  # type: ignore[misc, assignment]
BodyLabel = None  # type: ignore[misc, assignment]
StrongBodyLabel = None  # type: ignore[misc, assignment]
FluentIcon = None  # type: ignore[misc, assignment]

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
        StrongBodyLabel,
        SubtitleLabel,
        Theme,
        TitleLabel,
        setTheme,
        setThemeColor,
    )

    FLUENT_AVAILABLE = True
    setTheme(Theme.DARK)
    setThemeColor(ACCENT_COPPER)
except ImportError:
    from PyQt6.QtWidgets import QPushButton, QWidget

    PrimaryPushButton = QPushButton  # type: ignore[misc, assignment]
    PushButton = QPushButton  # type: ignore[misc, assignment]
    CardWidget = QWidget  # type: ignore[misc, assignment]
    TitleLabel = QWidget  # type: ignore[misc, assignment]
    SubtitleLabel = QWidget  # type: ignore[misc, assignment]
    CaptionLabel = QWidget  # type: ignore[misc, assignment]
    BodyLabel = QWidget  # type: ignore[misc, assignment]
    StrongBodyLabel = QWidget  # type: ignore[misc, assignment]

    def setThemeColor(_color: str) -> None:
        return


def app_stylesheet() -> str:
    if FLUENT_AVAILABLE:
        return ""
    from ui_styles import APP_STYLESHEET

    return APP_STYLESHEET
