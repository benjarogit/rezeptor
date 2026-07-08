#!/usr/bin/env python3
"""Rezeptor — GUI für getestete Wine-Software-Rezepte (Proton-GE)."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import uuid
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

try:
    from PyQt6.QtCore import Qt, QProcess, QProcessEnvironment, QSize, QTimer, QUrl
    from PyQt6.QtGui import QAction, QColor, QDesktopServices, QFont, QIcon, QPixmap
    from PyQt6.QtWidgets import (
        QApplication,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFileDialog,
        QFormLayout,
        QFrame,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QListWidget,
        QListWidgetItem,
        QMainWindow,
        QMenu,
        QMessageBox,
        QProgressBar,
        QPushButton,
        QScrollArea,
        QSizePolicy,
        QStackedWidget,
        QStatusBar,
        QTabWidget,
        QTextBrowser,
        QTextEdit,
        QToolButton,
        QVBoxLayout,
        QWidget,
    )
except ImportError:
    print(
        "PyQt6 wird benötigt:\n"
        "  pacman -S python-pyqt6   (Arch/CachyOS)\n"
        "Optional Fluent Design:\n"
        "  pip install --user --break-system-packages PyQt6-Fluent-Widgets",
        file=sys.stderr,
    )
    sys.exit(1)


ROOT = Path(__file__).resolve().parent.parent
_LAUNCHER_DIR = Path(__file__).resolve().parent
if str(_LAUNCHER_DIR) not in sys.path:
    sys.path.insert(0, str(_LAUNCHER_DIR))

from app_support import (
    GITHUB_REPO,
    LOG_RETENTION_DAYS,
    VERSION_GUARANTEE_HELP,
    collect_report_bundle,
    fetch_latest_release,
    github_issue_url,
    humanize_log_line,
    parse_validate_version_fields,
    prune_old_logs,
    read_version,
    report_clipboard_text,
    version_compare,
)
from ui_fluent import (
    ACCENT_COPPER,
    COLOR_TESTED,
    FLUENT_AVAILABLE,
    CaptionLabel,
    CardWidget,
    FluentIcon,
    Pivot,
    PrimaryPushButton,
    PushButton,
    SubtitleLabel,
    TitleLabel,
    app_stylesheet,
)
from ui_rezeptor import (
    REZEPTOR_ICON,
    SEGMENT_TAB_STYLES,
    RecipeSidebarCard,
    SegmentTabBar,
    StatusPill,
)
from ui_source import (
    RecipeSourceDialog,
    needs_source_dialog,
    source_configure_label,
)
from recipe_trust import rezeptor_dev_mode, verify_recipe_trust
from ui_styles import APP_STYLESHEET, STATE_COLORS

RECIPES_DIR = ROOT / "recipes"
MANIFEST_PATH = RECIPES_DIR / "manifest.json"
LOG_ROOT = Path.home() / ".local/share/wine-software/logs"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m|\x08+")
SPINNER_RE = re.compile(r"^\[[\\/\-\|]\]\s*$")
GUI_TAG_RE = re.compile(r"^@(step|ok|warn|error|info|progress):(.+)$")
PROGRESS_RE = re.compile(r"Progress:\s*(\d+)%", re.I)


class RecipeState(str, Enum):
    NOT_INSTALLED = "not_installed"
    PARTIAL = "partial"
    INSTALLED = "installed"
    UNKNOWN = "unknown"


STATE_LABEL = {
    RecipeState.NOT_INSTALLED: "Nicht installiert",
    RecipeState.PARTIAL: "Teilweise",
    RecipeState.INSTALLED: "Installiert",
    RecipeState.UNKNOWN: "Unbekannt",
}


@dataclass
class RecipeInfo:
    rid: str
    meta: dict[str, str]
    state: RecipeState = RecipeState.UNKNOWN
    status_detail: str = ""
    version_detected: str = ""
    version_warning: str = ""


def parse_recipe_yml(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        data[key.strip()] = val.strip().strip('"')
    return data


def discover_recipes() -> list[RecipeInfo]:
    found: list[RecipeInfo] = []
    trust_failures: list[str] = []
    if not RECIPES_DIR.is_dir():
        return found
    for yml in sorted(RECIPES_DIR.glob("*/recipe.yml")):
        if yml.parent.name.startswith("_"):
            continue
        ok, reason = verify_recipe_trust(yml.parent, MANIFEST_PATH)
        if not ok:
            rid_hint = yml.parent.name
            trust_failures.append(f"{rid_hint}: {reason}")
            continue
        meta = parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        meta["_dir"] = str(yml.parent)
        found.append(RecipeInfo(rid=rid, meta=meta))
    if trust_failures and not rezeptor_dev_mode():
        os.environ.setdefault(
            "REZEPTOR_TRUST_LOG",
            "\n".join(trust_failures),
        )
    return found


def expand_home(path: str) -> Path:
    return Path(os.path.expanduser(path.replace("{repo}", str(ROOT))))


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text).strip()


LAUNCH_PROCESS_PATTERNS: dict[str, list[str]] = {
    "wiso-steuer": ["wmain26", "wiso2026", "QtWebEngineProcess"],
    "photoshop": ["Photoshop.exe"],
}


def desktop_entry_for_recipe(rid: str, meta: dict[str, str]) -> Path | None:
    dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{rid}"))
    candidates = [
        Path.home() / ".local/share/applications/photoshop.desktop",
        dr / "launcher/photoshop.desktop",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None


def recipe_icon(meta: dict[str, str]) -> QIcon:
    raw = meta.get("icon", "")
    if raw:
        p = expand_home(raw)
        if p.is_file():
            return QIcon(str(p))
    if REZEPTOR_ICON.is_file():
        return QIcon(str(REZEPTOR_ICON))
    return QIcon()


def recipe_fluent_icon(rid: str):
    if not FLUENT_AVAILABLE or FluentIcon is None:
        return None
    if rid == "wiso-steuer":
        return FluentIcon.CALENDAR
    return FluentIcon.BRUSH


def recipe_info_text(rid: str, recipe_dir: Path) -> str:
    for name in (f"info.de.txt", f"info.txt", f"{rid}.info.de.txt"):
        p = recipe_dir / name
        if p.is_file():
            return p.read_text(encoding="utf-8").strip()
    return "Keine Rezept-Beschreibung vorhanden."


def query_recipe_state(
    rid: str, meta: dict[str, str], env: dict[str, str]
) -> tuple[RecipeState, str, str, str]:
    rd = Path(meta["_dir"])
    validate = rd / "validate.sh"
    dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{rid}"))
    prefix = dr / "prefix"
    empty = ("", "")

    if validate.is_file():
        proc = subprocess.run(
            ["bash", str(validate)],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        detected, version_warn = parse_validate_version_fields(out)
        if proc.returncode == 0:
            detail = version_warn or "Alle Prüfungen OK"
            return RecipeState.INSTALLED, detail, detected, version_warn
        if prefix.is_dir() and (prefix / "user.reg").is_file():
            fail = next((ln for ln in out.splitlines() if ln.startswith("FAIL:")), "")
            detail = fail or version_warn or "Prefix vorhanden"
            return RecipeState.PARTIAL, detail, detected, version_warn
        return (
            RecipeState.NOT_INSTALLED,
            out.strip().splitlines()[0] if out.strip() else "Nicht installiert",
            detected,
            version_warn,
        )

    if prefix.is_dir() and (prefix / "user.reg").is_file():
        return RecipeState.PARTIAL, str(prefix), *empty
    return RecipeState.NOT_INSTALLED, "Nicht installiert", *empty


class AboutDialog(QDialog):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Über Rezeptor")
        self.resize(480, 320)
        layout = QVBoxLayout(self)
        ver = read_version()
        layout.addWidget(QLabel(f"<h2>Rezeptor</h2><p>Version {ver}</p>"))
        body = QTextBrowser()
        body.setOpenExternalLinks(True)
        body.setHtml(
            f"<p>Getestete Wine-Rezepte — Installieren, Starten, Prüfen, Reparieren.</p>"
            f"<p><b>Projekt:</b> <a href='https://github.com/{GITHUB_REPO}'>"
            f"github.com/{GITHUB_REPO}</a></p>"
            f"<p><b>Lizenz:</b> GPL-2.0</p>"
            f"<p>Copyright © 2024–2026 Sunny C.</p>"
        )
        layout.addWidget(body)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        buttons.accepted.connect(self.accept)
        buttons.clicked.connect(lambda _: self.accept())
        layout.addWidget(buttons)


class RezeptorWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(f"Rezeptor — v{read_version()}")
        if REZEPTOR_ICON.is_file():
            self.setWindowIcon(QIcon(str(REZEPTOR_ICON)))
        self.resize(1080, 680)
        self.setMinimumSize(880, 520)
        self.session_id = uuid.uuid4().hex[:12]
        self.recipes = discover_recipes()
        self._dev_mode = rezeptor_dev_mode()
        self._selected: RecipeInfo | None = None
        self._selected_index = -1
        self._recipe_cards: list[tuple[RecipeSidebarCard, RecipeInfo]] = []
        self._process: QProcess | None = None
        self._busy = False
        self._raw_log_buffer: list[str] = []
        self._latest_release = ""
        self._release_url = f"https://github.com/{GITHUB_REPO}/releases"
        self._wiso_mono_hint_shown = False

        self._build_menus()
        self._build_status_bar()
        self._build_layout()

        self._populate_list()
        removed = prune_old_logs()
        if removed:
            self._activity("info", f"{removed} alte Log-Datei(en) entfernt (>{LOG_RETENTION_DAYS} Tage)")
        self.populate_log_files()
        trust_log = os.environ.pop("REZEPTOR_TRUST_LOG", "")
        if trust_log:
            for line in trust_log.splitlines():
                self._activity(
                    "warn",
                    f"Rezept ausgeblendet: {line} "
                    "(Fix: ./scripts/recipe-manifest.sh, Rezeptor neu starten)",
                )
        if self._dev_mode:
            self._activity("info", "Dev-Modus — Manifest-Prüfung deaktiviert")
        if self.recipes:
            self._select_recipe_index(0)
        QTimer.singleShot(500, self.check_updates_background)

    def _build_menus(self) -> None:
        recipe_menu = self.menuBar().addMenu("Rezept")
        self.action_refresh = QAction("Status neu prüfen", self)
        self.action_refresh.setToolTip(
            "Installationsstatus aller Rezepte per validate.sh aktualisieren "
            "(Passiert automatisch nach Install/Reparatur und beim Start)."
        )
        self.action_refresh.triggered.connect(self.refresh_statuses)
        recipe_menu.addAction(self.action_refresh)

        help_menu = self.menuBar().addMenu("Hilfe")
        help_menu.addAction("Update prüfen…", self.check_updates)
        help_menu.addSeparator()
        help_menu.addAction("Fehler auf GitHub melden…", self.report_bug)
        help_menu.addAction("Über Rezeptor…", self.show_about)

    def _build_status_bar(self) -> None:
        sb = QStatusBar()
        sb.setContentsMargins(8, 0, 8, 0)
        self.setStatusBar(sb)
        self.status_footer = QLabel()
        self.status_footer.setObjectName("statusFooter")
        self._refresh_status_footer()
        sb.addWidget(self.status_footer)

    def _refresh_status_footer(self, update: str = "") -> None:
        cur = read_version()
        dev = "  ·  Dev-Modus" if self._dev_mode else ""
        if update:
            self.status_footer.setText(f"Rezeptor v{cur}{dev}  ·  ● Update v{update}")
            self.status_footer.setStyleSheet("color: #9d9da6;")
        else:
            self.status_footer.setText(f"Rezeptor v{cur}{dev}")
            self.status_footer.setStyleSheet("color: #9d9da6;")

    def _build_layout(self) -> None:
        central = QWidget()
        self.setCentralWidget(central)
        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # —— Sidebar ——
        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(240)
        sl = QVBoxLayout(sidebar)
        sl.setContentsMargins(12, 14, 12, 12)
        sl.setSpacing(10)

        st = QLabel("REZEPTE")
        st.setObjectName("sidebarTitle")
        sl.addWidget(st)

        self.recipe_cards_host = QWidget()
        self.recipe_cards_host.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        self.recipe_cards_layout = QVBoxLayout(self.recipe_cards_host)
        self.recipe_cards_layout.setContentsMargins(0, 0, 0, 0)
        self.recipe_cards_layout.setSpacing(8)
        self.recipe_cards_layout.setAlignment(Qt.AlignmentFlag.AlignTop)
        sl.addWidget(self.recipe_cards_host, 0, Qt.AlignmentFlag.AlignTop)
        sl.addStretch(1)
        root.addWidget(sidebar)

        # —— Hauptbereich ——
        main = QWidget()
        ml = QVBoxLayout(main)
        ml.setContentsMargins(16, 14, 16, 12)
        ml.setSpacing(12)

        header = CardWidget() if FLUENT_AVAILABLE else QFrame()
        if not FLUENT_AVAILABLE:
            header.setObjectName("headerCard")
        hl = QHBoxLayout(header)
        hl.setContentsMargins(16, 14, 16, 14)
        hl.setSpacing(16)

        self.icon_label = QLabel()
        self.icon_label.setFixedSize(72, 72)
        self.icon_label.setScaledContents(True)
        if REZEPTOR_ICON.is_file():
            self.icon_label.setPixmap(QIcon(str(REZEPTOR_ICON)).pixmap(72, 72))
        hl.addWidget(self.icon_label, alignment=Qt.AlignmentFlag.AlignTop)

        hc = QVBoxLayout()
        hc.setSpacing(6)
        self.name_label = TitleLabel("Rezept wählen") if FLUENT_AVAILABLE else QLabel("Rezept wählen")
        if not FLUENT_AVAILABLE:
            self.name_label.setObjectName("appTitle")
        else:
            self.name_label.setText("Rezept wählen")

        self.version_info_btn = QToolButton()
        self.version_info_btn.setText("ℹ")
        self.version_info_btn.setToolTip("Version & Garantie — Klick für Details")
        self.version_info_btn.setFixedSize(24, 24)
        self.version_info_btn.clicked.connect(self._show_version_guarantee_info)
        self.version_info_btn.setVisible(False)

        title_row = QHBoxLayout()
        title_row.setSpacing(8)
        title_row.addWidget(self.name_label, stretch=1)
        title_row.addWidget(
            self.version_info_btn, alignment=Qt.AlignmentFlag.AlignTop
        )

        pills_row = QHBoxLayout()
        pills_row.setSpacing(8)
        self.tested_pill = StatusPill("—", COLOR_TESTED)
        self.proton_pill = StatusPill("Proton-GE", ACCENT_COPPER)
        pills_row.addWidget(self.tested_pill)
        pills_row.addWidget(self.proton_pill)
        pills_row.addStretch(1)

        self.path_label = QLabel()
        self.path_label.setObjectName("appPath")
        self.path_label.setWordWrap(True)
        self.status_detail_label = QLabel()
        self.status_detail_label.setObjectName("muted")
        self.status_detail_label.setWordWrap(True)
        hc.addLayout(title_row)
        hc.addLayout(pills_row)
        hc.addWidget(self.path_label)
        hc.addWidget(self.status_detail_label)
        hl.addLayout(hc, stretch=1)
        ml.addWidget(header)

        self._build_action_bar(ml)

        overview = self._create_overview_tab()
        progress = self._create_progress_tab()
        logs = self._create_logs_tab()
        self._tab_overview = overview
        self._tab_progress = progress
        self._tab_logs = logs

        content_shell = CardWidget() if FLUENT_AVAILABLE else QFrame()
        if not FLUENT_AVAILABLE:
            content_shell.setObjectName("contentShell")
        content_l = QVBoxLayout(content_shell)
        content_l.setContentsMargins(0, 0, 0, 0)
        content_l.setSpacing(0)

        self.stack = QStackedWidget()
        self.stack.addWidget(overview)
        self.stack.addWidget(progress)
        self.stack.addWidget(logs)

        self.segment_tabs = SegmentTabBar(
            [
                ("overview", "Übersicht"),
                ("progress", "Vorgang"),
                ("logs", "Log-Dateien"),
            ]
        )
        self.segment_tabs.tabSelected.connect(self._set_content_tab)
        content_l.addWidget(self.segment_tabs)
        content_l.addWidget(self.stack, stretch=1)

        ml.addWidget(content_shell, stretch=1)
        root.addWidget(main, stretch=1)

    def _build_action_bar(self, parent_layout: QVBoxLayout) -> None:
        bar = QFrame()
        bar.setObjectName("actionBar")
        row = QHBoxLayout(bar)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)

        if FLUENT_AVAILABLE and FluentIcon is not None:
            self.launch_btn = PrimaryPushButton(FluentIcon.PLAY, "Starten")
        else:
            self.launch_btn = PrimaryPushButton("Starten")
            self.launch_btn.setObjectName("primaryBtn")
        self.launch_btn.setMinimumWidth(120)
        self.launch_btn.clicked.connect(self.run_launch)

        if FLUENT_AVAILABLE and FluentIcon is not None:
            self.install_btn = PushButton(FluentIcon.DOWNLOAD, "Installieren")
            self.repair_btn = PushButton(FluentIcon.SYNC, "Reparieren")
            self.validate_btn = PushButton(FluentIcon.CERTIFICATE, "Prüfen")
            self.kill_btn = PushButton(FluentIcon.CLOSE, "Beenden")
            self.logs_btn = PushButton(FluentIcon.HISTORY, "Logs")
        else:
            self.install_btn = PushButton("Installieren")
            self.repair_btn = PushButton("Reparieren")
            self.validate_btn = PushButton("Prüfen")
            self.kill_btn = PushButton("Beenden")
            self.logs_btn = PushButton("Logs")
        self.install_btn.clicked.connect(self.run_install)
        self.repair_btn.clicked.connect(self.run_repair)
        self.validate_btn.clicked.connect(self.run_validate)
        self.kill_btn.clicked.connect(self.run_kill)

        row.addWidget(self.launch_btn)
        row.addWidget(self.install_btn)
        row.addWidget(self.repair_btn)
        row.addWidget(self.validate_btn)
        row.addWidget(self.kill_btn)
        row.addSpacing(16)

        self.logs_btn.clicked.connect(self.open_log_file)

        self.more_btn = QToolButton()
        self.more_btn.setText("Mehr ▾")
        self.more_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        more_menu = QMenu(self)
        self._source_configure_action = more_menu.addAction(
            "Quelle konfigurieren…", self.run_source_configure
        )
        more_menu.addSeparator()
        more_menu.addAction("Deinstallieren", self.run_uninstall)
        more_menu.addSeparator()
        more_menu.addAction("Fehler melden…", self.report_bug)
        self.more_btn.setMenu(more_menu)

        row.addWidget(self.logs_btn)
        row.addWidget(self.more_btn)
        row.addStretch(1)
        parent_layout.addWidget(bar)

    def _create_overview_tab(self) -> QWidget:
        tab = QWidget()
        lay = QVBoxLayout(tab)
        lay.setContentsMargins(10, 10, 10, 10)
        hint = QLabel("Beschreibung und Voraussetzungen für das gewählte Rezept.")
        hint.setObjectName("muted")
        lay.addWidget(hint)
        self.info_browser = QTextBrowser()
        self.info_browser.setObjectName("infoBrowser")
        self.info_browser.setOpenExternalLinks(True)
        self.info_browser.setFrameShape(QFrame.Shape.NoFrame)
        lay.addWidget(self.info_browser)
        return tab

    def _create_progress_tab(self) -> QWidget:
        tab = QWidget()
        lay = QVBoxLayout(tab)
        lay.setContentsMargins(12, 10, 12, 12)
        lay.setSpacing(8)

        status_row = QHBoxLayout()
        self.step_label = QLabel("Kein Vorgang aktiv.")
        self.step_label.setObjectName("stepLabel")
        status_row.addWidget(self.step_label, stretch=1)
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setVisible(False)
        self.progress.setFixedWidth(220)
        status_row.addWidget(self.progress)
        lay.addLayout(status_row)

        act_label = QLabel("Schritte")
        act_label.setObjectName("muted")
        lay.addWidget(act_label)
        self.activity_list = QListWidget()
        self.activity_list.setObjectName("activityList")
        self.activity_list.setFrameShape(QFrame.Shape.StyledPanel)
        lay.addWidget(self.activity_list, stretch=2)

        log_label = QLabel("Live-Ausgabe")
        log_label.setObjectName("muted")
        lay.addWidget(log_label)
        self.raw_log = QTextEdit()
        self.raw_log.setReadOnly(True)
        self.raw_log.setFont(QFont("monospace", 9))
        self.raw_log.setPlaceholderText(
            "Erscheint während Install/Reparatur/Prüfung…"
        )
        self.raw_log.setMinimumHeight(100)
        self.raw_log.setMaximumHeight(160)
        lay.addWidget(self.raw_log, stretch=1)
        return tab

    def _create_logs_tab(self) -> QWidget:
        tab = QWidget()
        lay = QVBoxLayout(tab)
        lay.setContentsMargins(10, 10, 10, 10)
        lr = QHBoxLayout()
        lr.addWidget(QLabel("Log-Datei:"))
        self.log_combo = QComboBox()
        self.log_combo.currentIndexChanged.connect(self._load_log_file)
        lr.addWidget(self.log_combo, stretch=1)
        rb = QPushButton("Aktualisieren")
        rb.setObjectName("ghostBtn")
        rb.clicked.connect(self.populate_log_files)
        lr.addWidget(rb)
        lay.addLayout(lr)
        self.file_log = QTextEdit()
        self.file_log.setReadOnly(True)
        self.file_log.setFont(QFont("monospace", 9))
        lay.addWidget(self.file_log)
        return tab

    def _window_title(self, cur: str | None = None, update: str = "") -> str:
        ver = cur or read_version()
        base = f"Rezeptor — v{ver}"
        if update:
            return f"{base}  ·  Update: v{update}"
        return base

    def check_updates_background(self) -> None:
        latest, url = fetch_latest_release()
        self._latest_release = latest
        self._release_url = url
        cur = read_version()
        if latest and version_compare(cur, latest):
            self._refresh_status_footer(latest)
            self.setWindowTitle(self._window_title(cur, latest))
        else:
            self._refresh_status_footer()
            self.setWindowTitle(self._window_title(cur))

    def check_updates(self) -> None:
        latest, url = fetch_latest_release()
        cur = read_version()
        if latest and version_compare(cur, latest):
            if QMessageBox.question(
                self,
                "Update verfügbar",
                f"Installiert: v{cur}\nNeueste Release: v{latest}\n\nGitHub Releases öffnen?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            ) == QMessageBox.StandardButton.Yes:
                QDesktopServices.openUrl(QUrl(url))
        else:
            QMessageBox.information(
                self,
                "Kein Update",
                f"Version v{cur} ist aktuell{f' (neueste: v{latest})' if latest else ''}.",
            )

    def show_about(self) -> None:
        AboutDialog(self).exec()

    def report_bug(self) -> None:
        rid = self._selected.rid if self._selected else "launcher"
        if QMessageBox.question(
            self,
            "Fehler melden",
            "Sanitisierten Log-Report erstellen und GitHub-Issue öffnen?\n\n"
            "(Pfade/E-Mails werden anonymisiert)",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        report = collect_report_bundle(rid, self.session_id)
        clip = QApplication.clipboard()
        clip.setText(report_clipboard_text(rid, report, self.session_id))
        QDesktopServices.openUrl(QUrl(github_issue_url(rid, report)))
        QMessageBox.information(
            self,
            "GitHub geöffnet",
            "Das Issue-Formular nutzt die offizielle Bug-Vorlage.\n\n"
            "1. Im Browser: Abschnitte „Problem“ und „Tatsächliches Verhalten“ kurz ausfüllen\n"
            "2. Logs sind bereits formatiert — mit Strg+V in „📸 Logs“ einfügen\n\n"
            f"Report-Datei: {report.name}",
        )
        self._activity("info", f"Report in Zwischenablage — {report.name}")

    def _show_failure(self, done_label: str, code: int) -> None:
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Critical)
        box.setWindowTitle("Fehler")
        box.setText(f"{done_label} fehlgeschlagen (Exit {code}).")
        box.setInformativeText("Siehe Log-Dateien. Fehler können direkt auf GitHub gemeldet werden.")
        report = box.addButton("Auf GitHub melden", QMessageBox.ButtonRole.ActionRole)
        box.addButton(QMessageBox.StandardButton.Ok)
        box.exec()
        if box.clickedButton() == report:
            self.report_bug()

    def _base_env(self) -> dict[str, str]:
        env = os.environ.copy()
        env["PROJECT_ROOT"] = str(ROOT)
        env["LAUNCHER_GUI"] = "1"
        env["LAUNCHER_SESSION_ID"] = self.session_id
        if self._selected:
            env["RECIPE_ID"] = self._selected.rid
            rt = self._selected.meta.get("runtime", "proton-ge")
            env["WINE_METHOD"] = rt
            env["RECIPE_RUNTIME"] = rt
            dr = expand_home(
                self._selected.meta.get(
                    "data_root", f"~/.local/share/wine-software/{self._selected.rid}"
                )
            )
            env["WINEPREFIX"] = f"{dr}/prefix"
        else:
            env["WINE_METHOD"] = "proton-ge"
            env["RECIPE_RUNTIME"] = "proton-ge"
        if not env.get("DISPLAY") and env.get("WAYLAND_DISPLAY"):
            env["DISPLAY"] = ":0"
        return env

    def _populate_list(self) -> None:
        while self.recipe_cards_layout.count():
            item = self.recipe_cards_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()
        self._recipe_cards.clear()

        grouped: dict[str, list[tuple[int, RecipeInfo]]] = {}
        for i, info in enumerate(self.recipes):
            cat = info.meta.get("category", "Sonstige").strip() or "Sonstige"
            grouped.setdefault(cat, []).append((i, info))

        for cat in sorted(grouped.keys()):
            header = QLabel(cat.upper())
            header.setObjectName("sidebarCategory")
            self.recipe_cards_layout.addWidget(header)
            for i, info in grouped[cat]:
                card = RecipeSidebarCard(
                    info.meta.get("name", info.rid),
                    info.state.value,
                    recipe_fluent_icon(info.rid),
                )
                card.clicked.connect(lambda idx=i: self._select_recipe_index(idx))
                self.recipe_cards_layout.addWidget(
                    card, 0, Qt.AlignmentFlag.AlignTop
                )
                self._recipe_cards.append((card, info))

    def _select_recipe_index(self, row: int) -> None:
        if row < 0 or row >= len(self.recipes):
            return
        self._selected_index = row
        for i, (card, info) in enumerate(self._recipe_cards):
            card.set_selected(info.rid == self.recipes[row].rid)
        self._on_select(row)

    def refresh_statuses(self) -> None:
        env = self._base_env()
        for info in self.recipes:
            env["RECIPE_ID"] = info.rid
            info.state, info.status_detail, info.version_detected, info.version_warning = (
                query_recipe_state(info.rid, info.meta, env)
            )
        prev = self._selected_index
        self._populate_list()
        if self.recipes:
            self._select_recipe_index(prev if 0 <= prev < len(self.recipes) else 0)

    def _on_select(self, row: int) -> None:
        if row < 0 or row >= len(self.recipes):
            self._selected = None
            return
        self._selected = self.recipes[row]
        info = self._selected
        meta = info.meta
        dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{info.rid}"))

        pix = recipe_icon(meta).pixmap(72, 72)
        if not pix.isNull():
            self.icon_label.setPixmap(pix)
        self.name_label.setText(meta.get("name", info.rid))
        self._update_status_pills(info)
        self._update_version_header(info)
        self.path_label.setText(str(dr))
        detail = info.status_detail.strip()
        if info.state == RecipeState.INSTALLED and info.rid == "wiso-steuer":
            if not detail or detail == "Alle Prüfungen OK":
                detail = (
                    "Installiert — „Starten“ oder „Reparieren“; "
                    "Portable-Pfad unter Mehr ▾"
                )
        elif info.state == RecipeState.INSTALLED and (
            not detail or detail == "Alle Prüfungen OK"
        ):
            detail = "Installiert — „Starten“ oder „Reparieren“"
        self.status_detail_label.setText(detail if detail else " ")
        self.status_detail_label.setVisible(bool(detail))
        self.info_browser.setPlainText(recipe_info_text(info.rid, Path(meta["_dir"])))
        self._render_info_markdown()

        ok = info.state == RecipeState.INSTALLED
        partial_or_ok = info.state in (RecipeState.INSTALLED, RecipeState.PARTIAL)
        not_installed = info.state == RecipeState.NOT_INSTALLED

        self.launch_btn.setEnabled(ok and not self._busy)
        show_install = not_installed or info.state == RecipeState.PARTIAL
        self.install_btn.setVisible(show_install)
        self.install_btn.setEnabled(show_install and not self._busy)
        self.repair_btn.setEnabled(partial_or_ok and not self._busy)
        if hasattr(self, "_source_configure_action"):
            sk = info.meta.get("source_kind", "")
            self._source_configure_action.setVisible(sk == "folder")
            self._source_configure_action.setText(source_configure_label(info.meta))
        self.validate_btn.setEnabled(not not_installed and not self._busy)
        repair_script = Path(meta["_dir"]) / "repair.sh"
        self.repair_btn.setVisible(repair_script.is_file())
        kill_script = Path(meta["_dir"]) / "kill.sh"
        self.kill_btn.setVisible(kill_script.is_file())
        self.kill_btn.setEnabled(ok and not self._busy)

    def _update_status_pills(self, info: RecipeInfo) -> None:
        meta = info.meta
        guaranteed = meta.get("version_guaranteed", "")
        if guaranteed and not info.version_warning:
            self.tested_pill.setText(f"Getestet & garantiert · {guaranteed}")
            self.tested_pill.setStyleSheet(
                f"QLabel {{ color: {COLOR_TESTED}; background-color: rgba(255,255,255,0.06);"
                " padding: 4px 10px; border-radius: 6px; font-size: 12px; }"
            )
        elif info.version_warning:
            self.tested_pill.setText(info.version_warning[:72])
            self.tested_pill.setStyleSheet(
                "QLabel { color: #d9a441; background-color: rgba(255,255,255,0.06);"
                " padding: 4px 10px; border-radius: 6px; font-size: 12px; }"
            )
        else:
            self.tested_pill.setText(STATE_LABEL.get(info.state, "—"))
        tag = meta.get("runtime", "proton-ge")
        self.proton_pill.setText(tag.upper().replace("-", "-"))

    def _update_version_header(self, info: RecipeInfo) -> None:
        meta = info.meta
        guaranteed = meta.get("version_guaranteed", "")
        self.version_info_btn.setVisible(bool(guaranteed))
        if info.version_warning:
            self.version_info_btn.setToolTip(info.version_warning)
        elif info.version_detected:
            self.version_info_btn.setToolTip(
                f"Installiert: {info.version_detected} — Klick für Details"
            )
        else:
            self.version_info_btn.setToolTip("Version & Garantie — Klick für Details")

    def _show_version_guarantee_info(self) -> None:
        if not self._selected:
            return
        meta = self._selected.meta
        guaranteed = meta.get("version_guaranteed", "")
        label = meta.get("version_label") or guaranteed or "—"
        detected = self._selected.version_detected or "—"
        QMessageBox.information(
            self,
            "Version & Garantie",
            f"Getestete Version:\n{label}\n\n"
            f"Erkannt installiert:\n{detected}\n\n"
            f"{VERSION_GUARANTEE_HELP}",
        )

    def _render_info_markdown(self) -> None:
        raw = self.info_browser.toPlainText()
        parts: list[str] = []
        for line in raw.splitlines():
            esc = (
                line.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
            )
            if line.endswith(":") and len(line) < 80:
                parts.append(f"<p><b>{esc}</b></p>")
            elif line.startswith("- "):
                parts.append(f"<li>{esc[2:]}</li>")
            elif line.strip():
                parts.append(f"<p style='margin:4px 0'>{esc}</p>")
        html = (
            "<div style='line-height:1.45; color:#d4d4d8'>"
            + "".join(parts)
            + "</div>"
        )
        self.info_browser.setHtml(html)

    def _feed_line(self, raw: str) -> None:
        for part in raw.splitlines():
            line = strip_ansi(part)
            if not line or SPINNER_RE.match(line):
                continue

            human = humanize_log_line(line)
            if human is None:
                continue

            self._raw_log_buffer.append(human)
            self.raw_log.append(human)

            m = GUI_TAG_RE.match(line)
            if m:
                tag, msg = m.group(1), m.group(2).strip()
                self._activity(tag, msg)
                if tag == "step":
                    self.step_label.setText(msg)
                elif tag == "progress":
                    self.progress.setRange(0, 100)
                    self.progress.setVisible(True)
                    self.progress.setValue(min(100, max(0, int(msg))))
                    self.step_label.setText(f"Fortschritt — {msg}%")
                continue

            pm = PROGRESS_RE.search(line)
            if pm:
                self.progress.setRange(0, 100)
                self.progress.setVisible(True)
                self.progress.setValue(int(pm.group(1)))
                self.step_label.setText(f"Fortschritt — {pm.group(1)}%")
                continue

            if line.startswith("═══") or line.startswith("RECIPE_"):
                continue
            if "AKTION:" in line or line.startswith("USER:"):
                self._activity("warn", line.replace("AKTION:", "").replace("USER:", "").strip())
                self.step_label.setText(line.replace("AKTION:", "").strip()[:120])
                continue
            if any(line.startswith(p) for p in ("→", "✓", "⚠", "✗", "ℹ", "OK:", "FAIL:", "WARN:")):
                self._activity("log", line)

    def _activity(self, kind: str, text: str) -> None:
        prefix = {"step": "→", "ok": "✓", "warn": "⚠", "error": "✗", "info": "ℹ", "log": "·"}.get(kind, "·")
        self.activity_list.addItem(f"{prefix} {text}")
        self.activity_list.scrollToBottom()

    def _set_busy(self, busy: bool) -> None:
        self._busy = busy
        if busy:
            if self.progress.maximum() == 0 and self.progress.minimum() == 0:
                self.progress.setRange(0, 0)
            self.progress.setVisible(True)
        else:
            self.progress.setRange(0, 100)
            if self.progress.value() < 100:
                self.progress.setValue(100)
            self.step_label.setText("Fertig")
        for b in (
            self.install_btn,
            self.repair_btn,
            self.launch_btn,
            self.validate_btn,
            self.kill_btn,
            self.logs_btn,
            self.more_btn,
        ):
            b.setEnabled(not busy)
        self.action_refresh.setEnabled(not busy)
        if self._selected:
            self._select_recipe_index(self._selected_index)

    def _set_content_tab(self, key: str) -> None:
        pages = {
            "overview": self._tab_overview,
            "progress": self._tab_progress,
            "logs": self._tab_logs,
        }
        page = pages.get(key)
        if page is None:
            return
        self.stack.setCurrentWidget(page)
        if hasattr(self, "segment_tabs"):
            self.segment_tabs.set_current(key)

    def _switch_to_progress_tab(self) -> None:
        self._set_content_tab("progress")

    def _require_recipe(self) -> Path | None:
        if self._process and self._process.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.warning(self, "Läuft", "Ein Vorgang läuft noch.")
            return None
        if not self._selected:
            return None
        return Path(self._selected.meta["_dir"])

    def _run_async(
        self,
        script: Path,
        extra: dict[str, str] | None = None,
        done_label: str = "Fertig",
        dialog: bool = True,
    ) -> None:
        env = QProcessEnvironment.systemEnvironment()
        for k, v in self._base_env().items():
            env.insert(k, v)
        if extra:
            for k, v in extra.items():
                env.insert(k, v)

        self.raw_log.clear()
        self.activity_list.clear()
        self._raw_log_buffer.clear()
        self.progress.setValue(0)
        self.progress.setRange(0, 0)
        self.progress.setVisible(True)
        self._switch_to_progress_tab()
        self.step_label.setText("Vorgang wird gestartet…")
        self._activity("step", f"{script.name} (Session {self.session_id[:8]})")
        self._set_busy(True)

        proc = QProcess(self)
        self._process = proc
        proc.setProcessEnvironment(env)
        proc.setWorkingDirectory(str(ROOT))
        proc.setProgram("bash")
        proc.setArguments([str(script)])
        proc.readyReadStandardOutput.connect(
            lambda: self._feed_line(bytes(proc.readAllStandardOutput()).decode("utf-8", errors="replace"))
        )
        proc.readyReadStandardError.connect(
            lambda: self._feed_line(bytes(proc.readAllStandardError()).decode("utf-8", errors="replace"))
        )

        def done(code: int, _s: QProcess.ExitStatus) -> None:
            self._set_busy(False)
            self._activity("ok" if code == 0 else "error", f"{done_label} — Exit {code}")
            self.populate_log_files()
            self.refresh_statuses()
            if code != 0 and dialog:
                self._show_failure(done_label, code)
            elif code == 0 and dialog:
                QMessageBox.information(self, "Fertig", f"{done_label} abgeschlossen.")

        proc.finished.connect(done)
        proc.start()

    def populate_log_files(self) -> None:
        self.log_combo.blockSignals(True)
        self.log_combo.clear()
        if LOG_ROOT.is_dir():
            for f in sorted(LOG_ROOT.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)[:50]:
                self.log_combo.addItem(f.name, str(f))
        self.log_combo.blockSignals(False)
        if self.log_combo.count():
            self.log_combo.setCurrentIndex(0)

    def _load_log_file(self) -> None:
        p = self.log_combo.currentData()
        if not p:
            return
        try:
            self.file_log.setPlainText(Path(str(p)).read_text(encoding="utf-8", errors="replace")[-400_000:])
        except OSError as e:
            self.file_log.setPlainText(str(e))

    def _switch_to_logs_tab(self) -> None:
        self._set_content_tab("logs")

    def open_log_file(self) -> None:
        self._switch_to_logs_tab()
        self.populate_log_files()

    def _maybe_wiso_mono_hint(self, action: str) -> None:
        if not self._selected or self._selected.rid != "wiso-steuer":
            return
        if self._wiso_mono_hint_shown and action != "launch":
            return
        self._wiso_mono_hint_shown = True
        self._activity(
            "info",
            "Wine-Mono (.NET) wird still installiert — kein separates Fenster nötig.",
        )
        if action in ("install", "repair"):
            QMessageBox.information(
                self,
                "Wine-Mono — Hinweis",
                "WISO benötigt Wine-Mono (.NET). Rezeptor richtet das automatisch ein.\n\n"
                "Falls ein Fenster „Wine-Mono-Installation“ erscheint:\n"
                "• „Abbrechen“ klicken — nicht „Installieren“\n"
                "• Im Tab „Vorgang“ den Fortschritt abwarten\n\n"
                "Andere Wine-Dialoge mit OK/Installieren: ebenfalls Abbrechen — "
                "Rezeptor übernimmt die Einrichtung.",
            )

    def run_install(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        install = rd / "install.sh"
        if not install.is_file():
            QMessageBox.critical(self, "Fehlt", str(install))
            return

        info = recipe_info_text(self._selected.rid, rd)
        if QMessageBox.question(
            self,
            "Installation starten",
            f"{info}\n\n{'─' * 40}\n\nInstallation jetzt starten?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return

        if self._selected.state == RecipeState.INSTALLED:
            name = self._selected.meta.get("name", self._selected.rid)
            QMessageBox.information(
                self,
                "Bereits installiert",
                f"„{name}“ ist installiert.\n\n"
                "Für Reparatur-Schritte → „Reparieren“ (falls verfügbar).\n"
                "Neuinstallation nur nach Deinstallieren.",
            )
            return

        extra: dict[str, str] = {}
        meta = self._selected.meta
        if needs_source_dialog(meta):
            dlg = RecipeSourceDialog(
                self,
                rid=self._selected.rid,
                meta=meta,
                root=ROOT,
                title=f"{meta.get('name', self._selected.rid)} — Installation",
            )
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return
            dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{self._selected.rid}"))
            try:
                extra = dlg.build_env(dr)
            except OSError as exc:
                QMessageBox.critical(self, "Archiv", f"Entpacken fehlgeschlagen:\n{exc}")
                return
            if meta.get("source_kind") == "folder" and not extra.get("RECIPE_SOURCE_ROOT"):
                return

        self._maybe_wiso_mono_hint("install")
        self._run_async(install, extra, "Installation")

    def run_source_configure(self) -> None:
        rd = self._require_recipe()
        if rd is None or not self._selected:
            return
        meta = self._selected.meta
        if meta.get("source_kind") != "folder":
            return
        dlg = RecipeSourceDialog(
            self,
            rid=self._selected.rid,
            meta=meta,
            root=ROOT,
            title=f"{meta.get('name', self._selected.rid)} — Quelle",
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{self._selected.rid}"))
        extra = dlg.build_env(dr)
        if not extra.get("RECIPE_SOURCE_ROOT"):
            return
        install = rd / "install.sh"
        if not install.is_file():
            QMessageBox.critical(self, "Fehlt", str(install))
            return
        self._run_async(install, extra, "Quell-Konfiguration")

    def run_repair(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        repair = rd / "repair.sh"
        if not repair.is_file():
            QMessageBox.warning(self, "Fehlt", "Kein repair.sh für dieses Rezept.")
            return
        if self._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.warning(self, "Nicht installiert", "Zuerst installieren.")
            return
        if QMessageBox.question(
            self,
            "Reparatur",
            self._repair_message(self._selected.rid),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._maybe_wiso_mono_hint("repair")
        self._run_async(repair, done_label="Reparatur")

    def _repair_message(self, rid: str) -> str:
        if rid == "wiso-steuer":
            return (
                "Reparatur prüft validate.sh und behebt:\n"
                "• Portable-Root / Launch-Skript\n"
                "• vcrun2019, gdiplus, dotnet48 (Wine-Mono), win10\n\nFortfahren?"
            )
        return (
            "Reparatur prüft validate.sh und behebt:\n"
            "• Native MSXML\n• Schriften (ClearType/Segoe UI)\n"
            "• Proton-GE Grafik-DLLs\n• Desktop-Icon\n\nFortfahren?"
        )

    def _spawn_detached(self, cmd: list[str], env: dict[str, str]) -> Path:
        rid = env.get("RECIPE_ID", "app")
        log_path = LOG_ROOT / f"launch_{rid}_{self.session_id[:8]}.log"
        LOG_ROOT.mkdir(parents=True, exist_ok=True)
        log_f = open(log_path, "a", encoding="utf-8")  # noqa: SIM115
        log_f.write(f"\n--- {rid} launch ---\n")
        log_f.flush()
        subprocess.Popen(
            cmd,
            cwd=str(ROOT),
            env=env,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=log_f,
            stderr=subprocess.STDOUT,
        )
        self._activity("info", f"Log: {log_path.name}")
        return log_path

    def _check_launch_alive(
        self, rid: str, log_path: Path, attempt: int = 0
    ) -> None:
        patterns = LAUNCH_PROCESS_PATTERNS.get(rid, [])
        if not patterns:
            return
        alive = any(
            subprocess.run(["pgrep", "-f", pat], capture_output=True).returncode == 0
            for pat in patterns
        )
        if alive:
            if attempt < 4:
                QTimer.singleShot(
                    5000,
                    lambda: self._check_launch_alive(rid, log_path, attempt + 1),
                )
            return
        name = self._selected.meta.get("name", rid) if self._selected else rid
        tips = (
            "Rezeptor → WISO → Reparieren (stellt wined3d + Qt-Startfix ein).\n"
            "Erster Start kann 10–20 s dauern — Log-Tab prüfen.\n"
            "Linux-Internet bleibt aktiv; nur ein WISO-Qt-Plugin wird deaktiviert."
            if rid == "wiso-steuer"
            else "Reparieren ausführen oder Log-Tab prüfen."
        )
        QMessageBox.warning(
            self,
            "Anwendung läuft nicht",
            f"„{name}“ scheint nach dem Start nicht aktiv zu sein.\n\n"
            f"Log: {log_path}\n\n{tips}",
        )
        self._activity("warn", f"Prozess nicht aktiv — siehe {log_path.name}")
        self._switch_to_logs_tab()
        self.populate_log_files()

    def run_launch(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        if self._selected and self._selected.version_warning:
            guaranteed = self._selected.meta.get("version_guaranteed", "")
            if QMessageBox.warning(
                self,
                "Versionsabweichung",
                f"{self._selected.version_warning}\n\n"
                f"Trotzdem starten? (Nicht getestet — kein Support)",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            ) != QMessageBox.StandardButton.Yes:
                return
        self._maybe_wiso_mono_hint("launch")
        env = self._base_env()
        if self._selected and self._selected.rid == "wiso-steuer":
            env.pop("WINE_DISABLE_WOW64", None)
        meta = self._selected.meta
        launch = rd / "launch.sh"
        if not launch.is_file():
            QMessageBox.warning(self, "Fehlt", "Kein launch.sh für dieses Rezept.")
            return
        log_path = self._spawn_detached(["bash", str(launch)], env)
        self._activity("ok", f"{meta.get('name')} gestartet")
        rid = self._selected.rid
        if rid in LAUNCH_PROCESS_PATTERNS:
            QTimer.singleShot(
                8000, lambda: self._check_launch_alive(rid, log_path)
            )

    def run_validate(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        v = rd / "validate.sh"
        if v.is_file():
            self._run_async(v, done_label="Prüfung", dialog=False)

    def run_kill(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        kill = rd / "kill.sh"
        if not kill.is_file():
            QMessageBox.warning(self, "Fehlt", "Kein kill.sh für dieses Rezept.")
            return
        name = self._selected.meta.get("name", self._selected.rid)
        if QMessageBox.question(
            self,
            "Beenden",
            f"{name} und zugehörige Wine-Prozesse beenden?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._run_async(kill, done_label="Beenden", dialog=False)

    def run_uninstall(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        un = rd / "uninstall.sh"
        if not un.is_file():
            QMessageBox.warning(self, "Fehlt", "Kein uninstall.sh für dieses Rezept.")
            return
        if QMessageBox.question(
            self, "Deinstallieren",
            f"„{self._selected.meta.get('name')}“ entfernen?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        extra = {"PHOTOSHOP_UNINSTALL_YES": "1", "UNINSTALL_YES": "1"}
        self._run_async(un, extra, "Deinstallation")


def main() -> int:
    if "--dev" in sys.argv:
        os.environ["REZEPTOR_DEV"] = "1"
        sys.argv = [a for a in sys.argv if a != "--dev"]
    app = QApplication(sys.argv)
    if not FLUENT_AVAILABLE:
        app.setStyle("Fusion")
    sheet = app_stylesheet()
    combined = (sheet or "") + SEGMENT_TAB_STYLES
    if combined.strip():
        app.setStyleSheet(combined)
    w = RezeptorWindow()
    w.show()
    QTimer.singleShot(200, w.refresh_statuses)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
