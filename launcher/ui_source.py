"""Unified recipe source picker (folder / installer / archive)."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from PyQt6.QtWidgets import (
    QButtonGroup,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)

from app_support import detect_source_version, version_guarantee_mismatch
from i18n import t

_DIR_DIALOG_OPTS = (
    QFileDialog.Option.ShowDirsOnly | QFileDialog.Option.DontUseNativeDialog
)


def documents_dir() -> Path:
    """XDG-Dokumente (de: ~/Dokumente)."""
    try:
        proc = subprocess.run(
            ["xdg-user-dir", "DOCUMENTS"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            p = Path(proc.stdout.strip())
            if p.is_dir():
                return p
    except (OSError, subprocess.TimeoutExpired):
        pass
    for cand in (Path.home() / "Dokumente", Path.home() / "Documents"):
        if cand.is_dir():
            return cand
    return Path.home()


def normalize_user_path(raw: str, root: Path | None = None) -> str:
    """~, {repo}, //Dokumente/… und doppelte Slashes bereinigen."""
    text = (raw or "").strip()
    if not text:
        return text
    if root is not None:
        text = text.replace("{repo}", str(root))
    expanded = os.path.expanduser(text)
    # KDE/Hand-Eingabe: //Dokumente/… ohne Home → ~/Dokumente/…
    if expanded.startswith("//") and not expanded.startswith("///"):
        rest = expanded[2:]
        if rest and not rest.startswith("/"):
            expanded = str(Path.home() / rest)
        else:
            expanded = "/" + expanded.lstrip("/")
    return os.path.normpath(expanded)


def dialog_start_dir(raw: str, fallback: Path | None = None) -> str:
    """Startverzeichnis für QFileDialog — nur existierende Ordner."""
    fb = fallback or documents_dir()
    if not raw.strip():
        return str(fb)
    p = Path(normalize_user_path(raw))
    if p.is_dir():
        return str(p)
    if p.parent.is_dir():
        return str(p.parent)
    return str(fb)


def pick_directory(parent: QWidget, title: str, start: str) -> str:
    """Ordner wählen (Qt-Dialog: „Neuer Ordner“, kein KDE-Pflicht-Existenz-Fehler)."""
    start_dir = dialog_start_dir(start)
    chosen = QFileDialog.getExistingDirectory(
        parent,
        title,
        start_dir,
        options=_DIR_DIALOG_OPTS,
    )
    return normalize_user_path(chosen) if chosen else ""


def needs_target_dir(meta: dict[str, str]) -> bool:
    if meta.get("deploy_mode", "copy") == "link":
        return False
    return meta.get("install_type", "") in (
        "portable_launch",
        "portable_bootstrap",
        "game_portable",
    )


def default_target_dir(
    meta: dict[str, str], rid: str = "", data_root: Path | None = None
) -> str:
    if rid == "wiso-steuer" and data_root is not None:
        env_path = data_root / "portable.env"
        if env_path.is_file():
            for line in env_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line.startswith("WISO_PORTABLE_ROOT="):
                    continue
                val = line.split("=", 1)[1].strip().strip('"')
                if val and Path(val).is_dir():
                    return normalize_user_path(val)
    raw = (meta.get("target_default") or "").strip()
    if raw:
        return normalize_user_path(raw)
    return str(documents_dir() / "WISO Steuer 2026" if rid == "wiso-steuer" else documents_dir())


def normalize_folder_source(rid: str, raw: str) -> str:
    p = Path(raw)
    if not p.is_dir():
        return raw
    if rid == "wiso-steuer" and p.name.startswith("Steuersoftware"):
        return str(p.parent.resolve())
    return str(p.resolve())


def default_folder_source(rid: str, data_root: Path) -> str:
    if rid == "wiso-steuer":
        env_path = data_root / "portable.env"
        if env_path.is_file():
            for line in env_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line.startswith("WISO_PORTABLE_ROOT="):
                    continue
                val = line.split("=", 1)[1].strip().strip('"')
                if val and Path(val).is_dir():
                    return val
        for base in (Path.home() / "Downloads", Path.home() / "Dokumente"):
            if not base.is_dir():
                continue
            try:
                candidates = sorted(
                    (
                        p
                        for p in base.iterdir()
                        if p.is_dir() and "wiso" in p.name.lower()
                    ),
                    key=lambda p: p.stat().st_mtime,
                    reverse=True,
                )
            except OSError:
                continue
            for cand in candidates:
                if (cand / "start.exe").is_file() or list(cand.glob("Steuersoftware*")):
                    return str(cand.resolve())
    return ""


def archive_filter(formats: str) -> str:
    parts = [p.strip() for p in formats.split(",") if p.strip()]
    if not parts:
        parts = ["zip", "tar.gz", "tgz"]
    labels: list[str] = []
    for p in parts:
        labels.append(f"*.{p}")
    return f"Archive ({' '.join(labels)})"


class RecipeSourceDialog(QDialog):
    """Meta-driven source picker for install / reconfigure."""

    def __init__(
        self,
        parent: QWidget | None,
        *,
        rid: str,
        meta: dict[str, str],
        root: Path,
        title: str = "",
    ) -> None:
        super().__init__(parent)
        self._rid = rid
        self._meta = meta
        self._root = root
        self._source_kind = meta.get("source_kind", "folder")
        self._fix_kind = meta.get("fix_kind", "none")
        self._version_guaranteed = meta.get("version_guaranteed", "").strip()
        self._show_target = needs_target_dir(meta)
        self._allow_archive = bool((meta.get("source_formats") or "").strip())
        self._pick_archive = False

        self.setWindowTitle(title or t("source.title"))
        self.resize(620, 320 if self._show_target else 260)

        layout = QVBoxLayout(self)
        layout.setSpacing(12)

        label = meta.get("source_label") or t("source.label")
        intro = QLabel(label)
        intro.setObjectName("muted")
        intro.setWordWrap(True)
        layout.addWidget(intro)

        if self._rid == "wiso-steuer" and self._source_kind == "folder":
            wiso_hint = QLabel(t("source.wiso_hint"))
            wiso_hint.setObjectName("muted")
            wiso_hint.setWordWrap(True)
            layout.addWidget(wiso_hint)

        if self._allow_archive and self._source_kind == "folder":
            mode_row = QHBoxLayout()
            self._mode_folder = QRadioButton(t("source.folder"))
            self._mode_archive = QRadioButton(t("source.archive"))
            self._mode_folder.setChecked(True)
            mode_group = QButtonGroup(self)
            mode_group.addButton(self._mode_folder)
            mode_group.addButton(self._mode_archive)
            self._mode_folder.toggled.connect(self._on_source_mode_changed)
            mode_row.addWidget(self._mode_folder)
            mode_row.addWidget(self._mode_archive)
            mode_row.addStretch(1)
            layout.addLayout(mode_row)

        self.version_hint = QLabel("")
        self.version_hint.setObjectName("muted")
        self.version_hint.setWordWrap(True)
        layout.addWidget(self.version_hint)

        if self._show_target:
            target_hint = QLabel(t("source.target_hint"))
            target_hint.setObjectName("muted")
            target_hint.setWordWrap(True)
            layout.addWidget(target_hint)

        form = QFormLayout()
        self.primary_edit = QLineEdit()
        self.target_edit = QLineEdit()
        self.fix_edit = QLineEdit()
        self.primary_btn = QPushButton(t("source.pick"))
        self.target_btn = QPushButton(t("source.pick_target"))
        self.fix_btn = QPushButton(t("source.pick_fix"))

        self.primary_btn.clicked.connect(self._pick_primary)
        self.target_btn.clicked.connect(self._pick_target)
        self.fix_btn.clicked.connect(self._pick_fix)

        primary_row = QHBoxLayout()
        primary_row.addWidget(self.primary_edit, stretch=1)
        primary_row.addWidget(self.primary_btn)

        target_row = QHBoxLayout()
        target_row.addWidget(self.target_edit, stretch=1)
        target_row.addWidget(self.target_btn)

        fix_row = QHBoxLayout()
        fix_row.addWidget(self.fix_edit, stretch=1)
        fix_row.addWidget(self.fix_btn)

        primary_label = self._primary_label()
        form.addRow(primary_label + ":", primary_row)
        if self._show_target:
            target_label = meta.get("target_label") or t("source.target_label")
            form.addRow(target_label + ":", target_row)
        else:
            self.target_edit.hide()
            self.target_btn.hide()
        if self._fix_kind != "none":
            form.addRow(t("source.fix") + ":", fix_row)
        else:
            self.fix_edit.hide()
            self.fix_btn.hide()

        layout.addLayout(form)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        self._apply_defaults()

    def _on_source_mode_changed(self) -> None:
        self._pick_archive = self._mode_archive.isChecked()
        if self._pick_archive:
            self.primary_edit.clear()
            self.primary_edit.setPlaceholderText(t("source.archive_ph"))
            self.version_hint.setText("")
        else:
            self._apply_defaults()

    def _primary_label(self) -> str:
        if self._pick_archive:
            return t("source.archive")
        kind = self._source_kind
        if kind == "folder":
            return t("source.folder")
        if kind == "installer":
            return t("source.installer")
        if kind == "archive":
            return t("source.archive")
        return t("source.label")

    def _apply_defaults(self) -> None:
        dr = Path(
            os.path.expanduser(
                self._meta.get("data_root", f"~/.local/share/wine-software/{self._rid}")
                .replace("{repo}", str(self._root))
            )
        )
        if self._source_kind == "folder":
            default = default_folder_source(self._rid, dr)
            if default:
                self.primary_edit.setText(default)
                self._update_version_hint(default)
        elif self._source_kind == "installer":
            self.primary_edit.setPlaceholderText(t("source.installer_ph"))
        elif self._source_kind == "archive":
            self.primary_edit.setPlaceholderText(t("source.archive_ph"))
        if self._show_target:
            self.target_edit.setText(default_target_dir(self._meta, self._rid, dr))
            self.target_edit.setPlaceholderText(
                str(documents_dir() / "WISO Steuer 2026")
                if self._rid == "wiso-steuer"
                else t("source.portable_ph")
            )

    def _pick_primary(self) -> None:
        if self._pick_archive:
            fmts = self._meta.get("source_formats", "zip,tar.gz,tgz")
            path, _ = QFileDialog.getOpenFileName(
                self,
                t("source.pick_archive"),
                "",
                archive_filter(fmts),
            )
            if path:
                self.primary_edit.setText(path)
            return
        kind = self._source_kind
        if kind == "folder":
            d = pick_directory(
                self, t("source.pick_folder"), self.primary_edit.text()
            )
            if d:
                normalized = normalize_folder_source(self._rid, d)
                self.primary_edit.setText(normalized)
                self._update_version_hint(normalized)
            return
        if kind == "installer":
            exe, _ = QFileDialog.getOpenFileName(
                self,
                t("source.pick_installer"),
                "",
                t("source.exe_filter"),
            )
            if exe:
                self.primary_edit.setText(exe)
            return
        if kind == "archive":
            fmts = self._meta.get("source_formats", "zip,tar.gz,tgz")
            path, _ = QFileDialog.getOpenFileName(
                self,
                t("source.pick_archive"),
                "",
                archive_filter(fmts),
            )
            if path:
                self.primary_edit.setText(path)

    def _pick_target(self) -> None:
        d = pick_directory(
            self,
            t("source.pick_target_dir"),
            self.target_edit.text() or str(documents_dir()),
        )
        if d:
            self.target_edit.setText(d)

    def _pick_fix(self) -> None:
        exe, _ = QFileDialog.getOpenFileName(
            self,
            t("source.pick_fix_exe"),
            "",
            t("source.exe_filter"),
        )
        if exe:
            self.fix_edit.setText(exe)
            return
        d = pick_directory(
            self, t("source.pick_fix_dir"), self.fix_edit.text()
        )
        if d:
            self.fix_edit.setText(d)

    def _normalize_primary(self) -> str:
        raw = self.primary_edit.text().strip()
        if self._source_kind == "folder" and raw and not self._pick_archive:
            return normalize_folder_source(self._rid, normalize_user_path(raw, self._root))
        return normalize_user_path(raw, self._root) if raw else raw

    def _normalize_target(self) -> str:
        return normalize_user_path(self.target_edit.text(), self._root)

    def _update_version_hint(self, path: str) -> None:
        guaranteed = self._version_guaranteed
        detected = detect_source_version(self._rid, path)
        if not guaranteed:
            self.version_hint.setText("")
            return
        if not detected:
            self.version_hint.setText(t("source.version_unknown"))
            self.version_hint.setStyleSheet("color: #fbbf24")
            return
        if version_guarantee_mismatch(guaranteed, detected):
            self.version_hint.setText(
                t(
                    "source.version_mismatch",
                    detected=detected,
                    guaranteed=guaranteed,
                )
            )
            self.version_hint.setStyleSheet("color: #fbbf24")
        else:
            self.version_hint.setText(t("source.version_ok", detected=detected))
            self.version_hint.setStyleSheet("color: #86efac")

    def _on_accept(self) -> None:
        kind = self._source_kind
        primary = self._normalize_primary()
        if kind == "folder":
            if self._pick_archive:
                primary = normalize_user_path(self.primary_edit.text().strip(), self._root)
            if not primary:
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_source")
                )
                return
            if self._pick_archive and not Path(primary).is_file():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_archive")
                )
                return
            if not self._pick_archive and not Path(primary).is_dir():
                QMessageBox.warning(
                    self,
                    t("source.folder_missing_title"),
                    t("source.need_folder", path=primary),
                )
                return
            if self._fix_kind == "required" and not self.fix_edit.text().strip():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_fix")
                )
                return
            if self._show_target:
                target = self._normalize_target()
                if not target:
                    QMessageBox.warning(
                        self, t("dialog.missing"), t("source.need_target")
                    )
                    return
                parent = Path(target).parent
                if not parent.is_dir():
                    QMessageBox.warning(
                        self,
                        t("source.target_invalid_title"),
                        t("source.target_invalid", parent=parent),
                    )
                    return
                self.target_edit.setText(target)
            self.primary_edit.setText(primary)
            self.accept()
            return
        primary = normalize_user_path(self.primary_edit.text().strip(), self._root)
        if kind == "installer":
            if not primary or not Path(primary).is_file():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_exe")
                )
                return
            self.accept()
            return
        if kind == "archive":
            if not primary or not Path(primary).is_file():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_archive")
                )
                return
            if self._show_target:
                target = self._normalize_target()
                if not target:
                    QMessageBox.warning(
                        self, t("dialog.missing"), t("source.need_target")
                    )
                    return
                self.target_edit.setText(target)
            self.primary_edit.setText(primary)
            self.accept()
            return
        self.reject()

    def primary_path(self) -> str:
        return self._normalize_primary()

    def fix_path(self) -> str:
        return normalize_user_path(self.fix_edit.text().strip(), self._root)

    def target_path(self) -> str:
        return self._normalize_target()

    def build_env(self, data_root: Path) -> dict[str, str]:
        """Return env vars for install.sh (Archiv-Entpacken erfolgt in prepare_source)."""
        kind = self._source_kind
        extra: dict[str, str] = {}
        deploy = self._meta.get("deploy_mode", "copy")
        if deploy:
            extra["RECIPE_DEPLOY_MODE"] = deploy
        if self._show_target:
            tgt = self.target_path()
            extra["RECIPE_TARGET_DIR"] = tgt
            if self._rid == "wiso-steuer":
                extra["WISO_TARGET_DIR"] = tgt
        if kind == "folder":
            if self._pick_archive:
                extra["RECIPE_ARCHIVE_PATH"] = self.primary_path()
            else:
                root = self.primary_path()
                extra["RECIPE_SOURCE_ROOT"] = root
                if self._rid == "wiso-steuer":
                    extra["WISO_PORTABLE_ROOT"] = root
            fix = self.fix_path()
            if fix:
                extra["RECIPE_FIX_ROOT"] = fix
                if self._rid == "wiso-steuer":
                    extra["WISO_FIX_ROOT"] = fix
            return extra
        if kind == "installer":
            extra["RECIPE_INSTALLER_PATH"] = self.primary_path()
            return extra
        if kind == "archive":
            extra["RECIPE_ARCHIVE_PATH"] = self.primary_path()
            return extra
        return extra


def needs_source_dialog(meta: dict[str, str]) -> bool:
    return meta.get("source_kind", "") not in ("", "fixed_path")


def source_configure_label(meta: dict[str, str]) -> str:
    kind = meta.get("source_kind", "")
    if kind == "folder":
        label = meta.get("source_label") or t("source.configure_folder")
        return label[:40] + "…"
    if kind == "installer":
        return t("source.configure_installer")
    if kind == "archive":
        return t("source.configure_archive")
    return t("source.configure")
