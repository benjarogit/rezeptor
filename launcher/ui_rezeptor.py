"""Rezeptor — Marken-Widgets (Fluent + Fallback)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import QPoint, QSize, Qt, pyqtSignal
from PyQt6.QtGui import QFontMetrics, QIcon, QKeyEvent, QResizeEvent
from PyQt6.QtWidgets import (
    QApplication,
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

from ui_fluent import (
    ACCENT_COPPER,
    COLOR_EXPERIMENTAL,
    COLOR_PARCHMENT,
    COLOR_TESTED,
    FLUENT_AVAILABLE,
    MUTED,
    IconWidget,
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
    "checking": "#9ca3af",
    "running": "#3ddc84",
}

_STATE_TIP_KEYS = {
    "installed": "state.installed_tip",
    "partial": "state.partial_tip",
    "not_installed": "state.not_installed_tip",
    "untrusted": "state.untrusted_tip",
    "checking": "state.checking_tip",
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
        # Reset caps from a previous open (otherwise popup can glue/clip oddly)
        view.setMinimumHeight(0)
        view.setMaximumHeight(16777215)
        parent = view.parentWidget()
        if parent is not None:
            parent.setMinimumHeight(0)
            parent.setMaximumHeight(16777215)
        row = view.sizeHintForRow(0)
        if row <= 0:
            fm = self.fontMetrics()
            row = max(28, fm.height() + 10)
        # Exakte Höhe der sichtbaren Zeilen
        height = n * row + 8
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

    def hidePopup(self) -> None:
        view = self.view()
        view.setMinimumHeight(0)
        view.setMaximumHeight(16777215)
        parent = view.parentWidget()
        if parent is not None:
            parent.setMinimumHeight(0)
            parent.setMaximumHeight(16777215)
        super().hidePopup()


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
    padding: 8px 4px 2px 4px;
    background-color: transparent;
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


class ElidedLabel(QLabel):
    """Single-line label that shrinks inside the sidebar and shows full text as tip."""

    def __init__(self, text: str = "", parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._full = text
        self.setWordWrap(False)
        self.setMinimumWidth(0)
        self.setSizePolicy(
            QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred
        )
        self.setToolTip(text)
        self._apply_elide()

    def full_text(self) -> str:
        return self._full

    def set_full_text(self, text: str) -> None:
        self._full = text or ""
        self.setToolTip(self._full)
        self._apply_elide()

    def resizeEvent(self, event: QResizeEvent) -> None:  # noqa: N802
        super().resizeEvent(event)
        self._apply_elide()

    def _apply_elide(self) -> None:
        width = max(0, self.width())
        if width <= 0:
            self.setText(self._full)
            return
        elided = QFontMetrics(self.font()).elidedText(
            self._full, Qt.TextElideMode.ElideRight, width
        )
        # Avoid feedback loops when text is unchanged
        if elided != self.text():
            self.setText(elided)


class SidebarCategoryHeader(ElidedLabel):
    """Category label in the sidebar — drop target for cross-category moves."""

    def __init__(self, category: str, parent: QWidget | None = None) -> None:
        super().__init__(category.upper(), parent)
        self.category = category
        self.setObjectName("sidebarCategory")
        self.setProperty("dropInsert", "")
        self.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )

    def set_drop_highlight(self, on: bool) -> None:
        self.setProperty("dropInsert", "header" if on else "")
        if on:
            self.setStyleSheet(
                f"QLabel#sidebarCategory {{ color: {ACCENT_COPPER};"
                f" border-bottom: 2px solid {ACCENT_COPPER}; padding-bottom: 2px;"
                f" background-color: transparent; }}"
            )
        else:
            self.setStyleSheet("")


class RecipeSidebarCard(QFrame):
    """Kompakter Rezept-Eintrag — Details im Hauptbereich.

    Reorder uses grabMouse (not QDrag): Wayland/Plasma often drops
    in-window QDrag silently; context menu Nach oben/unten remains fallback.
    Cross-category drop sets a user override (settings), not recipe.yml.
    """

    clicked = pyqtSignal()
    contextMenuRequested = pyqtSignal()
    # source_id, target_id, place ("before" | "after")
    reorderRequested = pyqtSignal(str, str, str)
    # source_id, category_name — drop on category header
    categoryDropRequested = pyqtSignal(str, str)

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
        self._press_pos = QPoint()
        self._press_armed = False
        self._dragging = False
        self._hover_target: RecipeSidebarCard | None = None
        self._hover_header: SidebarCategoryHeader | None = None
        self._insert_place: str = ""  # before | after
        self.setObjectName("RecipeSidebarCard")
        self.setFixedHeight(42)
        self.setMinimumWidth(0)
        self.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setMouseTracking(True)
        self._card_name = name
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self._set_a11y(name, state)
        self.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.customContextMenuRequested.connect(lambda _pos: self.contextMenuRequested.emit())
        self._selected = False
        self._running = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 6, 10, 6)
        layout.setSpacing(8)

        def _pass_mouse(w: QWidget) -> QWidget:
            w.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
            return w

        if FLUENT_AVAILABLE and icon is not None and not icon.isNull():
            iw = _pass_mouse(IconWidget(icon, self))
            iw.setFixedSize(20, 20)
            layout.addWidget(iw)
        else:
            dot = _pass_mouse(QLabel("●", self))
            dot.setFixedWidth(16)
            layout.addWidget(dot)

        # Plain ElidedLabel — Fluent StrongBodyLabel ignores shrink/elide in the list.
        title = _pass_mouse(ElidedLabel(name, self))
        title.setObjectName("sidebarCardTitle")
        title.setStyleSheet(
            "background: transparent; color: #EDE6D6; font-weight: 600;"
        )
        self._title = title
        layout.addWidget(title, stretch=1)

        self._run_dot = _pass_mouse(QLabel("●", self))
        self._run_dot.setFixedWidth(12)
        self._run_dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._run_dot.setStyleSheet(
            f"color: {STATE_DOT['running']}; font-size: 10px;"
        )
        self._run_dot.setToolTip(t("state.running"))
        self._run_dot.setVisible(False)
        layout.addWidget(self._run_dot)

        self._state_dot = _pass_mouse(QLabel("●", self))
        self._state_dot.setFixedWidth(12)
        self._state_dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._state_dot.setStyleSheet(
            f"color: {STATE_DOT.get(state, STATE_DOT['unknown'])}; font-size: 10px;"
        )
        self._state_dot.setToolTip(_state_tip(state))
        layout.addWidget(self._state_dot)
        self._theme: str = "dark"
        self._apply_border()

    def _set_a11y(self, name: str, state: str) -> None:
        tip = _state_tip(state)
        self.setAccessibleName(f"{name}, {tip}" if tip else name)
        self.setAccessibleDescription(tip)

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter, Qt.Key.Key_Space):
            self.clicked.emit()
            event.accept()
            return
        if event.key() in (Qt.Key.Key_Up, Qt.Key.Key_Down):
            parent = self.parentWidget()
            if parent is not None:
                cards = [
                    w
                    for w in parent.findChildren(RecipeSidebarCard)
                    if w.isVisible()
                ]
                if self in cards:
                    idx = cards.index(self)
                    nxt = idx - 1 if event.key() == Qt.Key.Key_Up else idx + 1
                    if 0 <= nxt < len(cards):
                        cards[nxt].setFocus(Qt.FocusReason.TabFocusReason)
                        cards[nxt].clicked.emit()
                        event.accept()
                        return
        super().keyPressEvent(event)

    def mousePressEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.button() == Qt.MouseButton.LeftButton:
            self._press_pos = event.position().toPoint()
            self._press_armed = True
            self._dragging = False
            self._clear_hover_target()
        elif event.button() == Qt.MouseButton.RightButton:
            self.contextMenuRequested.emit()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if self._press_armed and event.buttons() & Qt.MouseButton.LeftButton:
            dist = (event.position().toPoint() - self._press_pos).manhattanLength()
            threshold = max(8, QApplication.startDragDistance())
            if not self._dragging and dist >= threshold and self._recipe_id:
                self._dragging = True
                self.grabMouse()
                self.setCursor(Qt.CursorShape.ClosedHandCursor)
                self.setProperty("dragging", True)
                self._apply_border()
            if self._dragging:
                self._update_hover_target(event.globalPosition().toPoint())
                return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.button() == Qt.MouseButton.LeftButton:
            was_dragging = self._dragging
            target = self._hover_target
            header = self._hover_header
            place = self._insert_place or "before"
            self._clear_hover_target()
            if self._dragging:
                self.releaseMouse()
                self.setCursor(Qt.CursorShape.PointingHandCursor)
            self.setProperty("dragging", False)
            self._dragging = False
            self._press_armed = False
            self._apply_border()
            if was_dragging:
                if header is not None and header.category:
                    self.categoryDropRequested.emit(self._recipe_id, header.category)
                elif (
                    target is not None
                    and target is not self
                    and target._recipe_id
                    and target._recipe_id != self._recipe_id
                    and place in ("before", "after")
                ):
                    self.reorderRequested.emit(
                        self._recipe_id, target._recipe_id, place
                    )
            else:
                self.clicked.emit()
        super().mouseReleaseEvent(event)

    def _update_hover_target(self, global_pos: QPoint) -> None:
        widget = QApplication.widgetAt(global_pos)
        card: RecipeSidebarCard | None = None
        header: SidebarCategoryHeader | None = None
        walk = widget
        while walk is not None:
            if isinstance(walk, RecipeSidebarCard):
                card = walk
                break
            if isinstance(walk, SidebarCategoryHeader):
                header = walk
                break
            walk = walk.parentWidget()

        place = ""
        if card is self:
            card = None
        elif card is not None:
            local_y = card.mapFromGlobal(global_pos).y()
            place = "before" if local_y < card.height() / 2 else "after"
            header = None
        elif header is not None:
            place = "header"

        if (
            card is self._hover_target
            and header is self._hover_header
            and place == self._insert_place
        ):
            return

        self._clear_hover_target()
        self._hover_target = card
        self._hover_header = header
        self._insert_place = place
        if card is not None and place in ("before", "after"):
            card.setProperty("dropInsert", place)
            card._apply_border()
        elif header is not None:
            header.set_drop_highlight(True)

    def _clear_hover_target(self) -> None:
        if self._hover_target is not None:
            self._hover_target.setProperty("dropInsert", "")
            self._hover_target._apply_border()
            self._hover_target = None
        if self._hover_header is not None:
            self._hover_header.set_drop_highlight(False)
            self._hover_header = None
        self._insert_place = ""

    def set_selected(self, selected: bool) -> None:
        self._selected = selected
        self._apply_border()

    def set_running(self, running: bool) -> None:
        self._running = running
        self._run_dot.setVisible(running)
        self._state_dot.setVisible(not running)

    def set_install_state(self, state: str) -> None:
        self._state_dot.setStyleSheet(
            f"color: {STATE_DOT.get(state, STATE_DOT['unknown'])}; font-size: 10px;"
        )
        self._state_dot.setToolTip(_state_tip(state))
        self._state_dot.setVisible(not self._running)
        self._set_a11y(self._card_name, state)

    def apply_theme(self, theme: str = "dark") -> None:
        self._theme = theme
        self._apply_border()

    def sizeHint(self) -> QSize:  # noqa: N802
        # Don't expand the scroll host to the full unelided title width.
        return QSize(0, 42)

    def minimumSizeHint(self) -> QSize:  # noqa: N802
        return QSize(0, 42)

    def _apply_border(self) -> None:
        insert = str(self.property("dropInsert") or "")
        dragging = bool(self.property("dragging"))
        if insert == "before":
            self.setStyleSheet(
                f"#RecipeSidebarCard {{ background: rgba(255,255,255,0.06);"
                f" border: 1px solid rgba(255,255,255,0.08); border-radius: 6px;"
                f" border-top: 3px solid {ACCENT_COPPER}; }}"
            )
        elif insert == "after":
            self.setStyleSheet(
                f"#RecipeSidebarCard {{ background: rgba(255,255,255,0.06);"
                f" border: 1px solid rgba(255,255,255,0.08); border-radius: 6px;"
                f" border-bottom: 3px solid {ACCENT_COPPER}; }}"
            )
        elif dragging:
            self.setStyleSheet(
                "#RecipeSidebarCard { background: rgba(255,255,255,0.02);"
                " border: 1px dashed rgba(255,255,255,0.35); border-radius: 6px; }"
            )
        elif self._selected:
            self.setStyleSheet(
                f"#RecipeSidebarCard {{ background: rgba(255,255,255,0.06);"
                f" border: 2px solid {ACCENT_COPPER}; border-radius: 6px; }}"
            )
        else:
            self.setStyleSheet(
                "#RecipeSidebarCard { background: rgba(255,255,255,0.04);"
                " border: 1px solid rgba(255,255,255,0.08); border-radius: 6px; }"
            )
