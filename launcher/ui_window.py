"""Fenster-Hilfen: Taskleisten-Schließbarkeit + Geometrie speichern/laden."""

from __future__ import annotations

import base64
from typing import Literal

from PyQt6.QtCore import QByteArray, Qt
from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QApplication, QDialog, QMessageBox, QSplitter, QWidget

from i18n import t

UnsavedChoice = Literal["save", "discard", "cancel"]


def confirm_unsaved_changes(
    parent: QWidget | None,
    *,
    title: str = "",
    body: str = "",
) -> UnsavedChoice:
    """Speichern / Schließen ohne Speichern / Abbrechen."""
    box = QMessageBox(parent)
    box.setIcon(QMessageBox.Icon.Warning)
    box.setWindowTitle(title or t("dialog.unsaved_title"))
    box.setText(body or t("dialog.unsaved_body"))
    save_btn = box.addButton(
        t("dialog.unsaved_save"), QMessageBox.ButtonRole.AcceptRole
    )
    discard_btn = box.addButton(
        t("dialog.unsaved_discard"), QMessageBox.ButtonRole.DestructiveRole
    )
    box.addButton(t("dialog.unsaved_cancel"), QMessageBox.ButtonRole.RejectRole)
    box.setDefaultButton(save_btn)
    box.exec()
    clicked = box.clickedButton()
    if clicked is save_btn:
        return "save"
    if clicked is discard_btn:
        return "discard"
    return "cancel"


def geometry_to_b64(widget: QWidget) -> str:
    raw = bytes(widget.saveGeometry())
    if not raw:
        return ""
    return base64.b64encode(raw).decode("ascii")


def restore_geometry(widget: QWidget, b64: str) -> bool:
    text = (b64 or "").strip()
    if not text:
        return False
    try:
        data = QByteArray(base64.b64decode(text))
    except Exception:
        return False
    if data.isEmpty():
        return False
    return bool(widget.restoreGeometry(data))


def splitter_to_b64(splitter: QSplitter) -> str:
    raw = bytes(splitter.saveState())
    if not raw:
        return ""
    return base64.b64encode(raw).decode("ascii")


def restore_splitter(splitter: QSplitter, b64: str) -> bool:
    text = (b64 or "").strip()
    if not text:
        return False
    try:
        data = QByteArray(base64.b64decode(text))
    except Exception:
        return False
    if data.isEmpty():
        return False
    return bool(splitter.restoreState(data))


def apply_tool_window(
    widget: QWidget,
    *,
    icon: QIcon | None = None,
    modal: bool = False,
    delete_on_close: bool | None = None,
) -> None:
    """Eigenständiges Fenster: Taskleisten-Eintrag, Schließen per RMB funktioniert.

    Parent-modale Dialoge ohne Window-Flag fehlen oft in der Taskleiste und
    blockieren „Schließen“ am Hauptfenster.

    WA_DeleteOnClose: nur bei nicht-modalen show()-Fenstern (default).
    Bei modal=True + exec() muss das Objekt nach return noch lesbar sein
    (Geometrie, result_settings) — sonst RuntimeError/SIGABRT.
    """
    flags = (
        Qt.WindowType.Window
        | Qt.WindowType.WindowTitleHint
        | Qt.WindowType.WindowSystemMenuHint
        | Qt.WindowType.WindowMinMaxButtonsHint
        | Qt.WindowType.WindowCloseButtonHint
    )
    widget.setWindowFlags(flags)
    # Taskleisten-Schließen beendet nur dieses Fenster; App-Quit über Hauptfenster.
    if delete_on_close is None:
        delete_on_close = not modal
    widget.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose, delete_on_close)
    if icon is not None and not icon.isNull():
        widget.setWindowIcon(icon)
    if isinstance(widget, QDialog):
        widget.setWindowModality(
            Qt.WindowModality.WindowModal if modal else Qt.WindowModality.NonModal
        )
        widget.setSizeGripEnabled(True)
    # Nie kleiner als schon gesetztes Minimum (Settings/Rezept-View sonst gequetscht).
    floor_w, floor_h = 480, 360
    cur = widget.minimumSize()
    widget.setMinimumSize(max(floor_w, cur.width()), max(floor_h, cur.height()))
    # __init__-resize als Standard halten (WM/adjustSize darf nicht dauerhaft schrumpfen).
    ensure_usable_size(
        widget,
        min_w=widget.minimumWidth(),
        min_h=widget.minimumHeight(),
        default_w=max(widget.width(), widget.minimumWidth()),
        default_h=max(widget.height(), widget.minimumHeight()),
    )


def _available_screen_size(widget: QWidget) -> tuple[int, int]:
    screen = widget.screen()
    if screen is None:
        app = QApplication.instance()
        screen = app.primaryScreen() if app is not None else None
    if screen is None:
        return 1600, 900
    ag = screen.availableGeometry()
    return max(640, ag.width() - 48), max(480, ag.height() - 48)


def ensure_usable_size(
    widget: QWidget,
    *,
    min_w: int = 520,
    min_h: int = 360,
    default_w: int | None = None,
    default_h: int | None = None,
) -> None:
    """Mindestgröße + Standard; sizeHint als Wunschgröße, nicht als harte Min."""
    floor_w = max(min_w, widget.minimumWidth())
    floor_h = max(min_h, widget.minimumHeight())
    widget.setMinimumSize(floor_w, floor_h)

    hint = widget.sizeHint()
    hint_w = hint.width() if hint.isValid() else 0
    hint_h = hint.height() if hint.isValid() else 0
    max_w, max_h = _available_screen_size(widget)
    want_w = max(widget.width(), floor_w, default_w or 0, hint_w)
    want_h = max(widget.height(), floor_h, default_h or 0, hint_h)
    want_w = min(want_w, max_w)
    want_h = min(want_h, max_h)
    if widget.width() != want_w or widget.height() != want_h:
        widget.resize(want_w, want_h)


def clamp_restored_geometry(
    widget: QWidget, *, min_w: int = 520, min_h: int = 360
) -> None:
    """Nach restoreGeometry: zu kleine Fenster auf nutzbare Größe anheben."""
    ensure_usable_size(widget, min_w=min_w, min_h=min_h)


def ensure_on_screen(widget: QWidget) -> None:
    """Fenster sichtbar im verfügbaren Bildschirm halten (Wayland/Multi-Monitor)."""
    screen = widget.screen()
    if screen is None:
        app = QApplication.instance()
        screen = app.primaryScreen() if app is not None else None
    if screen is None:
        return
    ag = screen.availableGeometry()
    g = widget.frameGeometry() if widget.isWindow() else widget.geometry()
    w = min(max(widget.width(), widget.minimumWidth()), ag.width())
    h = min(max(widget.height(), widget.minimumHeight()), ag.height())
    x = g.x()
    y = g.y()
    if x + w < ag.left() + 40 or x > ag.right() - 40:
        x = ag.left() + max(0, (ag.width() - w) // 2)
    if y + h < ag.top() + 40 or y > ag.bottom() - 40:
        y = ag.top() + max(0, (ag.height() - h) // 2)
    x = max(ag.left(), min(x, ag.right() - w))
    y = max(ag.top(), min(y, ag.bottom() - h))
    widget.setGeometry(x, y, w, h)
