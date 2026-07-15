"""Rezeptor — Marken-Widgets (Fluent + Fallback)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import QMimeData, QPoint, Qt, pyqtSignal
from PyQt6.QtGui import QDrag, QFont, QIcon
from PyQt6.QtWidgets import (
    QButtonGroup,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

RECIPE_MIME = "application/x-rezeptor-recipe-id"

from ui_fluent import (
    ACCENT_COPPER,
    COLOR_EXPERIMENTAL,
    COLOR_PARCHMENT,
    COLOR_TESTED,
    FLUENT_AVAILABLE,
    MUTED,
    CaptionLabel,
    CardWidget,
    IconWidget,
    StrongBodyLabel,
)
from ui_icons import ensure_chevron_png
from i18n import t

ROOT = Path(__file__).resolve().parent.parent
REZEPTOR_ICON = ROOT / "images" / "rezeptor-icon.svg"
REZEPTOR_WORDMARK = ROOT / "images" / "rezeptor-wordmark.svg"

STATE_DOT = {
    "installed": COLOR_TESTED,
    "partial": COLOR_EXPERIMENTAL,
    "not_installed": "#6b7280",
    "unknown": "#6b7280",
    "untrusted": "#d9a441",
    "running": "#3ddc84",
}

_STATE_TIP_KEYS = {
    "installed": "state.installed_tip",
    "partial": "state.partial_tip",
    "not_installed": "state.not_installed_tip",
    "untrusted": "state.untrusted_tip",
}


def _state_tip(state: str) -> str:
    return t(_STATE_TIP_KEYS.get(state, "state.unknown"))


class LimitedComboBox(QComboBox):
    """QComboBox mit harter Popup-Höhe.

    setMaxVisibleItems allein greift unter Fusion+QSS oft nicht — deshalb
    View + Container in showPopup() begrenzen.
    """

    def __init__(
        self,
        parent: QWidget | None = None,
        *,
        max_visible: int = 12,
    ) -> None:
        super().__init__(parent)
        self._max_visible = max(1, int(max_visible))
        self.setMaxVisibleItems(self._max_visible)
        view = self.view()
        view.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        view.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self._apply_arrow_style()

    def _apply_arrow_style(self) -> None:
        """Pfeil explizit setzen — App-QSS allein reicht unter Fusion oft nicht."""
        arrow = ensure_chevron_png("down", COLOR_PARCHMENT).resolve().as_posix()
        self.setStyleSheet(
            f"""
            QComboBox {{
                background-color: rgba(255, 255, 255, 0.06);
                border: 1px solid #3A3A3A;
                border-radius: 4px;
                padding: 6px 28px 6px 10px;
                color: {COLOR_PARCHMENT};
                min-height: 20px;
            }}
            QComboBox:hover {{
                border-color: rgba(184, 115, 51, 0.55);
            }}
            QComboBox:focus, QComboBox:on {{
                border-color: {ACCENT_COPPER};
            }}
            QComboBox::drop-down {{
                subcontrol-origin: padding;
                subcontrol-position: center right;
                width: 22px;
                border: none;
                background: transparent;
            }}
            QComboBox::down-arrow {{
                image: url("{arrow}");
                width: 12px;
                height: 12px;
            }}
            """
        )

    def showPopup(self) -> None:
        n = min(self._max_visible, max(self.count(), 1))
        view = self.view()
        row = view.sizeHintForRow(0)
        if row <= 0:
            fm = self.fontMetrics()
            row = max(28, fm.height() + 10)
        # Exakte Höhe der sichtbaren Zeilen
        height = n * row + 8
        view.setMinimumHeight(0)
        view.setMaximumHeight(height)
        super().showPopup()
        # Popup-Frame (QComboBoxPrivateContainer) nach Shrink
        parent = view.parentWidget()
        if parent is not None:
            margins = parent.contentsMargins()
            extra = margins.top() + margins.bottom() + 4
            cap = height + extra
            parent.setMaximumHeight(cap)
            if parent.height() > cap:
                parent.resize(parent.width(), cap)


SEGMENT_TAB_STYLES = f"""
QFrame#segmentTabBar {{
    background-color: rgba(255, 255, 255, 0.03);
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}}
QPushButton#segmentTab {{
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 6px;
    color: {MUTED};
    font-size: 13px;
    font-weight: 500;
    padding: 6px 16px;
    min-height: 28px;
}}
QPushButton#segmentTab:hover {{
    background-color: rgba(255, 255, 255, 0.06);
    color: {COLOR_PARCHMENT};
    border-color: rgba(255, 255, 255, 0.1);
}}
QPushButton#segmentTab:checked {{
    background-color: rgba(184, 115, 51, 0.18);
    border-color: {ACCENT_COPPER};
    color: {COLOR_PARCHMENT};
    font-weight: 600;
}}
QLabel#sidebarCategory {{
    color: {MUTED};
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

    def set_labels(self, tabs: list[tuple[str, str]]) -> None:
        for key, label in tabs:
            btn = self._buttons.get(key)
            if btn is not None:
                btn.setText(label)

    def apply_theme(self, theme: str = "dark") -> None:
        _ = theme
        self.setStyleSheet(SEGMENT_TAB_STYLES)


class StatusPill(QLabel):
    """Inline Status-Badge (Getestet, Status, Autor, Runtime, …)."""

    clicked = pyqtSignal()

    def __init__(self, text: str, color: str, parent: QWidget | None = None) -> None:
        super().__init__(text, parent)
        self._color = color
        self.setVisible(bool(text.strip()))
        self.apply_theme("dark")

    def set_content(self, text: str, color: str | None = None) -> None:
        if color is not None:
            self._color = color
        self.setText(text)
        self.setVisible(bool((text or "").strip()))
        self.apply_theme("dark")

    def mouseReleaseEvent(self, event) -> None:  # noqa: ANN001
        if (
            event.button() == Qt.MouseButton.LeftButton
            and self.isVisible()
            and bool(self.text().strip())
        ):
            self.clicked.emit()
        super().mouseReleaseEvent(event)

    def apply_theme(self, theme: str = "dark") -> None:
        _ = theme
        # Fluent-ähnliche Surface: 6% Weiß-Overlay; Text Brand/Status
        color = (self._color or "").strip() or MUTED
        low = color.lower()
        if low in ("#9d9da6", "#a1a1aa", "#6b6b6b", "#6b7280", "#71717a", "#888888", "#c4c4cc", "#d4d4d8"):
            color = MUTED
        self.setStyleSheet(
            f"""
            QLabel {{
                color: {color};
                background-color: rgba(255, 255, 255, 0.0605);
                padding: 4px 10px;
                border-radius: 6px;
                font-size: 12px;
                font-weight: 500;
            }}
            """
        )


class RecipeSidebarCard(CardWidget):
    """Kompakter Rezept-Eintrag — Details im Hauptbereich."""

    clicked = pyqtSignal()
    contextMenuRequested = pyqtSignal()
    reorderRequested = pyqtSignal(str, str)  # source_id, target_id

    def __init__(
        self,
        name: str,
        state: str,
        icon: QIcon | None = None,
        parent: QWidget | None = None,
        *,
        recipe_id: str = "",
    ) -> None:
        super().__init__(parent)
        self._recipe_id = recipe_id
        self._drag_start = QPoint()
        self.setFixedHeight(42)
        self.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setAcceptDrops(True)
        self.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.customContextMenuRequested.connect(lambda _pos: self.contextMenuRequested.emit())
        self._selected = False
        self._running = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 6, 10, 6)
        layout.setSpacing(8)

        if FLUENT_AVAILABLE and icon is not None and not icon.isNull():
            iw = IconWidget(icon, self)
            iw.setFixedSize(20, 20)
            layout.addWidget(iw)
        else:
            dot = QLabel("●", self)
            dot.setFixedWidth(16)
            layout.addWidget(dot)

        title = StrongBodyLabel(name, self) if FLUENT_AVAILABLE else QLabel(name, self)
        title.setWordWrap(False)
        title.setObjectName("sidebarCardTitle")
        self._title = title
        layout.addWidget(title, stretch=1)

        self._run_dot = QLabel("●", self)
        self._run_dot.setFixedWidth(12)
        self._run_dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._run_dot.setStyleSheet(
            f"color: {STATE_DOT['running']}; font-size: 10px;"
        )
        self._run_dot.setToolTip(t("state.running"))
        self._run_dot.setVisible(False)
        layout.addWidget(self._run_dot)

        self._state_dot = QLabel("●", self)
        self._state_dot.setFixedWidth(12)
        self._state_dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._state_dot.setStyleSheet(
            f"color: {STATE_DOT.get(state, STATE_DOT['unknown'])}; font-size: 10px;"
        )
        self._state_dot.setToolTip(_state_tip(state))
        layout.addWidget(self._state_dot)
        self._theme: str = "dark"
        self._apply_border()

    def mousePressEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_start = event.position().toPoint()
            self.clicked.emit()
        elif event.button() == Qt.MouseButton.RightButton:
            self.contextMenuRequested.emit()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if (
            event.buttons() & Qt.MouseButton.LeftButton
            and self._recipe_id
            and (event.position().toPoint() - self._drag_start).manhattanLength() >= 8
        ):
            mime = QMimeData()
            mime.setData(RECIPE_MIME, self._recipe_id.encode("utf-8"))
            drag = QDrag(self)
            drag.setMimeData(mime)
            drag.exec(Qt.DropAction.MoveAction)
            return
        super().mouseMoveEvent(event)

    def dragEnterEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if self._can_accept_recipe_drop(event):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dragMoveEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if self._can_accept_recipe_drop(event):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        src = self._drop_source_id(event)
        if src and src != self._recipe_id:
            self.reorderRequested.emit(src, self._recipe_id)
            event.acceptProposedAction()
        else:
            event.ignore()

    def _can_accept_recipe_drop(self, event) -> bool:  # type: ignore[no-untyped-def]
        src = self._drop_source_id(event)
        return bool(src and src != self._recipe_id)

    @staticmethod
    def _drop_source_id(event) -> str:  # type: ignore[no-untyped-def]
        mime = event.mimeData()
        if mime is None or not mime.hasFormat(RECIPE_MIME):
            return ""
        raw = bytes(mime.data(RECIPE_MIME))
        return raw.decode("utf-8", errors="replace").strip()

    def set_selected(self, selected: bool) -> None:
        self._selected = selected
        self._apply_border()

    def set_running(self, running: bool) -> None:
        self._running = running
        # Nur ein Punkt rechts: hellgrün = läuft; sonst Install-Status
        self._run_dot.setVisible(running)
        self._state_dot.setVisible(not running)

    def set_install_state(self, state: str) -> None:
        self._state_dot.setStyleSheet(
            f"color: {STATE_DOT.get(state, STATE_DOT['unknown'])}; font-size: 10px;"
        )
        self._state_dot.setToolTip(_state_tip(state))
        self._state_dot.setVisible(not self._running)

    def apply_theme(self, theme: str = "dark") -> None:
        self._theme = theme
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
