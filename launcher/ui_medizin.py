"""Medizin — lasting per-recipe options (not one-shot install actions)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QCloseEvent
from PyQt6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QLabel,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from i18n import get_locale, t
from recipe_options import (
    RecipeOption,
    migrate_photoshop_windows_like_ui,
    read_option_values,
    write_option_value,
)
from ui_fluent import FLUENT_AVAILABLE
from ui_styles import MUTED, style_status_label
from ui_window import mark_force_close, mark_user_dismiss


# Options that need Repair after toggle (prefix/prefs already written).
_REPAIR_AFTER = frozenset(
    {
        "PREMIERE_NVIDIA_LIBS",
        "PHOTOSHOP_GENP_ON_REPAIR",
        "PHOTOSHOP_WINDOWS_LIKE_UI",
        "PHOTOSHOP_UI_HOME_SCREEN",
        "PHOTOSHOP_UI_RICH_TOOLTIPS",
        "PHOTOSHOP_UI_MODERN_NEW",
        "HALO_GOLDBERG_EMU",
    }
)


class MedizinDialog(QDialog):
    """Show recipe options with always-visible explanations (no menu tooltips)."""

    def __init__(
        self,
        options: list[RecipeOption],
        data_root: Path,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(t("medizin.dialog_title"))
        # Modalität/Taskleiste setzt apply_tool_window(compact=True) im Launcher.
        self.setMinimumWidth(400)
        self.setMaximumWidth(560)
        self._data_root = data_root
        self._options = options
        self._needs_repair_hint = False

        lay = QVBoxLayout(self)
        lay.setContentsMargins(16, 12, 16, 12)
        lay.setSpacing(8)

        intro = QLabel(t("medizin.dialog_intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        intro.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self._style_muted(intro)
        lay.addWidget(intro)

        migrate_photoshop_windows_like_ui(data_root)
        values = read_option_values(data_root, options)
        locale = get_locale()
        self._boxes: list[tuple[RecipeOption, QCheckBox]] = []

        for opt in options:
            block = QVBoxLayout()
            block.setSpacing(2)
            block.setContentsMargins(0, 0, 0, 0)
            cb = QCheckBox(opt.label_for(locale))
            cb.setChecked(bool(values.get(opt.id, opt.default)))
            cb.toggled.connect(
                lambda checked, o=opt: self._on_toggle(o, checked)
            )
            tip = QLabel(opt.tip_for(locale) or "")
            tip.setWordWrap(True)
            tip.setObjectName("muted")
            tip.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
            )
            self._style_muted(tip)
            tip.setContentsMargins(22, 0, 0, 4)
            block.addWidget(cb)
            if tip.text().strip():
                block.addWidget(tip)
            wrap = QWidget()
            wrap.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
            )
            wrap.setLayout(block)
            lay.addWidget(wrap)
            self._boxes.append((opt, cb))

        self._hint = QLabel("")
        self._hint.setWordWrap(True)
        self._hint.setObjectName("statusHint")
        self._hint.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self._hint.setVisible(False)
        lay.addWidget(self._hint)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        close_btn = buttons.button(QDialogButtonBox.StandardButton.Close)
        if close_btn is not None:
            close_btn.setText(t("medizin.close"))
            close_btn.clicked.connect(self.accept)
        lay.addWidget(buttons)

        if FLUENT_AVAILABLE:
            self.setObjectName("medizinDialog")

        # An Inhalt anpassen — apply_tool_window(compact) hält das Minimum klein
        self.adjustSize()
        hint = self.sizeHint()
        if hint.isValid():
            self.resize(
                max(400, min(hint.width() + 8, 560)),
                max(hint.height(), 120),
            )
            self.setMinimumHeight(min(hint.height(), 200))

    @staticmethod
    def _style_muted(label: QLabel) -> None:
        label.setStyleSheet(f"color: {MUTED}; font-size: 12px; background: transparent;")

    def _set_status(self, text: str, kind: str) -> None:
        self._hint.setText(text)
        style_status_label(self._hint, kind)
        self._hint.setVisible(bool(text.strip()))

    def _on_toggle(self, opt: RecipeOption, checked: bool) -> None:
        try:
            write_option_value(self._data_root, opt, checked)
        except OSError as exc:
            self._set_status(
                t("medizin.error_body", error=str(exc)),
                "error",
            )
            return
        if opt.env in _REPAIR_AFTER:
            self._needs_repair_hint = True
            self._set_status(t("medizin.apply_repair_hint"), "warn")
        else:
            self._set_status(t("medizin.saved_ok"), "ok")

    @property
    def needs_repair_hint(self) -> bool:
        return self._needs_repair_hint

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

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        if getattr(self, "_rezeptor_force_close", False) or self.property(
            "rezeptor_force_close"
        ):
            super().closeEvent(event)
            return
        mark_user_dismiss(self)
        super().closeEvent(event)
