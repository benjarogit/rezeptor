"""Medizin — lasting per-recipe options (not one-shot install actions)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QLabel,
    QVBoxLayout,
    QWidget,
)

from i18n import get_locale, t
from recipe_options import (
    RecipeOption,
    read_option_values,
    write_option_value,
)
from ui_fluent import FLUENT_AVAILABLE
from ui_styles import palette


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
        self.setModal(True)
        self.setMinimumWidth(420)
        self._data_root = data_root
        self._options = options
        self._needs_repair_hint = False
        theme = "dark"
        muted = palette(theme)["muted"]

        lay = QVBoxLayout(self)
        lay.setSpacing(12)

        intro = QLabel(t("medizin.dialog_intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        self._style_muted(intro, muted)
        lay.addWidget(intro)

        values = read_option_values(data_root, options)
        locale = get_locale()
        self._boxes: list[tuple[RecipeOption, QCheckBox]] = []

        for opt in options:
            block = QVBoxLayout()
            block.setSpacing(4)
            cb = QCheckBox(opt.label_for(locale))
            cb.setChecked(bool(values.get(opt.id, opt.default)))
            cb.toggled.connect(
                lambda checked, o=opt: self._on_toggle(o, checked)
            )
            tip = QLabel(opt.tip_for(locale) or "")
            tip.setWordWrap(True)
            tip.setObjectName("muted")
            self._style_muted(tip, muted)
            tip.setContentsMargins(22, 0, 0, 8)
            block.addWidget(cb)
            if tip.text().strip():
                block.addWidget(tip)
            wrap = QWidget()
            wrap.setLayout(block)
            lay.addWidget(wrap)
            self._boxes.append((opt, cb))

        self._hint = QLabel("")
        self._hint.setWordWrap(True)
        self._hint.setObjectName("muted")
        self._style_muted(self._hint, muted)
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

    @staticmethod
    def _style_muted(label: QLabel, color: str) -> None:
        label.setStyleSheet(f"color: {color}; font-size: 12px;")

    def _on_toggle(self, opt: RecipeOption, checked: bool) -> None:
        write_option_value(self._data_root, opt, checked)
        if opt.env == "PREMIERE_NVIDIA_LIBS":
            self._needs_repair_hint = True
            self._hint.setText(t("medizin.apply_repair_hint"))
            self._hint.setVisible(True)

    @property
    def needs_repair_hint(self) -> bool:
        return self._needs_repair_hint
