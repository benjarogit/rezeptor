"""Fenster-Hilfen: Taskleisten-Schließbarkeit + Geometrie speichern/laden."""

from __future__ import annotations

import base64

from PyQt6.QtCore import QByteArray, Qt
from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QDialog, QSplitter, QWidget


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
) -> None:
    """Eigenständiges Fenster: Taskleisten-Eintrag, Schließen per RMB funktioniert.

    Parent-modale Dialoge ohne Window-Flag fehlen oft in der Taskleiste und
    blockieren „Schließen“ am Hauptfenster.
    """
    flags = (
        Qt.WindowType.Window
        | Qt.WindowType.WindowTitleHint
        | Qt.WindowType.WindowSystemMenuHint
        | Qt.WindowType.WindowMinMaxButtonsHint
        | Qt.WindowType.WindowCloseButtonHint
    )
    widget.setWindowFlags(flags)
    if icon is not None and not icon.isNull():
        widget.setWindowIcon(icon)
    if isinstance(widget, QDialog):
        widget.setWindowModality(
            Qt.WindowModality.WindowModal if modal else Qt.WindowModality.NonModal
        )
        widget.setSizeGripEnabled(True)
    widget.setMinimumSize(420, 320)
