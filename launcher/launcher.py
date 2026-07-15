#!/usr/bin/env python3
"""Rezeptor — GUI für getestete Wine-Software-Rezepte (Proton-GE)."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from collections.abc import Callable
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
        QKeySequence,
        QPalette,
        QPixmap,
        QShortcut,
    )
    from PyQt6.QtWidgets import (
        QApplication,
        QDialog,
        QDialogButtonBox,
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
    detect_source_version,
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
    COLOR_EXPERIMENTAL,
    COLOR_TESTED,
    FLUENT_AVAILABLE,
    CaptionLabel,
    CardWidget,
    FluentIcon,
    Pivot,
    PrimaryPushButton,
    PushButton,
    RoundMenu,
    SubtitleLabel,
    TitleLabel,
    apply_rezeptor_theme,
    app_stylesheet,
)
from ui_rezeptor import (
    REZEPTOR_ICON,
    SEGMENT_TAB_STYLES,
    LimitedComboBox,
    RecipeSidebarCard,
    SegmentTabBar,
    StatusPill,
    STATE_DOT,
)
from settings import RezeptorSettings, load_settings, recipe_edit_allowed, save_settings
from ui_settings import SettingsDialog
from ui_docs import DeveloperDocsDialog
from ui_recipe_view import RecipeViewDialog
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
    friendly_trust_reason,
    generate_manifest,
    rezeptor_dev_mode,
    sync_manifest_if_stale,
    verify_recipe_trust,
)
from ui_styles import COLOR_PARCHMENT, MUTED, STATE_COLORS, palette
from ui_icons import ensure_fa_font, fa_color, fa_icon
from ui_progress import WaitingSpinner
from ui_window import (
    apply_tool_window,
    geometry_to_b64,
    restore_geometry,
)
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
    validate_fails: list[str] | None = None


def parse_recipe_yml(path: Path) -> dict[str, str]:
    """Flache Metadaten für die GUI. Eingebettete Blöcke (version_detect, …) werden übersprungen."""
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        # Nur Top-Level-Keys — eingerückte YAML-Zeilen nicht als Felder lesen
        if not line or line[0] in " \t#" or ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        if not key or key.startswith("-"):
            continue
        data[key] = val.strip().strip('"')
    return data


def discover_recipes() -> list[RecipeInfo]:
    found: list[RecipeInfo] = []
    trust_failures: list[str] = []
    if not RECIPES_DIR.is_dir():
        return found
    synced, sync_msg = sync_manifest_if_stale(RECIPES_DIR, MANIFEST_PATH, ROOT)
    if synced and sync_msg:
        os.environ["REZEPTOR_MANIFEST_SYNC"] = sync_msg

    yml_paths: list[Path] = []
    for yml in sorted(RECIPES_DIR.glob("*/recipe.yml")):
        if yml.parent.name.startswith("_"):
            continue
        if yml.parent.name == "community":
            continue
        yml_paths.append(yml)
    community = RECIPES_DIR / "community"
    if community.is_dir():
        for yml in sorted(community.glob("*/recipe.yml")):
            if yml.parent.name.startswith("_"):
                continue
            yml_paths.append(yml)

    for yml in yml_paths:
        ok, reason = verify_recipe_trust(yml.parent, MANIFEST_PATH)
        meta = parse_recipe_yml(yml)
        rid = meta.get("id", yml.parent.name)
        meta["_dir"] = str(yml.parent)
        if "community" in yml.parent.parts and meta.get("origin", "") != "official":
            meta.setdefault("origin", "community")
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
    "wiso-steuer": ["wiso2026.exe", "wmain26.exe"],
    "photoshop": ["Photoshop.exe"],
    "za4-trainer": ["ZA4-Trainer.exe"],
    "house-of-ashes": ["HouseOfAshes.exe"],
}

# Cmdlines, die nur über den Text matchen (Agent, Shell, Editor) — nie „läuft“.
_RUNNING_NOISE = (
    "cursor",
    "agent",
    "pgrep",
    "pkill",
    "recipe_process_running",
    "snap=$(command cat",
    "launcher.py",
    "recipe-lint",
    "rg ",
    "grep ",
    "/usr/bin/zsh -c",
)


def resolve_data_root(meta: dict[str, str], rid: str) -> Path:
    """Kanonischer data_root; Override aus data_root.path nur wenn Zielordner existiert."""
    canonical = expand_home(
        meta.get("data_root", f"~/.local/share/wine-software/{rid}")
    )
    pointer = Path(canonical) / "data_root.path"
    if pointer.is_file():
        raw = pointer.read_text(encoding="utf-8").strip()
        if raw:
            override = expand_home(raw)
            # Verwaistes Ziel (gelöscht) nicht als aktiv anzeigen — Install-Dialog
            # liest data_root.path weiterhin separat als Vorschlag.
            if override.is_dir():
                return override
    return Path(canonical)


def recipe_wine_prefix(meta: dict[str, str], rid: str) -> Path:
    dr = resolve_data_root(meta, rid)
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


def _proc_comm(pid: str) -> str:
    try:
        return Path(f"/proc/{pid}/comm").read_text(encoding="utf-8", errors="replace").strip()
    except (OSError, ProcessLookupError):
        return ""


def _proc_exe(pid: str) -> str:
    try:
        return os.readlink(f"/proc/{pid}/exe")
    except (OSError, ProcessLookupError):
        return ""


def _is_noise_process(cmd: str) -> bool:
    cl = (cmd or "").lower()
    if not cl.strip():
        return True
    return any(m in cl for m in _RUNNING_NOISE)


def _looks_like_wine_or_proton(pid: str, cmd: str) -> bool:
    """Echter Wine/Proton-Lauf — nicht nur Erwähnung der EXE in einer Shell."""
    cl = (cmd or "").lower()
    exe = _proc_exe(pid).lower()
    comm = _proc_comm(pid).lower()
    markers = (
        "proton",
        "wine-preloader",
        "wine64",
        "wine ",
        "/wine",
        "wineserver",
        "steam-runtime",
        "pressure-vessel",
    )
    blob = f"{cl} {exe} {comm}"
    if any(m in blob for m in markers):
        return True
    # Wine setzt oft Windows-artige Cmdlines: C:\... oder Z:\...
    if "\\" in cmd and (".exe" in cl or ".dll" in cl):
        return True
    return False


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
    """True nur bei echtem App-Prozess (Wine/Proton), nicht bei Shell-/Agent-Cmdlines."""
    patterns = LAUNCH_PROCESS_PATTERNS.get(rid, [])
    if not patterns:
        return False
    prefix: Path | None = None
    path_hints: list[str] = []
    steam_mode = False
    if meta:
        prefix = recipe_wine_prefix(meta, rid)
        dr = resolve_data_root(meta, rid)
        path_hints = [str(dr).lower(), str(prefix).lower()]
        for key in ("portable_root", "target_default"):
            raw = (meta.get(key) or "").strip()
            if raw:
                path_hints.append(str(expand_home(raw)).lower())
        env_path = dr / "recipe.env"
        if env_path.is_file():
            try:
                for line in env_path.read_text(encoding="utf-8").splitlines():
                    if "=" not in line or line.strip().startswith("#"):
                        continue
                    k, _, v = line.partition("=")
                    k, v = k.strip(), v.strip().strip('"')
                    if k in ("WORK_ROOT", "TRAINER_EXE", "COMPATDATA", "GAME_DIR", "GAME_EXE") and v:
                        path_hints.append(v.lower())
            except OSError:
                pass
        appid = (meta.get("steam_appid") or "").strip()
        if appid:
            steam_mode = True
            try:
                from steam_paths import steam_app_install_dir, steam_compatdata_dir

                game = steam_app_install_dir(appid)
                if game is not None:
                    path_hints.append(str(game).lower())
                compat = steam_compatdata_dir(appid)
                if compat is not None:
                    path_hints.append(str(compat).lower())
            except Exception:
                pass

    patterns_l = [p.lower() for p in patterns]
    for ent in Path("/proc").iterdir():
        if not ent.name.isdigit():
            continue
        cmd = _proc_cmdline(ent.name)
        if not cmd or _is_noise_process(cmd):
            continue
        cmd_l = cmd.lower()
        if not any(pat in cmd_l for pat in patterns_l):
            # Manche Wine-Prozesse haben nur den kurzen EXE-Namen in comm
            comm = _proc_comm(ent.name).lower()
            if not any(pat.rstrip(".exe") in comm or pat in comm for pat in patterns_l):
                continue
            cmd_l = f"{cmd_l} {comm}"

        if not _looks_like_wine_or_proton(ent.name, cmd):
            continue

        if steam_mode:
            if any(h and h in cmd_l for h in path_hints):
                return True
            # Proton-run ohne vollen Pfad in cmdline — EXE + Proton reicht
            if any(pat in cmd_l for pat in patterns_l):
                return True
            continue

        if prefix is not None and _proc_has_wineprefix(ent.name, prefix):
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


def _escape_html(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def _inline_md_html(escaped: str) -> str:
    """**fett** und `code` in bereits HTML-escaped Text."""
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"`([^`]+)`", r"<code style='font-size:12px'>\1</code>", escaped)
    return escaped


def format_recipe_info_html(
    raw: str,
    *,
    theme: str = "dark",
    author: str = "",
) -> str:
    """Einheitliches Info-Layout → HTML (Übersicht + Install-Dialog)."""
    fg = palette(theme)["fg"]
    muted = palette(theme)["muted"]
    parts: list[str] = []
    in_list = False

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            parts.append("</ul>")
            in_list = False

    for line in (raw or "").splitlines():
        stripped = line.strip()
        if not stripped:
            close_list()
            parts.append("<div style='height:6px'></div>")
            continue
        esc = _inline_md_html(_escape_html(line))
        if stripped.startswith("# "):
            close_list()
            title = _inline_md_html(_escape_html(stripped[2:].strip()))
            parts.append(
                f"<h2 style='margin:8px 0 4px;font-size:16px;color:{fg}'>{title}</h2>"
            )
        elif stripped.startswith("## "):
            close_list()
            title = _inline_md_html(_escape_html(stripped[3:].strip()))
            parts.append(
                f"<h3 style='margin:10px 0 4px;font-size:13px;color:{fg}'>{title}</h3>"
            )
        elif stripped.startswith(("• ", "- ", "* ")) or re.match(r"^\d+\.\s", stripped):
            if not in_list:
                parts.append("<ul style='margin:4px 0 4px 18px;padding:0'>")
                in_list = True
            if re.match(r"^\d+\.\s", stripped):
                body = _inline_md_html(_escape_html(re.sub(r"^\d+\.\s+", "", stripped)))
            else:
                body = _inline_md_html(_escape_html(stripped[2:].strip()))
            parts.append(f"<li style='margin:2px 0'>{body}</li>")
        elif stripped.startswith(("Autor:", "Author:", "Version:")):
            close_list()
            parts.append(
                f"<p style='margin:2px 0;color:{muted};font-size:12px'>{esc}</p>"
            )
        elif stripped.endswith(":") and len(stripped) < 80 and not stripped.startswith("http"):
            close_list()
            parts.append(f"<p style='margin:8px 0 2px'><b>{esc}</b></p>")
        else:
            close_list()
            parts.append(f"<p style='margin:4px 0'>{esc}</p>")
    close_list()

    meta_bits: list[str] = []
    if author.strip():
        # Nur wenn Info-Text keinen Autor-Block hat
        if not re.search(r"(?m)^(Autor|Author):", raw or ""):
            meta_bits.append(
                f"<p style='margin:0 0 8px;color:{muted};font-size:12px'>"
                f"{_escape_html(t('info.author', author=author.strip()))}</p>"
            )
    return (
        f"<div style='line-height:1.45; color:{fg}'>"
        + "".join(meta_bits)
        + "".join(parts)
        + "</div>"
    )


class InfoConfirmDialog(QDialog):
    """Install-Bestätigung mit formatiertem Rezept-Info (kein Roh-Markdown)."""

    def __init__(
        self,
        parent: QWidget | None,
        *,
        title: str,
        html: str,
        question: str,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(560, 520)
        lay = QVBoxLayout(self)
        browser = QTextBrowser()
        browser.setOpenExternalLinks(True)
        browser.setHtml(html)
        browser.setMinimumHeight(360)
        lay.addWidget(browser, stretch=1)
        q = QLabel(question)
        q.setWordWrap(True)
        q.setObjectName("stepLabel")
        lay.addWidget(q)
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Yes | QDialogButtonBox.StandardButton.No
        )
        buttons.button(QDialogButtonBox.StandardButton.Yes).setText(t("dialog.yes"))
        buttons.button(QDialogButtonBox.StandardButton.No).setText(t("dialog.no"))
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        lay.addWidget(buttons)


def query_recipe_state(
    rid: str, meta: dict[str, str], env: dict[str, str]
) -> tuple[RecipeState, str, str, str, list[str]]:
    rd = Path(meta["_dir"])
    validate = rd / "validate.sh"
    dr = resolve_data_root(meta, rid)
    prefix = dr / "prefix"
    empty = ("", "")

    # Validate muss denselben DATA_ROOT sehen wie die GUI
    env = dict(env)
    env["DATA_ROOT"] = str(dr)
    env["RECIPE_DATA_ROOT"] = str(dr)
    env["WINEPREFIX"] = str(prefix)
    env["WINE_PREFIX"] = str(prefix)

    def _has_marker() -> bool:
        if prefix.is_dir() and (prefix / "user.reg").is_file():
            return True
        return (dr / "recipe.env").is_file() or (dr / "portable.env").is_file()

    def _version_fallback(detected: str) -> str:
        if detected:
            return detected
        # Portable/Spiel: detect auf Quellordner (nicht nur data_root)
        roots: list[Path] = []
        for env_name, key in (
            ("portable.env", "WISO_PORTABLE_ROOT"),
            ("recipe.env", "GAME_DIR"),
            ("recipe.env", "WORK_ROOT"),
        ):
            ep = dr / env_name
            if not ep.is_file():
                continue
            try:
                for line in ep.read_text(encoding="utf-8", errors="replace").splitlines():
                    if line.startswith(f"{key}="):
                        raw = line.split("=", 1)[1].strip().strip("'\"")
                        # Unescape shell-ish spaces: "The\ Dark" → "The Dark"
                        raw = raw.replace("\\ ", " ")
                        if raw:
                            roots.append(Path(raw))
                        break
            except OSError:
                pass
        roots.append(dr)
        yml = rd / "recipe.yml"
        guaranteed = meta.get("version_guaranteed", "")
        for root in roots:
            if not root.exists():
                continue
            try:
                ver = detect_source_version(
                    rid, str(root), recipe_dir=rd, guaranteed=guaranteed
                )
            except OSError:
                ver = ""
            if ver:
                return ver
        return ""

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
        detected = _version_fallback(detected)
        fails = [
            ln[5:].strip()
            for ln in out.splitlines()
            if ln.startswith("FAIL:") and ln[5:].strip()
        ]
        fail = fails[0] if fails else ""
        if proc.returncode == 0:
            detail = version_warn or ""
            return RecipeState.INSTALLED, detail, detected, version_warn, []
        if _has_marker():
            detail = fail or version_warn or t("state.prefix_present")
            return RecipeState.PARTIAL, detail, detected, version_warn, fails
        # Nie @progress/@step als Status — bei fehlendem Prefix klar „nicht installiert“
        return (
            RecipeState.NOT_INSTALLED,
            t("state.not_installed"),
            detected,
            version_warn,
            fails,
        )

    if _has_marker():
        return RecipeState.PARTIAL, str(dr), *empty, []
    return RecipeState.NOT_INSTALLED, t("state.not_installed"), *empty, []


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
        self._recipe_view_dlg: RecipeViewDialog | None = None
        self._docs_dlg: DeveloperDocsDialog | None = None
        self._ui_restored = False
        self._suppress_tab_persist = False
        self.session_id = uuid.uuid4().hex[:12]
        self.recipes = discover_recipes()
        self._dev_mode = rezeptor_dev_mode()
        self._selected: RecipeInfo | None = None
        self._selected_index = -1
        self._recipe_cards: list[tuple[RecipeSidebarCard, RecipeInfo]] = []
        self._process: QProcess | None = None
        self._busy = False
        self._theme = "dark"
        self._raw_log_buffer: list[str] = []
        self._latest_release = ""
        self._release_url = f"https://github.com/{GITHUB_REPO}/releases"
        self._wiso_mono_hint_shown = False
        self._update_available = ""
        self._launch_alive_reported = False
        self._trust_btn: QPushButton | None = None
        self._menu_bar_built = False
        self._last_activity_key: tuple[str, str] | None = None
        self._progress_pct = 0
        self._progress_anchor = 0  # letzter echter @progress-Tick
        self._progress_pulse = 0
        self._progress_got_tick = False
        self._progress_changed_at = 0.0
        self._progress_stall_timer = QTimer(self)
        self._progress_stall_timer.setInterval(400)
        self._progress_stall_timer.timeout.connect(self._on_progress_stall_tick)
        self._running_poll = QTimer(self)
        self._running_poll.setInterval(3000)
        self._running_poll.timeout.connect(self._refresh_running_indicators)

        self._build_menus()
        self._build_status_bar()
        self._build_layout()
        self._apply_theme()

        self._install_shortcuts()
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
            start = 0
            last = (self._settings.last_recipe_id or "").strip()
            if last:
                for i, info in enumerate(self.recipes):
                    if info.rid == last:
                        start = i
                        break
            self._select_recipe_index(start)
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
        self.action_view_recipe = QAction(self._view_recipe_label(), self)
        self.action_view_recipe.triggered.connect(self.show_recipe_view)
        rezeptor_menu.addAction(self.action_view_recipe)
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

    def _view_recipe_label(self) -> str:
        if recipe_edit_allowed(self._settings):
            return t("menu.edit_recipe")
        return t("menu.view_recipe")

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
            muted = palette(getattr(self, "_theme", "dark"))["muted"]
            self.status_footer.setStyleSheet(f"color: {muted};")
            self.status_footer.setToolTip("")
            self.status_footer.setCursor(QCursor(Qt.CursorShape.ArrowCursor))

    def _build_layout(self) -> None:
        """Hauptfenster-Regionen (intern): Sidebar | HEADER | Navigation | INFO."""
        central = QWidget()
        self.setCentralWidget(central)
        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # —— Sidebar —— Rezeptliste (Kategorie nur hier) — feste Breite laut UI-Framework
        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setAccessibleName("Sidebar")
        sidebar.setFixedWidth(240)
        sl = QVBoxLayout(sidebar)
        sl.setContentsMargins(12, 14, 12, 12)
        sl.setSpacing(10)

        st = QLabel(t("app.sidebar_title"))
        st.setObjectName("sidebarTitle")
        self._sidebar_title = st
        sl.addWidget(st)

        self.sidebar_search = QLineEdit()
        self.sidebar_search.setObjectName("sidebarSearch")
        self.sidebar_search.setPlaceholderText(t("app.sidebar_search"))
        self.sidebar_search.setClearButtonEnabled(True)
        self.sidebar_search.textChanged.connect(self._on_sidebar_search)
        sl.addWidget(self.sidebar_search)

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

        # —— Rechte Spalte: HEADER + Navigation + INFO ——
        main = QWidget()
        main.setObjectName("mainColumn")
        main.setAccessibleName("Main")
        main.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
        )
        ml = QVBoxLayout(main)
        ml.setContentsMargins(16, 14, 16, 12)
        ml.setSpacing(12)

        # —— HEADER —— Titel, Badges, Pfad, Kurzhinweis
        header = CardWidget() if FLUENT_AVAILABLE else QFrame()
        header.setObjectName("headerCard")
        header.setAccessibleName("HEADER")
        hl = QHBoxLayout(header)
        hl.setContentsMargins(16, 14, 16, 14)
        hl.setSpacing(14)

        self.icon_label = QLabel()
        self.icon_label.setFixedSize(64, 64)
        self.icon_label.setScaledContents(True)
        if REZEPTOR_ICON.is_file():
            self.icon_label.setPixmap(QIcon(str(REZEPTOR_ICON)).pixmap(64, 64))
        hl.addWidget(self.icon_label, alignment=Qt.AlignmentFlag.AlignTop)

        hc = QVBoxLayout()
        hc.setSpacing(4)
        hc.setContentsMargins(0, 0, 0, 0)
        self.name_label = (
            TitleLabel(t("app.choose_recipe"))
            if FLUENT_AVAILABLE
            else QLabel(t("app.choose_recipe"))
        )
        self.name_label.setObjectName("appTitle")
        self.name_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        if FLUENT_AVAILABLE:
            self.name_label.setText(t("app.choose_recipe"))

        self.version_info_btn = QToolButton()
        self.version_info_btn.setObjectName("versionInfoBtn")
        self.version_info_btn.setAutoRaise(True)
        self.version_info_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.version_info_btn.setToolTip(t("tooltip.version_info"))
        self.version_info_btn.setFixedSize(26, 26)
        info_ic = fa_icon("info", 14, color=COLOR_PARCHMENT)
        if info_ic is not None:
            self.version_info_btn.setIcon(info_ic)
            self.version_info_btn.setIconSize(QSize(14, 14))
        else:
            self.version_info_btn.setText("i")
        self.version_info_btn.clicked.connect(self._show_version_guarantee_info)
        self.version_info_btn.setVisible(False)

        title_row = QHBoxLayout()
        title_row.setSpacing(6)
        title_row.setContentsMargins(0, 0, 0, 0)
        title_row.addWidget(self.name_label, stretch=1)
        title_row.addWidget(
            self.version_info_btn, alignment=Qt.AlignmentFlag.AlignVCenter
        )

        # Badges: Version · Garantie · Runtime · Autor — Status bei Zustand
        pills_row = QHBoxLayout()
        pills_row.setSpacing(8)
        self.status_pill = StatusPill("—", MUTED)
        self.status_pill.setVisible(False)
        self.version_pill = StatusPill("", COLOR_TESTED)
        self.version_pill.setCursor(Qt.CursorShape.PointingHandCursor)
        self.version_pill.setToolTip(t("tooltip.version_info"))
        self.version_pill.clicked.connect(self._show_version_guarantee_info)
        self.tested_pill = StatusPill("—", COLOR_TESTED)
        self.proton_pill = StatusPill("Proton-GE", COLOR_EXPERIMENTAL)
        self.author_pill = StatusPill("", MUTED)
        pills_row.addWidget(self.status_pill)
        pills_row.addWidget(self.version_pill)
        pills_row.addWidget(self.tested_pill)
        pills_row.addWidget(self.proton_pill)
        pills_row.addWidget(self.author_pill)
        self.health_chip = QToolButton()
        self.health_chip.setObjectName("healthChip")
        self.health_chip.setCursor(Qt.CursorShape.PointingHandCursor)
        self.health_chip.setAutoRaise(True)
        self.health_chip.setVisible(False)
        self.health_chip.clicked.connect(self._show_health_dialog)
        pills_row.addWidget(self.health_chip)
        self.progress_chip = QLabel("")
        self.progress_chip.setObjectName("progressChip")
        self.progress_chip.setVisible(False)
        pills_row.addWidget(self.progress_chip)
        pills_row.addStretch(1)

        self.path_label = QLabel()
        self.path_label.setObjectName("appPath")
        self.path_label.setWordWrap(True)
        self.path_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        self._style_secondary_label(self.path_label, MUTED, size_px=11)
        self.open_path_btn = QToolButton()
        self.open_path_btn.setObjectName("openPathBtn")
        self.open_path_btn.setAutoRaise(True)
        self.open_path_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.open_path_btn.setToolTip(t("tooltip.open_data_root"))
        self.open_path_btn.setFixedSize(26, 26)
        folder_ic = fa_icon("folder", 14, color=COLOR_PARCHMENT)
        if folder_ic is not None:
            self.open_path_btn.setIcon(folder_ic)
            self.open_path_btn.setIconSize(QSize(14, 14))
        else:
            self.open_path_btn.setText("…")
        self.open_path_btn.clicked.connect(self._open_data_root)
        self.open_path_btn.setEnabled(False)

        path_row = QHBoxLayout()
        path_row.setSpacing(4)
        path_row.setContentsMargins(0, 0, 0, 0)
        path_row.addWidget(self.path_label, stretch=1)
        path_row.addWidget(
            self.open_path_btn, alignment=Qt.AlignmentFlag.AlignTop
        )

        self.status_detail_label = QLabel()
        self.status_detail_label.setObjectName("statusDetail")
        self.status_detail_label.setWordWrap(True)
        self._style_secondary_label(self.status_detail_label, MUTED, size_px=12)
        hc.addLayout(title_row)
        hc.addLayout(pills_row)
        hc.addLayout(path_row)
        hc.addWidget(self.status_detail_label)
        hl.addLayout(hc, stretch=1)
        ml.addWidget(header)

        # —— Navigation —— Starten / Reparieren / Prüfen / Beenden / Mehr
        self._build_action_bar(ml)

        overview = self._create_overview_tab()
        progress = self._create_progress_tab()
        logs = self._create_logs_tab()
        self._tab_overview = overview
        self._tab_progress = progress
        self._tab_logs = logs

        # —— INFO —— Übersicht / Vorgang / Log-Dateien
        content_shell = CardWidget() if FLUENT_AVAILABLE else QFrame()
        content_shell.setObjectName("contentShell")
        content_shell.setAccessibleName("INFO")
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
        """Navigation: ein Primary-CTA (Steam/Heroic-Muster) + Mehr-Overflow."""
        bar = QFrame()
        bar.setObjectName("actionBar")
        bar.setAccessibleName("Navigation")
        row = QHBoxLayout(bar)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)

        hand = QCursor(Qt.CursorShape.PointingHandCursor)
        self._cta_mode = "none"

        # Ein Primärbutton — Text/Icon/Aktion wechseln mit Zustand
        self.primary_btn = PrimaryPushButton(t("btn.launch"))
        self.primary_btn.setObjectName("primaryBtn")
        self.primary_btn.setMinimumWidth(140)
        self.primary_btn.setCursor(hand)
        self.primary_btn.clicked.connect(self._on_primary_cta)
        # Aliase für bestehenden Code (_set_busy, retranslate, …)
        self.launch_btn = self.primary_btn
        self.install_btn = self.primary_btn
        self.repair_btn = self.primary_btn
        self.kill_btn = self.primary_btn

        self.trust_btn = PushButton(t("btn.update_rezeptor"))
        self.trust_btn.setCursor(hand)
        self.trust_btn.setVisible(False)
        self.trust_btn.clicked.connect(self._on_trust_action)

        # Fluent PushButton + RoundMenu (same family as secondary buttons; no DropDown chrome)
        if FLUENT_AVAILABLE:
            self.more_btn = PushButton(t("btn.more"))
            self._more_menu = RoundMenu(parent=self)
            self.more_btn.clicked.connect(self._popup_more_menu)
        else:
            self.more_btn = QToolButton()
            self.more_btn.setText(t("btn.more"))
            self.more_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
            self._more_menu = QMenu(self)
            self.more_btn.setMenu(self._more_menu)
        self.more_btn.setObjectName("moreBtn")
        self.more_btn.setCursor(hand)
        self.more_btn.setToolTip(t("tooltip.more"))
        self._rebuild_more_menu()

        # Versteckt: Alias falls alter Code validate_btn anspricht
        self.validate_btn = QPushButton(t("btn.validate"))
        self.validate_btn.setVisible(False)

        self.logs_btn = None

        row.addWidget(self.primary_btn)
        row.addWidget(self.trust_btn)
        row.addWidget(self.more_btn)
        row.addStretch(1)
        parent_layout.addWidget(bar)

    @staticmethod
    def _add_menu_action(menu: object, text: str, slot) -> QAction:
        """QAction for both QMenu and Fluent RoundMenu (no addAction(str, callable))."""
        action = QAction(text, menu)  # type: ignore[arg-type]
        action.triggered.connect(slot)
        menu.addAction(action)  # type: ignore[attr-defined]
        return action

    def _popup_more_menu(self) -> None:
        btn = self.more_btn
        pos = btn.mapToGlobal(btn.rect().bottomLeft())
        self._more_menu.exec(pos)

    def _rebuild_more_menu(self) -> None:
        menu = self._more_menu
        menu.clear()
        self._more_validate = self._add_menu_action(
            menu, t("menu.validate"), self.run_validate
        )
        self._more_repair = self._add_menu_action(
            menu, t("menu.repair"), self.run_repair
        )
        self._more_launch = self._add_menu_action(
            menu, t("menu.launch"), self.run_launch
        )
        self._more_kill = self._add_menu_action(menu, t("menu.kill"), self.run_kill)
        menu.addSeparator()
        self._source_configure_action = self._add_menu_action(
            menu, t("menu.source"), self.run_source_configure
        )
        self._more_open_path = self._add_menu_action(
            menu, t("menu.open_folder"), self._open_data_root
        )
        self._more_shortcuts = self._add_menu_action(
            menu, t("menu.shortcuts"), self.run_desktop_shortcuts
        )
        menu.addSeparator()
        self._more_view_recipe = self._add_menu_action(
            menu, self._view_recipe_label(), self.show_recipe_view
        )
        menu.addSeparator()
        self._more_uninstall = self._add_menu_action(
            menu, t("menu.uninstall"), self.run_uninstall
        )

    def _on_primary_cta(self) -> None:
        w = QApplication.focusWidget()
        if isinstance(w, (QLineEdit, QTextEdit, QTextBrowser)):
            return
        mode = getattr(self, "_cta_mode", "none")
        if mode == "install":
            self.run_install()
        elif mode == "launch":
            self.run_launch()
        elif mode == "repair":
            self.run_repair()
        elif mode == "kill":
            self.run_kill()

    def _can_launch_recipe(self, info: RecipeInfo, dr: Path) -> bool:
        if info.state == RecipeState.INSTALLED:
            return True
        if info.state != RecipeState.PARTIAL:
            return False
        if any(
            (dr / "prefix").joinpath(p).is_file()
            for p in (
                "drive_c/Program Files/Adobe/Adobe Photoshop 2021/Photoshop.exe",
                "drive_c/Program Files (x86)/Adobe/Adobe Photoshop 2021/Photoshop.exe",
            )
        ):
            return True
        return (dr / "prefix" / "user.reg").is_file()

    def _apply_primary_cta(
        self,
        info: RecipeInfo,
        *,
        can_launch: bool,
        running: bool,
        busy: bool,
    ) -> None:
        """Primary-CTA: Installieren | Starten | Reparieren | Beenden."""
        repair_ok = (Path(info.meta["_dir"]) / "repair.sh").is_file() and info.state in (
            RecipeState.INSTALLED,
            RecipeState.PARTIAL,
        )
        kill_ok = (Path(info.meta["_dir"]) / "kill.sh").is_file()
        untrusted = info.state == RecipeState.UNTRUSTED or not info.trust_ok

        if untrusted or busy:
            mode = "none"
        elif running and kill_ok:
            mode = "kill"
        elif info.state == RecipeState.NOT_INSTALLED:
            mode = "install"
        elif info.state == RecipeState.PARTIAL and not can_launch and repair_ok:
            mode = "repair"
        elif can_launch:
            mode = "launch"
        elif repair_ok:
            mode = "repair"
        else:
            mode = "none"

        self._cta_mode = mode
        btn = self.primary_btn
        mapping = {
            "install": ("btn.install", "tooltip.install", "install"),
            "launch": ("btn.launch", "tooltip.launch", "launch"),
            "repair": ("btn.repair", "tooltip.repair", "repair"),
            "kill": ("btn.kill", "tooltip.kill", "kill"),
        }
        if mode in mapping:
            label_k, tip_k, icon_k = mapping[mode]
            btn.setText(t(label_k))
            btn.setToolTip(t(tip_k))
            # Primary-CTA: dunkles Icon auf Kupfer/Accent (helles Icon wäre unsichtbar)
            icon = fa_icon(icon_k, 14, color="#1a1a1a" if mode != "kill" else "#7f1d1d")
            if icon is not None:
                btn.setIcon(icon)
                btn.setIconSize(QSize(14, 14))
            btn.setEnabled(True)
            btn.setVisible(True)
        else:
            btn.setEnabled(False)
            if not untrusted:
                btn.setText(t("btn.launch"))
                btn.setToolTip("")

        # Mehr-Menü: Sekundäraktionen, Primäraktion nicht verdoppeln
        if hasattr(self, "_more_validate"):
            self._more_validate.setEnabled(not busy and not untrusted)
            self._more_repair.setEnabled(repair_ok and not busy and not untrusted)
            self._more_repair.setVisible(mode != "repair")
            self._more_launch.setEnabled(can_launch and not busy and not untrusted)
            self._more_launch.setVisible(mode != "launch" and can_launch)
            self._more_kill.setEnabled(kill_ok and not busy and not untrusted)
            self._more_kill.setVisible(mode != "kill" and kill_ok)
            if hasattr(self, "_source_configure_action"):
                self._source_configure_action.setVisible(
                    needs_source_dialog(info.meta) and not untrusted
                )
                self._source_configure_action.setText(source_configure_label(info.meta))
            if hasattr(self, "_more_open_path"):
                dr = getattr(self, "_current_data_root", None)
                self._more_open_path.setEnabled(bool(dr and Path(dr).is_dir()))
            if hasattr(self, "_more_shortcuts"):
                can_shortcuts = (
                    info.state
                    in (RecipeState.INSTALLED, RecipeState.PARTIAL)
                    and not busy
                    and not untrusted
                )
                self._more_shortcuts.setVisible(can_shortcuts)
                self._more_shortcuts.setEnabled(can_shortcuts)
            if hasattr(self, "_more_view_recipe"):
                self._more_view_recipe.setEnabled(not busy)
            if hasattr(self, "_more_uninstall"):
                self._more_uninstall.setEnabled(
                    info.state
                    in (RecipeState.INSTALLED, RecipeState.PARTIAL)
                    and not busy
                    and not untrusted
                )

    def _on_sidebar_search(self, _text: str = "") -> None:
        self._populate_list()
        self._reselect_current_rid()

    def _reselect_current_rid(self) -> None:
        if self._selected is None:
            return
        rid = self._selected.rid
        for i, info in enumerate(self.recipes):
            if info.rid == rid:
                self._select_recipe_index(i)
                return

    def _install_shortcuts(self) -> None:
        sc_search = QShortcut(QKeySequence("/"), self)
        sc_search.setContext(Qt.ShortcutContext.WindowShortcut)
        sc_search.activated.connect(self._focus_sidebar_search)
        sc_enter = QShortcut(QKeySequence(Qt.Key.Key_Return), self)
        sc_enter.setContext(Qt.ShortcutContext.WindowShortcut)
        sc_enter.activated.connect(self._on_primary_cta)
        sc_enter2 = QShortcut(QKeySequence(Qt.Key.Key_Enter), self)
        sc_enter2.setContext(Qt.ShortcutContext.WindowShortcut)
        sc_enter2.activated.connect(self._on_primary_cta)
        sc_f5 = QShortcut(QKeySequence("F5"), self)
        sc_f5.activated.connect(self.refresh_statuses)
        sc_r = QShortcut(QKeySequence("R"), self)
        sc_r.setContext(Qt.ShortcutContext.WindowShortcut)
        sc_r.activated.connect(self._shortcut_validate)

    def _focus_sidebar_search(self) -> None:
        w = QApplication.focusWidget()
        if isinstance(w, (QLineEdit, QTextEdit, QTextBrowser)):
            return
        if hasattr(self, "sidebar_search"):
            self.sidebar_search.setFocus(Qt.FocusReason.ShortcutFocusReason)
            self.sidebar_search.selectAll()

    def _shortcut_validate(self) -> None:
        # Nicht auslösen, wenn Tippen in Eingabefeldern
        w = QApplication.focusWidget()
        if isinstance(w, (QLineEdit, QTextEdit, QTextBrowser)):
            return
        if self._busy or self._selected is None:
            return
        self.run_validate()

    def _remember_last_recipe(self, rid: str) -> None:
        if not rid or self._settings.last_recipe_id == rid:
            return
        self._settings.last_recipe_id = rid
        save_settings(self._settings)

    def _show_card_context_menu(self, info: RecipeInfo) -> None:
        # Auswahl setzen, dann Menü wie Mehr (ohne Duplikat-Primäraktion)
        for i, r in enumerate(self.recipes):
            if r.rid == info.rid:
                self._select_recipe_index(i)
                break
        menu = RoundMenu(parent=self) if FLUENT_AVAILABLE else QMenu(self)
        running = recipe_process_running(info.rid, info.meta)
        dr = resolve_data_root(info.meta, info.rid)
        can_launch = self._can_launch_recipe(info, dr)
        if running:
            self._add_menu_action(menu, t("menu.kill"), self.run_kill)
        elif info.state == RecipeState.NOT_INSTALLED:
            self._add_menu_action(menu, t("menu.install"), self.run_install)
        elif can_launch:
            self._add_menu_action(menu, t("menu.launch"), self.run_launch)
        if info.state in (RecipeState.INSTALLED, RecipeState.PARTIAL):
            self._add_menu_action(menu, t("menu.repair"), self.run_repair)
        self._add_menu_action(menu, t("menu.validate"), self.run_validate)
        menu.addSeparator()
        if needs_source_dialog(info.meta):
            self._add_menu_action(
                menu, source_configure_label(info.meta), self.run_source_configure
            )
        self._add_menu_action(menu, t("menu.open_folder"), self._open_data_root)
        self._add_menu_action(menu, self._view_recipe_label(), self.show_recipe_view)
        if info.state in (RecipeState.INSTALLED, RecipeState.PARTIAL):
            self._add_menu_action(
                menu, t("menu.shortcuts"), self.run_desktop_shortcuts
            )
            menu.addSeparator()
            self._add_menu_action(menu, t("menu.uninstall"), self.run_uninstall)
        menu.exec(self.cursor().pos())

    def _update_progress_chip(self) -> None:
        chip = getattr(self, "progress_chip", None)
        if chip is None:
            return
        if self._busy:
            chip.setText(t("app.chip_progress", pct=str(self._progress_pct)))
            chip.setVisible(True)
        else:
            chip.setVisible(False)
            chip.setText("")

    def _update_health_chip(self, info: RecipeInfo) -> None:
        chip = getattr(self, "health_chip", None)
        if chip is None:
            return
        fails = list(info.validate_fails or [])
        if info.state == RecipeState.PARTIAL and not fails and info.status_detail:
            detail = info.status_detail.strip()
            if detail.startswith("FAIL:"):
                detail = detail[5:].strip()
            if detail:
                fails = [detail]
        if fails and info.state == RecipeState.PARTIAL:
            chip.setText(t("app.health_hints", n=str(len(fails))))
            chip.setVisible(True)
            chip.setToolTip("\n".join(fails[:8]))
        else:
            chip.setVisible(False)
            chip.setText("")

    def _show_health_dialog(self) -> None:
        if self._selected is None:
            return
        info = self._selected
        fails = list(info.validate_fails or [])
        if not fails and info.status_detail:
            d = info.status_detail.strip()
            if d.startswith("FAIL:"):
                d = d[5:].strip()
            if d:
                fails = [d]
        body = "\n".join(f"• {f}" for f in fails) if fails else t("app.health_empty")
        box = QMessageBox(self)
        box.setWindowTitle(t("app.health_title"))
        box.setIcon(QMessageBox.Icon.Warning)
        box.setText(body)
        repair = box.addButton(t("app.health_repair"), QMessageBox.ButtonRole.AcceptRole)
        box.addButton("OK", QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if box.clickedButton() is repair and not self._busy:
            self.run_repair()

    def _update_workspace_chips(self, info: RecipeInfo, dr: Path) -> None:
        """Früher HEADER-Chips — entfernt (Jargon/Redundanz)."""
        _ = (info, dr)

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
        status_row.setSpacing(10)
        self.step_label = QLabel(t("status.no_process"))
        self.step_label.setObjectName("stepLabel")
        self.step_label.setWordWrap(True)
        self.step_label.setMinimumWidth(120)
        status_row.addWidget(self.step_label, stretch=1)

        self.progress_busy = WaitingSpinner(size=18)
        self.progress_busy.setVisible(False)
        status_row.addWidget(self.progress_busy, 0, Qt.AlignmentFlag.AlignVCenter)

        self.progress_pct_label = QLabel("")
        self.progress_pct_label.setObjectName("progressPct")
        self.progress_pct_label.setAlignment(
            Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
        )
        self.progress_pct_label.setVisible(False)
        status_row.addWidget(self.progress_pct_label, 0, Qt.AlignmentFlag.AlignVCenter)

        self.progress = QProgressBar()
        self.progress.setObjectName("rezeptorProgress")
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setTextVisible(False)
        self.progress.setFixedWidth(180)
        self.progress.setFixedHeight(10)
        self.progress.setVisible(False)
        status_row.addWidget(self.progress, 0, Qt.AlignmentFlag.AlignVCenter)
        lay.addLayout(status_row)

        act_label = QLabel(t("progress.steps"))
        act_label.setObjectName("muted")
        self._progress_steps_label = act_label
        lay.addWidget(act_label)
        self.activity_list = QListWidget()
        self.activity_list.setObjectName("activityList")
        self.activity_list.setFrameShape(QFrame.Shape.StyledPanel)
        self.activity_list.setIconSize(QSize(16, 16))
        self.activity_list.setSpacing(2)
        self.activity_list.setWordWrap(True)
        self.activity_list.setTextElideMode(Qt.TextElideMode.ElideNone)
        self.activity_list.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
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
        self.log_combo = LimitedComboBox(max_visible=8)
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
            apply_tool_window(
                dlg,
                icon=self.windowIcon(),
                modal=True,
            )
            if dlg.exec() == QDialog.DialogCode.Accepted:
                self.recipes = discover_recipes()
                self._populate_list()
                self.refresh_statuses()
            return
        RecipeWizardBlockedDialog(self).exec()

    def show_developer_docs(self) -> None:
        if self._docs_dlg is not None and self._docs_dlg.isVisible():
            self._docs_dlg.raise_()
            self._docs_dlg.activateWindow()
            return
        dlg = DeveloperDocsDialog(self)
        apply_tool_window(dlg, icon=self.windowIcon(), modal=False)
        restore_geometry(dlg, self._settings.docs_geometry)
        dlg.finished.connect(self._on_docs_closed)
        self._docs_dlg = dlg
        dlg.show()
        dlg.raise_()
        dlg.activateWindow()

    def _on_docs_closed(self, _result: int = 0) -> None:
        dlg = self._docs_dlg
        if dlg is not None:
            self._settings.docs_geometry = geometry_to_b64(dlg)
            save_settings(self._settings)
        self._docs_dlg = None

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
            dr = resolve_data_root(
                self._selected.meta,
                self._selected.rid,
            )
            env["DATA_ROOT"] = str(dr)
            env["WINEPREFIX"] = f"{dr}/prefix"
            env["WINE_PREFIX"] = f"{dr}/prefix"
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

        needle = ""
        if hasattr(self, "sidebar_search"):
            needle = (self.sidebar_search.text() or "").strip().lower()

        matched: list[tuple[int, RecipeInfo]] = []
        for i, info in enumerate(self.recipes):
            name = (info.meta.get("name") or info.rid).lower()
            if needle and needle not in name and needle not in info.rid.lower():
                continue
            matched.append((i, info))

        grouped: dict[str, list[tuple[int, RecipeInfo]]] = {}
        for i, info in matched:
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
                card.apply_theme(getattr(self, "_theme", "dark"))
                card.clicked.connect(lambda idx=i: self._select_recipe_index(idx))
                card.contextMenuRequested.connect(
                    lambda info=info: self._show_card_context_menu(info)
                )
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
                try:
                    (
                        info.state,
                        info.status_detail,
                        info.version_detected,
                        info.version_warning,
                        info.validate_fails,
                    ) = query_recipe_state(rid, meta, env)
                except Exception as exc:  # noqa: BLE001 — ein Rezept darf GUI nicht killen
                    info.state = RecipeState.PARTIAL
                    info.status_detail = f"Status-Fehler: {exc}"
                    info.version_detected = ""
                    info.version_warning = str(exc)
                    info.validate_fails = [str(exc)]
            refreshed.append(info)
        self.recipes = refreshed
        prev = self._selected_index
        self._populate_list()
        if self.recipes:
            self._select_recipe_index(prev if 0 <= prev < len(self.recipes) else 0)

    def _on_select(self, row: int) -> None:
        if row < 0 or row >= len(self.recipes):
            self._selected = None
            self.path_label.setText("")
            self._current_data_root = None
            self.open_path_btn.setEnabled(False)
            self.open_path_btn.setToolTip(t("tooltip.open_data_root"))
            return
        self._selected = self.recipes[row]
        info = self._selected
        meta = info.meta
        dr = resolve_data_root(meta, info.rid)

        icon = recipe_icon(meta)
        self.setWindowIcon(icon)
        pix = icon.pixmap(72, 72)
        if not pix.isNull():
            self.icon_label.setPixmap(pix)
        self.name_label.setText(meta.get("name", info.rid))
        self._update_status_pills(info)
        self._update_version_header(info)
        self._set_path_row(dr)
        self._update_workspace_chips(info, dr)
        self._update_health_chip(info)
        self._update_progress_chip()
        self._remember_last_recipe(info.rid)

        untrusted = info.state == RecipeState.UNTRUSTED or not info.trust_ok
        if untrusted:
            raw = info.trust_reason or info.status_detail or "?"
            reason_key = f"trust.reason_{friendly_trust_reason(raw)}"
            reason = t(reason_key)
            if reason == reason_key:
                reason = t("trust.reason_changed")
            detail = t("trust.detail", reason=reason)
            if (ROOT / ".git").is_dir():
                detail = f"{detail}\n{t('trust.hint_dev')}"
                self.trust_btn.setText(t("btn.regen_manifest"))
            else:
                detail = f"{detail}\n{t('trust.hint_user')}"
                self.trust_btn.setText(t("btn.update_rezeptor"))
            self.status_detail_label.setText(detail)
            self.status_detail_label.setVisible(True)
            self._status_detail_base = detail
            self._info_raw = recipe_info_text(info.rid, Path(meta["_dir"]))
            self._render_info_markdown()
            self.trust_btn.setVisible(True)
            self._apply_primary_cta(
                info, can_launch=False, running=False, busy=self._busy
            )
            self._refresh_running_indicators()
            return

        self.trust_btn.setVisible(False)
        if self._busy:
            detail = t("status.busy")
        else:
            detail = self._action_hint_for(info)
            # Validate-Detail bei PARTIAL: konkrete Ursache (ohne FAIL:-Prefix)
            raw = info.status_detail.strip()
            if (
                info.state == RecipeState.PARTIAL
                and raw
                and raw not in (t("state.not_installed"),)
            ):
                if raw.startswith("FAIL:"):
                    raw = raw[5:].strip()
                detail = raw
        self._status_detail_base = detail if detail else " "
        self.status_detail_label.setText(self._status_detail_base)
        self.status_detail_label.setVisible(bool(self._status_detail_base.strip()))
        self._info_raw = recipe_info_text(info.rid, Path(meta["_dir"]))
        self._render_info_markdown()

        can_launch = self._can_launch_recipe(info, dr)
        running = recipe_process_running(info.rid, info.meta)
        self._apply_primary_cta(
            info, can_launch=can_launch, running=running, busy=self._busy
        )
        if info.state == RecipeState.PARTIAL and can_launch:
            detail = info.status_detail.strip() or t("state.installed_with_warnings")
            if detail.startswith("FAIL:"):
                detail = detail[5:].strip()
            if "GPU-Experiment" in detail or "OpenGL an" in detail:
                self.status_detail_label.setText(t("status.gpu_experiment"))
                self.status_detail_label.setVisible(True)
                self._status_detail_base = t("status.gpu_experiment")
            elif detail:
                self.status_detail_label.setText(detail)
                self.status_detail_label.setVisible(True)
                self._status_detail_base = detail
        self._refresh_running_indicators()

    def _refresh_running_indicators(self) -> None:
        for card, info in self._recipe_cards:
            running = recipe_process_running(info.rid, info.meta)
            card.set_running(running)
            card.set_install_state(info.state.value)
            if not (self._selected and self._selected.rid == info.rid):
                continue
            self._update_status_pills(info)
            base = getattr(self, "_status_detail_base", "") or ""
            if not base.strip() or base.strip() == " ":
                base = self._action_hint_for(info) or " "
            self.status_detail_label.setText(base if base.strip() else " ")
            self.status_detail_label.setVisible(bool(base.strip()))
            if not self._busy:
                dr = resolve_data_root(info.meta, info.rid)
                self._apply_primary_cta(
                    info,
                    can_launch=self._can_launch_recipe(info, dr),
                    running=running,
                    busy=False,
                )

    def _update_status_pills(self, info: RecipeInfo) -> None:
        meta = info.meta
        guaranteed = meta.get("version_guaranteed", "")
        running = recipe_process_running(info.rid, info.meta)

        # Status-Badge: Zustand klar — CTA allein reicht nicht (Installieren vs. Zuletzt)
        if running:
            self.status_pill.set_content(t("badge.running"), STATE_DOT["running"])
            self.status_pill.setVisible(True)
        elif info.state == RecipeState.PARTIAL:
            self.status_pill.set_content(t("badge.partial"), COLOR_EXPERIMENTAL)
            self.status_pill.setVisible(True)
        elif info.state == RecipeState.UNTRUSTED:
            self.status_pill.set_content(t("badge.untrusted"), "#d9a441")
            self.status_pill.setVisible(True)
        elif info.state == RecipeState.INSTALLED:
            self.status_pill.set_content(t("badge.installed"), COLOR_TESTED)
            self.status_pill.setVisible(True)
        elif info.state == RecipeState.NOT_INSTALLED:
            self.status_pill.set_content(t("badge.not_installed"), MUTED)
            self.status_pill.setVisible(True)
        else:
            self.status_pill.setVisible(False)

        if guaranteed and not info.version_warning:
            show_ver = info.version_detected or guaranteed
            self.version_pill.set_content(show_ver, COLOR_TESTED)
            self.version_pill.setToolTip(
                t("tooltip.version_installed", version=show_ver)
                if info.version_detected
                else t("tooltip.version_info")
            )
            self.tested_pill.set_content(t("badge.tested"), COLOR_TESTED)
        elif info.version_warning:
            show_ver = info.version_detected or guaranteed
            if show_ver:
                self.version_pill.set_content(show_ver, "#d9a441")
                self.version_pill.setToolTip(info.version_warning)
            else:
                self.version_pill.set_content("", COLOR_TESTED)
            self.tested_pill.set_content(info.version_warning[:72], "#d9a441")
        elif guaranteed:
            self.version_pill.set_content(guaranteed, MUTED)
            self.version_pill.setToolTip(t("tooltip.version_info"))
            self.tested_pill.set_content(t("badge.tested"), COLOR_TESTED)
        else:
            self.version_pill.set_content("", COLOR_TESTED)
            self.tested_pill.set_content("", COLOR_TESTED)

        tag = (meta.get("runtime") or "proton-ge").strip().lower()
        steam_id = (meta.get("steam_appid") or "").strip()
        if tag == "system" and steam_id:
            self.proton_pill.set_content(t("badge.runtime_steam"), COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_steam"))
        elif tag == "system":
            self.proton_pill.set_content(t("badge.runtime_system"), COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_system"))
        elif steam_id:
            self.proton_pill.set_content(t("badge.runtime_proton"), COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_proton_steam"))
        else:
            self.proton_pill.set_content(t("badge.runtime_proton"), COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_proton"))
        self.proton_pill.setCursor(Qt.CursorShape.WhatsThisCursor)

        author = (meta.get("author") or "").strip()
        if author:
            self.author_pill.set_content(
                t("badge.author", author=author), MUTED
            )
        else:
            self.author_pill.set_content("", MUTED)

    def _set_path_row(self, dr: Path) -> None:
        """HEADER-Pfad + Öffnen-Icon: nur aktiv, wenn Ordner wirklich da ist."""
        self._current_data_root = dr
        self.path_label.setText(str(dr))
        exists = dr.is_dir()
        self.open_path_btn.setEnabled(exists)
        self.open_path_btn.setToolTip(
            t("tooltip.open_data_root")
            if exists
            else t("tooltip.open_data_root_missing")
        )

    def _action_hint_for(self, info: RecipeInfo) -> str:
        """Kurzer Hinweis — ergänzt Badge + CTA, ohne zu wiederholen."""
        if self._busy:
            return t("status.busy")
        if info.state == RecipeState.PARTIAL:
            return t("status.hint_partial")
        if info.state == RecipeState.NOT_INSTALLED:
            return t("status.hint_not_installed")
        if info.state == RecipeState.INSTALLED and info.rid == "wiso-steuer":
            return t("status.hint_wiso")
        return ""

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

    def _open_data_root(self) -> None:
        dr = getattr(self, "_current_data_root", None)
        if dr is None:
            path = (self.path_label.text() or "").strip()
            if not path:
                return
            dr = Path(path)
        if not dr.is_dir():
            self.open_path_btn.setEnabled(False)
            self.open_path_btn.setToolTip(t("tooltip.open_data_root_missing"))
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(dr.resolve())))

    def _render_info_markdown(self) -> None:
        raw = getattr(self, "_info_raw", "") or self.info_browser.toPlainText()
        author = ""
        if self._selected is not None:
            author = (self._selected.meta.get("author") or "").strip()
        theme = getattr(self, "_theme", "dark")
        self.info_browser.setHtml(
            format_recipe_info_html(raw, theme=theme, author=author)
        )

    def _set_step_text(self, text: str, *, style: str | None = None) -> None:
        full = (text or "").strip()
        self.step_label.setText(full)
        self.step_label.setToolTip(full)
        if style is not None:
            self.step_label.setStyleSheet(style)

    def _apply_progress_ui(self, pct: int) -> None:
        """Bar/Label/Chip auf pct setzen (ohne Anchor/Zeitstempel zu ändern)."""
        self.progress.setVisible(True)
        if hasattr(self, "progress_pct_label"):
            self.progress_pct_label.setVisible(True)
            self.progress_pct_label.setText(f"{pct}%")
        if self._busy and hasattr(self, "progress_busy"):
            self.progress_busy.start()
        self.progress.setRange(0, 100)
        self.progress.setValue(pct)
        self._update_progress_chip()
        if pct >= 100 and hasattr(self, "progress_busy"):
            self.progress_busy.stop()

    def _note_progress(self, pct: int) -> None:
        pct = min(100, max(0, int(pct)))
        self._progress_got_tick = True
        # Monoton: nie rückwärts (Adobe-/Validate-Ticks)
        if pct < self._progress_pct and self._progress_pct < 100 and pct < 90:
            pct = self._progress_pct
        if pct == self._progress_pct and self.progress.isVisible():
            self._progress_anchor = pct
            self._progress_changed_at = time.monotonic()
            return
        self._progress_pct = pct
        self._progress_anchor = pct
        self._progress_changed_at = time.monotonic()
        self._apply_progress_ui(pct)

    def _on_progress_stall_tick(self) -> None:
        """Spinner + leichte %-Interpolation zwischen echten @progress-Ticks (Cap 99)."""
        if not self._busy:
            self._progress_stall_timer.stop()
            if hasattr(self, "progress_busy"):
                self.progress_busy.stop()
            return
        if hasattr(self, "progress_busy") and self._progress_pct < 100:
            self.progress_busy.start()

        # Kein Fake-Creep vor dem ersten echten @progress (sonst „startet bei 12–30%“).
        if not getattr(self, "_progress_got_tick", False):
            return

        elapsed = time.monotonic() - self._progress_changed_at
        # Nach kurzer Pause langsam kriechen — nie über 99, nie mehr als +12 vom Anchor
        if (
            self._progress_anchor < 100
            and self._progress_pct < 99
            and elapsed >= 0.7
        ):
            creep = int((elapsed - 0.7) / 1.1)
            ceiling = min(99, self._progress_anchor + 12)
            target = min(ceiling, self._progress_anchor + creep)
            if target > self._progress_pct:
                self._progress_pct = target
                self._apply_progress_ui(target)
                self._set_step_text(
                    t("status.progress_pct", pct=str(self._progress_pct)),
                )

        stalled = elapsed >= 2.5
        if stalled and self._progress_pct < 100:
            cur = self.step_label.text()
            if "…" not in cur and "%" in cur:
                self._set_step_text(f"{cur} …")

    def _feed_line(self, raw: str) -> None:
        for part in raw.splitlines():
            line = strip_ansi(part)
            if not line or SPINNER_RE.match(line):
                continue

            # Strukturierte GUI-Tags → nur „Schritte“ (kein Duplikat in Live-Ausgabe)
            m = GUI_TAG_RE.match(line)
            if m:
                tag, msg = m.group(1), m.group(2).strip()
                if tag == "progress":
                    try:
                        pct = int(msg)
                    except ValueError:
                        continue
                    self._note_progress(pct)
                    self._set_step_text(
                        t("status.progress_pct", pct=str(self._progress_pct)),
                    )
                    continue
                if tag == "warn":
                    msg = msg.replace("AKTION:", "").strip()
                    self._set_step_text(msg)
                elif tag == "step":
                    self._set_step_text(msg)
                self._activity(tag, msg)
                continue

            human = humanize_log_line(line)
            if human is None:
                continue

            # Adobe/Wine „Progress: N%“ (oft \r) NICHT als Gesamtfortschritt —
            # sonst springt die Bar wild und flackert gegen @progress:-Tags.
            if PROGRESS_RE.search(line):
                if human and not human.startswith("Progress:"):
                    self._raw_log_buffer.append(human)
                    self.raw_log.append(human)
                continue

            if line.startswith("═══") or line.startswith("RECIPE_"):
                continue
            if "AKTION:" in line or line.startswith("USER:"):
                msg = line.replace("AKTION:", "").replace("USER:", "").strip()
                self._activity("warn", msg)
                self._set_step_text(msg)
                continue

            # Konsolen-/Rohzeilen → nur Live-Ausgabe (kein zweites Mal in Schritte)
            self._raw_log_buffer.append(human)
            self.raw_log.append(human)

    def _activity(self, kind: str, text: str) -> None:
        text = (text or "").strip()
        if not text:
            return
        key = (kind, text)
        # output::progress emits @step; callers sometimes also call output::step
        if kind == "step" and self._last_activity_key == key:
            return
        if kind in ("step", "ok", "warn", "error"):
            self._last_activity_key = key
        item = QListWidgetItem(text)
        item.setToolTip(text)
        icon = fa_icon(kind)
        if icon is not None:
            item.setIcon(icon)
        else:
            prefix = {
                "step": "→",
                "ok": "✓",
                "warn": "⚠",
                "error": "✗",
                "info": "ℹ",
                "log": "·",
            }.get(kind, "·")
            item.setText(f"{prefix} {text}")
        item.setForeground(QColor(fa_color(kind)))
        self.activity_list.addItem(item)
        self.activity_list.scrollToBottom()
        if kind in ("step", "ok", "warn", "error"):
            style = {
                "ok": "color: #50fa7b; font-weight: 600;",
                "error": "color: #ff5555; font-weight: 600;",
                "warn": "color: #ffb86c; font-weight: 600;",
            }.get(kind)
            self._set_step_text(text, style=style)

    def _set_busy(self, busy: bool) -> None:
        self._busy = busy
        if busy:
            self.progress.setVisible(True)
            if hasattr(self, "progress_pct_label"):
                self.progress_pct_label.setVisible(True)
            self._progress_changed_at = time.monotonic()
            if hasattr(self, "progress_busy"):
                self.progress_busy.start()
            if not self._progress_stall_timer.isActive():
                self._progress_stall_timer.start()
            self.status_detail_label.setText(t("status.busy"))
            self.status_detail_label.setVisible(True)
            self._update_progress_chip()
            for b in (
                self.primary_btn,
                self.more_btn,
            ):
                b.setEnabled(False)
            self.action_refresh.setEnabled(False)
            return
        self._progress_stall_timer.stop()
        if hasattr(self, "progress_busy"):
            self.progress_busy.stop()
        self.progress.setRange(0, 100)
        self.progress.setValue(100)
        if hasattr(self, "progress_pct_label"):
            self.progress_pct_label.setText("100%")
            self.progress_pct_label.setVisible(True)
        self._update_progress_chip()
        self._set_step_text(t("status.done"))
        self.action_refresh.setEnabled(True)
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
        if getattr(self, "_suppress_tab_persist", False):
            return
        if key in pages and self._settings.content_tab != key:
            self._settings.content_tab = key
            save_settings(self._settings)

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
        on_success: Callable[[], None] | None = None,
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
        self._last_activity_key = None
        self._progress_pct = 0
        self._progress_anchor = 0
        self._progress_pulse = 0
        self._progress_got_tick = False
        self._progress_changed_at = time.monotonic()
        self.progress.setValue(0)
        self.progress.setRange(0, 100)
        self.progress_pct_label.setText("0%")
        self.progress_pct_label.setVisible(True)
        self.progress_busy.start()
        self.progress.setVisible(True)
        self._switch_to_progress_tab()
        self._set_step_text(t("status.op_starting"))
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
            elif code == 0 and on_success is not None:
                on_success()
            elif code == 0 and dialog:
                QMessageBox.information(
                    self,
                    t("status.done"),
                    t("status.done_body", label=done_label),
                )

        proc.finished.connect(done)
        proc.start()

    def _desktop_cli(self) -> Path:
        return ROOT / "scripts" / "recipe-desktop.sh"

    def _install_desktop_shortcuts(self, recipe_dir: Path) -> bool:
        cli = self._desktop_cli()
        if not cli.is_file():
            return False
        env = {**os.environ, **self._base_env()}
        try:
            result = subprocess.run(
                ["bash", str(cli), "install", str(recipe_dir)],
                cwd=str(ROOT),
                env=env,
                capture_output=True,
                text=True,
                timeout=90,
                check=False,
            )
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def _offer_desktop_shortcuts(self, done_label: str) -> None:
        QMessageBox.information(
            self,
            t("status.done"),
            t("status.done_body", label=done_label),
        )
        if not self._selected:
            return
        name = self._selected.meta.get("name", self._selected.rid)
        if (
            QMessageBox.question(
                self,
                t("dialog.shortcuts_title"),
                t("dialog.shortcuts_body", name=name),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.Yes,
            )
            != QMessageBox.StandardButton.Yes
        ):
            self._activity("info", t("dialog.shortcuts_later"))
            return
        recipe_dir = Path(self._selected.meta["_dir"])
        if self._install_desktop_shortcuts(recipe_dir):
            self._activity("ok", t("dialog.shortcuts_ok"))
            QMessageBox.information(
                self,
                t("dialog.shortcuts_title"),
                t("dialog.shortcuts_created"),
            )
        else:
            QMessageBox.warning(
                self,
                t("dialog.shortcuts_title"),
                t("dialog.shortcuts_failed"),
            )

    def run_desktop_shortcuts(self) -> None:
        recipe_dir = self._require_recipe()
        if recipe_dir is None or not self._selected:
            return
        if self._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.information(
                self, t("dialog.not_installed_title"), t("dialog.install_first")
            )
            return
        name = self._selected.meta.get("name", self._selected.rid)
        if (
            QMessageBox.question(
                self,
                t("dialog.shortcuts_title"),
                t("dialog.shortcuts_body", name=name),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.Yes,
            )
            != QMessageBox.StandardButton.Yes
        ):
            return
        if self._install_desktop_shortcuts(recipe_dir):
            self._activity("ok", t("dialog.shortcuts_ok"))
            QMessageBox.information(
                self,
                t("dialog.shortcuts_title"),
                t("dialog.shortcuts_created"),
            )
        else:
            QMessageBox.warning(
                self,
                t("dialog.shortcuts_title"),
                t("dialog.shortcuts_failed"),
            )

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
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True)
        restore_geometry(dlg, self._settings.settings_geometry)
        accepted = dlg.exec() == QDialog.DialogCode.Accepted
        geo = geometry_to_b64(dlg)
        if accepted:
            prev_edit = recipe_edit_allowed(self._settings)
            self._settings = dlg.result_settings()
            self._settings.settings_geometry = geo
            save_settings(self._settings)
            set_locale(self._settings.locale)
            self._apply_theme()
            self.retranslate_ui()
            self._activity(
                "info",
                t(
                    "settings.saved",
                    days=self._settings.log_retention_days,
                    files=self._settings.log_max_files,
                ),
            )
            if recipe_edit_allowed(self._settings) and not prev_edit:
                self._activity("info", t("settings.developer_mode_ready"))
        else:
            self._settings.settings_geometry = geo
            save_settings(self._settings)

    def show_recipe_view(self) -> None:
        if self._selected is None:
            return
        if self._recipe_view_dlg is not None and self._recipe_view_dlg.isVisible():
            self._recipe_view_dlg.raise_()
            self._recipe_view_dlg.activateWindow()
            return
        info = self._selected
        recipe_dir = Path(info.meta["_dir"])
        editable = recipe_edit_allowed(self._settings)
        icon = recipe_icon(info.meta)
        dlg = RecipeViewDialog(
            self,
            recipe_dir=recipe_dir,
            project_root=ROOT,
            editable=editable,
            icon=icon,
        )
        apply_tool_window(dlg, icon=icon if not icon.isNull() else self.windowIcon())
        restore_geometry(dlg, self._settings.recipe_view_geometry)
        if editable:
            dlg.focus_source_tab()
        dlg.finished.connect(self._on_recipe_view_closed)
        self._recipe_view_dlg = dlg
        dlg.show()
        dlg.raise_()
        dlg.activateWindow()

    def _on_recipe_view_closed(self, _result: int = 0) -> None:
        dlg = self._recipe_view_dlg
        if dlg is not None:
            self._settings.recipe_view_geometry = geometry_to_b64(dlg)
            save_settings(self._settings)
        self._recipe_view_dlg = None
        self.refresh_statuses()

    def _persist_ui_layout(self) -> None:
        self._settings.window_maximized = self.isMaximized()
        if not self.isMaximized():
            self._settings.window_geometry = geometry_to_b64(self)
        save_settings(self._settings)

    def _restore_ui_layout(self) -> None:
        s = self._settings
        restored = restore_geometry(self, s.window_geometry)
        if not restored:
            self.resize(1080, 680)
        if s.window_maximized:
            self.showMaximized()
        self._suppress_tab_persist = True
        try:
            self._set_content_tab(s.content_tab or "overview")
        finally:
            self._suppress_tab_persist = False

    def showEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        super().showEvent(event)
        if not self._ui_restored:
            self._ui_restored = True
            # Nach erstem Show — sonst speichert der WM falsche Größen
            QTimer.singleShot(0, self._restore_ui_layout)

    def closeEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        self._persist_ui_layout()
        for dlg in (self._recipe_view_dlg, self._docs_dlg):
            if dlg is not None:
                dlg.close()
        super().closeEvent(event)

    @staticmethod
    def _style_secondary_label(
        label: QLabel, color: str, *, size_px: int = 12
    ) -> None:
        """Sekundärtext: QSS + Palette — sonst System-Light → dunkle Schrift auf Dark."""
        label.setStyleSheet(
            f"color: {color}; font-size: {size_px}px; background: transparent;"
        )
        pal = label.palette()
        qc = QColor(color)
        for group in (
            QPalette.ColorGroup.Active,
            QPalette.ColorGroup.Inactive,
            QPalette.ColorGroup.Disabled,
        ):
            pal.setColor(group, QPalette.ColorRole.WindowText, qc)
            pal.setColor(group, QPalette.ColorRole.Text, qc)
        label.setPalette(pal)

    def _apply_theme(self) -> None:
        # Fluent Dark + Brand — System-Theme irrelevant
        host = apply_rezeptor_theme()
        self._theme = "dark"
        app = QApplication.instance()
        if app is not None:
            app.setStyleSheet((host or "") + SEGMENT_TAB_STYLES)
        if hasattr(self, "segment_tabs"):
            self.segment_tabs.setStyleSheet(SEGMENT_TAB_STYLES)
        if hasattr(self, "name_label"):
            self.name_label.setStyleSheet(
                f"font-size: 20px; font-weight: 600; color: {COLOR_PARCHMENT}; "
                "background: transparent;"
            )
        if hasattr(self, "path_label"):
            self._style_secondary_label(self.path_label, MUTED, size_px=11)
        if hasattr(self, "status_detail_label"):
            self._style_secondary_label(self.status_detail_label, MUTED, size_px=12)
        for pill in (
            getattr(self, "status_pill", None),
            getattr(self, "version_pill", None),
            getattr(self, "tested_pill", None),
            getattr(self, "proton_pill", None),
            getattr(self, "author_pill", None),
        ):
            if pill is not None and hasattr(pill, "apply_theme"):
                pill.apply_theme("dark")
        self._refresh_status_footer(self._update_available or "")
        if self._selected is not None:
            self._render_info_markdown()

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
        if hasattr(self, "sidebar_search"):
            self.sidebar_search.setPlaceholderText(t("app.sidebar_search"))
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
        self.more_btn.setText(t("btn.more"))
        self.more_btn.setToolTip(t("tooltip.more"))
        if hasattr(self, "_rebuild_more_menu"):
            self._rebuild_more_menu()
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
            if QMessageBox.question(
                self,
                t("dialog.install_title"),
                t("dialog.install_reconfirm", name=name),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            ) != QMessageBox.StandardButton.Yes:
                return
        else:
            html = format_recipe_info_html(
                info,
                theme=getattr(self, "_theme", "dark"),
                author=(meta.get("author") or ""),
            )
            dlg = InfoConfirmDialog(
                self,
                title=t("dialog.install_title"),
                html=html,
                question=t("dialog.install_question"),
            )
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return

        self._maybe_wine_dialog_hint("install")
        label = (
            t("action.reinstall")
            if self._selected.state == RecipeState.INSTALLED
            else t("action.install")
        )
        self._run_async(
            install,
            extra,
            label,
            on_success=lambda: self._offer_desktop_shortcuts(label),
        )

    def run_source_configure(self) -> None:
        rd = self._require_recipe()
        if rd is None or not self._selected:
            return
        meta = self._selected.meta
        if not needs_source_dialog(meta):
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
        dr = resolve_data_root(meta, self._selected.rid)
        extra = dlg.build_env(dr)
        if not (
            extra.get("RECIPE_SOURCE_ROOT")
            or extra.get("RECIPE_ARCHIVE_PATH")
            or extra.get("RECIPE_INSTALLER_PATH")
        ):
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
        self.step_label.setStyleSheet("")
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
    app.setApplicationName("Rezeptor")
    # Leer: sonst KDE „Rezeptor — v… — Rezeptor“ im Fenstertitel
    app.setApplicationDisplayName("")
    app.setOrganizationName("Rezeptor")
    app.setDesktopFileName("rezeptor")
    ensure_fa_font()
    # Fusion für Host-Widgets (Combo/Listen) — sonst KDE-Blau statt Kupfer
    app.setStyle("Fusion")
    # Fluent Dark + Brand — egal ob System Light oder Dark
    host = apply_rezeptor_theme()
    app.setStyleSheet((host or "") + SEGMENT_TAB_STYLES)
    w = RezeptorWindow()
    w.show()
    QTimer.singleShot(0, w._apply_theme)
    QTimer.singleShot(200, w.refresh_statuses)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
