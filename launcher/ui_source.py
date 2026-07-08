"""Unified recipe source picker (folder / installer / archive)."""

from __future__ import annotations

import os
import subprocess
import zipfile
from pathlib import Path
from tarfile import TarFile

from PyQt6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from app_support import detect_source_version, version_guarantee_mismatch


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
        fallback = Path.home() / "Dokumente/WISO.2026.33.3.2920.Portable"
        if fallback.is_dir():
            return str(fallback)
    return ""


def archive_filter(formats: str) -> str:
    parts = [p.strip() for p in formats.split(",") if p.strip()]
    if not parts:
        parts = ["zip", "tar.gz", "tgz"]
    labels: list[str] = []
    for p in parts:
        labels.append(f"*.{p}")
    return f"Archive ({' '.join(labels)})"


def extract_archive_python(archive: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    name = archive.name.lower()
    if name.endswith(".zip"):
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(dest)
        return
    if name.endswith(".tar.gz") or name.endswith(".tgz"):
        with TarFile.open(archive, "r:gz") as tf:
            tf.extractall(dest)
        return
    raise ValueError(f"Unsupported archive: {archive}")


def extract_archive_bash(root: Path, archive: Path, dest: Path) -> bool:
    script = root / "core" / "recipe-source.sh"
    if not script.is_file():
        return False
    proc = subprocess.run(
        ["bash", str(script), "extract", str(archive), str(dest)],
        cwd=str(root),
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0


class RecipeSourceDialog(QDialog):
    """Meta-driven source picker for install / reconfigure."""

    def __init__(
        self,
        parent: QWidget | None,
        *,
        rid: str,
        meta: dict[str, str],
        root: Path,
        title: str = "Quelle wählen",
    ) -> None:
        super().__init__(parent)
        self._rid = rid
        self._meta = meta
        self._root = root
        self._source_kind = meta.get("source_kind", "folder")
        self._fix_kind = meta.get("fix_kind", "none")
        self._version_guaranteed = meta.get("version_guaranteed", "").strip()
        self._extract_dir: Path | None = None
        self._archive_path = ""

        self.setWindowTitle(title)
        self.resize(580, 260)

        layout = QVBoxLayout(self)
        layout.setSpacing(12)

        label = meta.get("source_label") or "Quelle"
        intro = QLabel(label)
        intro.setObjectName("muted")
        intro.setWordWrap(True)
        layout.addWidget(intro)

        self.version_hint = QLabel("")
        self.version_hint.setObjectName("muted")
        self.version_hint.setWordWrap(True)
        layout.addWidget(self.version_hint)

        form = QFormLayout()
        self.primary_edit = QLineEdit()
        self.fix_edit = QLineEdit()
        self.primary_btn = QPushButton("Wählen…")
        self.fix_btn = QPushButton("Fix wählen…")

        self.primary_btn.clicked.connect(self._pick_primary)
        self.fix_btn.clicked.connect(self._pick_fix)

        primary_row = QHBoxLayout()
        primary_row.addWidget(self.primary_edit, stretch=1)
        primary_row.addWidget(self.primary_btn)

        fix_row = QHBoxLayout()
        fix_row.addWidget(self.fix_edit, stretch=1)
        fix_row.addWidget(self.fix_btn)

        primary_label = self._primary_label()
        form.addRow(primary_label + ":", primary_row)
        if self._fix_kind != "none":
            form.addRow("Fix:", fix_row)
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

    def _primary_label(self) -> str:
        kind = self._source_kind
        if kind == "folder":
            return "Ordner"
        if kind == "installer":
            return "Installer"
        if kind == "archive":
            return "Archiv"
        return "Quelle"

    def _apply_defaults(self) -> None:
        if self._source_kind == "folder":
            dr = Path(
                os.path.expanduser(
                    self._meta.get("data_root", f"~/.local/share/wine-software/{self._rid}")
                    .replace("{repo}", str(self._root))
                )
            )
            default = default_folder_source(self._rid, dr)
            if default:
                self.primary_edit.setText(default)
                self._update_version_hint(default)
        elif self._source_kind == "installer":
            self.primary_edit.setPlaceholderText("Setup.exe")
        elif self._source_kind == "archive":
            self.primary_edit.setPlaceholderText("zip / tar.gz / tgz")

    def _pick_primary(self) -> None:
        kind = self._source_kind
        if kind == "folder":
            d = QFileDialog.getExistingDirectory(self, "Ordner wählen")
            if d:
                normalized = normalize_folder_source(self._rid, d)
                self.primary_edit.setText(normalized)
                self._update_version_hint(normalized)
            return
        if kind == "installer":
            exe, _ = QFileDialog.getOpenFileName(
                self,
                "Installer wählen",
                "",
                "Windows-Programme (*.exe);;Alle Dateien (*)",
            )
            if exe:
                self.primary_edit.setText(exe)
            return
        if kind == "archive":
            fmts = self._meta.get("source_formats", "zip,tar.gz,tgz")
            path, _ = QFileDialog.getOpenFileName(
                self,
                "Archiv wählen",
                "",
                archive_filter(fmts),
            )
            if path:
                self.primary_edit.setText(path)

    def _pick_fix(self) -> None:
        exe, _ = QFileDialog.getOpenFileName(
            self,
            "Fix — .exe wählen",
            "",
            "Windows-Programme (*.exe);;Alle Dateien (*)",
        )
        if exe:
            self.fix_edit.setText(exe)
            return
        d = QFileDialog.getExistingDirectory(self, "Fix — Ordner wählen (optional)")
        if d:
            self.fix_edit.setText(d)

    def _update_version_hint(self, path: str) -> None:
        guaranteed = self._version_guaranteed
        detected = detect_source_version(self._rid, path)
        if not guaranteed:
            self.version_hint.setText("")
            return
        if not detected:
            self.version_hint.setText(
                "Version nicht erkannt — Abweichung von der getesteten Version möglich."
            )
            self.version_hint.setStyleSheet("color: #fbbf24")
            return
        if version_guarantee_mismatch(guaranteed, detected):
            self.version_hint.setText(
                f"Erkannt: {detected} — getestet & garantiert ist {guaranteed}."
            )
            self.version_hint.setStyleSheet("color: #fbbf24")
        else:
            self.version_hint.setText(f"Version {detected} — getestet & garantiert.")
            self.version_hint.setStyleSheet("color: #86efac")

    def _on_accept(self) -> None:
        kind = self._source_kind
        primary = self.primary_edit.text().strip()
        if kind == "folder":
            if not primary:
                QMessageBox.warning(self, "Fehlt", "Bitte einen Ordner wählen.")
                return
            if self._fix_kind == "required" and not self.fix_edit.text().strip():
                QMessageBox.warning(self, "Fehlt", "Fix-Paket ist für dieses Rezept erforderlich.")
                return
            self.accept()
            return
        if kind == "installer":
            if not primary or not Path(primary).is_file():
                QMessageBox.warning(self, "Fehlt", "Bitte eine .exe-Datei wählen.")
                return
            self.accept()
            return
        if kind == "archive":
            if not primary or not Path(primary).is_file():
                QMessageBox.warning(self, "Fehlt", "Bitte ein Archiv wählen.")
                return
            self.accept()
            return
        self.reject()

    def primary_path(self) -> str:
        raw = self.primary_edit.text().strip()
        if self._source_kind == "folder" and raw:
            return normalize_folder_source(self._rid, raw)
        return raw

    def fix_path(self) -> str:
        return self.fix_edit.text().strip()

    def build_env(self, data_root: Path) -> dict[str, str]:
        """Return env vars for install.sh; extracts archives when needed."""
        kind = self._source_kind
        extra: dict[str, str] = {}
        if kind == "folder":
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
            archive = Path(self.primary_path())
            staging = data_root / "staging" / self._rid
            staging.mkdir(parents=True, exist_ok=True)
            try:
                extract_archive_python(archive, staging)
            except (OSError, ValueError, zipfile.BadZipFile):
                if not extract_archive_bash(self._root, archive, staging):
                    raise
            self._extract_dir = staging
            self._archive_path = str(archive)
            extra["RECIPE_ARCHIVE_PATH"] = self._archive_path
            extra["RECIPE_EXTRACT_DIR"] = str(staging)
            if self._rid == "wiso-steuer":
                extra["WISO_PORTABLE_ROOT"] = str(staging)
                extra["RECIPE_SOURCE_ROOT"] = str(staging)
            return extra
        return extra


def needs_source_dialog(meta: dict[str, str]) -> bool:
    return meta.get("source_kind", "") not in ("", "fixed_path")


def source_configure_label(meta: dict[str, str]) -> str:
    kind = meta.get("source_kind", "")
    if kind == "folder":
        return meta.get("source_label", "Quellordner…")[:40] + "…"
    if kind == "installer":
        return "Installer-Pfad…"
    if kind == "archive":
        return "Archiv-Pfad…"
    return "Quelle konfigurieren…"
