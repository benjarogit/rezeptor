"""Rezept-Ansicht: Übersicht / Dateien / Quelltext (Speichern nur im Dev-Modus)."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any

from PyQt6.QtCore import Qt, QUrl
from PyQt6.QtGui import QCloseEvent, QDesktopServices, QFont, QIcon
from PyQt6.QtWidgets import (
    QComboBox,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from i18n import t
from ui_window import confirm_unsaved_changes
from version_detect import load_recipe_mapping

HOOK_NAMES = (
    "install.sh",
    "launch.sh",
    "validate.sh",
    "repair.sh",
    "kill.sh",
    "uninstall.sh",
)


def _format_install_step(step: Any) -> str:
    """Lesbare Kurzform für install_steps (str oder Mapping)."""
    if isinstance(step, str):
        return step.strip() or "—"
    if isinstance(step, dict):
        if step.get("module"):
            return str(step["module"])
        if "winetricks" in step:
            vals = step.get("winetricks")
            if isinstance(vals, list) and vals:
                head = ", ".join(str(v) for v in vals[:3])
                more = f" +{len(vals) - 3}" if len(vals) > 3 else ""
                return f"winetricks ({head}{more})"
            return "winetricks"
        for key in ("id", "name", "run", "script"):
            if step.get(key):
                return str(step[key])
        if step:
            k, v = next(iter(step.items()))
            return f"{k}: {v}" if v is not None and v != "" else str(k)
    return str(step) if step is not None else "—"


def _chip(text: str) -> QLabel:
    lab = QLabel(text)
    lab.setObjectName("recipeChip")
    lab.setStyleSheet(
        "QLabel#recipeChip {"
        " background: #2a2a2e; color: #e4e4e7; border: 1px solid #3e3e42;"
        " border-radius: 4px; padding: 2px 8px; margin: 2px;"
        "}"
    )
    return lab


def _meta_scalar(data: dict[str, Any], key: str, default: str = "—") -> str:
    val = data.get(key, default)
    if val is None or val == "":
        return default
    if isinstance(val, (list, dict)):
        return str(val)
    return str(val)


def list_recipe_files(recipe_dir: Path) -> list[str]:
    """Relative paths of recipe files (hooks, yml, info, assets)."""
    out: list[str] = []
    if not recipe_dir.is_dir():
        return out
    for path in sorted(recipe_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(recipe_dir).as_posix()
        if "/__pycache__/" in f"/{rel}/" or rel.endswith(".pyc"):
            continue
        out.append(rel)
    return out


def resolve_recipe_icon(meta: dict[str, Any], project_root: Path) -> QIcon:
    raw = str(meta.get("icon", "") or "")
    if raw:
        p = Path(os.path.expanduser(raw.replace("{repo}", str(project_root))))
        if p.is_file():
            return QIcon(str(p))
    fallback = project_root / "images" / "Rezeptor.png"
    if fallback.is_file():
        return QIcon(str(fallback))
    return QIcon()


class RecipeViewDialog(QDialog):
    def __init__(
        self,
        parent: QWidget | None,
        *,
        recipe_dir: Path,
        project_root: Path,
        editable: bool,
        icon: QIcon | None = None,
    ) -> None:
        super().__init__(parent)
        self._recipe_dir = recipe_dir.resolve()
        self._project_root = project_root.resolve()
        self._yml = self._recipe_dir / "recipe.yml"
        self._data = load_recipe_mapping(self._yml) if self._yml.is_file() else {}
        self._rid = _meta_scalar(self._data, "id", self._recipe_dir.name)
        name = _meta_scalar(self._data, "name", self._rid)
        self.setWindowTitle(t("recipe_view.title", name=name))
        self.resize(720, 560)
        self.setMinimumSize(520, 400)

        writable = os.access(self._recipe_dir, os.W_OK) and self._recipe_dir.is_dir()
        self._editable = bool(editable and writable)
        self._read_only_reason = ""
        if editable and not writable:
            self._read_only_reason = t("recipe_view.readonly_packaged")
        elif not editable:
            self._read_only_reason = t("recipe_view.readonly_hint")

        self._current_rel: str | None = None
        self._dirty = False

        root = QVBoxLayout(self)

        if self._editable:
            banner = QLabel(t("recipe_view.dev_banner"))
            banner.setWordWrap(True)
            banner.setObjectName("muted")
            root.addWidget(banner)
        elif self._read_only_reason:
            banner = QLabel(self._read_only_reason)
            banner.setWordWrap(True)
            banner.setObjectName("muted")
            root.addWidget(banner)

        self.tabs = QTabWidget()
        overview_scroll = QScrollArea()
        overview_scroll.setWidgetResizable(True)
        overview_scroll.setFrameShape(QFrame.Shape.NoFrame)
        overview_scroll.setWidget(self._build_overview(icon))
        self.tabs.addTab(overview_scroll, t("recipe_view.tab_overview"))
        self.tabs.addTab(self._build_files(), t("recipe_view.tab_files"))
        self.tabs.addTab(self._build_source(), t("recipe_view.tab_source"))
        root.addWidget(self.tabs, 1)

        buttons = QHBoxLayout()
        open_btn = QPushButton(t("recipe_view.open_folder"))
        open_btn.clicked.connect(self._open_folder)
        buttons.addWidget(open_btn)
        buttons.addStretch(1)
        self.save_btn = QPushButton(t("recipe_view.save"))
        self.save_btn.setEnabled(False)
        self.save_btn.clicked.connect(self._save_current)
        self.save_btn.setVisible(self._editable)
        buttons.addWidget(self.save_btn)
        close_btn = QPushButton(t("recipe_view.close"))
        close_btn.clicked.connect(self.accept)
        buttons.addWidget(close_btn)
        root.addLayout(buttons)

        self.file_list.currentItemChanged.connect(self._on_file_selected)
        self.file_combo.currentIndexChanged.connect(self._on_combo_changed)
        self.editor.textChanged.connect(self._on_editor_changed)

        # Prefer recipe.yml in source tab
        self._select_rel("recipe.yml")

    def focus_source_tab(self) -> None:
        """Quelltext-Tab (nach Entwicklermodus-Aktivierung)."""
        self.tabs.setCurrentIndex(2)

    def is_dirty(self) -> bool:
        return bool(self._dirty)

    def force_close(self) -> None:
        """Hauptfenster-Quit: Dirty bereits behandelt — ohne zweite Nachfrage."""
        self._dirty = False
        self.setProperty("rezeptor_force_close", True)
        self.close()

    def prompt_and_save_or_discard(self) -> bool:
        """True = weiter (gespeichert oder verworfen), False = Abbruch."""
        if not self._dirty:
            return True
        choice = confirm_unsaved_changes(
            self,
            title=t("dialog.unsaved_title"),
            body=t("recipe_view.unsaved_body"),
        )
        if choice == "cancel":
            return False
        if choice == "save":
            if not self._save_current(silent=True):
                return False
            return True
        self._dirty = False
        self.save_btn.setEnabled(False)
        return True

    def closeEvent(self, event: QCloseEvent) -> None:
        """Taskleisten-/Fenster-Schließen: Speichern / Verwerfen / Abbrechen."""
        if self.property("rezeptor_force_close"):
            self._dirty = False
            event.accept()
            super().closeEvent(event)
            return
        if self._dirty and not self.prompt_and_save_or_discard():
            event.ignore()
            return
        self._dirty = False
        event.accept()
        super().closeEvent(event)

    def _build_overview(self, icon: QIcon | None) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        head = QHBoxLayout()
        icon_lab = QLabel()
        ic = icon or resolve_recipe_icon(self._data, self._project_root)
        if not ic.isNull():
            icon_lab.setPixmap(ic.pixmap(64, 64))
        head.addWidget(icon_lab)
        titles = QVBoxLayout()
        name = QLabel(_meta_scalar(self._data, "name", self._rid))
        name.setStyleSheet("font-size: 18px; font-weight: 600;")
        titles.addWidget(name)
        titles.addWidget(QLabel(f"id: {self._rid}"))
        head.addLayout(titles, 1)
        lay.addLayout(head)

        meta_row = QHBoxLayout()
        for key, label in (
            ("category", t("recipe_view.chip_category")),
            ("runtime", t("recipe_view.chip_runtime")),
            ("install_type", t("recipe_view.chip_install_type")),
            ("deploy_mode", t("recipe_view.chip_deploy")),
            ("source_kind", t("recipe_view.chip_source")),
        ):
            val = _meta_scalar(self._data, key, "")
            if val and val != "—":
                meta_row.addWidget(_chip(f"{label}: {val}"))
        steam = _meta_scalar(self._data, "steam_appid", "")
        if steam and steam != "—":
            meta_row.addWidget(_chip(f"Steam {steam}"))
        meta_row.addStretch(1)
        lay.addLayout(meta_row)

        vg = _meta_scalar(self._data, "version_guaranteed", "")
        vl = _meta_scalar(self._data, "version_label", "")
        if vg and vg != "—":
            lay.addWidget(QLabel(t("recipe_view.version_guaranteed", version=vg)))
        if vl and vl != "—" and vl != vg:
            muted = QLabel(vl)
            muted.setObjectName("muted")
            muted.setWordWrap(True)
            lay.addWidget(muted)

        # version_detect chips
        vd = self._data.get("version_detect")
        if isinstance(vd, list) and vd:
            lay.addWidget(QLabel(t("recipe_view.version_detect")))
            chip_row = QHBoxLayout()
            for item in vd:
                if not isinstance(item, dict):
                    continue
                kind = str(item.get("kind", "?"))
                bits = [kind]
                if item.get("identity_file"):
                    bits.append(str(item["identity_file"]))
                if item.get("ok_label"):
                    bits.append(str(item["ok_label"]))
                chip_row.addWidget(_chip(" · ".join(bits)))
            chip_row.addStretch(1)
            lay.addLayout(chip_row)

        # install_steps — vertikal (horizontale Chip-Reihe quetscht zu leeren Kästen)
        steps = self._data.get("install_steps")
        if isinstance(steps, list) and steps:
            lay.addWidget(QLabel(t("recipe_view.install_steps")))
            for i, step in enumerate(steps):
                label = _format_install_step(step)
                row = QHBoxLayout()
                row.setSpacing(6)
                if i:
                    arrow = QLabel("→")
                    arrow.setObjectName("muted")
                    row.addWidget(arrow)
                else:
                    row.addSpacing(14)
                chip = _chip(label)
                chip.setToolTip(label)
                row.addWidget(chip, stretch=1)
                lay.addLayout(row)

        # hooks present/missing
        lay.addWidget(QLabel(t("recipe_view.hooks")))
        hook_row = QHBoxLayout()
        for name in HOOK_NAMES:
            present = (self._recipe_dir / name).is_file()
            lab = _chip(name.replace(".sh", ""))
            if not present:
                lab.setStyleSheet(
                    "QLabel#recipeChip {"
                    " background: #2a2a2e; color: #71717a; border: 1px dashed #3e3e42;"
                    " border-radius: 4px; padding: 2px 8px; margin: 2px;"
                    "}"
                )
                lab.setToolTip(t("recipe_view.hook_missing"))
            hook_row.addWidget(lab)
        hook_row.addStretch(1)
        lay.addLayout(hook_row)

        lay.addStretch(1)
        return w

    def _build_files(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        self.file_list = QListWidget()
        for rel in list_recipe_files(self._recipe_dir):
            self.file_list.addItem(QListWidgetItem(rel))
        lay.addWidget(self.file_list)
        return w

    def _build_source(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        # Plain QComboBox: LimitedComboBox+QSS hat unter Wayland zu Crashes geführt.
        self.file_combo = QComboBox()
        self.file_combo.setMaxVisibleItems(12)
        for rel in list_recipe_files(self._recipe_dir):
            self.file_combo.addItem(rel)
        lay.addWidget(self.file_combo)
        self.editor = QPlainTextEdit()
        mono = QFont("monospace")
        mono.setStyleHint(QFont.StyleHint.Monospace)
        self.editor.setFont(mono)
        self.editor.setReadOnly(not self._editable)
        lay.addWidget(self.editor, 1)
        return w

    def _select_rel(self, rel: str) -> None:
        # Sync list + combo without recursive dirty noise
        for i in range(self.file_list.count()):
            if self.file_list.item(i).text() == rel:
                self.file_list.setCurrentRow(i)
                break
        idx = self.file_combo.findText(rel)
        if idx >= 0:
            self.file_combo.blockSignals(True)
            self.file_combo.setCurrentIndex(idx)
            self.file_combo.blockSignals(False)
        self._load_rel(rel)

    def _load_rel(self, rel: str) -> None:
        path = self._recipe_dir / rel
        self._current_rel = rel
        self._dirty = False
        self.save_btn.setEnabled(False)
        if not path.is_file():
            self.editor.setPlainText("")
            return
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            text = f"# {t('recipe_view.read_error')}: {exc}\n"
        self.editor.blockSignals(True)
        self.editor.setPlainText(text)
        self.editor.blockSignals(False)

    def _on_file_selected(
        self, current: QListWidgetItem | None, _prev: QListWidgetItem | None
    ) -> None:
        if current is None:
            return
        if self._dirty and not self._confirm_discard():
            # restore selection
            if self._current_rel:
                for i in range(self.file_list.count()):
                    if self.file_list.item(i).text() == self._current_rel:
                        self.file_list.blockSignals(True)
                        self.file_list.setCurrentRow(i)
                        self.file_list.blockSignals(False)
                        break
            return
        rel = current.text()
        self.tabs.setCurrentIndex(2)
        idx = self.file_combo.findText(rel)
        if idx >= 0:
            self.file_combo.blockSignals(True)
            self.file_combo.setCurrentIndex(idx)
            self.file_combo.blockSignals(False)
        self._load_rel(rel)

    def _on_combo_changed(self, index: int) -> None:
        if index < 0:
            return
        rel = self.file_combo.itemText(index)
        if rel == self._current_rel:
            return
        if self._dirty and not self._confirm_discard():
            if self._current_rel:
                idx = self.file_combo.findText(self._current_rel)
                if idx >= 0:
                    self.file_combo.blockSignals(True)
                    self.file_combo.setCurrentIndex(idx)
                    self.file_combo.blockSignals(False)
            return
        for i in range(self.file_list.count()):
            if self.file_list.item(i).text() == rel:
                self.file_list.blockSignals(True)
                self.file_list.setCurrentRow(i)
                self.file_list.blockSignals(False)
                break
        self._load_rel(rel)

    def _on_editor_changed(self) -> None:
        if not self._editable or self._current_rel is None:
            return
        self._dirty = True
        self.save_btn.setEnabled(True)

    def _confirm_discard(self) -> bool:
        box = QMessageBox.question(
            self,
            t("recipe_view.discard_title"),
            t("recipe_view.discard_body"),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        return box == QMessageBox.StandardButton.Yes

    def _open_folder(self) -> None:
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self._recipe_dir)))

    def _save_current(self, *, silent: bool = False) -> bool:
        if not self._editable or not self._current_rel:
            return True
        path = self._recipe_dir / self._current_rel
        try:
            path.write_text(self.editor.toPlainText(), encoding="utf-8")
        except OSError as exc:
            QMessageBox.warning(
                self, t("dialog.error"), t("recipe_view.save_fail", err=str(exc))
            )
            return False
        self._dirty = False
        self.save_btn.setEnabled(False)
        self._run_manifest()
        if not silent:
            QMessageBox.information(
                self, t("recipe_view.title", name=self._rid), t("recipe_view.save_ok")
            )
        return True

    def _run_manifest(self) -> None:
        script = self._project_root / "scripts" / "recipe-manifest.sh"
        if not script.is_file():
            return
        # Prefer script; fall back to in-process generate if needed
        subprocess.run(
            ["bash", str(script)],
            cwd=str(self._project_root),
            capture_output=True,
            text=True,
            check=False,
        )
