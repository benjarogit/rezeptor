"""Rezeptor settings dialog."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from app_support import LOG_ROOT, log_dir_stats, prune_old_logs
from i18n import available_locales, t
from settings import RezeptorSettings, save_settings
from ui_rezeptor import LimitedComboBox


class SettingsDialog(QDialog):
    def __init__(self, parent: QWidget | None, settings: RezeptorSettings) -> None:
        super().__init__(parent)
        self._settings = settings
        self.setWindowTitle(t("settings.title"))
        self.resize(440, 300)
        self.setMinimumSize(360, 260)

        layout = QVBoxLayout(self)
        intro = QLabel(t("settings.intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        layout.addWidget(intro)

        form = QFormLayout()
        self.lang_combo = LimitedComboBox(max_visible=12)
        for lid, name in available_locales():
            self.lang_combo.addItem(name, lid)
        idx = self.lang_combo.findData(settings.locale)
        if idx < 0:
            idx = 0
        self.lang_combo.setCurrentIndex(idx)
        form.addRow(t("settings.language"), self.lang_combo)

        self.retention_spin = QSpinBox()
        self.retention_spin.setRange(1, 365)
        self.retention_spin.setValue(settings.log_retention_days)
        self.retention_spin.setSuffix(t("settings.days"))
        form.addRow(t("settings.retention"), self.retention_spin)

        self.max_files_spin = QSpinBox()
        self.max_files_spin.setRange(5, 500)
        self.max_files_spin.setValue(settings.log_max_files)
        form.addRow(t("settings.max_files"), self.max_files_spin)

        self.prune_startup = QCheckBox(t("settings.prune_startup"))
        self.prune_startup.setChecked(settings.prune_logs_on_startup)
        layout.addLayout(form)
        layout.addWidget(self.prune_startup)

        self.dev_mode = QCheckBox(t("settings.developer_mode"))
        self.dev_mode.setChecked(settings.developer_mode)
        self.dev_mode.setToolTip(t("settings.developer_mode_tip"))
        layout.addWidget(self.dev_mode)

        count, size = log_dir_stats()
        self.stats_label = QLabel(t("settings.stats", count=count, size=size))
        self.stats_label.setObjectName("muted")
        layout.addWidget(self.stats_label)

        cleanup_row = QHBoxLayout()
        cleanup_btn = QPushButton(t("settings.cleanup_btn"))
        cleanup_btn.clicked.connect(self._cleanup_now)
        cleanup_row.addWidget(cleanup_btn)
        cleanup_row.addStretch(1)
        layout.addLayout(cleanup_row)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._save)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _cleanup_now(self) -> None:
        removed = prune_old_logs(
            retention_days=self.retention_spin.value(),
            max_files=self.max_files_spin.value(),
        )
        count, size = log_dir_stats()
        self.stats_label.setText(t("settings.stats", count=count, size=size))
        QMessageBox.information(
            self,
            t("settings.cleanup_title"),
            t("settings.cleanup_body", removed=removed, count=count, size=size),
        )

    def _save(self) -> None:
        self._settings.log_retention_days = self.retention_spin.value()
        self._settings.log_max_files = self.max_files_spin.value()
        self._settings.prune_logs_on_startup = self.prune_startup.isChecked()
        self._settings.developer_mode = self.dev_mode.isChecked()
        lid = self.lang_combo.currentData()
        if lid:
            self._settings.locale = str(lid)
        self._settings.theme = "dark"
        save_settings(self._settings)
        self.accept()

    def result_settings(self) -> RezeptorSettings:
        return self._settings
