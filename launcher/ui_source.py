"""Unified recipe source picker (folder / installer / archive)."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse

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
from steam_paths import default_trainer_target, steam_app_install_dir

# Keine Optionen, die Qt auf den internen Dialog zwingen (Laufwerke fehlen sonst).
_NATIVE_DIR_OPTS = QFileDialog.Option(0)


def _desktop_pick_directory(title: str, start_dir: str) -> str | None:
    """KDE/GNOME system picker — identical for host and AppImage (pip Qt lacks KDE theme)."""
    start = start_dir or str(Path.home())
    if os.path.isfile("/usr/bin/kdialog") or shutil.which("kdialog"):
        kdialog = shutil.which("kdialog") or "/usr/bin/kdialog"
        try:
            proc = subprocess.run(
                [kdialog, "--getexistingdirectory", start, "--title", title],
                capture_output=True,
                text=True,
                timeout=600,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        if proc.returncode == 0:
            return (proc.stdout or "").strip()
        return ""  # cancel — do not fall through to a second Qt dialog
    if shutil.which("zenity"):
        try:
            proc = subprocess.run(
                [
                    "zenity",
                    "--file-selection",
                    "--directory",
                    f"--title={title}",
                    f"--filename={start.rstrip('/')}/",
                ],
                capture_output=True,
                text=True,
                timeout=600,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        if proc.returncode == 0:
            return (proc.stdout or "").strip()
        return ""
    return None


def _desktop_pick_open_file(title: str, start_dir: str, file_filter: str) -> str | None:
    """System file picker (same host/AppImage path as directories)."""
    start = start_dir or str(Path.home())
    # Qt filter "Label (*.exe *.EXE)" → kdialog/zenity filter
    filt = ""
    if "(" in file_filter and ")" in file_filter:
        inner = file_filter[file_filter.find("(") + 1 : file_filter.find(")")]
        parts = [p.strip() for p in inner.replace(" ", "\n").split() if p.strip().startswith("*")]
        if parts:
            filt = " ".join(parts)
    if shutil.which("kdialog"):
        cmd = ["kdialog", "--getopenfilename", start, "--title", title]
        if filt:
            cmd.append(filt)
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if proc.returncode == 0:
            return (proc.stdout or "").strip()
        return ""
    if shutil.which("zenity"):
        cmd = [
            "zenity",
            "--file-selection",
            f"--title={title}",
            f"--filename={start.rstrip('/')}/",
        ]
        if filt:
            cmd.append(f"--file-filter={file_filter}")
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if proc.returncode == 0:
            return (proc.stdout or "").strip()
        return ""
    return None


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
    """~, {repo}, file://, //Dokumente/… und doppelte Slashes bereinigen."""
    text = (raw or "").strip()
    if not text:
        return text
    if root is not None:
        text = text.replace("{repo}", str(root))
    # Portal/Qt manchmal als file://-URL
    if text.startswith("file://"):
        parsed = urlparse(text)
        text = unquote(parsed.path or "")
        if parsed.netloc and not text.startswith("//"):
            # file://hostname/path (selten)
            text = f"/{parsed.netloc}{text}" if text.startswith("/") else f"/{parsed.netloc}/{text}"
    expanded = os.path.expanduser(text)
    # KDE/Hand-Eingabe: //Dokumente/… ohne Home → ~/Dokumente/…
    # Aber //mnt/… bzw. existierende Absolutpfade nicht nach $HOME schieben
    if expanded.startswith("//") and not expanded.startswith("///"):
        rest = expanded[2:]
        first = rest.split("/", 1)[0]
        abs_candidate = Path("/") / rest
        if first in {"mnt", "run", "media", "home", "opt", "var"} or abs_candidate.exists():
            expanded = str(abs_candidate)
        elif rest and not rest.startswith("/"):
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
    """Ordner wählen — gleicher Systemdialog für Host und AppImage (kdialog/zenity/Qt)."""
    start_dir = dialog_start_dir(start)
    desktop = _desktop_pick_directory(title, start_dir)
    if desktop is not None:
        return normalize_user_path(desktop) if desktop else ""
    chosen = QFileDialog.getExistingDirectory(
        parent,
        title,
        start_dir,
        options=_NATIVE_DIR_OPTS,
    )
    return normalize_user_path(chosen) if chosen else ""


def pick_open_file(
    parent: QWidget,
    title: str,
    start: str,
    file_filter: str,
) -> str:
    """Datei wählen — gleicher Systemdialog für Host und AppImage."""
    start_dir = dialog_start_dir(start)
    desktop = _desktop_pick_open_file(title, start_dir, file_filter)
    if desktop is not None:
        return normalize_user_path(desktop) if desktop else ""
    path, _ = QFileDialog.getOpenFileName(
        parent,
        title,
        start_dir,
        file_filter,
        options=_NATIVE_DIR_OPTS,
    )
    return normalize_user_path(path) if path else ""


def needs_target_dir(meta: dict[str, str]) -> bool:
    """Zielordner: Portable-Apps und jedes Rezept mit target_* (z. B. Photoshop-Datenordner)."""
    if meta.get("deploy_mode", "copy") == "link":
        return False
    if (meta.get("target_default") or "").strip() or (meta.get("target_label") or "").strip():
        return True
    return meta.get("install_type", "") in (
        "portable_launch",
        "portable_bootstrap",
        "game_portable",
    )


def is_portable_install(meta: dict[str, str]) -> bool:
    return meta.get("install_type", "") in (
        "portable_launch",
        "portable_bootstrap",
        "game_portable",
    )


def default_target_dir(
    meta: dict[str, str], rid: str = "", data_root: Path | None = None
) -> str:
    # Trainer / Steam: Spielordner automatisch, manuell überschreibbar
    appid = (meta.get("steam_appid") or "").strip()
    if appid:
        folder = (meta.get("steam_target_folder") or "Trainer").strip() or "Trainer"
        auto = default_trainer_target(appid, folder)
        if auto:
            return normalize_user_path(auto)
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
    if data_root is not None:
        pointer = data_root / "data_root.path"
        if pointer.is_file():
            val = pointer.read_text(encoding="utf-8").strip()
            if val:
                target = Path(normalize_user_path(val))
                # Existiert oder Parent da (wird bei Install angelegt) → Vorschlag behalten
                if target.is_dir() or target.parent.is_dir():
                    return str(target)
    raw = (meta.get("target_default") or "").strip()
    if raw:
        return normalize_user_path(raw)
    if data_root is not None:
        return str(data_root)
    return str(documents_dir())


def normalize_folder_source(rid: str, raw: str) -> str:
    p = Path(raw)
    if not p.is_dir():
        return raw
    if rid == "wiso-steuer" and p.name.startswith("Steuersoftware"):
        return str(p.parent.resolve())
    return str(p.resolve())


def default_folder_source(
    rid: str,
    data_root: Path,
    repo_root: Path | None = None,
    *,
    meta: dict[str, str] | None = None,
) -> str:
    meta = meta or {}
    # Steam-Spielordner (z. B. house-of-ashes mit deploy_mode: link)
    appid = (meta.get("steam_appid") or "").strip()
    if appid and meta.get("deploy_mode", "copy") == "link":
        game = steam_app_install_dir(appid)
        if game is not None and game.is_dir():
            return str(game)
    if rid == "photoshop":
        candidates: list[Path] = []
        if repo_root is not None:
            candidates.append(repo_root / "photoshop")
        for base in (Path.home() / "Downloads", Path.home() / "Dokumente"):
            if not base.is_dir():
                continue
            try:
                for p in sorted(base.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
                    if p.is_dir() and (p / "Set-up.exe").is_file():
                        candidates.append(p)
            except OSError:
                continue
        for cand in candidates:
            if cand.is_dir() and (cand / "Set-up.exe").is_file():
                return str(cand.resolve())
        return ""
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
            default = default_folder_source(self._rid, dr, self._root, meta=self._meta)
            if default:
                self.primary_edit.setText(default)
                self._update_version_hint(default)
        elif self._source_kind == "installer":
            self.primary_edit.setPlaceholderText(t("source.installer_ph"))
        elif self._source_kind == "archive":
            self.primary_edit.setPlaceholderText(t("source.archive_ph"))
        if self._show_target:
            self.target_edit.setText(default_target_dir(self._meta, self._rid, dr))
            if self._rid == "wiso-steuer":
                ph = str(documents_dir() / "WISO Steuer 2026")
            elif (self._meta.get("steam_appid") or "").strip():
                ph = t("source.steam_target_ph")
            elif is_portable_install(self._meta):
                ph = t("source.portable_ph")
            else:
                ph = t("source.data_root_ph")
            self.target_edit.setPlaceholderText(ph)

    def _pick_primary(self) -> None:
        start = self.primary_edit.text() or str(documents_dir())
        if self._pick_archive:
            fmts = self._meta.get("source_formats", "zip,tar.gz,tgz")
            path = pick_open_file(
                self, t("source.pick_archive"), start, archive_filter(fmts)
            )
            if path:
                self.primary_edit.setText(path)
                self._update_version_hint(path)
            return
        kind = self._source_kind
        if kind == "folder":
            title = (self._meta.get("source_label") or "").strip() or t(
                "source.pick_folder"
            )
            d = pick_directory(self, title, start)
            if d:
                normalized = normalize_folder_source(self._rid, d)
                self.primary_edit.setText(normalized)
                self._update_version_hint(normalized)
            return
        if kind == "installer":
            fmts = (self._meta.get("source_formats") or "").strip()
            if fmts:
                parts = [p.strip() for p in fmts.split(",") if p.strip()]
                globs = " ".join(f"*.{p}" for p in parts)
                file_filter = f"{t('source.file_filter_label')} ({globs});;{t('source.all_files')}"
            else:
                file_filter = t("source.exe_filter")
            exe = pick_open_file(
                self, t("source.pick_installer"), start, file_filter
            )
            if exe:
                self.primary_edit.setText(exe)
                self._update_version_hint(exe)
            return
        if kind == "archive":
            fmts = self._meta.get("source_formats", "zip,tar.gz,tgz")
            path = pick_open_file(
                self, t("source.pick_archive"), start, archive_filter(fmts)
            )
            if path:
                self.primary_edit.setText(path)
                self._update_version_hint(path)

    def _pick_target(self) -> None:
        d = pick_directory(
            self,
            t("source.pick_target_dir"),
            self.target_edit.text() or str(documents_dir()),
        )
        if d:
            self.target_edit.setText(d)

    def _pick_fix(self) -> None:
        start = self.fix_edit.text() or str(documents_dir())
        exe = pick_open_file(
            self, t("source.pick_fix_exe"), start, t("source.exe_filter")
        )
        if exe:
            self.fix_edit.setText(exe)
            return
        d = pick_directory(self, t("source.pick_fix_dir"), start)
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
        detected = detect_source_version(
            self._rid,
            path,
            recipe_dir=self._meta.get("_dir"),
            guaranteed=guaranteed,
        )
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
            if is_portable_install(self._meta):
                if self._rid == "wiso-steuer":
                    extra["WISO_TARGET_DIR"] = tgt
            else:
                # Installer / native: Ziel = Datenordner (Prefix darunter)
                extra["RECIPE_DATA_ROOT"] = tgt
                extra["DATA_ROOT"] = tgt
                extra["WINEPREFIX"] = f"{tgt}/prefix"
                extra["WINE_PREFIX"] = f"{tgt}/prefix"
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
