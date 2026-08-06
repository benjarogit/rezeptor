"""Steam-medicine hint when a recipe is selected (Steam present, option off)."""

from __future__ import annotations

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QShowEvent
from PyQt6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QLabel,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from i18n import t
from ui_window import mark_force_close, mark_user_dismiss


class SteamMedicineHintDialog(QDialog):
    """Inform user that Steam was detected and Steam medicine is recommended."""

    def __init__(self, recipe_name: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle(t("steam_medicine.dialog_title"))
        self.setMinimumWidth(460)
        self.setMaximumWidth(580)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(14)

        self._body = QLabel(
            t(
                "steam_medicine.dialog_body",
                name=recipe_name or "?",
            )
        )
        self._body.setWordWrap(True)
        self._body.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        self._body.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        layout.addWidget(self._body)

        self._dont_show = QCheckBox(t("steam_medicine.dont_show_again"))
        self._dont_show.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        layout.addWidget(self._dont_show)

        buttons = QDialogButtonBox()
        self._open_btn = buttons.addButton(
            t("steam_medicine.open_medizin"),
            QDialogButtonBox.ButtonRole.AcceptRole,
        )
        self._ok_btn = buttons.addButton(
            t("steam_medicine.ok"),
            QDialogButtonBox.ButtonRole.RejectRole,
        )
        layout.addWidget(buttons)
        self._open_btn.clicked.connect(self.accept)
        self._ok_btn.clicked.connect(self.reject)

        self._fit_body_height()

    def _fit_body_height(self) -> None:
        """Word-wrapped QLabel needs an explicit height or the last lines clip."""
        w = max(self.width(), self.minimumWidth()) - 32
        if w < 200:
            w = 428
        self._body.setFixedWidth(w)
        h = self._body.heightForWidth(w)
        if h > 0:
            self._body.setMinimumHeight(h)
        self.adjustSize()
        hint = self.sizeHint()
        self.setMinimumHeight(max(hint.height(), 260))
        self.resize(max(hint.width(), 480), max(hint.height(), 280))

    def showEvent(self, event: QShowEvent) -> None:  # noqa: N802
        super().showEvent(event)
        self._fit_body_height()

    def resizeEvent(self, event) -> None:  # noqa: N802, ANN001
        super().resizeEvent(event)
        w = max(self.width() - 32, 200)
        self._body.setFixedWidth(w)
        h = self._body.heightForWidth(w)
        if h > 0:
            self._body.setMinimumHeight(h)

    @property
    def dont_show_again(self) -> bool:
        return self._dont_show.isChecked()

    def accept(self) -> None:
        mark_user_dismiss(self)
        super().accept()

    def reject(self) -> None:
        if getattr(self, "_rezeptor_force_close", False) or self.property(
            "rezeptor_force_close"
        ):
            super().reject()
            return
        mark_user_dismiss(self)
        super().reject()

    def force_close(self) -> None:
        mark_force_close(self)
        self.done(QDialog.DialogCode.Rejected)
