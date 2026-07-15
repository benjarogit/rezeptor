"""Dialog: neues Rezept aus Vorlage erzeugen (wraps scripts/new-recipe.sh)."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QDesktopServices
from PyQt6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from i18n import t
from ui_rezeptor import LimitedComboBox

ROOT = Path(__file__).resolve().parent.parent


def can_create_recipes(project_root: Path | None = None) -> bool:
    root = project_root or ROOT
    if os.environ.get("REZEPTOR_DEV", "").lower() in ("1", "true", "yes"):
        return True
    return (root / ".git").is_dir() and (root / "scripts" / "new-recipe.sh").is_file()


class RecipeWizardDialog(QDialog):
    """Create a recipe directory via new-recipe.sh + lint + manifest."""

    def __init__(self, parent: QWidget | None = None, project_root: Path | None = None) -> None:
        super().__init__(parent)
        self._root = project_root or ROOT
        self.setWindowTitle(t("wizard.title"))
        self.setMinimumWidth(480)

        layout = QVBoxLayout(self)
        intro = QLabel(t("wizard.intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        layout.addWidget(intro)

        form = QFormLayout()
        self.id_edit = QLineEdit()
        self.id_edit.setPlaceholderText("meine-app")
        form.addRow(t("wizard.id"), self.id_edit)

        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("Meine App")
        form.addRow(t("wizard.name"), self.name_edit)

        self.type_combo = LimitedComboBox(max_visible=8)
        self.type_combo.addItem(t("wizard.type_portable"), "portable")
        self.type_combo.addItem(t("wizard.type_installer"), "installer")
        form.addRow(t("wizard.type"), self.type_combo)

        self.category_edit = QLineEdit()
        self.category_edit.setPlaceholderText(t("wizard.category_ph"))
        form.addRow(t("wizard.category"), self.category_edit)
        layout.addLayout(form)

        self.status = QLabel("")
        self.status.setWordWrap(True)
        self.status.setObjectName("muted")
        layout.addWidget(self.status)

        btn_row = QHBoxLayout()
        self.manifest_btn = QPushButton(t("wizard.manifest_again"))
        self.manifest_btn.setEnabled(False)
        self.manifest_btn.clicked.connect(self._run_manifest)
        btn_row.addWidget(self.manifest_btn)
        btn_row.addStretch(1)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText(t("wizard.create"))
        buttons.accepted.connect(self._create)
        buttons.rejected.connect(self.reject)
        btn_row.addWidget(buttons)
        layout.addLayout(btn_row)

        self._created_id = ""

    def _create(self) -> None:
        rid = self.id_edit.text().strip()
        name = self.name_edit.text().strip() or rid
        rtype = str(self.type_combo.currentData() or "portable")
        if not rid:
            QMessageBox.warning(self, t("wizard.title"), t("wizard.err_id"))
            return
        script = self._root / "scripts" / "new-recipe.sh"
        if not script.is_file():
            QMessageBox.critical(self, t("wizard.title"), t("wizard.err_script"))
            return
        dest = self._root / "recipes" / rid
        if dest.exists():
            QMessageBox.warning(self, t("wizard.title"), t("wizard.err_exists", id=rid))
            return

        self.status.setText(t("wizard.running"))
        try:
            proc = subprocess.run(
                ["bash", str(script), "--type", rtype, rid, name],
                cwd=str(self._root),
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as exc:
            QMessageBox.critical(self, t("wizard.title"), str(exc))
            return
        if proc.returncode != 0:
            QMessageBox.critical(
                self,
                t("wizard.title"),
                (proc.stderr or proc.stdout or t("wizard.err_failed")).strip(),
            )
            return

        cat = self.category_edit.text().strip()
        if cat:
            yml = dest / "recipe.yml"
            try:
                text = yml.read_text(encoding="utf-8")
                lines = []
                replaced = False
                for line in text.splitlines():
                    if line.startswith("category:") and not replaced:
                        lines.append(f'category: "{cat}"')
                        replaced = True
                    else:
                        lines.append(line)
                if not replaced:
                    lines.insert(3, f'category: "{cat}"')
                yml.write_text("\n".join(lines) + "\n", encoding="utf-8")
            except OSError:
                pass

        lint = self._root / "scripts" / "recipe-lint.sh"
        lint_ok = True
        if lint.is_file():
            lp = subprocess.run(
                ["bash", str(lint)],
                cwd=str(self._root),
                capture_output=True,
                text=True,
                check=False,
            )
            lint_ok = lp.returncode == 0
            if not lint_ok:
                self.status.setText(t("wizard.lint_fail"))

        self._created_id = rid
        self._run_manifest(silent=True)
        self.manifest_btn.setEnabled(True)
        self.status.setText(t("wizard.done", id=rid))

        # Ordner im System-Dateimanager öffnen
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(dest.resolve())))

        if lint_ok:
            QMessageBox.information(self, t("wizard.title"), t("wizard.done", id=rid))
            self.accept()
        else:
            QMessageBox.warning(self, t("wizard.title"), t("wizard.lint_fail"))

    def _run_manifest(self, silent: bool = False) -> None:
        script = self._root / "scripts" / "recipe-manifest.sh"
        if not script.is_file():
            return
        proc = subprocess.run(
            ["bash", str(script)],
            cwd=str(self._root),
            capture_output=True,
            text=True,
            check=False,
        )
        if silent:
            return
        if proc.returncode == 0:
            self.status.setText(t("wizard.manifest_ok"))
            QMessageBox.information(self, t("wizard.title"), t("wizard.manifest_ok"))
        else:
            QMessageBox.warning(
                self,
                t("wizard.title"),
                (proc.stderr or proc.stdout or "manifest failed").strip(),
            )


class RecipeWizardBlockedDialog(QDialog):
    """Shown when recipe creation is not available (AppImage / no git)."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle(t("wizard.title"))
        self.setMinimumWidth(420)
        layout = QVBoxLayout(self)
        msg = QLabel(t("wizard.blocked"))
        msg.setWordWrap(True)
        layout.addWidget(msg)
        row = QHBoxLayout()
        docs = QPushButton(t("wizard.open_docs"))
        docs.clicked.connect(self._docs)
        github = QPushButton(t("wizard.open_github"))
        github.clicked.connect(self._github)
        row.addWidget(docs)
        row.addWidget(github)
        row.addStretch(1)
        close = QPushButton(t("wizard.close"))
        close.clicked.connect(self.accept)
        row.addWidget(close)
        layout.addLayout(row)

    def _docs(self) -> None:
        from ui_docs import DeveloperDocsDialog

        DeveloperDocsDialog(self).exec()

    def _github(self) -> None:
        from app_support import GITHUB_REPO

        QDesktopServices.openUrl(QUrl(f"https://github.com/{GITHUB_REPO}"))
