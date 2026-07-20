"""Rezeptor settings dialog."""

from __future__ import annotations

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QCloseEvent, QColor, QPalette
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QSpinBox,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from app_support import log_dir_stats, prune_old_logs
from archive_passwords import normalize_password_list_text
from i18n import available_locales, t
from settings import RezeptorSettings, save_settings
from ui_window import confirm_unsaved_changes

# Feste Zeilenhöhe — verhindert Combo/Spin-Überlappung unter Fusion+Host-QSS.
_FIELD_H = 36


class SettingsDialog(QDialog):
    def __init__(self, parent: QWidget | None, settings: RezeptorSettings) -> None:
        super().__init__(parent)
        self._settings = settings
        self._dirty = False
        self._closing = False
        self.setWindowTitle(t("settings.title"))
        # Groß genug für Allgemein + Passwort-Tab (apply_tool_window darf nicht kleiner machen).
        self.resize(560, 580)
        self.setMinimumSize(520, 520)

        root = QVBoxLayout(self)
        root.setSpacing(12)
        root.setContentsMargins(12, 12, 12, 12)

        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_general_tab(settings), t("settings.tab_general"))
        self.tabs.addTab(self._build_passwords_tab(settings), t("settings.tab_passwords"))
        root.addWidget(self.tabs, stretch=1)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._save)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

        self._wire_dirty()

    @staticmethod
    def _stack_field(parent_lay: QVBoxLayout, label: str, widget: QWidget) -> None:
        """Label darüber, Feld darunter — kein Grid (keine Überlappung)."""
        lab = QLabel(label)
        lab.setObjectName("muted")
        parent_lay.addWidget(lab)
        widget.setFixedHeight(_FIELD_H)
        widget.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        parent_lay.addWidget(widget)
        parent_lay.addSpacing(6)

    def _build_general_tab(self, settings: RezeptorSettings) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(4)

        intro = QLabel(t("settings.intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        layout.addWidget(intro)
        layout.addSpacing(8)

        # Plain combo — kein Extra-QSS (max-height + Host-padding → Überlappung).
        self.lang_combo = QComboBox()
        self.lang_combo.setMaxVisibleItems(4)
        for lid, name in available_locales():
            self.lang_combo.addItem(name, lid)
        idx = self.lang_combo.findData(settings.locale)
        if idx < 0:
            idx = 0
        self.lang_combo.setCurrentIndex(idx)
        self._stack_field(layout, t("settings.language"), self.lang_combo)

        self.retention_spin = QSpinBox()
        self.retention_spin.setRange(1, 365)
        self.retention_spin.setValue(settings.log_retention_days)
        self.retention_spin.setSuffix(t("settings.days"))
        self.retention_spin.setToolTip(t("settings.retention_tip"))
        self._stack_field(layout, t("settings.retention"), self.retention_spin)

        self.max_files_spin = QSpinBox()
        self.max_files_spin.setRange(5, 500)
        self.max_files_spin.setValue(settings.log_max_files)
        self.max_files_spin.setToolTip(t("settings.max_files_tip"))
        self._stack_field(layout, t("settings.max_files"), self.max_files_spin)

        self.prune_startup = QCheckBox(t("settings.prune_startup"))
        self.prune_startup.setChecked(settings.prune_logs_on_startup)
        layout.addWidget(self.prune_startup)

        self.validate_startup = QCheckBox(t("settings.validate_startup"))
        self.validate_startup.setChecked(settings.validate_on_startup)
        self.validate_startup.setToolTip(t("settings.validate_startup_tip"))
        layout.addWidget(self.validate_startup)

        self.dev_mode = QCheckBox(t("settings.developer_mode"))
        self.dev_mode.setChecked(settings.developer_mode)
        self.dev_mode.setToolTip(t("settings.developer_mode_tip"))
        layout.addWidget(self.dev_mode)

        layout.addSpacing(8)
        count, size = log_dir_stats()
        self.stats_label = QLabel(t("settings.stats", count=count, size=size))
        self.stats_label.setObjectName("muted")
        layout.addWidget(self.stats_label)

        cleanup_btn = QPushButton(t("settings.cleanup_btn"))
        cleanup_btn.setFixedHeight(_FIELD_H)
        cleanup_btn.clicked.connect(self._cleanup_now)
        layout.addWidget(cleanup_btn)
        layout.addStretch(1)
        return page

    def _build_passwords_tab(self, settings: RezeptorSettings) -> QWidget:
        """Status/Button über dem Editor — kann nicht in den Viewport rutschen."""
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)

        intro = QLabel(t("settings.archive_passwords_hint"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        layout.addWidget(intro)

        self.pw_count = QLabel("")
        self.pw_count.setObjectName("muted")
        layout.addWidget(self.pw_count)

        toolbar = QHBoxLayout()
        toolbar.setSpacing(12)
        self.pw_status = QLabel("")
        self.pw_status.setWordWrap(True)
        self.pw_status.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        self.pw_status.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        toolbar.addWidget(self.pw_status, stretch=1)
        self.pw_fix_btn = QPushButton(t("settings.archive_passwords_fix"))
        self.pw_fix_btn.setToolTip(t("settings.archive_passwords_fix_tip"))
        self.pw_fix_btn.setFixedHeight(_FIELD_H)
        self.pw_fix_btn.clicked.connect(self._fix_passwords)
        toolbar.addWidget(self.pw_fix_btn, stretch=0)
        layout.addLayout(toolbar)

        self.pw_show = QCheckBox(t("settings.archive_passwords_show"))
        self.pw_show.setChecked(False)
        self.pw_show.toggled.connect(self._toggle_password_visibility)
        layout.addWidget(self.pw_show)

        self._pw_plain = "\n".join(settings.archive_passwords)
        if self._pw_plain:
            self._pw_plain += "\n"
        self._pw_syncing = False
        self.archive_passwords = QPlainTextEdit()
        self.archive_passwords.document().setDocumentMargin(10)
        pal = self.archive_passwords.palette()
        pal.setColor(QPalette.ColorRole.PlaceholderText, QColor("#6B6B66"))
        self.archive_passwords.setPalette(pal)
        self.archive_passwords.setPlaceholderText(t("settings.archive_passwords_ph"))
        self.archive_passwords.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        self.archive_passwords.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAsNeeded
        )
        self.archive_passwords.setVerticalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAsNeeded
        )
        self.archive_passwords.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
        )
        self.archive_passwords.setMinimumHeight(180)
        self.archive_passwords.textChanged.connect(self._on_password_editor_changed)
        self.archive_passwords.textChanged.connect(self._on_passwords_changed)
        layout.addWidget(self.archive_passwords, stretch=1)
        self._apply_password_display()

        self._on_passwords_changed()
        return page

    def _mask_password_text(self, plain: str) -> str:
        lines: list[str] = []
        for line in plain.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                lines.append(line)
            else:
                lines.append("•" * max(8, min(24, len(stripped))))
        if plain.endswith("\n"):
            return "\n".join(lines) + "\n"
        return "\n".join(lines)

    def _apply_password_display(self) -> None:
        self._pw_syncing = True
        show = self.pw_show.isChecked()
        if show:
            self.archive_passwords.setPlainText(self._pw_plain)
        else:
            self.archive_passwords.setPlainText(self._mask_password_text(self._pw_plain))
        self.archive_passwords.setReadOnly(not show)
        self._pw_syncing = False

    def _toggle_password_visibility(self, _checked: bool = False) -> None:
        self._apply_password_display()

    def _on_password_editor_changed(self) -> None:
        if self._pw_syncing:
            return
        if self.pw_show.isChecked():
            self._pw_plain = self.archive_passwords.toPlainText()
        # When masked, ignore edits that would corrupt the bullet display

    def _wire_dirty(self) -> None:
        self.lang_combo.currentIndexChanged.connect(self._mark_dirty)
        self.retention_spin.valueChanged.connect(self._mark_dirty)
        self.max_files_spin.valueChanged.connect(self._mark_dirty)
        self.prune_startup.toggled.connect(self._mark_dirty)
        self.validate_startup.toggled.connect(self._mark_dirty)
        self.dev_mode.toggled.connect(self._mark_dirty)
        self.archive_passwords.textChanged.connect(self._mark_dirty)

    def _mark_dirty(self, *_args: object) -> None:
        self._dirty = True

    def is_dirty(self) -> bool:
        return bool(self._dirty)

    def _password_text_for_normalize(self) -> str:
        if self.pw_show.isChecked():
            return self.archive_passwords.toPlainText()
        return self._pw_plain

    def _on_passwords_changed(self) -> None:
        result = normalize_password_list_text(self._password_text_for_normalize())
        n = len(result.passwords)
        if n == 0:
            self.pw_count.setText(t("settings.archive_passwords_count_empty"))
        else:
            self.pw_count.setText(t("settings.archive_passwords_count", count=n))
        if result.errors:
            self.pw_status.setText(
                t("settings.archive_passwords_errors", detail="\n".join(result.errors))
            )
            self.pw_status.setStyleSheet(f"color: #fbbf24;")
            self.pw_fix_btn.setEnabled(bool(result.corrected_text is not None))
        elif result.auto_fixed:
            self.pw_status.setText(t("settings.archive_passwords_dirty"))
            self.pw_status.setStyleSheet("color: #fbbf24;")
            self.pw_fix_btn.setEnabled(True)
        else:
            self.pw_status.setText(t("settings.archive_passwords_ok"))
            self.pw_status.setStyleSheet("color: #86efac;")
            self.pw_fix_btn.setEnabled(False)

    def _fix_passwords(self) -> None:
        result = normalize_password_list_text(self._password_text_for_normalize())
        if result.corrected_text is None:
            QMessageBox.warning(
                self,
                t("settings.tab_passwords"),
                t(
                    "settings.archive_passwords_fix_fail",
                    detail="\n".join(result.errors) or "—",
                ),
            )
            return
        self._pw_plain = result.corrected_text
        self._apply_password_display()
        self._mark_dirty()
        self._on_passwords_changed()

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

    def _apply_to_settings(self) -> bool:
        result = normalize_password_list_text(self._password_text_for_normalize())
        if result.errors and result.corrected_text is None:
            self.tabs.setCurrentIndex(1)
            QMessageBox.warning(
                self,
                t("settings.tab_passwords"),
                t(
                    "settings.archive_passwords_fix_fail",
                    detail="\n".join(result.errors),
                ),
            )
            return False
        if result.auto_fixed and result.corrected_text is not None:
            self._pw_plain = result.corrected_text
            self._apply_password_display()
            result = normalize_password_list_text(self._pw_plain)
        if result.errors:
            self.tabs.setCurrentIndex(1)
            QMessageBox.warning(
                self,
                t("settings.tab_passwords"),
                t(
                    "settings.archive_passwords_errors",
                    detail="\n".join(result.errors),
                ),
            )
            return False

        self._settings.log_retention_days = self.retention_spin.value()
        self._settings.log_max_files = self.max_files_spin.value()
        self._settings.prune_logs_on_startup = self.prune_startup.isChecked()
        self._settings.validate_on_startup = self.validate_startup.isChecked()
        self._settings.developer_mode = self.dev_mode.isChecked()
        self._settings.archive_passwords = result.passwords
        lid = self.lang_combo.currentData()
        if lid:
            self._settings.locale = str(lid)
        self._settings.theme = "dark"
        save_settings(self._settings)
        self._dirty = False
        return True

    def _save(self) -> None:
        if self._apply_to_settings():
            self.accept()

    def reject(self) -> None:
        if self.property("rezeptor_force_close"):
            self._dirty = False
            self._closing = True
            super().reject()
            return
        if not self._prompt_close_if_dirty():
            return
        super().reject()

    def closeEvent(self, event: QCloseEvent) -> None:
        if self._closing or self.property("rezeptor_force_close"):
            self._dirty = False
            self._closing = True
            event.accept()
            super().closeEvent(event)
            return
        if not self._prompt_close_if_dirty():
            event.ignore()
            return
        self._closing = True
        event.accept()
        super().closeEvent(event)

    def _prompt_close_if_dirty(self) -> bool:
        if self.property("rezeptor_force_close"):
            self._dirty = False
            return True
        if not self._dirty:
            return True
        choice = confirm_unsaved_changes(
            self,
            title=t("dialog.unsaved_title"),
            body=t("settings.unsaved_body"),
        )
        if choice == "cancel":
            return False
        if choice == "save":
            return self._apply_to_settings()
        self._dirty = False
        return True

    def result_settings(self) -> RezeptorSettings:
        return self._settings

    def show_passwords_tab(self) -> None:
        self.tabs.setCurrentIndex(1)
