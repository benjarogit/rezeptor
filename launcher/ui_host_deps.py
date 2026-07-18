"""Host dependency check dialog (first start + menu System prüfen)."""

from __future__ import annotations

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from host_deps import (
    HostDep,
    has_gaps,
    install_command,
    is_immutable_host,
    missing_deps,
    run_install,
    scan_host_deps,
)
from i18n import t
from settings import RezeptorSettings, save_settings


class HostDepsDialog(QDialog):
    def __init__(
        self,
        parent: QWidget | None,
        *,
        first_run: bool = False,
    ) -> None:
        super().__init__(parent)
        self._first_run = first_run
        self.setWindowTitle(t("deps.title"))
        self.resize(520, 360)
        self.setMinimumSize(400, 280)

        layout = QVBoxLayout(self)
        intro_key = "deps.intro_first" if first_run else "deps.intro"
        intro = QLabel(t(intro_key))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        layout.addWidget(intro)

        self._list_label = QLabel("")
        self._list_label.setWordWrap(True)
        self._list_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        layout.addWidget(self._list_label)

        self._cmd_label = QLabel("")
        self._cmd_label.setObjectName("muted")
        self._cmd_label.setWordWrap(True)
        self._cmd_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        layout.addWidget(self._cmd_label)

        btn_row = QHBoxLayout()
        self.install_btn = QPushButton(t("deps.install"))
        self.install_btn.setToolTip(t("deps.install_tip"))
        self.install_btn.clicked.connect(self._on_install)
        self.copy_btn = QPushButton(t("deps.copy_cmd"))
        self.copy_btn.setToolTip(t("deps.copy_cmd_tip"))
        self.copy_btn.clicked.connect(self._on_copy)
        btn_row.addWidget(self.install_btn)
        btn_row.addWidget(self.copy_btn)
        btn_row.addStretch(1)
        layout.addLayout(btn_row)

        buttons = QDialogButtonBox()
        close_label = t("deps.later") if first_run else t("deps.close")
        close_btn = buttons.addButton(close_label, QDialogButtonBox.ButtonRole.RejectRole)
        close_btn.clicked.connect(self.reject)
        layout.addWidget(buttons)

        self._refresh()

    def _item_line(self, dep: HostDep) -> str:
        name = t(f"deps.item_{dep.id}")
        why = t(f"deps.why_{dep.id}")
        level = t("deps.required") if dep.required else t("deps.recommended")
        if dep.present:
            return t("deps.line_ok", level=level, name=name, why=why)
        return t("deps.line_missing", level=level, name=name, why=why)

    def _refresh(self) -> None:
        self._deps = scan_host_deps()
        self._missing = missing_deps(self._deps)
        lines = [self._item_line(d) for d in self._deps]
        self._list_label.setText("\n".join(lines))
        cmd = install_command(self._missing)
        self._cmd = cmd
        if not self._missing:
            self._cmd_label.setText(t("deps.all_ok"))
            self.install_btn.setEnabled(False)
            self.copy_btn.setEnabled(False)
            return
        if is_immutable_host():
            self._cmd_label.setText(t("deps.immutable_hint", cmd=cmd))
            self.install_btn.setEnabled(False)
        else:
            self._cmd_label.setText(t("deps.cmd_hint", cmd=cmd))
            self.install_btn.setEnabled(bool(cmd) and not cmd.startswith("#"))
        self.copy_btn.setEnabled(bool(cmd))

    def _on_copy(self) -> None:
        if not self._cmd:
            return
        QGuiApplication.clipboard().setText(self._cmd)
        QMessageBox.information(self, t("deps.title"), t("deps.copied"))

    def _on_install(self) -> None:
        if not self._missing:
            return
        ok, detail = run_install(self._missing)
        if ok:
            QMessageBox.information(self, t("deps.title"), t("deps.install_ok"))
            self._refresh()
            if not has_gaps(self._deps):
                self.accept()
            return
        if detail == "immutable":
            QMessageBox.warning(self, t("deps.title"), t("deps.immutable_only"))
        elif detail == "no_pkexec":
            QMessageBox.warning(self, t("deps.title"), t("deps.no_pkexec"))
        elif detail == "unsupported":
            QMessageBox.warning(self, t("deps.title"), t("deps.unsupported"))
        else:
            QMessageBox.warning(
                self,
                t("deps.title"),
                t("deps.install_fail", detail=detail[:400]),
            )
        self._refresh()


def mark_host_deps_prompt_done(settings: object) -> None:
    if not isinstance(settings, RezeptorSettings):
        return
    if settings.host_deps_prompt_done:
        return
    settings.host_deps_prompt_done = True
    save_settings(settings)
