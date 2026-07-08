"""Rezeptor — Marken-Widgets (Fluent + Fallback)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QButtonGroup,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from ui_fluent import (
    ACCENT_COPPER,
    COLOR_EXPERIMENTAL,
    COLOR_TESTED,
    FLUENT_AVAILABLE,
    CaptionLabel,
    CardWidget,
    IconWidget,
    StrongBodyLabel,
)

ROOT = Path(__file__).resolve().parent.parent
REZEPTOR_ICON = ROOT / "images" / "rezeptor-icon.svg"
REZEPTOR_WORDMARK = ROOT / "images" / "rezeptor-wordmark.svg"

STATE_DOT = {
    "installed": COLOR_TESTED,
    "partial": COLOR_EXPERIMENTAL,
    "not_installed": "#6b7280",
    "unknown": "#6b7280",
}

SEGMENT_TAB_STYLES = f"""
QFrame#segmentTabBar {{
    background-color: rgba(255, 255, 255, 0.03);
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}}
QPushButton#segmentTab {{
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 6px;
    color: #a1a1aa;
    font-size: 13px;
    font-weight: 500;
    padding: 6px 16px;
    min-height: 28px;
}}
QPushButton#segmentTab:hover {{
    background-color: rgba(255, 255, 255, 0.06);
    color: #e4e4e7;
    border-color: rgba(255, 255, 255, 0.1);
}}
QPushButton#segmentTab:checked {{
    background-color: rgba(184, 115, 51, 0.18);
    border-color: {ACCENT_COPPER};
    color: #f4f4f5;
    font-weight: 600;
}}
QLabel#sidebarCategory {{
    color: #71717a;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.08em;
    padding: 10px 4px 4px 4px;
}}
"""


class SegmentTabBar(QFrame):
    """Klar klickbare Tabs (ersetzt Fluent-Pivot)."""

    tabSelected = pyqtSignal(str)

    def __init__(
        self,
        tabs: list[tuple[str, str]],
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setObjectName("segmentTabBar")
        self.setStyleSheet(SEGMENT_TAB_STYLES)
        self._buttons: dict[str, QPushButton] = {}
        row = QHBoxLayout(self)
        row.setContentsMargins(10, 8, 10, 6)
        row.setSpacing(6)
        group = QButtonGroup(self)
        group.setExclusive(True)
        for key, label in tabs:
            btn = QPushButton(label)
            btn.setCheckable(True)
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setObjectName("segmentTab")
            btn.clicked.connect(lambda _checked, k=key: self.tabSelected.emit(k))
            group.addButton(btn)
            row.addWidget(btn)
            self._buttons[key] = btn
        row.addStretch(1)
        if tabs:
            self.set_current(tabs[0][0])

    def set_current(self, key: str) -> None:
        btn = self._buttons.get(key)
        if btn is not None:
            btn.setChecked(True)


class StatusPill(QLabel):
    """Inline Status-Badge (Getestet, Proton-GE, …)."""

    def __init__(self, text: str, color: str, parent: QWidget | None = None) -> None:
        super().__init__(text, parent)
        self.setStyleSheet(
            f"""
            QLabel {{
                color: {color};
                background-color: rgba(255, 255, 255, 0.06);
                padding: 4px 10px;
                border-radius: 6px;
                font-size: 12px;
            }}
            """
        )


class RecipeSidebarCard(CardWidget):
    """Kompakter Rezept-Eintrag — Details im Hauptbereich."""

    clicked = pyqtSignal()

    def __init__(
        self,
        name: str,
        state: str,
        icon=None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setFixedHeight(42)
        self.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._selected = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 6, 10, 6)
        layout.setSpacing(8)

        if FLUENT_AVAILABLE and icon is not None:
            iw = IconWidget(icon, self)
            iw.setFixedSize(20, 20)
            layout.addWidget(iw)
        else:
            dot = QLabel("●", self)
            dot.setFixedWidth(16)
            layout.addWidget(dot)

        title = StrongBodyLabel(name, self) if FLUENT_AVAILABLE else QLabel(name, self)
        title.setWordWrap(False)
        layout.addWidget(title, stretch=1)

        state_dot = QLabel("●", self)
        state_dot.setFixedWidth(12)
        state_dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        state_dot.setStyleSheet(
            f"color: {STATE_DOT.get(state, STATE_DOT['unknown'])}; font-size: 10px;"
        )
        state_dot.setToolTip(
            {
                "installed": "Installiert",
                "partial": "Teilweise",
                "not_installed": "Nicht installiert",
            }.get(state, "Unbekannt")
        )
        layout.addWidget(state_dot)
        self._apply_border()

    def mousePressEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()
        super().mousePressEvent(event)

    def set_selected(self, selected: bool) -> None:
        self._selected = selected
        self._apply_border()

    def _apply_border(self) -> None:
        if self._selected:
            self.setStyleSheet(
                f"RecipeSidebarCard {{ border: 2px solid {ACCENT_COPPER}; border-radius: 6px; }}"
            )
        else:
            self.setStyleSheet(
                "RecipeSidebarCard { border: 1px solid rgba(255,255,255,0.08); border-radius: 6px; }"
            )
