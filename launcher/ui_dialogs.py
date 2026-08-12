"""QMessageBox helpers using Font Awesome icons (not Qt stock glyphs)."""

from __future__ import annotations

from PyQt6.QtWidgets import QMessageBox, QWidget

from ui_icons import fa_icon

_FA_KIND = {
    QMessageBox.Icon.Information: "info",
    QMessageBox.Icon.Warning: "warn",
    QMessageBox.Icon.Critical: "error",
    QMessageBox.Icon.Question: "question",
}


def apply_fa_message_icon(
    box: QMessageBox,
    kind: str | QMessageBox.Icon,
    *,
    pixel: int = 48,
) -> None:
    """Replace Qt stock message icons with Font Awesome Free glyphs."""
    if isinstance(kind, QMessageBox.Icon):
        if kind == QMessageBox.Icon.NoIcon:
            box.setIcon(QMessageBox.Icon.NoIcon)
            return
        kind = _FA_KIND.get(kind, "info")
    icon = fa_icon(kind, pixel)
    box.setIcon(QMessageBox.Icon.NoIcon)
    if icon is not None:
        box.setIconPixmap(icon.pixmap(pixel, pixel))


def ask_yes_no(
    parent: QWidget | None,
    title: str,
    text: str,
    *,
    default_yes: bool = True,
    icon: str = "question",
) -> bool:
    box = QMessageBox(parent)
    apply_fa_message_icon(box, icon)
    box.setWindowTitle(title)
    box.setText(text)
    box.setStandardButtons(
        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
    )
    box.setDefaultButton(
        QMessageBox.StandardButton.Yes
        if default_yes
        else QMessageBox.StandardButton.No
    )
    return box.exec() == QMessageBox.StandardButton.Yes


def show_information(parent: QWidget | None, title: str, text: str) -> None:
    box = QMessageBox(parent)
    apply_fa_message_icon(box, "info")
    box.setWindowTitle(title)
    box.setText(text)
    box.setStandardButtons(QMessageBox.StandardButton.Ok)
    box.exec()


def show_warning(parent: QWidget | None, title: str, text: str) -> None:
    box = QMessageBox(parent)
    apply_fa_message_icon(box, "warn")
    box.setWindowTitle(title)
    box.setText(text)
    box.setStandardButtons(QMessageBox.StandardButton.Ok)
    box.exec()


def show_critical(parent: QWidget | None, title: str, text: str) -> None:
    box = QMessageBox(parent)
    apply_fa_message_icon(box, "error")
    box.setWindowTitle(title)
    box.setText(text)
    box.setStandardButtons(QMessageBox.StandardButton.Ok)
    box.exec()
