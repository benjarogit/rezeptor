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
    from PyQt6.QtGui import (
        QAction,
        QColor,
        QCursor,
        QDesktopServices,
        QFont,
        QIcon,
        QPixmap,
    )
    from PyQt6.QtWidgets import (
        QApplication,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFileDialog,
        QFormLayout,
        QFrame,
        QHBoxLayout,
        QInputDialog,
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
from settings import RezeptorSettings, load_settings, save_settings
from ui_settings import SettingsDialog
from ui_docs import DeveloperDocsDialog
from ui_recipe_wizard import (
    RecipeWizardBlockedDialog,
    RecipeWizardDialog,
    can_create_recipes,
)
from ui_source import (
    RecipeSourceDialog,
    needs_source_dialog,
    source_configure_label,
)
from recipe_trust import (
    generate_manifest,
    rezeptor_dev_mode,
    sync_manifest_if_stale,
    verify_recipe_trust,
)
from ui_styles import APP_STYLESHEET, STATE_COLORS
from i18n import get_locale, set_locale, t
from log_context import (
    E_LAUNCH_NO_PROCESS,
    E_SCRIPT_FAILED,
    E_TRUST_MANIFEST,
    E_UPDATE_APPLY,
    E_UPDATE_ROLLBACK,
    LogEvent,
)
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
    UNTRUSTED = "untrusted"


STATE_LABEL = {
    RecipeState.NOT_INSTALLED: "state.not_installed",
    RecipeState.PARTIAL: "state.partial",
    RecipeState.INSTALLED: "state.installed",
    RecipeState.UNKNOWN: "state.unknown",
    RecipeState.UNTRUSTED: "state.untrusted",
}


@dataclass
class RecipeInfo:
    rid: str
    meta: dict[str, str]
    state: RecipeState = RecipeState.UNKNOWN
    status_detail: str = ""
    version_detected: str = ""
    version_warning: str = ""
    trust_ok: bool = True
    trust_reason: str = ""


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
    synced, sync_msg = sync_manifest_if_stale(RECIPES_DIR, MANIFEST_PATH, ROOT)
    if synced and sync_msg:
        os.environ["REZEPTOR_MANIFEST_SYNC"] = sync_msg
    for yml in sorted(RECIPES_DIR.glob("*/recipe.yml")):
        if yml.parent.name.startswith("_"):
            continue
        ok, reason = verify_recipe_trust(yml.parent, MANIFEST_PATH)
        meta = parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        meta["_dir"] = str(yml.parent)
        info = RecipeInfo(rid=rid, meta=meta, trust_ok=ok, trust_reason=reason or "")
        if not ok:
            info.state = RecipeState.UNTRUSTED
            info.status_detail = reason or t("trust.manifest_failed")
            trust_failures.append(f"{rid}: {reason}")
        found.append(info)
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


# Nur App-spezifische Muster — kein QtWebEngineProcess / start.exe (zu breit).
LAUNCH_PROCESS_PATTERNS: dict[str, list[str]] = {
    "wiso-steuer": ["wiso2026.exe", "wmain26.dll", "wmain26.exe"],
    "photoshop": ["Photoshop.exe"],
}


def recipe_wine_prefix(meta: dict[str, str], rid: str) -> Path:
    dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{rid}"))
    raw = meta.get("prefix", "{data_root}/prefix")
    return expand_home(raw.replace("{data_root}", str(dr)))


def _proc_cmdline(pid: str) -> str:
    try:
        return (
            Path(f"/proc/{pid}/cmdline")
            .read_bytes()
            .replace(b"\0", b" ")
            .decode("utf-8", "replace")
        )
    except (OSError, ProcessLookupError):
        return ""


def _proc_has_wineprefix(pid: str, prefix: Path) -> bool:
    try:
        env = Path(f"/proc/{pid}/environ").read_bytes()
    except (OSError, ProcessLookupError):
        return False
    needle = str(prefix).encode()
    return needle in env and (
        b"WINEPREFIX=" + needle in env or needle + b"/" in env or needle in env
    )


def recipe_process_running(rid: str, meta: dict[str, str] | None = None) -> bool:
    """True nur wenn ein Prozess zum Rezept-Prefix + App-Muster gehört.

    Globales ``pgrep -f`` ist zu breit (Shell-Cmdlines, Cursor, andere Qt-Apps).
    """
    patterns = LAUNCH_PROCESS_PATTERNS.get(rid, [])
    if not patterns:
        return False
    prefix: Path | None = None
    path_hints: list[str] = []
    if meta:
        prefix = recipe_wine_prefix(meta, rid)
        dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{rid}"))
        path_hints = [str(dr).lower(), str(prefix).lower()]
        # Portable-Ziel (WISO) oft unter Dokumente — Cmdline enthält den Pfad
        for key in ("portable_root", "target_default"):
            raw = (meta.get(key) or "").strip()
            if raw:
                path_hints.append(str(expand_home(raw)).lower())
    patterns_l = [p.lower() for p in patterns]
    for ent in Path("/proc").iterdir():
        if not ent.name.isdigit():
            continue
        cmd = _proc_cmdline(ent.name)
        if not cmd:
            continue
        cmd_l = cmd.lower()
        if "pgrep" in cmd_l or "recipe_process_running" in cmd_l:
            continue
        if not any(pat in cmd_l for pat in patterns_l):
            continue
        if prefix is None:
            if any(pat.endswith(".exe") and pat in cmd_l for pat in patterns_l):
                return True
            continue
        if _proc_has_wineprefix(ent.name, prefix):
            return True
        if any(h and h in cmd_l for h in path_hints):
            return True
    return False


def recipe_icon(meta: dict[str, str]) -> QIcon:
    raw = meta.get("icon", "")
    if raw:
        p = expand_home(raw)
        if p.is_file():
            return QIcon(str(p))
    if REZEPTOR_ICON.is_file():
        return QIcon(str(REZEPTOR_ICON))
    return QIcon()


def recipe_info_text(rid: str, recipe_dir: Path) -> str:
    locale = get_locale()
    candidates = [
        f"info.{locale}.txt",
        "info.en.txt",
        "info.de.txt",
        "info.txt",
        f"{rid}.info.de.txt",
    ]
    # Prefer locale, then en, then de
    seen: set[str] = set()
    for name in candidates:
        if name in seen:
            continue
        seen.add(name)
        p = recipe_dir / name
        if p.is_file():
            return p.read_text(encoding="utf-8").strip()
    return t("info.missing")


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
            detail = version_warn or ""
            return RecipeState.INSTALLED, detail, detected, version_warn
        if prefix.is_dir() and (prefix / "user.reg").is_file():
            fail = next((ln for ln in out.splitlines() if ln.startswith("FAIL:")), "")
            detail = fail or version_warn or t("state.prefix_present")
            return RecipeState.PARTIAL, detail, detected, version_warn
        return (
            RecipeState.NOT_INSTALLED,
            out.strip().splitlines()[0] if out.strip() else t("state.not_installed"),
            detected,
            version_warn,
        )

    if prefix.is_dir() and (prefix / "user.reg").is_file():
        return RecipeState.PARTIAL, str(prefix), *empty
    return RecipeState.NOT_INSTALLED, t("state.not_installed"), *empty


class AboutDialog(QDialog):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle(t("dialog.about_title"))
        self.resize(480, 320)
        layout = QVBoxLayout(self)
        ver = read_version()
        layout.addWidget(QLabel(t("dialog.about_heading", version=ver)))
        body = QTextBrowser()
        body.setOpenExternalLinks(True)
        body.setHtml(t("dialog.about_body", repo=GITHUB_REPO))
        layout.addWidget(body)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        buttons.accepted.connect(self.accept)
        buttons.clicked.connect(lambda _: self.accept())
        layout.addWidget(buttons)


class RezeptorWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self._settings = load_settings()
        if not self._settings.locale:
            from i18n import detect_system_locale

            self._settings.locale = detect_system_locale()
            save_settings(self._settings)
        set_locale(self._settings.locale)
        self.setWindowTitle(t("app.title", version=read_version()))
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
        self._update_available = ""
        self._launch_alive_reported = False
        self._trust_btn: QPushButton | None = None
        self._menu_bar_built = False
        self._running_poll = QTimer(self)
        self._running_poll.setInterval(3000)
        self._running_poll.timeout.connect(self._refresh_running_indicators)

        self._build_menus()
        self._build_status_bar()
        self._build_layout()

        self._populate_list()
        self._running_poll.start()
        removed = 0
        if self._settings.prune_logs_on_startup:
            removed = prune_old_logs(
                retention_days=self._settings.log_retention_days,
                max_files=self._settings.log_max_files,
            )
        if removed:
            self._activity(
                "info",
                f"{removed} alte Log-Datei(en) entfernt "
                f"(>{self._settings.log_retention_days} Tage / max. {self._settings.log_max_files})",
            )
        self.populate_log_files()
        manifest_sync = os.environ.pop("REZEPTOR_MANIFEST_SYNC", "")
        if manifest_sync:
            self._activity("info", manifest_sync)
        trust_log = os.environ.pop("REZEPTOR_TRUST_LOG", "")
        if trust_log:
            for line in trust_log.splitlines():
                self._activity("warn", t("trust.hidden_warn", line=line))
        if self._dev_mode:
            self._activity("info", t("app.dev_mode_info"))
        if self.recipes:
            self._select_recipe_index(0)
        QTimer.singleShot(500, self.check_updates_background)

    def _build_menus(self) -> None:
        self.menuBar().clear()
        rezeptor_menu = self.menuBar().addMenu(t("menu.rezeptor"))
        rezeptor_menu.addAction(t("menu.settings"), self.show_settings)
        rezeptor_menu.addSeparator()
        self.action_refresh = QAction(t("menu.refresh"), self)
        self.action_refresh.setToolTip(t("menu.refresh_tip"))
        self.action_refresh.triggered.connect(self.refresh_statuses)
        rezeptor_menu.addAction(self.action_refresh)
        rezeptor_menu.addAction(t("menu.new_recipe"), self.show_recipe_wizard)
        rezeptor_menu.addSeparator()
        rezeptor_menu.addAction(t("menu.cleanup_logs"), self.cleanup_logs_now)
        rezeptor_menu.addAction(t("menu.rollback"), self.show_rollback_dialog)

        help_menu = self.menuBar().addMenu(t("menu.help"))
        help_menu.addAction(t("menu.docs"), self.show_developer_docs)
        help_menu.addSeparator()
        help_menu.addAction(t("menu.check_update"), self.check_updates)
        help_menu.addSeparator()
        help_menu.addAction(t("menu.report_bug"), self.report_bug)
        help_menu.addAction(t("menu.about"), self.show_about)
        self._menu_bar_built = True

    def _build_status_bar(self) -> None:
        sb = QStatusBar()
        sb.setContentsMargins(8, 0, 8, 0)
        self.setStatusBar(sb)
        self.status_footer = QLabel()
        self.status_footer.setObjectName("statusFooter")
        self.status_footer.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.status_footer.setAlignment(
            Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft
        )
        self.status_footer.mousePressEvent = (  # type: ignore[method-assign]
            lambda event: self._on_status_footer_clicked(event)
        )
        self._refresh_status_footer()
        sb.addWidget(self.status_footer, 1)

    def _on_status_footer_clicked(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.button() == Qt.MouseButton.LeftButton and self._update_available:
            self.check_updates()

    def _refresh_status_footer(self, update: str = "") -> None:
        cur = read_version()
        dev = f"  ·  {t('app.dev_mode')}" if self._dev_mode else ""
        self._update_available = update or ""
        if update:
            self.status_footer.setText(
                t("app.footer_update", version=cur, dev=dev, update=update)
            )
            self.status_footer.setStyleSheet(
                f"color: {ACCENT_COPPER}; font-weight: 600;"
            )
            self.status_footer.setToolTip(t("app.footer_update_tip"))
            self.status_footer.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        else:
            self.status_footer.setText(t("app.footer_version", version=cur, dev=dev))
            self.status_footer.setStyleSheet("color: #9d9da6;")
            self.status_footer.setToolTip("")
            self.status_footer.setCursor(QCursor(Qt.CursorShape.ArrowCursor))

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

        st = QLabel(t("app.sidebar_title"))
        st.setObjectName("sidebarTitle")
        self._sidebar_title = st
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
        self.name_label = (
            TitleLabel(t("app.choose_recipe"))
            if FLUENT_AVAILABLE
            else QLabel(t("app.choose_recipe"))
        )
        if not FLUENT_AVAILABLE:
            self.name_label.setObjectName("appTitle")
        else:
            self.name_label.setText(t("app.choose_recipe"))

        self.version_info_btn = QToolButton()
        self.version_info_btn.setText("ℹ")
        self.version_info_btn.setToolTip(t("tooltip.version_info"))
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
                ("overview", t("tab.overview")),
                ("progress", t("tab.progress")),
                ("logs", t("tab.logs")),
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
            self.launch_btn = PrimaryPushButton(FluentIcon.PLAY, t("btn.launch"))
            self.install_btn = PushButton(FluentIcon.DOWNLOAD, t("btn.install"))
            self.repair_btn = PushButton(FluentIcon.SYNC, t("btn.repair"))
            self.validate_btn = PushButton(FluentIcon.CERTIFICATE, t("btn.validate"))
            self.kill_btn = PushButton(FluentIcon.CLOSE, t("btn.kill"))
        else:
            self.launch_btn = PrimaryPushButton(t("btn.launch"))
            self.launch_btn.setObjectName("primaryBtn")
            self.install_btn = PushButton(t("btn.install"))
            self.repair_btn = PushButton(t("btn.repair"))
            self.validate_btn = PushButton(t("btn.validate"))
            self.kill_btn = PushButton(t("btn.kill"))

        self.launch_btn.setMinimumWidth(120)
        self.launch_btn.setToolTip(t("tooltip.launch"))
        self.install_btn.setToolTip(t("tooltip.install"))
        self.repair_btn.setToolTip(t("tooltip.repair"))
        self.validate_btn.setToolTip(t("tooltip.validate"))
        self.kill_btn.setToolTip(t("tooltip.kill"))

        hand = QCursor(Qt.CursorShape.PointingHandCursor)
        for btn in (
            self.launch_btn,
            self.install_btn,
            self.repair_btn,
            self.validate_btn,
            self.kill_btn,
        ):
            btn.setCursor(hand)

        self.launch_btn.clicked.connect(self.run_launch)
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

        self.trust_btn = PushButton(t("btn.update_rezeptor"))
        self.trust_btn.setCursor(hand)
        self.trust_btn.setVisible(False)
        self.trust_btn.clicked.connect(self._on_trust_action)
        row.addWidget(self.trust_btn)

        self.logs_btn = None

        self.more_btn = QToolButton()
        self.more_btn.setText(t("btn.more"))
        self.more_btn.setCursor(hand)
        self.more_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        self.more_btn.setToolTip(t("tooltip.more"))
        more_menu = QMenu(self)
        self._source_configure_action = more_menu.addAction(
            t("menu.source"), self.run_source_configure
        )
        more_menu.addSeparator()
        more_menu.addAction(t("menu.uninstall"), self.run_uninstall)
        self.more_btn.setMenu(more_menu)

        row.addWidget(self.more_btn)
        row.addStretch(1)
        parent_layout.addWidget(bar)

    def _create_overview_tab(self) -> QWidget:
        tab = QWidget()
        lay = QVBoxLayout(tab)
        lay.setContentsMargins(10, 10, 10, 10)
        hint = QLabel(t("overview.hint"))
        hint.setObjectName("muted")
        self._overview_hint = hint
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
        self.step_label = QLabel(t("status.no_process"))
        self.step_label.setObjectName("stepLabel")
        status_row.addWidget(self.step_label, stretch=1)
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setVisible(False)
        self.progress.setFixedWidth(220)
        status_row.addWidget(self.progress)
        lay.addLayout(status_row)

        act_label = QLabel(t("progress.steps"))
        act_label.setObjectName("muted")
        self._progress_steps_label = act_label
        lay.addWidget(act_label)
        self.activity_list = QListWidget()
        self.activity_list.setObjectName("activityList")
        self.activity_list.setFrameShape(QFrame.Shape.StyledPanel)
        lay.addWidget(self.activity_list, stretch=2)

        log_label = QLabel(t("progress.live"))
        log_label.setObjectName("muted")
        self._progress_live_label = log_label
        lay.addWidget(log_label)
        self.raw_log = QTextEdit()
        self.raw_log.setReadOnly(True)
        self.raw_log.setFont(QFont("monospace", 9))
        self.raw_log.setPlaceholderText(t("progress.live_placeholder"))
        self.raw_log.setMinimumHeight(100)
        self.raw_log.setMaximumHeight(160)
        lay.addWidget(self.raw_log, stretch=1)
        return tab

    def _create_logs_tab(self) -> QWidget:
        tab = QWidget()
        lay = QVBoxLayout(tab)
        lay.setContentsMargins(10, 10, 10, 10)
        lr = QHBoxLayout()
        self._logs_file_label = QLabel(t("logs.label"))
        lr.addWidget(self._logs_file_label)
        self.log_combo = QComboBox()
        self.log_combo.currentIndexChanged.connect(self._load_log_file)
        lr.addWidget(self.log_combo, stretch=1)
        rb = QPushButton(t("logs.refresh"))
        rb.setObjectName("ghostBtn")
        self._logs_refresh_btn = rb
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
        if update:
            return t("app.title_update", version=ver, update=update)
        return t("app.title", version=ver)

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
        self._latest_release = latest or self._latest_release
        self._release_url = url
        cur = read_version()
        if latest and version_compare(cur, latest):
            box = QMessageBox(self)
            box.setIcon(QMessageBox.Icon.Information)
            box.setWindowTitle(t("update.available_title"))
            box.setText(
                t("update.available_body", current=cur, latest=latest)
            )
            auto_btn = box.addButton(
                t("update.btn_auto"), QMessageBox.ButtonRole.AcceptRole
            )
            browser_btn = box.addButton(
                t("update.btn_browser"), QMessageBox.ButtonRole.ActionRole
            )
            box.addButton(t("update.btn_cancel"), QMessageBox.ButtonRole.RejectRole)
            box.exec()
            clicked = box.clickedButton()
            if clicked == auto_btn:
                self._run_rezeptor_update(latest)
            elif clicked == browser_btn:
                QDesktopServices.openUrl(QUrl(url))
        else:
            hint = t("update.none_latest", latest=latest) if latest else ""
            QMessageBox.information(
                self,
                t("update.none_title"),
                t("update.none_body", current=cur, latest_hint=hint),
            )

    def _run_rezeptor_update(self, tag: str = "") -> None:
        script = ROOT / "scripts" / "rezeptor-update.sh"
        if not script.is_file():
            QMessageBox.warning(self, t("dialog.missing"), str(script))
            return
        self._switch_to_progress_tab()
        self._activity("step", t("update.applying"))
        cmd = ["bash", str(script), "apply"]
        if tag:
            cmd.append(tag if tag.startswith("v") else f"v{tag}")
        env = self._base_env()
        proc = QProcess(self)
        self._process = proc
        self._set_busy(True)
        qenv = QProcessEnvironment.systemEnvironment()
        for k, v in env.items():
            qenv.insert(k, v)
        proc.setProcessEnvironment(qenv)
        proc.setWorkingDirectory(str(ROOT))
        proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)

        def on_out() -> None:
            data = bytes(proc.readAllStandardOutput()).decode("utf-8", "replace")
            for line in data.splitlines():
                line = strip_ansi(line)
                if line:
                    self.raw_log.append(line)
                    self._activity("log", line[:200])

        def done(code: int, _status: QProcess.ExitStatus) -> None:
            self._set_busy(False)
            self._process = None
            if code == 0:
                self._activity("ok", t("update.done"))
                QMessageBox.information(self, t("update.available_title"), t("update.done"))
            else:
                ev = LogEvent(
                    level="error",
                    code=E_UPDATE_APPLY,
                    message_key="update.failed",
                    extras={"code": code},
                    session_id=self.session_id,
                )
                self._activity("error", ev.display_text())
                QMessageBox.critical(
                    self, t("dialog.error"), t("update.failed", code=code)
                )

        proc.readyReadStandardOutput.connect(on_out)
        proc.finished.connect(done)
        proc.start(cmd[0], cmd[1:])

    def show_rollback_dialog(self) -> None:
        script = ROOT / "scripts" / "rezeptor-update.sh"
        if not script.is_file():
            QMessageBox.warning(self, t("dialog.missing"), str(script))
            return
        try:
            out = subprocess.run(
                ["bash", str(script), "list"],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            import json as _json

            items = _json.loads(out.stdout or "[]")
        except (OSError, ValueError):
            items = []
        if not items:
            QMessageBox.information(
                self, t("update.rollback_title"), t("update.rollback_empty")
            )
            return
        labels = []
        for it in items:
            bid = it.get("id", "?")
            vf = it.get("version_from", "?")
            vt = it.get("version_to", "?")
            mode = it.get("mode", "?")
            labels.append(f"{bid}  ({vf} → {vt}, {mode})")
        choice, ok = QInputDialog.getItem(
            self,
            t("update.rollback_title"),
            t("update.rollback_title"),
            labels,
            0,
            False,
        )
        if not ok or not choice:
            return
        bid = choice.split()[0]
        meta = next((it for it in items if it.get("id") == bid), {})
        if QMessageBox.question(
            self,
            t("update.rollback_title"),
            t(
                "update.rollback_confirm",
                id=bid,
                meta=str(meta),
            ),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._switch_to_progress_tab()
        proc = subprocess.run(
            ["bash", str(script), "rollback", bid],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if proc.stdout:
            self.raw_log.append(proc.stdout)
        if proc.returncode == 0:
            self._activity("ok", t("update.rollback_done"))
            QMessageBox.information(
                self, t("update.rollback_title"), t("update.rollback_done")
            )
        else:
            self._activity(
                "error",
                t("update.rollback_failed", code=proc.returncode),
            )
            QMessageBox.critical(
                self,
                t("dialog.error"),
                t("update.rollback_failed", code=proc.returncode)
                + "\n"
                + (proc.stderr or ""),
            )

    def _on_trust_action(self) -> None:
        if (ROOT / ".git").is_dir():
            try:
                n = generate_manifest(RECIPES_DIR, MANIFEST_PATH)
                self._activity("ok", t("trust.regen_ok") + f" ({n})")
                self.recipes = discover_recipes()
                self.refresh_statuses()
            except OSError as exc:
                self._activity("error", t("trust.regen_fail") + f": {exc}")
                QMessageBox.critical(self, t("dialog.error"), str(exc))
        else:
            self.check_updates()

    def show_about(self) -> None:
        AboutDialog(self).exec()

    def show_recipe_wizard(self) -> None:
        if can_create_recipes(ROOT):
            dlg = RecipeWizardDialog(self, ROOT)
            if dlg.exec() == QDialog.DialogCode.Accepted:
                self.recipes = discover_recipes()
                self._populate_list()
                self.refresh_statuses()
            return
        RecipeWizardBlockedDialog(self).exec()

    def show_developer_docs(self) -> None:
        DeveloperDocsDialog(self).exec()

    def report_bug(self) -> None:
        rid = self._selected.rid if self._selected else "launcher"
        if QMessageBox.question(
            self,
            t("dialog.report_title"),
            t("dialog.report_confirm"),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        report = collect_report_bundle(rid, self.session_id)
        clip = QApplication.clipboard()
        clip.setText(report_clipboard_text(rid, report, self.session_id))
        QDesktopServices.openUrl(QUrl(github_issue_url(rid, report)))
        QMessageBox.information(
            self,
            t("dialog.report_opened_title"),
            t("dialog.report_opened_body", name=report.name),
        )
        self._activity("info", t("dialog.report_clipboard", name=report.name))

    def _show_failure(self, done_label: str, code: int) -> None:
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Critical)
        box.setWindowTitle(t("dialog.error"))
        box.setText(t("error.E_SCRIPT_FAILED", label=done_label, code=code))
        box.setInformativeText(t("dialog.failure_info"))
        report = box.addButton(
            t("btn.report_github"), QMessageBox.ButtonRole.ActionRole
        )
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
                    recipe_icon(info.meta),
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
        # Re-verify trust + install state
        refreshed: list[RecipeInfo] = []
        for yml in sorted(RECIPES_DIR.glob("*/recipe.yml")):
            if yml.parent.name.startswith("_"):
                continue
            ok, reason = verify_recipe_trust(yml.parent, MANIFEST_PATH)
            meta = parse_recipe_yml(yml)
            rid = meta.get("id", yml.parent.name)
            meta["_dir"] = str(yml.parent)
            info = RecipeInfo(rid=rid, meta=meta, trust_ok=ok, trust_reason=reason or "")
            if not ok:
                info.state = RecipeState.UNTRUSTED
                info.status_detail = reason or t("trust.manifest_failed")
            else:
                env["RECIPE_ID"] = rid
                (
                    info.state,
                    info.status_detail,
                    info.version_detected,
                    info.version_warning,
                ) = query_recipe_state(rid, meta, env)
            refreshed.append(info)
        self.recipes = refreshed
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

        untrusted = info.state == RecipeState.UNTRUSTED or not info.trust_ok
        if untrusted:
            reason = info.trust_reason or info.status_detail or "?"
            detail = t("trust.detail", reason=reason)
            if (ROOT / ".git").is_dir():
                detail = f"{detail}\n{t('trust.hint_dev')}"
                self.trust_btn.setText(t("btn.regen_manifest"))
            else:
                detail = f"{detail}\n{t('trust.hint_user')}"
                self.trust_btn.setText(t("btn.update_rezeptor"))
            self.status_detail_label.setText(detail)
            self.status_detail_label.setVisible(True)
            self.info_browser.setPlainText(recipe_info_text(info.rid, Path(meta["_dir"])))
            self._render_info_markdown()
            self.trust_btn.setVisible(True)
            self.launch_btn.setEnabled(False)
            self.install_btn.setVisible(False)
            self.install_btn.setEnabled(False)
            self.repair_btn.setEnabled(False)
            self.validate_btn.setEnabled(False)
            self.kill_btn.setEnabled(False)
            self._refresh_running_indicators()
            return

        self.trust_btn.setVisible(False)
        detail = info.status_detail.strip()
        if info.state == RecipeState.INSTALLED and info.rid == "wiso-steuer":
            if not detail:
                detail = t("status.installed_wiso")
        elif info.state == RecipeState.INSTALLED and not detail:
            detail = t("status.installed_actions")
        self.status_detail_label.setText(detail if detail else " ")
        self.status_detail_label.setVisible(bool(detail))
        self.info_browser.setPlainText(recipe_info_text(info.rid, Path(meta["_dir"])))
        self._render_info_markdown()

        ok = info.state == RecipeState.INSTALLED
        partial_or_ok = info.state in (RecipeState.INSTALLED, RecipeState.PARTIAL)
        not_installed = info.state == RecipeState.NOT_INSTALLED
        can_launch = ok or (
            info.state == RecipeState.PARTIAL
            and any(
                (dr / "prefix").joinpath(p).is_file()
                for p in (
                    "drive_c/Program Files/Adobe/Adobe Photoshop 2021/Photoshop.exe",
                    "drive_c/Program Files (x86)/Adobe/Adobe Photoshop 2021/Photoshop.exe",
                )
            )
        )
        if not can_launch and info.state == RecipeState.PARTIAL and (dr / "prefix" / "user.reg").is_file():
            can_launch = True

        self.launch_btn.setEnabled(can_launch and not self._busy)
        show_install = not_installed
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
        self.kill_btn.setEnabled(can_launch and not self._busy)
        if info.state == RecipeState.PARTIAL and can_launch:
            detail = info.status_detail.strip() or t("state.installed_with_warnings")
            if "GPU-Experiment" in detail or "OpenGL an" in detail:
                self.status_detail_label.setText(t("status.gpu_experiment"))
            else:
                self.status_detail_label.setText(detail)
                self.status_detail_label.setVisible(True)
        self._refresh_running_indicators()

    def _refresh_running_indicators(self) -> None:
        for card, info in self._recipe_cards:
            running = recipe_process_running(info.rid, info.meta)
            card.set_running(running)
            card.set_install_state(info.state.value)
            if self._selected and self._selected.rid == info.rid and running:
                tip = self.status_detail_label.text()
                tip_l = tip.lower()
                if "läuft" not in tip_l and "running" not in tip_l:
                    base = tip.strip() if tip.strip() and tip.strip() != " " else t("state.installed")
                    self.status_detail_label.setText(
                        t("status.running_suffix", base=base)
                    )
                    self.status_detail_label.setVisible(True)
    def _update_status_pills(self, info: RecipeInfo) -> None:
        meta = info.meta
        guaranteed = meta.get("version_guaranteed", "")
        if guaranteed and not info.version_warning:
            self.tested_pill.setText(
                t("state.tested_guaranteed", version=guaranteed)
            )
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
            self.tested_pill.setText(t(STATE_LABEL.get(info.state, "state.unknown")))
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
                t("tooltip.version_installed", version=info.version_detected)
            )
        else:
            self.version_info_btn.setToolTip(t("tooltip.version_info"))

    def _show_version_guarantee_info(self) -> None:
        if not self._selected:
            return
        meta = self._selected.meta
        guaranteed = meta.get("version_guaranteed", "")
        label = meta.get("version_label") or guaranteed or "—"
        detected = self._selected.version_detected or "—"
        QMessageBox.information(
            self,
            t("dialog.version_title"),
            t(
                "dialog.version_body",
                label=label,
                detected=detected,
                help=t("dialog.version_help"),
            ),
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
                elif tag == "warn":
                    action = msg.replace("AKTION:", "").strip()
                    self.step_label.setText(action[:120])
                elif tag == "progress":
                    self.progress.setRange(0, 100)
                    self.progress.setVisible(True)
                    self.progress.setValue(min(100, max(0, int(msg))))
                    self.step_label.setText(t("status.progress_pct", pct=msg))
                continue

            pm = PROGRESS_RE.search(line)
            if pm:
                self.progress.setRange(0, 100)
                self.progress.setVisible(True)
                self.progress.setValue(int(pm.group(1)))
                self.step_label.setText(t("status.progress_pct", pct=pm.group(1)))
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
        prefix = {
            "step": "→",
            "ok": "✓",
            "warn": "⚠",
            "error": "✗",
            "info": "ℹ",
            "log": "·",
        }.get(kind, "·")
        item = QListWidgetItem(f"{prefix} {text}")
        colors = {
            "ok": QColor("#3ddc84"),
            "error": QColor("#f85149"),
            "warn": QColor("#e6a700"),
            "step": QColor("#58a6ff"),
            "info": QColor("#a1a1aa"),
            "log": QColor("#c9d1d9"),
        }
        if kind in colors:
            item.setForeground(colors[kind])
        self.activity_list.addItem(item)
        self.activity_list.scrollToBottom()
        if kind in ("step", "ok", "warn", "error"):
            self.step_label.setText(text[:140])
            if kind == "ok":
                self.step_label.setStyleSheet("color: #3ddc84; font-weight: 600;")
            elif kind == "error":
                self.step_label.setStyleSheet("color: #f85149; font-weight: 600;")
            elif kind == "warn":
                self.step_label.setStyleSheet("color: #e6a700; font-weight: 600;")
            else:
                self.step_label.setStyleSheet("color: #58a6ff; font-weight: 600;")

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
            self.step_label.setText(t("status.done"))
        for b in (
            self.install_btn,
            self.repair_btn,
            self.launch_btn,
            self.validate_btn,
            self.kill_btn,
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
            QMessageBox.warning(self, t("dialog.running"), t("dialog.busy_warn"))
            return None
        if not self._selected:
            return None
        return Path(self._selected.meta["_dir"])

    def _run_async(
        self,
        script: Path,
        extra: dict[str, str] | None = None,
        done_label: str = "",
        dialog: bool = True,
    ) -> None:
        if not done_label:
            done_label = t("action.done")
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
        self.step_label.setText(t("status.op_starting"))
        # Stale Prüf-Status (z. B. „FAIL: Wine-Prefix fehlt") während des Vorgangs
        # ausblenden — nach Abschluss setzt refresh_statuses() den echten Stand.
        self.status_detail_label.setText(t("status.busy"))
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
            self._activity(
                "ok" if code == 0 else "error",
                t("status.exit_code", label=done_label, code=code),
            )
            self.populate_log_files()
            self.refresh_statuses()
            if code != 0 and dialog:
                self._show_failure(done_label, code)
            elif code == 0 and dialog:
                QMessageBox.information(
                    self,
                    t("status.done"),
                    t("status.done_body", label=done_label),
                )

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

    def _maybe_wine_dialog_hint(self, action: str) -> None:
        if action not in ("install", "repair"):
            return
        if self._wiso_mono_hint_shown:
            return
        self._wiso_mono_hint_shown = True
        self._activity(
            "info",
            t("dialog.wine_dialogs_activity"),
        )
        QMessageBox.information(
            self,
            t("dialog.wine_dialogs_title"),
            t("dialog.wine_dialogs_body"),
        )

    def show_settings(self) -> None:
        dlg = SettingsDialog(self, self._settings)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        self._settings = dlg.result_settings()
        set_locale(self._settings.locale)
        self.retranslate_ui()
        self._activity(
            "info",
            t(
                "settings.saved",
                days=self._settings.log_retention_days,
                files=self._settings.log_max_files,
            ),
        )

    def retranslate_ui(self) -> None:
        self._build_menus()
        self.setWindowTitle(
            self._window_title(
                read_version(), self._update_available or ""
            )
        )
        self._refresh_status_footer(self._update_available)
        if hasattr(self, "_sidebar_title"):
            self._sidebar_title.setText(t("app.sidebar_title"))
        if hasattr(self, "_overview_hint"):
            self._overview_hint.setText(t("overview.hint"))
        if hasattr(self, "_progress_steps_label"):
            self._progress_steps_label.setText(t("progress.steps"))
        if hasattr(self, "_progress_live_label"):
            self._progress_live_label.setText(t("progress.live"))
        if hasattr(self, "raw_log"):
            self.raw_log.setPlaceholderText(t("progress.live_placeholder"))
        if hasattr(self, "_logs_file_label"):
            self._logs_file_label.setText(t("logs.label"))
        if hasattr(self, "_logs_refresh_btn"):
            self._logs_refresh_btn.setText(t("logs.refresh"))
        self.launch_btn.setText(t("btn.launch"))
        self.install_btn.setText(t("btn.install"))
        self.repair_btn.setText(t("btn.repair"))
        self.validate_btn.setText(t("btn.validate"))
        self.kill_btn.setText(t("btn.kill"))
        self.more_btn.setText(t("btn.more"))
        self.launch_btn.setToolTip(t("tooltip.launch"))
        self.install_btn.setToolTip(t("tooltip.install"))
        self.repair_btn.setToolTip(t("tooltip.repair"))
        self.validate_btn.setToolTip(t("tooltip.validate"))
        self.kill_btn.setToolTip(t("tooltip.kill"))
        self.more_btn.setToolTip(t("tooltip.more"))
        if not self._selected:
            self.name_label.setText(t("app.choose_recipe"))
        if hasattr(self, "segment_tabs"):
            self.segment_tabs.set_labels(
                [
                    ("overview", t("tab.overview")),
                    ("progress", t("tab.progress")),
                    ("logs", t("tab.logs")),
                ]
            )
        if self._selected:
            self._on_select(self._selected_index)

    def cleanup_logs_now(self) -> None:
        removed = prune_old_logs(
            retention_days=self._settings.log_retention_days,
            max_files=self._settings.log_max_files,
        )
        self.populate_log_files()
        self._activity("info", t("settings.cleanup_activity", removed=removed))
        QMessageBox.information(
            self,
            t("settings.cleanup_title"),
            t("settings.cleanup_short", removed=removed),
        )

    def run_install(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        install = rd / "install.sh"
        if not install.is_file():
            QMessageBox.critical(self, t("dialog.missing"), str(install))
            return

        meta = self._selected.meta
        extra: dict[str, str] = {}

        if needs_source_dialog(meta):
            dlg = RecipeSourceDialog(
                self,
                rid=self._selected.rid,
                meta=meta,
                root=ROOT,
                title=t(
                    "dialog.source_pick_title",
                    name=meta.get("name", self._selected.rid),
                ),
            )
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return
            dr = expand_home(
                meta.get("data_root", f"~/.local/share/wine-software/{self._selected.rid}")
            )
            try:
                extra = dlg.build_env(dr)
            except OSError as exc:
                QMessageBox.critical(
                    self,
                    t("dialog.source_label"),
                    t("dialog.source_invalid", error=exc),
                )
                return
            if meta.get("source_kind") == "folder" and not (
                extra.get("RECIPE_SOURCE_ROOT") or extra.get("RECIPE_ARCHIVE_PATH")
            ):
                return

        info = recipe_info_text(self._selected.rid, rd)
        name = meta.get("name", self._selected.rid)
        if self._selected.state == RecipeState.INSTALLED:
            confirm = t("dialog.install_reconfirm", name=name)
        else:
            confirm = t("dialog.install_start", info=info)

        if QMessageBox.question(
            self,
            t("dialog.install_title"),
            confirm,
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return

        self._maybe_wine_dialog_hint("install")
        label = (
            t("action.reinstall")
            if self._selected.state == RecipeState.INSTALLED
            else t("action.install")
        )
        self._run_async(install, extra, label)

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
            title=t(
                "dialog.source_title",
                name=meta.get("name", self._selected.rid),
            ),
        )
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        dr = expand_home(meta.get("data_root", f"~/.local/share/wine-software/{self._selected.rid}"))
        extra = dlg.build_env(dr)
        if not (extra.get("RECIPE_SOURCE_ROOT") or extra.get("RECIPE_ARCHIVE_PATH")):
            return
        install = rd / "install.sh"
        if not install.is_file():
            QMessageBox.critical(self, t("dialog.missing"), str(install))
            return
        self._run_async(install, extra, t("action.source_config"))

    def run_repair(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        repair = rd / "repair.sh"
        if not repair.is_file():
            QMessageBox.warning(self, t("dialog.missing"), t("dialog.no_repair"))
            return
        if self._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.warning(
                self, t("dialog.not_installed_title"), t("dialog.install_first")
            )
            return
        if QMessageBox.question(
            self,
            t("dialog.repair_title"),
            self._repair_message(self._selected.rid),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._maybe_wine_dialog_hint("repair")
        self._run_async(repair, done_label=t("action.repair"))

    def _repair_message(self, rid: str) -> str:
        if rid == "wiso-steuer":
            return t("dialog.repair_wiso")
        return t("dialog.repair_default")

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
        # launch.sh kann sofort abbrechen („Läuft bereits“) — Log prüfen.
        try:
            log_tail = log_path.read_text(encoding="utf-8", errors="replace")[-4000:]
        except OSError:
            log_tail = ""
        if "Läuft bereits:" in log_tail:
            name = self._selected.meta.get("name", rid) if self._selected else rid
            self._activity(
                "warn",
                t("dialog.launch_already", name=name),
            )
            return
        if "Hängende unsichtbare" in log_tail and attempt == 0:
            self._activity("info", t("dialog.launch_hung"))
        meta = self._selected.meta if self._selected else None
        if not LAUNCH_PROCESS_PATTERNS.get(rid):
            return
        if recipe_process_running(rid, meta):
            if not getattr(self, "_launch_alive_reported", False):
                self._launch_alive_reported = True
                self._activity("ok", t("status.app_running"))
            return
        if attempt < 7:
            QTimer.singleShot(
                2500,
                lambda: self._check_launch_alive(rid, log_path, attempt + 1),
            )
            return
        name = self._selected.meta.get("name", rid) if self._selected else rid
        tips = (
            t("dialog.launch_tips_wiso")
            if rid == "wiso-steuer"
            else t("dialog.launch_tips_default")
        )
        QMessageBox.warning(
            self,
            t("status.app_not_running"),
            t("dialog.launch_not_alive", name=name, log=log_path, tips=tips),
        )
        ev = LogEvent(
            level="warn",
            code=E_LAUNCH_NO_PROCESS,
            message_key="error.E_LAUNCH_NO_PROCESS",
            detail=log_path.name,
            session_id=self.session_id,
            recipe_id=rid,
        )
        self._activity("warn", ev.display_text())
        self._switch_to_logs_tab()
        self.populate_log_files()

    def run_launch(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        if self._selected and not self._selected.trust_ok:
            QMessageBox.warning(
                self,
                t("trust.title"),
                t("trust.detail", reason=self._selected.trust_reason or "?"),
            )
            return
        if self._selected and self._selected.version_warning:
            if QMessageBox.warning(
                self,
                t("dialog.version_warn_title"),
                t(
                    "dialog.version_warn_body",
                    warning=self._selected.version_warning,
                ),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            ) != QMessageBox.StandardButton.Yes:
                return
        env = self._base_env()
        if self._selected and self._selected.rid == "wiso-steuer":
            env.pop("WINE_DISABLE_WOW64", None)
        meta = self._selected.meta
        launch = rd / "launch.sh"
        if not launch.is_file():
            QMessageBox.warning(self, t("dialog.missing"), t("dialog.no_launch"))
            return
        log_path = self._spawn_detached(["bash", str(launch)], env)
        self._switch_to_progress_tab()
        self.activity_list.clear()
        self.raw_log.clear()
        self._launch_alive_reported = False
        name = meta.get("name", self._selected.rid)
        self.step_label.setText(t("status.starting", name=name))
        self.step_label.setStyleSheet("color: #58a6ff; font-weight: 600;")
        self._activity("step", t("status.start_triggered", name=name))
        self._activity("info", t("status.window_soon"))
        rid = self._selected.rid
        if rid in LAUNCH_PROCESS_PATTERNS:
            QTimer.singleShot(
                2500, lambda: self._check_launch_alive(rid, log_path, 0)
            )

    def run_validate(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        v = rd / "validate.sh"
        if v.is_file():
            self._run_async(v, done_label=t("action.validate"), dialog=True)

    def run_kill(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        kill = rd / "kill.sh"
        if not kill.is_file():
            QMessageBox.warning(self, t("dialog.missing"), t("dialog.no_kill"))
            return
        name = self._selected.meta.get("name", self._selected.rid)
        if QMessageBox.question(
            self,
            t("dialog.kill_title"),
            t("dialog.kill_body", name=name),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._switch_to_progress_tab()
        self._run_async(kill, done_label=t("action.kill"), dialog=False)

    def run_uninstall(self) -> None:
        rd = self._require_recipe()
        if rd is None:
            return
        un = rd / "uninstall.sh"
        if not un.is_file():
            QMessageBox.warning(self, t("dialog.missing"), t("dialog.no_uninstall"))
            return
        if QMessageBox.question(
            self,
            t("dialog.uninstall_title"),
            t(
                "dialog.uninstall_confirm",
                name=self._selected.meta.get("name", self._selected.rid),
            ),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        extra = {"PHOTOSHOP_UNINSTALL_YES": "1", "UNINSTALL_YES": "1"}
        self._run_async(un, extra, t("action.uninstall"))


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
