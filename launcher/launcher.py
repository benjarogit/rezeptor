#!/usr/bin/env python3
"""Rezeptor — GUI für getestete Wine-Software-Rezepte (Proton-GE)."""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from collections.abc import Callable
from pathlib import Path

try:
    from PyQt6.QtCore import (
        Qt,
        QEvent,
        QObject,
        QProcess,
        QProcessEnvironment,
        QRect,
        QRectF,
        QSize,
        QThread,
        QTimer,
        QUrl,
        pyqtSignal,
    )
    from PyQt6.QtGui import (
        QAction,
        QBrush,
        QColor,
        QCursor,
        QDesktopServices,
        QFont,
        QIcon,
        QKeySequence,
        QLinearGradient,
        QPainter,
        QPainterPath,
        QPalette,
        QPixmap,
        QShortcut,
    )
    from PyQt6.QtWidgets import (
        QApplication,
        QCheckBox,
        QDialog,
        QDialogButtonBox,
        QFrame,
        QGridLayout,
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
    build_diagnose_zip,
    cachyos_url,
    collect_report_bundle,
    community_reddit_url,
    describe_runtime_for_report,
    detect_distro,
    detect_source_version,
    detect_update_channel,
    fetch_latest_release,
    github_issue_url,
    github_repo_url,
    humanize_log_line,
    parse_validate_version_fields,
    effective_proton_ge_tag,
    format_tested_on_display,
    linuxchooser_url,
    linuxguides_url,
    proton_ge_badge_label,
    prune_old_logs,
    public_docs_url,
    read_version,
    report_clipboard_text,
    sanitize_log_text,
    update_auto_supported,
    version_compare,
)
from themes import next_theme, normalize_theme, theme_tokens
from ui_fluent import (
    ACCENT_COPPER,
    COLOR_EXPERIMENTAL,
    COLOR_TESTED,
    FLUENT_AVAILABLE,
    CardWidget,
    PrimaryPushButton,
    PushButton,
    RoundMenu,
    TitleLabel,
    apply_rezeptor_theme,
)
from ui_rezeptor import (
    REZEPTOR_ICON,
    LimitedComboBox,
    RecipeSidebarCard,
    SegmentTabBar,
    SidebarCategoryHeader,
    StatusPill,
    STATE_DOT,
    segment_tab_styles,
)
from host_deps import (
    has_gaps,
    has_required_gaps,
    missing_wow64_deps,
    recipe_needs_host_wow64,
)
from settings import (
    clear_recipe_install_env,
    has_recipe_install_source,
    load_recipe_install_env,
    load_settings,
    recipe_edit_allowed,
    save_recipe_install_env,
    save_settings,
)
from ui_host_deps import HostDepsDialog, mark_host_deps_prompt_done
from ui_settings import SettingsDialog
from ui_docs import DeveloperDocsDialog
from ui_recipe_view import RecipeViewDialog
from ui_catalog import CatalogDialog, HiddenRecipesDialog
from ui_recipe_wizard import (
    RecipeWizardBlockedDialog,
    RecipeWizardDialog,
    can_create_recipes,
)
from ui_source import (
    RecipeSourceDialog,
    needs_source_dialog,
    needs_target_dir,
    recipe_supports_update,
    source_configure_label,
)
from recipe_categories import (
    category_label,
    default_category,
    effective_category,
    sort_categories,
    sort_recipes_in_category,
)
from recipe_discovery import (
    DiscoverOutcome,
    RecipeInfo,
    RecipeState,
    discover_recipes as _discover_recipes,
    launch_process_patterns_from_meta,
    parse_recipe_yml,
    sidebar_card_texts,
    sidebar_label_for_meta,
)
from recipe_options import (
    env_overrides_for_options,
    load_options_from_recipe_dir,
    option_visible,
    read_option_values,
)
from steam_paths import steam_roots
from steam_proton_catalog import is_steam_medicine_option
from ui_steam_medicine import SteamMedicineHintDialog
from recipe_paths import (
    manifest_for_recipe_dir,
    overlay_manifest_path,
    overlay_recipes_dir,
)
from recipe_sync import (
    RecipeSyncError,
    RecipeSyncPlan,
    apply_recipe_sync,
    check_recipe_updates,
    format_plan_summary,
    pending_attention_count,
)
from recipe_process import RecipeProcessOps
from recipe_trust import (
    approve_recipe_manifest,
    friendly_trust_reason,
    generate_manifest,
    rezeptor_dev_mode,
    verify_recipe_trust,
)
from ui_styles import COLOR_PARCHMENT, MUTED, palette
from ui_icons import (
    ensure_fa_brands_font,
    ensure_fa_font,
    fa_icon,
    rounded_pixmap,
)
from ui_dialogs import apply_fa_message_icon, show_warning
from ui_medizin import MedizinDialog
from ui_progress import WaitingSpinner
from ui_window import (
    apply_tool_window,
    clamp_restored_geometry,
    dismiss_all_top_level_windows,
    ensure_on_screen,
    geometry_to_b64,
    install_application_close_guard,
    restore_geometry,
    unwind_modal_dialogs,
)
from diagnostics import (
    DIAG_LOG,
    install_exception_logging,
    install_exit_logging,
    install_signal_logging,
    log_call_site,
    log_line,
    log_session_start,
)
from i18n import get_locale, set_locale, t
from log_context import (
    E_STATUS_QUERY,
    E_UNCAUGHT,
    E_UPDATE_APPLY,
    LogEvent,
)
RECIPES_DIR = ROOT / "recipes"
MANIFEST_PATH = RECIPES_DIR / "manifest.json"
LOG_ROOT = Path.home() / ".local/share/wine-software/logs"

_VALIDATE_SUBPROCESS_TIMEOUT_SEC = 25
_ROLLBACK_UNINSTALL_TIMEOUT_SEC = 180
_DESKTOP_SHORTCUT_TIMEOUT_SEC = 90
_RAW_LOG_MAX_LINES = 2000


def _linux_child_pids(pid: int) -> list[int]:
    """Direkte Kind-PIDs aus /proc (Linux)."""
    out: list[int] = []
    task = Path(f"/proc/{pid}/task")
    try:
        for tid_dir in task.iterdir():
            children = tid_dir / "children"
            if not children.is_file():
                continue
            for tok in children.read_text(encoding="utf-8", errors="ignore").split():
                if tok.isdigit():
                    out.append(int(tok))
    except OSError:
        return []
    return out


def _descendant_pids(pid: int) -> list[int]:
    """PID plus alle Nachkommen aus /proc — enthält den Launcher nie."""
    seen: set[int] = set()
    stack = [pid]
    while stack:
        p = stack.pop()
        if p <= 0 or p in seen:
            continue
        seen.add(p)
        stack.extend(_linux_child_pids(p))
    return sorted(seen)


def own_process_group(pid: int) -> int:
    """PGID nur, wenn der Prozess selbst Gruppenführer ist (setsid) — sonst 0.

    Eine geratene PGID ist im Zweifel die der GUI; killpg darauf beendet Rezeptor
    beim Install-Abbruch mit.
    """
    try:
        pg = os.getpgid(pid)
    except OSError:
        return 0
    if pg != pid or pg == os.getpgrp():
        return 0
    return pg


def signal_subprocess_tree(pid: int, sig: int) -> None:
    """Install-/Wine-Baum beenden: eigene Prozessgruppe plus alle Nachkommen."""
    if pid <= 0:
        return
    pgid = own_process_group(pid)
    if pgid:
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    for p in _descendant_pids(pid):
        try:
            os.kill(p, sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass


def _signal_qprocess_tree(proc: QProcess, sig: int) -> None:
    pid = int(proc.processId())
    if pid > 0:
        log_line(
            "SIGNAL-TREE",
            f"pid={pid} pgid={own_process_group(pid)} own={os.getpgrp()} sig={sig}",
        )
        signal_subprocess_tree(pid, sig)
    elif sig == signal.SIGTERM:
        proc.terminate()
    else:
        proc.kill()
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m|\x08+")
SPINNER_RE = re.compile(r"^\[[\\/\-\|]\]\s*$")
GUI_TAG_RE = re.compile(r"^@(step|ok|warn|error|info|progress):(.+)$")
PROGRESS_RE = re.compile(r"Progress:\s*(\d+)%", re.I)


def discover_recipes(*, verify_trust: bool = True) -> DiscoverOutcome:
    return _discover_recipes(
        recipes_dir=RECIPES_DIR,
        manifest_path=MANIFEST_PATH,
        project_root=ROOT,
        verify_trust=verify_trust,
        overlay_recipes=overlay_recipes_dir(),
        overlay_manifest=overlay_manifest_path(),
    )


def _recipe_manifest_path(recipe_dir: Path) -> Path:
    return manifest_for_recipe_dir(
        recipe_dir,
        bundled_manifest=MANIFEST_PATH,
        overlay_manifest=overlay_manifest_path(),
    )


def _recipe_is_checking(info: RecipeInfo) -> bool:
    return info.state == RecipeState.CHECKING or (
        not info.trust_ok
        and friendly_trust_reason(info.trust_reason or info.status_detail) == "checking"
    )


def _recipe_is_untrusted(info: RecipeInfo) -> bool:
    """True when scripts must stay blocked (not during async integrity check)."""
    if _recipe_is_checking(info):
        return False
    return info.state == RecipeState.UNTRUSTED or not info.trust_ok


def _sidebar_attention(info: RecipeInfo) -> bool:
    """Warn-Icon nur bei Reparatur/Freigabe-Bedarf — nicht bei „nicht installiert“.

    validate.sh meldet bei fehlender Installation immer FAIL-Zeilen; das ist
    erwartet und kein Hinweis-Zustand. Versions-WARN hat eigene Pill/Dialog.
    """
    if _recipe_is_checking(info):
        return False
    if info.state in (RecipeState.PARTIAL, RecipeState.UNTRUSTED):
        return True
    if _recipe_is_untrusted(info):
        return True
    return False


def _debug_log(message: str) -> None:
    if rezeptor_dev_mode():
        print(f"rezeptor: {message}", file=sys.stderr)


def expand_home(path: str) -> Path:
    return Path(os.path.expanduser(path.replace("{repo}", str(ROOT))))


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text).strip()


# Fallback when recipe.yml has no launch_process_patterns (prefer YAML).
LAUNCH_PROCESS_PATTERNS: dict[str, list[str]] = {
    "photoshop": ["Photoshop.exe"],
    "photoshop-m0nkrus": ["Photoshop.exe"],
}


def launch_process_patterns(rid: str, meta: dict[str, str] | None = None) -> list[str]:
    if meta:
        from_meta = launch_process_patterns_from_meta(meta, rid)
        if from_meta:
            return from_meta
    return list(LAUNCH_PROCESS_PATTERNS.get(rid, []))

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


def _parse_env_file_values(path: Path) -> dict[str, str]:
    """recipe.env / portable.env — Werte mit Shell-Quoting (%q) lesen."""
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for line in text.splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        key, _, val = raw.partition("=")
        key = key.strip()
        val = val.strip()
        if not key:
            continue
        # printf %q: backslash-escapes; einfache Anführungszeichen möglich
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
            val = val[1:-1]
        else:
            val = (
                val.replace("\\ ", " ")
                .replace("\\'", "'")
                .replace('\\"', '"')
                .replace("\\\\", "\\")
            )
        out[key] = val
    return out


def source_target_from_env(
    env: dict[str, str], *, install_type: str = ""
) -> tuple[str, str, str]:
    """Extract (source, target, work) paths from install/pending env."""
    work = (env.get("WORK_ROOT") or "").strip()
    source = (
        (env.get("GAME_DIR") or "").strip()
        or (env.get("RECIPE_SOURCE_ROOT") or "").strip()
        or (env.get("RECIPE_INSTALLER_PATH") or "").strip()
        or (env.get("RECIPE_ARCHIVE_PATH") or "").strip()
    )
    target = (
        (env.get("WISO_PORTABLE_ROOT") or "").strip()
        or (env.get("RECIPE_TARGET_DIR") or "").strip()
        or (env.get("RECIPE_DATA_ROOT") or "").strip()
        or (env.get("DATA_ROOT") or "").strip()
        or (env.get("TRAINER_EXE") or "").strip()
    )
    # Trainer/portable: EXE copy is the deploy target — show as target, not source
    if install_type == "portable_launch":
        trainer = (env.get("TRAINER_EXE") or "").strip()
        if trainer:
            target = trainer
            source = source if source and source != trainer else ""
    return source, target, work


def format_source_target_lines(
    *,
    source: str = "",
    target: str = "",
    work: str = "",
    data_root: str = "",
    include_data: bool = False,
) -> str:
    """Labeled multiline path summary for the header path row."""
    lines: list[str] = []
    dr_s = (data_root or "").strip()
    if include_data and dr_s:
        lines.append(f"{t('tooltip.path_data')}: {dr_s}")
    # When Daten is shown, skip Ziel/Programm that only repeat data_root.
    skip_dr = {dr_s} if include_data and dr_s else set()
    if work and work not in skip_dr | {source, target}:
        lines.append(f"{t('tooltip.path_app')}: {work}")
    if source and source not in skip_dr | {work, target}:
        lines.append(f"{t('tooltip.path_source')}: {source}")
    if target and target not in skip_dr | {work, source}:
        lines.append(f"{t('tooltip.path_target')}: {target}")
    return "\n".join(lines)


def installed_paths_text(meta: dict[str, str], rid: str, dr: Path) -> str:
    """Mehrzeilig: Daten + Programm/Quelle/Ziel aus recipe.env / portable.env."""
    _ = rid
    env: dict[str, str] = {}
    env.update(_parse_env_file_values(dr / "recipe.env"))
    env.update(_parse_env_file_values(dr / "portable.env"))
    source, target, work = source_target_from_env(
        env, install_type=meta.get("install_type", "")
    )
    return format_source_target_lines(
        source=source,
        target=target,
        work=work,
        data_root=str(dr),
        include_data=True,
    )


def pending_paths_text(meta: dict[str, str], pending: dict[str, str], dr: Path) -> str:
    """Quelle/Ziel from settings.recipe_install_env (chosen, not installed yet)."""
    source, target, work = source_target_from_env(
        pending, install_type=meta.get("install_type", "")
    )
    # Explicit target from dialog, else canonical data root (prefix / recipe home).
    if not target:
        target = str(dr)
    return format_source_target_lines(
        source=source,
        target=target,
        work=work,
        data_root=str(dr),
        include_data=False,
    )


def data_root_browsable(dr: Path) -> bool:
    """True when opening the folder helps the user (not only internal pointer files)."""
    if not dr.is_dir():
        return False
    if (dr / "prefix").is_dir():
        return True
    ignore = {"data_root.path"}
    try:
        for entry in dr.iterdir():
            if entry.name in ignore:
                continue
            return True
    except OSError:
        return False
    return False


def app_link_in_data_root(meta: dict[str, str], dr: Path) -> tuple[str, Path] | None:
    """Return (link_name, resolved_target) if DATA_ROOT has a working app/game symlink."""
    if not dr.is_dir():
        return None
    rid = (meta.get("id") or "").strip()
    names: list[str] = []
    custom = (meta.get("app_link_name") or "").strip()
    if custom:
        names.append(custom)
    if rid and rid not in names:
        names.append(rid)
    for name in names:
        link = dr / name
        if not link.is_symlink():
            continue
        try:
            target = link.resolve(strict=True)
        except OSError:
            continue
        if target.is_dir():
            return name, target
    return None


def open_data_root_tooltip(meta: dict[str, str] | None, dr: Path | None) -> str:
    """Tooltip for the install-data folder button (mentions app link when present)."""
    base = t("tooltip.open_data_root")
    if meta is None or dr is None:
        return base
    hit = app_link_in_data_root(meta, dr)
    if hit is None:
        return base
    name, _target = hit
    return t("tooltip.open_data_root_with_link", name=name)


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


def _proc_argv0(pid: str) -> str:
    """Erstes Cmdline-Argument (Null-getrennt) — Pfade mit Leerzeichen bleiben intakt."""
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except (OSError, ProcessLookupError):
        return ""
    if not raw:
        return ""
    return raw.split(b"\0", 1)[0].decode("utf-8", "replace")


def _exe_basename(path_or_name: str) -> str:
    s = (path_or_name or "").replace("\\", "/").rstrip("/")
    return s.rsplit("/", 1)[-1].lower() if s else ""


def _pattern_matches_main_exe(cmd: str, pid: str, patterns_l: list[str]) -> bool:
    """True nur wenn argv0/comm die App-EXE ist — nicht wenn sie nur als Argument vorkommt.

    AdobeIPCBroker: ``…\\AdobeIPCBroker.exe …\\Photoshop.exe`` darf nicht als Photoshop gelten.
    """
    del cmd  # cmdline-String mit Spaces zerstört argv0; /proc null-sep nutzen
    argv0 = _exe_basename(_proc_argv0(pid))
    argv0_stem = argv0[:-4] if argv0.endswith(".exe") else argv0
    comm = _proc_comm(pid).lower().rstrip(".\x00 ")
    comm_stem = comm[:-4] if comm.endswith(".exe") else comm

    for pat in patterns_l:
        stem = pat[:-4] if pat.endswith(".exe") else pat
        if argv0_stem == stem or argv0 == pat:
            return True
        # argv0 ist eine andere EXE → dieses Pattern verwerfen
        if argv0_stem:
            continue
        # Fallback: nur comm (Wine), wenn argv0 leer
        if comm_stem == stem or (
            len(comm_stem) >= 8 and stem.startswith(comm_stem)
        ):
            return True
    return False


def recipe_process_running(rid: str, meta: dict[str, str] | None = None) -> bool:
    """True nur bei echtem App-Prozess (Wine/Proton), nicht bei Shell-/Agent-Cmdlines."""
    patterns = launch_process_patterns(rid, meta)
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
            except Exception as exc:  # noqa: BLE001
                _debug_log(f"steam path lookup for appid {appid}: {exc}")

    patterns_l = [p.lower() for p in patterns]
    for ent in Path("/proc").iterdir():
        if not ent.name.isdigit():
            continue
        cmd = _proc_cmdline(ent.name)
        if not cmd or _is_noise_process(cmd):
            continue
        if not _pattern_matches_main_exe(cmd, ent.name, patterns_l):
            continue
        if not _looks_like_wine_or_proton(ent.name, cmd):
            continue

        cmd_l = cmd.lower()
        if steam_mode:
            if any(h and h in cmd_l for h in path_hints):
                return True
            # Proton-run ohne Prefix in environ — Haupt-EXE reicht
            return True

        if prefix is not None and _proc_has_wineprefix(ent.name, prefix):
            return True
        if any(h and h in cmd_l for h in path_hints):
            return True
    return False


# Matches QFrame#headerCard border-radius in ui_styles.host_stylesheet.
_HEADER_CARD_RADIUS = 8


def faded_header_watermark(
    src: QPixmap,
    target: QSize,
    *,
    radius: int = _HEADER_CARD_RADIUS,
) -> QPixmap:
    """Header backdrop: icon on the right, L→R fade, clipped to card radius.

    Watermark fills the full header rect so top/bottom-right corners follow the
    same 8px radius as headerCard (no square bleed past rounded chrome).
    """
    tw = max(48, target.width())
    th = max(40, target.height())
    out = QPixmap(tw, th)
    out.fill(Qt.GlobalColor.transparent)
    if src.isNull():
        return out

    # Draw icon in the right ~44% band, flush to the right edge.
    band_w = max(140, int(tw * 0.44))
    scaled = src.scaled(
        band_w,
        th,
        Qt.AspectRatioMode.KeepAspectRatioByExpanding,
        Qt.TransformationMode.SmoothTransformation,
    )
    x = tw - scaled.width()
    y = (th - scaled.height()) // 2

    painter = QPainter(out)
    painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.drawPixmap(x, y, scaled)

    # Soft L→R alpha (transparent left → soft right).
    fade = QPixmap(tw, th)
    fade.fill(Qt.GlobalColor.transparent)
    fp = QPainter(fade)
    grad = QLinearGradient(tw - band_w, 0, tw, 0)
    grad.setColorAt(0.0, QColor(255, 255, 255, 0))
    grad.setColorAt(0.22, QColor(255, 255, 255, 18))
    grad.setColorAt(0.55, QColor(255, 255, 255, 95))
    grad.setColorAt(1.0, QColor(255, 255, 255, 155))
    fp.fillRect(0, 0, tw, th, QBrush(grad))
    fp.end()
    painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_DestinationIn)
    painter.drawPixmap(0, 0, fade)

    # Clip to header rounded rect so corners match the card.
    r = max(0, min(radius, tw // 2, th // 2))
    if r > 0:
        clip = QPixmap(tw, th)
        clip.fill(Qt.GlobalColor.transparent)
        cp = QPainter(clip)
        cp.setRenderHint(QPainter.RenderHint.Antialiasing)
        cp.setPen(Qt.PenStyle.NoPen)
        cp.setBrush(QColor(255, 255, 255, 255))
        path = QPainterPath()
        path.addRoundedRect(QRectF(0, 0, tw, th), float(r), float(r))
        cp.drawPath(path)
        cp.end()
        painter.drawPixmap(0, 0, clip)

    painter.end()
    return out


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
    """Load recipe overview text (info.<locale>.txt|.md, then en/de fallbacks)."""
    locale = get_locale()
    # Locale first, then en, then de — .txt and .md both allowed (Halo uses .md).
    stems = [
        f"info.{locale}",
        "info.en",
        "info.de",
        "info",
        f"{rid}.info.de",
    ]
    candidates: list[str] = []
    for stem in stems:
        candidates.append(f"{stem}.txt")
        candidates.append(f"{stem}.md")
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
    """Install confirmation: scrollable recipe info, sticky Install/Cancel footer."""

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
        # Tall enough for sticky footer + recipe info (browser min 360).
        self.setMinimumSize(480, 520)
        self.resize(560, 560)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 12, 12, 12)
        lay.setSpacing(0)

        browser = QTextBrowser()
        browser.setOpenExternalLinks(True)
        browser.setHtml(html)
        browser.setMinimumHeight(360)
        lay.addWidget(browser, stretch=1)

        # Footer stays visible; only the browser scrolls for long recipe info.
        footer = QWidget()
        footer_l = QVBoxLayout(footer)
        footer_l.setContentsMargins(0, 12, 0, 0)
        footer_l.setSpacing(10)
        q = QLabel(question)
        q.setWordWrap(True)
        q.setObjectName("stepLabel")
        footer_l.addWidget(q)
        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel
        )
        ok_btn = buttons.button(QDialogButtonBox.StandardButton.Ok)
        cancel_btn = buttons.button(QDialogButtonBox.StandardButton.Cancel)
        if ok_btn is not None:
            ok_btn.setText(t("btn.install"))
            ok_btn.setDefault(True)
        if cancel_btn is not None:
            cancel_btn.setText(t("btn.cancel_install"))
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        footer_l.addWidget(buttons)
        lay.addWidget(footer, stretch=0)


def _recipe_has_install_marker(meta: dict[str, str], rid: str) -> bool:
    dr = resolve_data_root(meta, rid)
    prefix = dr / "prefix"
    if prefix.is_dir() and (prefix / "user.reg").is_file():
        return True
    return (dr / "recipe.env").is_file() or (dr / "portable.env").is_file()


def query_recipe_state_quick(
    rid: str, meta: dict[str, str]
) -> tuple[RecipeState, str, str, str, list[str]]:
    """Ohne validate.sh — nur Marker. Für sofortigen GUI-Start."""
    empty = ("", "")
    if _recipe_has_install_marker(meta, rid):
        return RecipeState.INSTALLED, "", *empty, []
    return RecipeState.NOT_INSTALLED, t("state.not_installed"), *empty, []


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
        return _recipe_has_install_marker(meta, rid)

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
        try:
            proc = subprocess.run(
                ["bash", str(validate)],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=_VALIDATE_SUBPROCESS_TIMEOUT_SEC,
            )
        except subprocess.TimeoutExpired:
            detected = _version_fallback("")
            detail = t("state.validate_timeout")
            if _has_marker():
                return RecipeState.PARTIAL, detail, detected, detail, [detail]
            return (
                RecipeState.NOT_INSTALLED,
                t("state.not_installed"),
                detected,
                detail,
                [detail],
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
        body.setHtml(
            t(
                "dialog.about_body",
                repo=GITHUB_REPO,
                runtime=describe_runtime_for_report(),
            )
            + t("dialog.about_dracula_html")
        )
        layout.addWidget(body)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        buttons.accepted.connect(self.accept)
        buttons.clicked.connect(lambda _: self.accept())
        layout.addWidget(buttons)


class _RecipeStatusWorker(QObject):
    """Background trust verify + optional validate.sh (keeps UI thread free)."""

    finished = pyqtSignal(object)  # list[RecipeInfo]
    failed = pyqtSignal(str)

    def __init__(self, env: dict[str, str], *, full_validate: bool) -> None:
        super().__init__()
        self._env = env
        self._full_validate = full_validate

    def run(self) -> None:
        try:
            self.finished.emit(
                _collect_recipe_statuses(self._env, full_validate=self._full_validate)
            )
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


def _collect_recipe_statuses(
    env: dict[str, str], *, full_validate: bool
) -> DiscoverOutcome:
    """Trust + install state off the UI thread (subprocess.validate, hashing)."""
    outcome = discover_recipes(verify_trust=True)
    for info in outcome.recipes:
        if not info.trust_ok:
            continue
        try:
            if full_validate:
                recipe_env = dict(env)
                recipe_env["RECIPE_ID"] = info.rid
                # Drop selected-recipe roots before query_recipe_state fills
                # the correct ones — avoids leaking Halo DATA_ROOT into PS, etc.
                for _k in ("DATA_ROOT", "RECIPE_DATA_ROOT", "WINEPREFIX", "WINE_PREFIX"):
                    recipe_env.pop(_k, None)
                (
                    info.state,
                    info.status_detail,
                    info.version_detected,
                    info.version_warning,
                    info.validate_fails,
                ) = query_recipe_state(info.rid, info.meta, recipe_env)
            else:
                (
                    info.state,
                    info.status_detail,
                    info.version_detected,
                    info.version_warning,
                    _,
                ) = query_recipe_state_quick(info.rid, info.meta)
                # Quick refresh skips validate.sh — keep last full-validate fails
                # so the health chip does not hide known problems.
        except Exception as exc:  # noqa: BLE001 — ein Rezept darf GUI nicht killen
            _debug_log(f"status query for {info.rid}: {exc}")
            info.state = RecipeState.PARTIAL
            info.status_detail = t("status.query_error", error=str(exc))
            info.version_detected = ""
            info.version_warning = str(exc)
            info.validate_fails = [str(exc)]
    return outcome


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
        self.resize(1000, 560)
        self.setMinimumSize(880, 480)
        self._recipe_view_dlg: RecipeViewDialog | None = None
        self._docs_dlg: DeveloperDocsDialog | None = None
        self._ui_restored = False
        self._suppress_tab_persist = False
        self.session_id = uuid.uuid4().hex[:12]
        # First paint without hashing — trust verify runs on a worker thread.
        self.recipes = discover_recipes(verify_trust=False).recipes
        self._dev_mode = rezeptor_dev_mode()
        self._selected: RecipeInfo | None = None
        self._selected_index = -1
        self._recipe_cards: list[tuple[RecipeSidebarCard, RecipeInfo]] = []
        self._process: QProcess | None = None
        self._busy = False
        self._busy_rid: str = ""  # Rezept-ID des laufenden Vorgangs (leer = systemweit)
        self._current_op = ""  # install | repair | …
        self._cancel_requested = False
        self._install_pgid = 0  # Prozessgruppe des laufenden Skripts (0 = unbekannt)
        self._internal_error_shown = False
        self._install_recipe_dir: Path | None = None
        self._theme = "dark"
        self._raw_log_buffer: list[str] = []
        self._latest_release = ""
        self._release_url = f"https://github.com/{GITHUB_REPO}/releases"
        self._wiso_mono_hint_shown = False
        self._update_available = ""
        self._launch_alive_reported = False
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
        self._running_poll.setInterval(1500)
        self._running_poll.timeout.connect(self._refresh_running_indicators)
        self._running_prev: dict[str, bool] = {}
        self._watched_launch_rid: str | None = None
        # Skip cleanup-orphans.sh when Quit/kill.sh already tears the session down.
        self._skip_exit_cleanup: set[str] = set()
        self._status_thread: QThread | None = None
        self._status_worker: _RecipeStatusWorker | None = None
        self._status_refresh_announce = False
        self._status_refresh_pending: tuple[bool, bool] | None = None
        self._post_config_dir: str | None = None
        # Nach Freigabe/Medizin: Primary = „Jetzt aktualisieren“, bis Repair durch ist
        self._pending_repair_rid: str | None = None

        self._ops = RecipeProcessOps(self)

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
        if self._dev_mode:
            self._activity("info", t("app.dev_mode_info"))
        # Startseite statt erstem/letztem Rezept — Auswahl erst durch Klick.
        self._show_home()
        # Trust + quick status off UI thread (after first paint).
        QTimer.singleShot(0, self._start_deferred_trust_verify)
        self._recipe_sync_plan: RecipeSyncPlan | None = None
        # Netzwerk nicht auf dem UI-Thread — verzögert + Hintergrund.
        QTimer.singleShot(2500, self.check_updates_background)
        QTimer.singleShot(4000, self.check_recipe_sync_background)

    def _build_menus(self) -> None:
        self.menuBar().clear()
        # Rezeptor — app shell
        rezeptor_menu = self.menuBar().addMenu(t("menu.rezeptor"))
        rezeptor_menu.addAction(t("menu.home"), self._show_home)
        rezeptor_menu.addAction(t("menu.settings"), self.show_settings)

        # Rezepte — catalog / status / sync
        recipes_menu = self.menuBar().addMenu(t("menu.recipes"))
        self.action_refresh = QAction(t("menu.refresh"), self)
        self.action_refresh.setToolTip(t("menu.refresh_tip"))
        self.action_refresh.setStatusTip(t("menu.refresh_tip"))
        self.action_refresh.triggered.connect(self.refresh_statuses)
        recipes_menu.addAction(self.action_refresh)
        act_sync = QAction(t("menu.check_recipes"), self)
        act_sync.setToolTip(t("menu.check_recipes_tip"))
        act_sync.setStatusTip(t("menu.check_recipes_tip"))
        act_sync.triggered.connect(self.check_recipe_sync)
        recipes_menu.addAction(act_sync)
        recipes_menu.addSeparator()
        act_new = QAction(t("menu.new_recipe"), self)
        act_new.setToolTip(t("menu.new_recipe_tip"))
        act_new.setStatusTip(t("menu.new_recipe_tip"))
        act_new.triggered.connect(self.show_recipe_wizard)
        recipes_menu.addAction(act_new)
        act_cat = QAction(t("menu.add_recipe_catalog"), self)
        act_cat.setToolTip(t("menu.add_recipe_catalog_tip"))
        act_cat.setStatusTip(t("menu.add_recipe_catalog_tip"))
        act_cat.triggered.connect(self.show_catalog_dialog)
        recipes_menu.addAction(act_cat)
        self.action_view_recipe = QAction(self._view_recipe_label(), self)
        self.action_view_recipe.setToolTip(self._view_recipe_tip())
        self.action_view_recipe.setStatusTip(self._view_recipe_tip())
        self.action_view_recipe.triggered.connect(self.show_recipe_view)
        recipes_menu.addAction(self.action_view_recipe)
        recipes_menu.addAction(
            t("menu.show_hidden_recipes"), self.show_hidden_recipes_dialog
        )

        # Werkzeuge — maintenance (not day-to-day recipe ops)
        extras_menu = self.menuBar().addMenu(t("menu.extras"))
        act_sys = QAction(t("menu.system_check"), self)
        act_sys.setToolTip(t("menu.system_check_tip"))
        act_sys.setStatusTip(t("menu.system_check_tip"))
        act_sys.triggered.connect(self.show_host_deps_check)
        extras_menu.addAction(act_sys)
        extras_menu.addAction(t("menu.cleanup_logs"), self.cleanup_logs_now)
        extras_menu.addAction(t("menu.rollback"), self.show_rollback_dialog)

        # Hilfe — docs, app update, support
        help_menu = self.menuBar().addMenu(t("menu.help"))
        act_docs = QAction(t("menu.docs"), self)
        act_docs.setToolTip(t("menu.docs_tip"))
        act_docs.setStatusTip(t("menu.docs_tip"))
        act_docs.triggered.connect(self.show_developer_docs)
        help_menu.addAction(act_docs)
        help_menu.addSeparator()
        help_menu.addAction(t("menu.check_update"), self.check_updates)
        help_menu.addSeparator()
        help_menu.addAction(t("menu.report_bug"), self.report_bug)
        help_menu.addAction(t("menu.diagnose_zip"), self.export_diagnose_zip)
        help_menu.addAction(t("menu.open_log_folder"), self.open_log_folder)
        help_menu.addAction(t("menu.about"), self.show_about)
        self._ensure_lang_toggle()
        self._menu_bar_built = True

    def _ensure_lang_toggle(self) -> None:
        """Menubar corner: language | theme — same compact hit target."""
        if not hasattr(self, "_corner_host") or self._corner_host is None:
            self._corner_host = QWidget(self)
            row = QHBoxLayout(self._corner_host)
            row.setContentsMargins(0, 0, 4, 0)
            row.setSpacing(0)

            self._lang_btn = QToolButton(self._corner_host)
            self._lang_btn.setObjectName("langToggle")
            self._lang_btn.setAutoRaise(True)
            self._lang_btn.setToolButtonStyle(
                Qt.ToolButtonStyle.ToolButtonTextOnly
            )
            self._lang_btn.setCursor(Qt.CursorShape.PointingHandCursor)
            self._lang_btn.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
            self._lang_btn.setFixedSize(36, 28)
            font = self._lang_btn.font()
            font.setPointSize(16)
            self._lang_btn.setFont(font)
            self._lang_btn.clicked.connect(self._toggle_ui_locale)
            row.addWidget(self._lang_btn)

            self._theme_btn = QToolButton(self._corner_host)
            self._theme_btn.setObjectName("themeToggle")
            self._theme_btn.setAutoRaise(True)
            self._theme_btn.setToolButtonStyle(
                Qt.ToolButtonStyle.ToolButtonTextOnly
            )
            self._theme_btn.setCursor(Qt.CursorShape.PointingHandCursor)
            self._theme_btn.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
            self._theme_btn.setFixedSize(28, 28)
            tfont = self._theme_btn.font()
            tfont.setPointSize(14)
            self._theme_btn.setFont(tfont)
            self._theme_btn.clicked.connect(self._cycle_ui_theme)
            row.addWidget(self._theme_btn)

        self._sync_lang_toggle()
        self._sync_theme_toggle()
        self.menuBar().setCornerWidget(
            self._corner_host, Qt.Corner.TopRightCorner
        )

    def _sync_lang_toggle(self) -> None:
        if not hasattr(self, "_lang_btn") or self._lang_btn is None:
            return
        de = (get_locale() or "en").startswith("de")
        self._lang_btn.setText("🇩🇪" if de else "🇬🇧")
        self._lang_btn.setToolTip(t("menu.language_toggle_tip"))
        self._lang_btn.setAccessibleName(t("menu.language_toggle"))
        self._lang_btn.setStatusTip(t("menu.language_toggle_tip"))

    def _sync_theme_toggle(self) -> None:
        if not hasattr(self, "_theme_btn") or self._theme_btn is None:
            return
        tid = normalize_theme(getattr(self._settings, "theme", None))
        # Text only — FA icon made a huge circular hit target in the menubar.
        self._theme_btn.setIcon(QIcon())
        self._theme_btn.setText("◐")
        label = t(f"theme.{tid}")
        self._theme_btn.setToolTip(t("menu.theme_toggle_tip", theme=label))
        self._theme_btn.setAccessibleName(t("menu.theme_toggle"))
        self._theme_btn.setStatusTip(t("menu.theme_toggle_tip", theme=label))

    def _cycle_ui_theme(self) -> None:
        cur = normalize_theme(getattr(self._settings, "theme", None))
        self._settings.theme = next_theme(cur)
        save_settings(self._settings)
        self._apply_theme()
        self._sync_theme_toggle()
        # Status flash only — do not flood Schritte with theme-switch noise.
        self._flash_status(
            t("menu.theme_switched", theme=t(f"theme.{self._settings.theme}"))
        )

    def _toggle_ui_locale(self) -> None:
        new = "en" if (get_locale() or "en").startswith("de") else "de"
        self._settings.locale = new
        save_settings(self._settings)
        set_locale(new)
        self.retranslate_ui()
        self._flash_status(t("menu.language_switched", lang=new.upper()))

    def _view_recipe_label(self) -> str:
        if recipe_edit_allowed(self._settings):
            return t("menu.edit_recipe")
        return t("menu.view_recipe")

    def _view_recipe_tip(self) -> str:
        if recipe_edit_allowed(self._settings):
            return t("menu.edit_recipe_tip")
        return t("menu.view_recipe_tip")

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
        sidebar.setFixedWidth(268)
        self._sidebar = sidebar
        sidebar.installEventFilter(self)
        sl = QVBoxLayout(sidebar)
        sl.setContentsMargins(12, 14, 12, 12)
        sl.setSpacing(10)

        st = QLabel(t("app.sidebar_title"))
        st.setObjectName("sidebarTitle")
        self._sidebar_title = st
        sl.addWidget(st)

        self._home_btn = QPushButton(t("app.home_sidebar"))
        self._home_btn.setObjectName("homeSidebarBtn")
        self._home_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self._home_btn.setToolTip(t("menu.home"))
        self._home_btn.clicked.connect(self._show_home)
        sl.addWidget(self._home_btn)

        self.sidebar_search = QLineEdit()
        self.sidebar_search.setObjectName("sidebarSearch")
        self.sidebar_search.setPlaceholderText(t("app.sidebar_search"))
        self.sidebar_search.setClearButtonEnabled(True)
        self.sidebar_search.textChanged.connect(self._on_sidebar_search)
        sl.addWidget(self.sidebar_search)

        self.recipe_cards_host = QWidget()
        self.recipe_cards_host.setObjectName("recipeCardsHost")
        self.recipe_cards_host.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        self.recipe_cards_host.setAutoFillBackground(False)
        self.recipe_cards_layout = QVBoxLayout(self.recipe_cards_host)
        self.recipe_cards_layout.setContentsMargins(0, 0, 4, 0)
        self.recipe_cards_layout.setSpacing(4)
        self.recipe_cards_layout.setAlignment(Qt.AlignmentFlag.AlignTop)
        self.recipe_cards_scroll = QScrollArea()
        self.recipe_cards_scroll.setObjectName("recipeCardsScroll")
        # False: host height = content; scroll viewport height synced in _sync_sidebar_scroll_gap.
        self.recipe_cards_scroll.setWidgetResizable(False)
        self.recipe_cards_scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.recipe_cards_scroll.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self.recipe_cards_scroll.setVerticalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAsNeeded
        )
        self.recipe_cards_scroll.setAlignment(Qt.AlignmentFlag.AlignTop)
        self.recipe_cards_scroll.setAutoFillBackground(False)
        self.recipe_cards_scroll.viewport().setAutoFillBackground(False)
        self.recipe_cards_scroll.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum
        )
        self.recipe_cards_scroll.setWidget(self.recipe_cards_host)
        self.recipe_cards_scroll.setAccessibleName(t("app.sidebar_title"))
        self.recipe_cards_scroll.viewport().installEventFilter(self)
        # stretch 0: height follows recipe count; leftover is plain sidebar below.
        sl.addWidget(self.recipe_cards_scroll, 0)
        sl.addStretch(1)
        root.addWidget(sidebar)
        QTimer.singleShot(0, self._sync_sidebar_scroll_gap)

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
        header.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum
        )
        self._header = header
        self._header_watermark_src: QPixmap | None = None
        self._header_watermark = QLabel(header)
        self._header_watermark.setObjectName("headerWatermark")
        self._header_watermark.setAttribute(
            Qt.WidgetAttribute.WA_TransparentForMouseEvents, True
        )
        self._header_watermark.setAlignment(
            Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
        )
        self._header_watermark.setStyleSheet(
            "background: transparent; border: none;"
        )
        self._header_watermark.lower()

        hl = QHBoxLayout(header)
        hl.setContentsMargins(12, 10, 12, 10)
        hl.setSpacing(10)

        self.icon_label = QLabel()
        self.icon_label.setFixedSize(48, 48)
        self.icon_label.setScaledContents(True)
        if REZEPTOR_ICON.is_file():
            self.icon_label.setPixmap(
                rounded_pixmap(QIcon(str(REZEPTOR_ICON)).pixmap(48, 48), 10)
            )
        hl.addWidget(self.icon_label, alignment=Qt.AlignmentFlag.AlignTop)

        hc = QVBoxLayout()
        hc.setSpacing(2)
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
        # Fluent TitleLabel verbindet bereits LabelContextMenu („Select all“) —
        # das parallel zu unserem Menü → Doppel-Popup/Überlappung. Abklemmen.
        if FLUENT_AVAILABLE:
            try:
                self.name_label.customContextMenuRequested.disconnect()
            except TypeError:
                pass
        self.name_label.setContextMenuPolicy(
            Qt.ContextMenuPolicy.CustomContextMenu
        )
        self.name_label.customContextMenuRequested.connect(
            self._show_title_context_menu
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
        self.tested_on_pill = StatusPill("", MUTED)
        self.author_pill = StatusPill("", MUTED)
        pills_row.addWidget(self.status_pill)
        pills_row.addWidget(self.version_pill)
        pills_row.addWidget(self.tested_pill)
        pills_row.addWidget(self.proton_pill)
        pills_row.addWidget(self.tested_on_pill)
        pills_row.addWidget(self.author_pill)
        self.health_chip = QToolButton()
        self.health_chip.setObjectName("healthChip")
        self.health_chip.setCursor(Qt.CursorShape.PointingHandCursor)
        self.health_chip.setAutoRaise(True)
        self.health_chip.setVisible(False)
        self.health_chip.clicked.connect(self._show_health_dialog)
        pills_row.addWidget(self.health_chip)
        # Fortschritt nur unter Tab „Vorgang“ — kein doppeltes „Vorgang %“ im Header
        pills_row.addStretch(1)

        self.path_label = QLabel()
        self.path_label.setObjectName("appPath")
        self.path_label.setWordWrap(True)
        self.path_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop
        )
        self.path_label.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self.path_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        # Native QLabel menu is unstyled (black) and often fails on Wayland —
        # Fluent/QMenu + explicit clipboard actions instead.
        self.path_label.setContextMenuPolicy(
            Qt.ContextMenuPolicy.CustomContextMenu
        )
        self.path_label.customContextMenuRequested.connect(
            self._show_path_context_menu
        )
        self._style_secondary_label(self.path_label, MUTED, size_px=11)
        self.open_path_btn = QToolButton()
        self.open_path_btn.setObjectName("openPathBtn")
        self.open_path_btn.setAutoRaise(True)
        self.open_path_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.open_path_btn.setToolTip(t("tooltip.open_data_root"))
        self.open_path_btn.setAccessibleName(t("menu.open_folder"))
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
        self.status_detail_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop
        )
        self.status_detail_label.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self.status_detail_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        self._style_secondary_label(self.status_detail_label, MUTED, size_px=12)
        hc.addLayout(title_row)
        hc.addLayout(pills_row)
        hc.addLayout(path_row)
        hc.addWidget(self.status_detail_label)
        self.status_detail_label.setVisible(False)
        hl.addLayout(hc, stretch=1)
        ml.addWidget(header)
        header.installEventFilter(self)
        if REZEPTOR_ICON.is_file():
            self._set_header_watermark(QIcon(str(REZEPTOR_ICON)))
        QTimer.singleShot(0, self._layout_header_watermark)

        # —— Navigation —— always visible (home CTA + recipe CTA)
        self._build_action_bar(ml)

        # Detail: Startseite | Rezept (Tabs)
        self._home_page = self._create_home_page()
        recipe_pane = QWidget()
        recipe_pane.setObjectName("recipePane")
        rp = QVBoxLayout(recipe_pane)
        rp.setContentsMargins(0, 0, 0, 0)
        rp.setSpacing(8)

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

        rp.addWidget(content_shell, stretch=1)

        self._detail_stack = QStackedWidget()
        self._detail_stack.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
        )
        self._detail_stack.addWidget(self._home_page)
        self._detail_stack.addWidget(recipe_pane)
        ml.addWidget(self._detail_stack, stretch=1)
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
        # Wide enough for DE CTAs („Rezept freigeben“ / „Jetzt aktualisieren“) — less width hop
        self.primary_btn.setMinimumWidth(200)
        self.primary_btn.setCursor(hand)
        self.primary_btn.clicked.connect(self._on_primary_cta)
        # Aliase für bestehenden Code (_set_busy, retranslate, …)
        self.launch_btn = self.primary_btn
        self.install_btn = self.primary_btn
        self.repair_btn = self.primary_btn
        self.kill_btn = self.primary_btn

        # Trust-Freigabe sitzt auf dem Kupfer-Primary — kein grauer Nebenbutton.
        self.trust_btn = None

        # Fluent PushButton + RoundMenu (same family as secondary buttons; no DropDown chrome)
        if FLUENT_AVAILABLE:
            self.more_btn = PushButton(t("btn.more"))
            self._more_menu = RoundMenu(parent=self)
            self.more_btn.clicked.connect(self._popup_more_menu)
            self.medizin_btn = PushButton(t("btn.medizin"))
        else:
            self.more_btn = QToolButton()
            self.more_btn.setText(t("btn.more"))
            self.more_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
            self._more_menu = QMenu(self)
            self.more_btn.setMenu(self._more_menu)
            self.medizin_btn = QPushButton(t("btn.medizin"))
        self.more_btn.setObjectName("moreBtn")
        self.more_btn.setCursor(hand)
        self.more_btn.setToolTip(t("tooltip.more"))
        self._rebuild_more_menu()

        self.medizin_btn.setObjectName("medizinBtn")
        self.medizin_btn.setCursor(hand)
        self.medizin_btn.setToolTip(t("tooltip.medizin"))
        self.medizin_btn.clicked.connect(self._open_medizin_dialog)
        med_ic = fa_icon("kit-medical", 14, color=COLOR_PARCHMENT)
        if med_ic is not None:
            self.medizin_btn.setIcon(med_ic)
            self.medizin_btn.setIconSize(QSize(14, 14))
        self.medizin_btn.setVisible(False)

        # Versteckt: Alias falls alter Code validate_btn anspricht
        self.validate_btn = QPushButton(t("btn.validate"))
        self.validate_btn.setVisible(False)

        self.logs_btn = None

        row.addWidget(self.primary_btn)
        row.addWidget(self.more_btn)
        row.addWidget(self.medizin_btn)
        row.addStretch(1)
        parent_layout.addWidget(bar)

    @staticmethod
    def _add_menu_action(menu: object, text: str, slot) -> QAction:
        """QAction for both QMenu and Fluent RoundMenu (no addAction(str, callable))."""
        action = QAction(text, menu)  # type: ignore[arg-type]
        action.triggered.connect(slot)
        menu.addAction(action)  # type: ignore[attr-defined]
        return action

    def _visible_recipe_options(self):
        if not self._selected:
            return []
        rd = Path(self._selected.meta.get("_dir") or "")
        opts = load_options_from_recipe_dir(rd) if rd.is_dir() else []
        return [o for o in opts if option_visible(o)]

    def _sync_medizin_button(self) -> None:
        btn = getattr(self, "medizin_btn", None)
        if btn is None:
            return
        opts = self._visible_recipe_options()
        # No ▾ — opens a dialog, not a flaky RoundMenu
        btn.setText(t("btn.medizin"))
        btn.setVisible(bool(opts) and self._selected is not None)
        btn.setEnabled(bool(opts) and not getattr(self, "_busy", False))
        med_ic = fa_icon("kit-medical", 14, color=COLOR_PARCHMENT)
        if med_ic is not None:
            btn.setIcon(med_ic)
            btn.setIconSize(QSize(14, 14))

    def _open_medizin_dialog(self) -> None:
        opts = self._visible_recipe_options()
        if not opts or not self._selected:
            return
        dr = resolve_data_root(self._selected.meta, self._selected.rid)
        dlg = MedizinDialog(opts, dr, self)
        # Eigenes Taskleisten-Fenster — sonst blockiert modaler Child „Alles schließen“.
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True, compact=True)
        dlg.exec()
        if dlg.needs_repair_hint and self._selected is not None:
            rid = self._selected.rid
            self._pending_repair_rid = rid
            self._activity("info", t("medizin.apply_repair_hint"))
            # Stable one-liner + CTA only — full _on_select reflows header (flash/hop).
            hint = t("medizin.apply_repair_hint")
            self._status_detail_base = hint
            self.status_detail_label.setText(hint)
            self.status_detail_label.setVisible(True)
            info = self._selected
            dr = resolve_data_root(info.meta, info.rid)
            self._apply_primary_cta(
                info,
                can_launch=self._can_launch_recipe(info, dr),
                running=recipe_process_running(info.rid, info.meta),
                busy=self._busy,
            )
            self._sync_medizin_button()

    def _maybe_steam_medicine_prompt(self) -> None:
        """When user selects a recipe: recommend Steam medicine if Steam is present."""
        if self._busy:
            return
        info = self._selected
        if info is None:
            return
        if _recipe_is_checking(info) or _recipe_is_untrusted(info):
            return
        opts = self._visible_recipe_options()
        steam_opt = next((o for o in opts if is_steam_medicine_option(o)), None)
        if steam_opt is None:
            return
        if not steam_roots():
            return
        dismissed = self._settings.steam_medicine_prompt_dismissed or {}
        if dismissed.get(info.rid):
            return
        dr = resolve_data_root(info.meta, info.rid)
        values = read_option_values(dr, [steam_opt])
        if bool(values.get(steam_opt.id, steam_opt.default)):
            return
        name = str(info.meta.get("name") or info.rid)
        dlg = SteamMedicineHintDialog(name, self)
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True, compact=True)
        result = dlg.exec()
        if dlg.dont_show_again:
            self._settings.steam_medicine_prompt_dismissed = {
                **dict(dismissed),
                info.rid: True,
            }
            save_settings(self._settings)
        if result == QDialog.DialogCode.Accepted:
            self._open_medizin_dialog()

    def _popup_more_menu(self) -> None:
        self._rebuild_more_menu()
        # Defer exec so the click is finished — otherwise RoundMenu closes on first move.
        btn = self.more_btn
        pos = btn.mapToGlobal(btn.rect().bottomLeft())
        QTimer.singleShot(0, lambda p=pos: self._exec_more_menu(p))

    def _exec_more_menu(self, pos) -> None:  # type: ignore[no-untyped-def]
        menu = getattr(self, "_more_menu", None)
        if menu is None:
            return
        menu.exec(pos)

    def _rebuild_more_menu(self) -> None:
        """Mehr-menu: only applicable actions (omit instead of disable).

        Fresh RoundMenu each time — clear() leaves empty separator rows.
        Do not add hidden QActions; omission avoids Fluent empty cells.
        """
        self._more_menu = (
            RoundMenu(parent=self) if FLUENT_AVAILABLE else QMenu(self)
        )
        menu = self._more_menu
        info = self._selected
        busy = bool(getattr(self, "_busy", False))
        mode = getattr(self, "_cta_mode", "none")
        if info is None:
            self._add_menu_action(menu, t("app.home_cta_docs"), self.show_developer_docs)
            self._add_menu_action(menu, t("menu.settings"), self.show_settings)
            self._add_menu_action(menu, t("menu.refresh"), self.refresh_statuses)
            return

        dr = resolve_data_root(info.meta, info.rid)
        can_launch = self._can_launch_recipe(info, dr)
        running = recipe_process_running(info.rid, info.meta)
        repair_ok = (Path(info.meta["_dir"]) / "repair.sh").is_file() and info.state in (
            RecipeState.INSTALLED,
            RecipeState.PARTIAL,
        )
        kill_ok = (Path(info.meta["_dir"]) / "kill.sh").is_file()
        untrusted = _recipe_is_untrusted(info) or _recipe_is_checking(info)
        installed_ish = info.state in (
            RecipeState.INSTALLED,
            RecipeState.PARTIAL,
        )
        pending_repair = self._pending_repair_rid == info.rid
        ops_ok = not busy and not untrusted
        since_sep = 0

        def _add(
            label: str,
            slot: object,
            *,
            show: bool,
            tip: str = "",
        ) -> None:
            nonlocal since_sep
            if not show:
                return
            act = self._add_menu_action(menu, label, slot)
            if tip:
                act.setToolTip(tip)
            since_sep += 1

        def _sep() -> None:
            nonlocal since_sep
            if since_sep <= 0:
                return
            menu.addSeparator()
            since_sep = 0

        _add(t("menu.validate"), self.run_validate, show=ops_ok)
        _add(
            t("menu.repair"),
            self.run_repair,
            show=ops_ok and repair_ok and mode != "repair",
        )
        _add(
            t("menu.launch"),
            self.run_launch,
            # Freigabe/Medizin: kein Start-Umweg, solange Repair aussteht
            show=ops_ok and can_launch and mode != "launch" and not pending_repair,
        )
        _add(
            t("menu.kill"),
            self.run_kill,
            show=ops_ok and kill_ok and running and mode != "kill",
        )
        update_ok = recipe_supports_update(info.meta) and installed_ish
        _add(t("menu.update"), self.run_update, show=ops_ok and update_ok)
        relocate_ok = installed_ish and (
            needs_target_dir(info.meta) or data_root_browsable(dr)
        )
        _add(
            t("menu.relocate"),
            self.run_relocate,
            show=ops_ok and relocate_ok and not running,
            tip=t("menu.relocate_tip"),
        )

        # Separator only when the next group has at least one visible row.
        will_source = bool(needs_source_dialog(info.meta) and ops_ok)
        will_shortcuts = bool(ops_ok and installed_ish)
        genp_script = Path(info.meta["_dir"]) / "genp.sh"
        will_genp = bool(genp_script.is_file() and ops_ok and installed_ish)
        if will_source or will_shortcuts or will_genp:
            _sep()
            if will_source:
                _add(
                    source_configure_label(info.meta),
                    self.run_source_configure,
                    show=True,
                    tip=t("menu.source_tip"),
                )
            # Installationsdaten: nur am Pfad-Icon neben dem Pfad (klarer als im Mehr-Menü)
            _add(
                t("menu.shortcuts"),
                self.run_desktop_shortcuts,
                show=will_shortcuts,
            )
            if will_genp:
                _add(
                    t("menu.genp_from_pack"),
                    self.run_genp_from_pack,
                    show=True,
                    tip=t("menu.genp_from_pack_tip"),
                )

        # Only open a new separator group when the next item will actually show —
        # otherwise RoundMenu keeps an empty separator row (translucent “hole”).
        if not busy:
            _sep()
            _add(
                self._view_recipe_label(),
                self.show_recipe_view,
                show=True,
                tip=self._view_recipe_tip(),
            )

        if ops_ok and installed_ish:
            _sep()
            _add(
                t("menu.uninstall"),
                self.run_uninstall,
                show=True,
            )

    def _on_primary_cta(self) -> None:
        w = QApplication.focusWidget()
        if isinstance(w, (QLineEdit, QTextEdit, QTextBrowser)):
            return
        # Hard gate: disabled styling can race with re-select/status refresh.
        if getattr(self, "_busy", False):
            return
        mode = getattr(self, "_cta_mode", "none")
        if mode in ("none", "busy_hold"):
            return
        if mode == "docs":
            self.show_developer_docs()
            return
        if mode in ("trust_approve", "trust_update"):
            self._on_trust_action()
            return
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
        """Primary-CTA global: Freigeben | Installieren | Starten | Reparieren | Beenden.

        Pflicht-Aktionen (Freigabe, Jetzt-reparieren) immer auf dem Kupfer-Primary —
        kein grauer Nebenbutton, kein Rezept-Sonderweg.
        """
        repair_sh = (Path(info.meta["_dir"]) / "repair.sh").is_file()
        repair_ok = repair_sh and info.state in (
            RecipeState.INSTALLED,
            RecipeState.PARTIAL,
        )
        kill_ok = (Path(info.meta["_dir"]) / "kill.sh").is_file()
        checking = _recipe_is_checking(info)
        untrusted = _recipe_is_untrusted(info)
        # After Freigabe, pending must win even when rediscover still reports
        # UNTRUSTED/UNKNOWN (install state is masked until status refresh).
        # Only require repair.sh — not INSTALLED|PARTIAL — or CTA flashes back
        # to „Rezept freigeben“ and stays clickable.
        pending_repair = (
            self._pending_repair_rid == info.rid and repair_sh and not checking
        )
        git_dev = (ROOT / ".git").is_dir()

        if checking and not pending_repair:
            mode = "none"
        elif pending_repair:
            # Beat untrusted + busy: Freigabe sets pending_repair immediately so the
            # Kupfer-CTA never sticks on „Rezept freigeben“ mid-approve.
            mode = "repair"
        elif busy:
            # Keep current meaningful label — mode "none" used to flash „Starten“.
            mode = "busy_hold"
        elif untrusted and git_dev:
            mode = "trust_approve"
        elif untrusted:
            mode = "trust_update"
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
        if pending_repair and busy:
            repair_label = "btn.repair_busy"
        elif pending_repair:
            repair_label = "btn.repair_required"
        else:
            repair_label = "btn.repair"
        mapping = {
            "install": ("btn.install", "tooltip.install", "install"),
            "launch": ("btn.launch", "tooltip.launch", "launch"),
            "repair": (
                repair_label,
                "tooltip.repair",
                "warn" if pending_repair else "repair",
            ),
            "kill": ("btn.kill", "tooltip.kill", "kill"),
            "trust_approve": (
                "btn.regen_manifest",
                "tooltip.regen_manifest",
                "warn",
            ),
            "trust_update": (
                "btn.update_rezeptor",
                "tooltip.regen_manifest",
                "warn",
            ),
        }
        if mode == "busy_hold":
            # Disabled, but do not rewrite label (avoids Freigeben→Starten flash).
            btn.setEnabled(False)
            btn.setVisible(True)
        elif mode in mapping:
            label_k, tip_k, icon_k = mapping[mode]
            btn.setText(t(label_k))
            btn.setToolTip(t(tip_k))
            # Primary-CTA: dunkles Icon auf Kupfer/Accent (helles Icon wäre unsichtbar)
            icon = fa_icon(icon_k, 14, color="#1a1a1a" if mode != "kill" else "#7f1d1d")
            if icon is not None:
                btn.setIcon(icon)
                btn.setIconSize(QSize(14, 14))
            # Always disable while busy — including pending_repair handoff.
            btn.setEnabled(not busy)
            btn.setVisible(True)
        else:
            btn.setEnabled(False)
            btn.setText(t("btn.launch"))
            btn.setToolTip("")
            btn.setIcon(QIcon())

        # Mehr-Menü: neu gebaut in _popup_more_menu (omit inapplicable actions).

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
        act_open = self._add_menu_action(
            menu, t("menu.open_folder"), self._open_data_root
        )
        act_open.setEnabled(data_root_browsable(dr))
        self._add_menu_action(menu, self._view_recipe_label(), self.show_recipe_view)
        menu.addSeparator()
        self._add_menu_action(
            menu, t("menu.move_up"), lambda: self._move_recipe(info.rid, -1)
        )
        self._add_menu_action(
            menu, t("menu.move_down"), lambda: self._move_recipe(info.rid, 1)
        )
        if (self._settings.recipe_category_overrides or {}).get(info.rid):
            self._add_menu_action(
                menu,
                t("menu.reset_category"),
                lambda: self.reset_recipe_category(info.rid),
            )
        self._add_menu_action(
            menu, t("menu.hide_recipe"), lambda: self.hide_recipe(info.rid)
        )
        if not self._is_official_bundled_recipe(info.rid):
            self._add_menu_action(
                menu,
                t("recipe_remove.menu"),
                lambda: self.remove_recipe_definition(info.rid),
            )
        if info.state in (RecipeState.INSTALLED, RecipeState.PARTIAL):
            self._add_menu_action(
                menu, t("menu.shortcuts"), self.run_desktop_shortcuts
            )
            menu.addSeparator()
            self._add_menu_action(menu, t("menu.uninstall"), self.run_uninstall)
        menu.exec(self.cursor().pos())

    def _update_progress_chip(self) -> None:
        """No-op: progress lives only in the Vorgang tab (not header pills)."""
        return

    def _update_health_chip(self, info: RecipeInfo) -> None:
        """Hinweise nur für das aktuell gewählte Rezept (Header-Chip)."""
        chip = getattr(self, "health_chip", None)
        if chip is None:
            return
        if self._selected is None or self._selected.rid != info.rid:
            chip.setVisible(False)
            chip.setText("")
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
        apply_fa_message_icon(box, "warn")
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

    def _create_home_page(self) -> QWidget:
        """Startseite: Intro + Kennzahlen (Header bleibt darüber)."""
        # Plain widget (not contentShell Card) so unused height is not a hollow card.
        page = QWidget()
        page.setObjectName("homePage")
        page.setAutoFillBackground(False)
        page.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum
        )
        lay = QVBoxLayout(page)
        lay.setContentsMargins(4, 2, 4, 4)
        lay.setSpacing(6)
        lay.setAlignment(Qt.AlignmentFlag.AlignTop)

        intro = QLabel(t("app.home_intro"))
        intro.setObjectName("homeIntro")
        intro.setWordWrap(True)
        intro.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self._home_intro = intro
        lay.addWidget(intro)

        stats_row = QHBoxLayout()
        stats_row.setSpacing(6)
        self._home_stat_labels: dict[str, QLabel] = {}
        for key in ("recipes", "installed", "attention", "hidden"):
            card = QFrame()
            card.setObjectName("homeStatCard")
            card.setMinimumWidth(90)
            cl = QVBoxLayout(card)
            cl.setContentsMargins(6, 4, 6, 4)
            cl.setSpacing(0)
            val = QLabel("0")
            val.setObjectName("homeStatValue")
            val.setAlignment(Qt.AlignmentFlag.AlignCenter)
            lab = QLabel(t(f"app.home_stat_{key}"))
            lab.setObjectName("homeStatLabel")
            lab.setAlignment(Qt.AlignmentFlag.AlignCenter)
            lab.setWordWrap(True)
            cl.addWidget(val)
            cl.addWidget(lab)
            stats_row.addWidget(card, stretch=1)
            self._home_stat_labels[key] = val
            setattr(self, f"_home_stat_caption_{key}", lab)
        lay.addLayout(stats_row)

        tip = QLabel(t("app.home_tip"))
        tip.setObjectName("muted")
        tip.setWordWrap(True)
        self._home_tip = tip
        lay.addWidget(tip)

        activity_title = QLabel(t("home.activity_title"))
        activity_title.setObjectName("homeActivityTitle")
        self._home_activity_title = activity_title
        lay.addWidget(activity_title)

        self._home_activity_list = QListWidget()
        self._home_activity_list.setObjectName("homeActivityList")
        self._home_activity_list.setFrameShape(QFrame.Shape.StyledPanel)
        self._home_activity_list.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum
        )
        self._home_activity_list.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self._home_activity_list.setVerticalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAsNeeded
        )
        self._home_activity_list.itemClicked.connect(self._on_home_activity_clicked)
        lay.addWidget(self._home_activity_list)
        self._refresh_home_activity()

        links_hint = QLabel(t("app.home_links_hint"))
        links_hint.setObjectName("homeLinksHint")
        links_hint.setWordWrap(True)
        self._home_links_hint = links_hint
        lay.addWidget(links_hint)

        links_grid = QGridLayout()
        links_grid.setSpacing(6)
        links_grid.setContentsMargins(0, 0, 0, 0)
        self._home_github_btn, self._home_github_title, self._home_github_sub = (
            self._make_home_link_card(
                icon_kind="github",
                title_key="app.home_link_github",
                subtitle_key="app.home_link_github_sub",
                tip_key="app.home_link_github_tip",
                on_click=self._open_home_github,
            )
        )
        self._home_wiki_btn, self._home_wiki_title, self._home_wiki_sub = (
            self._make_home_link_card(
                icon_kind="book_open",
                title_key="app.home_link_wiki",
                subtitle_key="app.home_link_wiki_sub",
                tip_key="app.home_link_wiki_tip",
                on_click=self._open_home_wiki,
            )
        )
        self._home_reddit_btn, self._home_reddit_title, self._home_reddit_sub = (
            self._make_home_link_card(
                icon_kind="reddit",
                title_key="app.home_link_reddit",
                subtitle_key="app.home_link_reddit_sub",
                tip_key="app.home_link_reddit_tip",
                on_click=self._open_home_reddit,
            )
        )
        links_grid.addWidget(self._home_github_btn, 0, 0)
        links_grid.addWidget(self._home_wiki_btn, 0, 1)
        links_grid.addWidget(self._home_reddit_btn, 0, 2)
        self._home_linuxchooser_btn, self._home_linuxchooser_title, self._home_linuxchooser_sub = (
            self._make_home_link_card(
                icon_kind="linuxchooser",
                title_key="app.home_link_linuxchooser",
                subtitle_key="app.home_link_linuxchooser_sub",
                tip_key="app.home_link_linuxchooser_tip",
                on_click=self._open_home_linuxchooser,
            )
        )
        self._home_cachyos_btn, self._home_cachyos_title, self._home_cachyos_sub = (
            self._make_home_link_card(
                icon_kind="cachyos",
                title_key="app.home_link_cachyos",
                subtitle_key="app.home_link_cachyos_sub",
                tip_key="app.home_link_cachyos_tip",
                on_click=self._open_home_cachyos,
            )
        )
        self._home_linuxguides_btn, self._home_linuxguides_title, self._home_linuxguides_sub = (
            self._make_home_link_card(
                icon_kind="linuxguides",
                title_key="app.home_link_linuxguides",
                subtitle_key="app.home_link_linuxguides_sub",
                tip_key="app.home_link_linuxguides_tip",
                on_click=self._open_home_linuxguides,
            )
        )
        links_grid.addWidget(self._home_linuxchooser_btn, 1, 0)
        links_grid.addWidget(self._home_cachyos_btn, 1, 1)
        links_grid.addWidget(self._home_linuxguides_btn, 1, 2)
        lay.addLayout(links_grid)
        # No bottom stretch: page height = content; leftover is mainColumn bg.
        return page

    def _make_home_link_card(
        self,
        *,
        icon_kind: str,
        title_key: str,
        subtitle_key: str,
        tip_key: str,
        on_click,
    ) -> tuple[QFrame, QLabel, QLabel]:
        """Compact link row: 16px icon | title + subtitle (no stacked/overlap)."""
        card = QFrame()
        card.setObjectName("homeLinkCard")
        card.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        card.setToolTip(t(tip_key))
        card.setFixedHeight(48)
        card.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        card.setAccessibleName(t(title_key))
        card.setProperty("homeIconKind", icon_kind)
        card.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        card.mouseReleaseEvent = (  # type: ignore[method-assign]
            lambda event, cb=on_click: (
                cb()
                if event.button() == Qt.MouseButton.LeftButton
                else None
            )
        )
        card.keyPressEvent = (  # type: ignore[method-assign]
            lambda event, cb=on_click: (
                cb()
                if event.key()
                in (Qt.Key.Key_Return, Qt.Key.Key_Enter, Qt.Key.Key_Space)
                else QFrame.keyPressEvent(card, event)
            )
        )

        row = QHBoxLayout(card)
        row.setContentsMargins(10, 6, 10, 6)
        row.setSpacing(8)

        icon_lbl = QLabel()
        icon_lbl.setObjectName("homeLinkIcon")
        icon_lbl.setFixedSize(18, 18)
        icon_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        icon_lbl.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
        card._home_icon_lbl = icon_lbl  # type: ignore[attr-defined]
        self._paint_home_link_icon(card, icon_kind)

        texts = QVBoxLayout()
        texts.setContentsMargins(0, 0, 0, 0)
        texts.setSpacing(0)
        title = QLabel(t(title_key))
        title.setObjectName("homeLinkTitle")
        title.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
        sub = QLabel(t(subtitle_key))
        sub.setObjectName("homeLinkSub")
        sub.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
        texts.addWidget(title)
        texts.addWidget(sub)

        row.addWidget(icon_lbl, 0, Qt.AlignmentFlag.AlignVCenter)
        row.addLayout(texts, 1)
        return card, title, sub

    def _paint_home_link_icon(self, card: QFrame, icon_kind: str | None = None) -> None:
        kind = icon_kind or str(card.property("homeIconKind") or "")
        lbl = getattr(card, "_home_icon_lbl", None)
        if not kind or lbl is None:
            return
        # Site favicons (vendored) for community links; FA for GitHub/Reddit/Wiki.
        fav_dir = _LAUNCHER_DIR / "assets" / "home-favicons"
        for ext in (".svg", ".png", ".ico"):
            fav = fav_dir / f"{kind}{ext}"
            if fav.is_file():
                pix = QIcon(str(fav)).pixmap(18, 18)
                if not pix.isNull():
                    lbl.setPixmap(pix)
                    return
        fa_kind = {
            "linuxchooser": "compass",
            "cachyos": "linux",
            "linuxguides": "globe",
        }.get(kind, kind)
        accent = theme_tokens(normalize_theme(self._settings.theme))["accent"]
        ic = fa_icon(fa_kind, 14, color=accent)
        if ic is None:
            return
        lbl.setPixmap(ic.pixmap(18, 18))

    def _refresh_home_link_icons(self) -> None:
        for prefix in (
            "github",
            "wiki",
            "reddit",
            "linuxchooser",
            "cachyos",
            "linuxguides",
        ):
            btn = getattr(self, f"_home_{prefix}_btn", None)
            if btn is not None:
                self._paint_home_link_icon(btn)

    def _open_home_github(self) -> None:
        QDesktopServices.openUrl(QUrl(github_repo_url()))

    def _open_home_wiki(self) -> None:
        QDesktopServices.openUrl(QUrl(public_docs_url(get_locale())))

    def _open_home_reddit(self) -> None:
        QDesktopServices.openUrl(QUrl(community_reddit_url()))

    def _open_home_linuxchooser(self) -> None:
        QDesktopServices.openUrl(QUrl(linuxchooser_url()))

    def _open_home_cachyos(self) -> None:
        QDesktopServices.openUrl(QUrl(cachyos_url()))

    def _open_home_linuxguides(self) -> None:
        QDesktopServices.openUrl(QUrl(linuxguides_url()))

    def _recipe_stats(self) -> dict[str, int]:
        hidden = set(self._settings.hidden_recipe_ids or [])
        visible = [r for r in self.recipes if r.rid not in hidden]
        installed = sum(1 for r in visible if r.state == RecipeState.INSTALLED)
        attention = sum(
            1
            for r in visible
            if r.state == RecipeState.PARTIAL or _recipe_is_untrusted(r)
        )
        sync_n = pending_attention_count()
        if sync_n:
            attention += sync_n
        return {
            "recipes": len(visible),
            "installed": installed,
            "attention": attention,
            "hidden": len(hidden),
        }

    def _refresh_home_stats(self) -> None:
        if not hasattr(self, "_home_stat_labels"):
            return
        stats = self._recipe_stats()
        for key, val in self._home_stat_labels.items():
            val.setText(str(stats.get(key, 0)))

    def _set_home_btn_active(self, active: bool) -> None:
        btn = getattr(self, "_home_btn", None)
        if btn is None:
            return
        btn.setProperty("homeActive", "true" if active else "false")
        btn.style().unpolish(btn)
        btn.style().polish(btn)

    def _show_home(self) -> None:
        """Hauptansicht ohne Rezept — Intro + Statistiken."""
        self._selected = None
        self._selected_index = -1
        for card, _info in self._recipe_cards:
            card.set_selected(False)
        self._set_home_btn_active(True)

        if REZEPTOR_ICON.is_file():
            ic = QIcon(str(REZEPTOR_ICON))
            self.setWindowIcon(ic)
            self.icon_label.setPixmap(rounded_pixmap(ic.pixmap(48, 48), 10))
            self._set_header_watermark(ic)
        else:
            self._set_header_watermark(None)
        self.name_label.setText(t("app.home_title"))
        self.version_info_btn.setVisible(False)
        self.status_pill.setVisible(False)
        self.health_chip.setVisible(False)

        ver = read_version()
        stats = self._recipe_stats()
        self.version_pill.set_content(t("app.home_pill_version", version=ver), COLOR_TESTED)
        self.tested_pill.set_content(
            t("app.home_pill_recipes", n=stats["recipes"]), COLOR_TESTED
        )
        self.proton_pill.set_content("Proton-GE", COLOR_EXPERIMENTAL)
        self.tested_on_pill.set_content("", MUTED)
        self.author_pill.set_content("", MUTED)

        # Home: no path/folder row (tagline lives in intro) — kills header dead space.
        self.path_label.clear()
        self.path_label.setVisible(False)
        self.open_path_btn.setVisible(False)
        self.open_path_btn.setEnabled(False)
        self.status_detail_label.clear()
        self.status_detail_label.setVisible(False)

        self._cta_mode = "docs"
        self.primary_btn.setText(t("app.home_cta_docs"))
        self.primary_btn.setToolTip(t("app.home_cta_docs_tip"))
        docs_ic = fa_icon("info", 14, color="#1a1a1a")
        if docs_ic is not None:
            self.primary_btn.setIcon(docs_ic)
            self.primary_btn.setIconSize(QSize(14, 14))
        self.primary_btn.setEnabled(True)
        self.primary_btn.setVisible(True)
        self.more_btn.setEnabled(True)
        self._sync_medizin_button()

        self._refresh_home_stats()
        self._refresh_home_activity()
        if hasattr(self, "_detail_stack"):
            self._detail_stack.setCurrentIndex(0)
        self._rebuild_more_menu()
        QTimer.singleShot(0, lambda: self._apply_content_window_height(allow_grow=False))

    def _refresh_home_activity(self) -> None:
        """Newest completed recipe ops on the home page (cap DISPLAY_CAP)."""
        from activity_history import (
            DISPLAY_CAP,
            format_activity_line,
            load_activity_history,
        )

        lst = getattr(self, "_home_activity_list", None)
        if lst is None:
            return
        lst.clear()
        tok = theme_tokens(normalize_theme(getattr(self._settings, "theme", None)))
        entries = load_activity_history()[:DISPLAY_CAP]
        if not entries:
            item = QListWidgetItem(t("home.activity_empty"))
            item.setFlags(Qt.ItemFlag.NoItemFlags)
            item.setForeground(QColor(tok["muted"]))
            lst.addItem(item)
            self._fit_home_activity_list()
            return
        fail_fg = QColor(tok.get("danger") or "#e07070")
        ok_fg = QColor(tok["fg"])
        for entry in entries:
            item = QListWidgetItem(format_activity_line(entry))
            item.setData(Qt.ItemDataRole.UserRole, entry.rid)
            item.setToolTip(item.text())
            item.setForeground(fail_fg if not entry.ok else ok_fg)
            lst.addItem(item)
        self._fit_home_activity_list()

    def _fit_home_activity_list(self) -> None:
        """Keep Zuletzt as tall as its rows — no empty box."""
        lst = getattr(self, "_home_activity_list", None)
        if lst is None:
            return
        n = max(1, lst.count())
        row = lst.sizeHintForRow(0)
        if row <= 0:
            row = 22
        # Cap ~5 rows; grow with content up to that (tight padding).
        h = min(5, n) * row + 6
        lst.setFixedHeight(h)
        lst.setMaximumHeight(h)

    def _on_home_activity_clicked(self, item: QListWidgetItem) -> None:
        rid = str(item.data(Qt.ItemDataRole.UserRole) or "").strip()
        if not rid:
            return
        for i, info in enumerate(self.recipes):
            if info.rid == rid:
                self._select_recipe_index(i, user_initiated=True)
                return

    def _create_progress_tab(self) -> QWidget:
        tab = QWidget()
        lay = QVBoxLayout(tab)
        lay.setContentsMargins(10, 8, 10, 8)
        lay.setSpacing(6)

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

        self.cancel_install_btn = QPushButton(t("btn.cancel_install"))
        self.cancel_install_btn.setObjectName("cancelInstallBtn")
        self.cancel_install_btn.setToolTip(t("tooltip.cancel_install"))
        self.cancel_install_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.cancel_install_btn.setVisible(False)
        self.cancel_install_btn.clicked.connect(self._cancel_current_install)
        status_row.addWidget(
            self.cancel_install_btn, 0, Qt.AlignmentFlag.AlignVCenter
        )
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
        self.activity_list.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum
        )
        lay.addWidget(self.activity_list, stretch=0)
        self._show_activity_empty_hint()

        log_label = QLabel(t("progress.live"))
        log_label.setObjectName("muted")
        self._progress_live_label = log_label
        lay.addWidget(log_label)
        self.raw_log = QTextEdit()
        self.raw_log.setObjectName("rawLog")
        self.raw_log.setReadOnly(True)
        self.raw_log.setFont(QFont("monospace", 9))
        self.raw_log.setPlaceholderText(t("progress.live_placeholder"))
        self.raw_log.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum
        )
        lay.addWidget(self.raw_log, stretch=0)
        lay.addStretch(1)
        self._fit_progress_panels()
        return tab

    def _fit_progress_panels(self) -> None:
        """Idle: compact Schritte/Live boxes. Busy: taller, still content-capped."""
        if not hasattr(self, "activity_list") or not hasattr(self, "raw_log"):
            return
        lst = self.activity_list
        n = max(1, lst.count())
        row = lst.sizeHintForRow(0)
        if row <= 0:
            row = 22
        busy = bool(getattr(self, "_busy", False))
        cap = 12 if busy else min(n, 3)
        h = min(cap, n) * row + 8
        lst.setFixedHeight(max(h, 40 if not busy else 72))

        has_log = bool(getattr(self, "_raw_log_buffer", None))
        if busy or has_log:
            self.raw_log.setFixedHeight(140)
        else:
            self.raw_log.setFixedHeight(56)

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
        actions = QHBoxLayout()
        self._logs_open_folder_btn = QPushButton(t("logs.open_folder"))
        self._logs_open_folder_btn.setObjectName("ghostBtn")
        self._logs_open_folder_btn.clicked.connect(self.open_log_folder)
        actions.addWidget(self._logs_open_folder_btn)
        self._logs_copy_path_btn = QPushButton(t("logs.copy_path"))
        self._logs_copy_path_btn.setObjectName("ghostBtn")
        self._logs_copy_path_btn.clicked.connect(self.copy_selected_log_path)
        actions.addWidget(self._logs_copy_path_btn)
        self._logs_copy_content_btn = QPushButton(t("logs.copy_content"))
        self._logs_copy_content_btn.setObjectName("ghostBtn")
        self._logs_copy_content_btn.clicked.connect(self.copy_selected_log_content)
        actions.addWidget(self._logs_copy_content_btn)
        self._logs_diagnose_btn = QPushButton(t("btn.diagnose_zip"))
        self._logs_diagnose_btn.setObjectName("ghostBtn")
        self._logs_diagnose_btn.clicked.connect(self.export_diagnose_zip)
        actions.addWidget(self._logs_diagnose_btn)
        actions.addStretch(1)
        lay.addLayout(actions)
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
        """GitHub-Check im Hintergrund — blockiert den Start nicht."""

        def work() -> None:
            latest, url = fetch_latest_release()
            cur = read_version()

            def apply() -> None:
                self._latest_release = latest
                self._release_url = url
                if latest and version_compare(cur, latest):
                    self._refresh_status_footer(latest)
                    self.setWindowTitle(self._window_title(cur, latest))
                else:
                    self._refresh_status_footer()
                    self.setWindowTitle(self._window_title(cur))

            QTimer.singleShot(0, apply)

        threading.Thread(target=work, daemon=True, name="rezeptor-update-check").start()

    def check_recipe_sync_background(self) -> None:
        """Silent recipe-bundle check — updates Home attention counter."""

        def work() -> None:
            try:
                plan = check_recipe_updates(
                    bundled_recipes=RECIPES_DIR,
                    bundled_manifest=MANIFEST_PATH,
                )
            except RecipeSyncError:
                return

            def apply() -> None:
                self._recipe_sync_plan = plan
                self._refresh_home_stats()
                if plan.has_actionable or plan.pending_count:
                    self._activity(
                        "info",
                        t(
                            "recipe_sync.available_activity",
                            n=plan.pending_count,
                            ver=plan.bundle_version,
                        ),
                    )

            QTimer.singleShot(0, apply)

        threading.Thread(target=work, daemon=True, name="rezeptor-recipe-sync").start()

    def check_recipe_sync(self) -> None:
        """Interactive: check GitHub recipes bundle and optionally apply."""
        try:
            plan = check_recipe_updates(
                bundled_recipes=RECIPES_DIR,
                bundled_manifest=MANIFEST_PATH,
            )
        except RecipeSyncError as exc:
            QMessageBox.warning(
                self,
                t("recipe_sync.error_title"),
                t("recipe_sync.error_body", error=str(exc)),
            )
            return

        self._recipe_sync_plan = plan
        self._refresh_home_stats()

        if not plan.changes:
            QMessageBox.information(
                self,
                t("recipe_sync.none_title"),
                t("recipe_sync.none_body", ver=plan.bundle_version),
            )
            return

        summary = format_plan_summary(plan)
        box = QMessageBox(self)
        apply_fa_message_icon(box, "info")
        box.setWindowTitle(t("recipe_sync.available_title"))
        box.setText(
            t(
                "recipe_sync.available_body",
                ver=plan.bundle_version,
                n=plan.pending_count,
            )
        )
        box.setInformativeText(summary[:4000] if summary else "")
        apply_btn = None
        if plan.has_actionable:
            apply_btn = box.addButton(
                t("recipe_sync.btn_apply"), QMessageBox.ButtonRole.AcceptRole
            )
        box.addButton(t("recipe_sync.btn_later"), QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if apply_btn is not None and box.clickedButton() == apply_btn:
            self._apply_recipe_sync_plan(plan)

    def _apply_recipe_sync_plan(self, plan: RecipeSyncPlan) -> None:
        try:
            applied = apply_recipe_sync(plan, bundled_recipes=RECIPES_DIR)
        except RecipeSyncError as exc:
            QMessageBox.warning(
                self,
                t("recipe_sync.error_title"),
                t("recipe_sync.error_body", error=str(exc)),
            )
            return
        self._apply_discover_outcome(discover_recipes())
        self._populate_list()
        self._refresh_home_stats()
        QMessageBox.information(
            self,
            t("recipe_sync.done_title"),
            t("recipe_sync.done_body", n=len(applied), ver=plan.bundle_version),
        )

    def check_updates(self) -> None:
        latest, url = fetch_latest_release()
        self._latest_release = latest or self._latest_release
        self._release_url = url
        cur = read_version()
        channel = detect_update_channel()
        channel_label = t(f"update.channel_{channel}")
        if latest and version_compare(cur, latest):
            box = QMessageBox(self)
            apply_fa_message_icon(box, "info")
            box.setWindowTitle(t("update.available_title"))
            if channel == "flatpak":
                box.setText(
                    t(
                        "update.available_body_flatpak",
                        current=cur,
                        latest=latest,
                        channel=channel_label,
                    )
                )
            else:
                box.setText(
                    t(
                        "update.available_body",
                        current=cur,
                        latest=latest,
                        channel=channel_label,
                    )
                )
            auto_btn = None
            if update_auto_supported(channel):
                auto_btn = box.addButton(
                    t("update.btn_auto"), QMessageBox.ButtonRole.AcceptRole
                )
            browser_btn = box.addButton(
                t("update.btn_browser"), QMessageBox.ButtonRole.ActionRole
            )
            box.addButton(t("update.btn_cancel"), QMessageBox.ButtonRole.RejectRole)
            box.exec()
            clicked = box.clickedButton()
            if auto_btn is not None and clicked == auto_btn:
                self._run_rezeptor_update(latest)
            elif clicked == browser_btn:
                QDesktopServices.openUrl(QUrl(url))
        else:
            hint = t("update.none_latest", latest=latest) if latest else ""
            QMessageBox.information(
                self,
                t("update.none_title"),
                t(
                    "update.none_body",
                    current=cur,
                    latest_hint=hint,
                    channel=channel_label,
                ),
            )

    def _run_rezeptor_update(self, tag: str = "") -> None:
        channel = detect_update_channel()
        if not update_auto_supported(channel):
            latest = tag.lstrip("v") if tag else (self._latest_release or "")
            QMessageBox.information(
                self,
                t("update.available_title"),
                t("update.flatpak_manual", latest=latest),
            )
            if self._release_url:
                QDesktopServices.openUrl(QUrl(self._release_url))
            return
        script = ROOT / "scripts" / "rezeptor-update.sh"
        if not script.is_file():
            QMessageBox.warning(self, t("dialog.missing"), str(script))
            return
        if self._reject_if_subprocess_busy():
            return
        self._switch_to_progress_tab()
        self._activity("step", t("update.applying"))
        cmd = ["bash", str(script), "apply"]
        if tag:
            cmd.append(tag if tag.startswith("v") else f"v{tag}")
        env = self._base_env()
        proc = QProcess(self)
        self._process = proc
        self._set_busy(True, rid="")
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
            if self._process is not proc:
                return
            self._set_busy(False)
            if code == 0:
                self._activity("ok", t("update.done"))
                QMessageBox.information(self, t("update.available_title"), t("update.done"))
            elif code == 3 and detect_update_channel() == "flatpak":
                latest = tag.lstrip("v") if tag else (self._latest_release or "")
                self._activity("error", t("update.failed_flatpak", code=code, latest=latest))
                QMessageBox.warning(
                    self,
                    t("update.available_title"),
                    t("update.failed_flatpak", code=code, latest=latest),
                )
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
            if self._process is proc:
                self._process = None

        def on_update_error(err: QProcess.ProcessError) -> None:
            self._activity("error", f"update process error: {err}")

        proc.readyReadStandardOutput.connect(on_out)
        proc.errorOccurred.connect(on_update_error)
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
        if not (ROOT / ".git").is_dir():
            self.check_updates()
            return
        if self._selected is None:
            self._flash_status(t("trust.regen_fail") + ": kein Rezept gewählt")
            return
        # Block re-entry while approve/repair is already running (QProcess-only
        # reject is not enough — freigeben is sync until handoff).
        if getattr(self, "_busy", False):
            return
        if self._reject_if_subprocess_busy():
            return
        info = self._selected
        rid = info.rid
        recipe_dir = Path(info.meta.get("_dir") or "")
        if not recipe_dir.is_dir():
            self._activity("error", t("trust.regen_fail") + f": {rid}")
            return

        repair = recipe_dir / "repair.sh"
        # UNTRUSTED masks INSTALLED|PARTIAL — use install markers so Freigabe
        # still hands off to repair / pending „Jetzt aktualisieren“.
        installed_ish = info.state in (
            RecipeState.INSTALLED,
            RecipeState.PARTIAL,
        ) or _recipe_has_install_marker(info.meta, rid)
        # Always pin pending when repair exists so CTA cannot fall back to
        # clickable „Rezept freigeben“ mid-approve or after rediscover.
        if repair.is_file():
            self._pending_repair_rid = rid
        self._assert_recipe_trusted(rid)
        self.raw_log.clear()
        self._clear_activity_list()
        self._switch_to_progress_tab()
        self._set_busy(True, rid=rid)
        self._apply_primary_cta(
            info, can_launch=False, running=False, busy=True
        )
        self._set_step_text(t("trust.regen_busy"))
        self._activity("step", t("trust.regen_busy"))
        QApplication.processEvents()

        handoff_repair = False
        try:
            approve_recipe_manifest(recipe_dir, _recipe_manifest_path(recipe_dir))
            self._activity("ok", t("trust.regen_ok") + f" ({rid})")
            # Re-assert after rediscover — hash verify can briefly look untrusted.
            if repair.is_file():
                self._pending_repair_rid = rid
            self._assert_recipe_trusted(rid)
            self._apply_discover_outcome(discover_recipes())
            self._assert_recipe_trusted(rid)
            if repair.is_file():
                self._pending_repair_rid = rid
            self.refresh_statuses()
            idx = next(
                (i for i, r in enumerate(self.recipes) if r.rid == rid),
                -1,
            )
            if idx >= 0:
                self._on_select(idx)
            # Keep busy through select/rediscover — Primary stays disabled.
            self._set_busy(True, rid=rid)
            if self._selected is not None and self._selected.rid == rid:
                self._apply_primary_cta(
                    self._selected,
                    can_launch=False,
                    running=False,
                    busy=True,
                )

            # Approve alone is not enough — login/runtime fixes need repair.
            # Stay busy into _run_async (reject checks QProcess, not _busy).
            if repair.is_file() and installed_ish:
                self._pending_repair_rid = rid
                self._activity("step", t("trust.regen_then_repair"))
                self._maybe_wine_dialog_hint("repair")
                handoff_repair = True
                self._run_async(repair, done_label=t("action.repair"), op="repair")
                return

            if repair.is_file():
                self._pending_repair_rid = rid
                self._activity("info", t("trust.force_repair_followup"))
        except OSError as exc:
            self._activity("error", t("trust.regen_fail") + f": {exc}")
            QMessageBox.critical(self, t("dialog.error"), str(exc))
            # Failed freigabe: drop pending so CTA can return to Freigeben.
            if self._pending_repair_rid == rid and not handoff_repair:
                self._pending_repair_rid = None
        finally:
            # Handoff: QProcess may still be Starting — never clear busy then.
            if handoff_repair and self._process is not None:
                pass
            elif self._busy and self._process is None:
                self._set_busy(False)
                # After freigeben without auto-repair: show „Jetzt aktualisieren“
                # immediately (enabled). Re-apply after busy clear so label sticks.
                if (
                    self._pending_repair_rid == rid
                    and self._selected is not None
                    and self._selected.rid == rid
                ):
                    self._apply_primary_cta(
                        self._selected,
                        can_launch=False,
                        running=False,
                        busy=False,
                    )

    def _assert_recipe_trusted(self, rid: str) -> None:
        """Force trust after Freigabe; clear UNTRUSTED mask with marker state."""
        for r in self.recipes:
            if r.rid != rid:
                continue
            r.trust_ok = True
            r.trust_reason = ""
            if r.state in (RecipeState.UNTRUSTED, RecipeState.CHECKING):
                st, detail, detected, version_warn, _actions = query_recipe_state_quick(
                    r.rid, r.meta
                )
                r.state = st
                if detail:
                    r.status_detail = detail
                if detected:
                    r.version_detected = detected
                if version_warn:
                    r.version_warning = version_warn
            break

    def _clear_pending_repair(self, rid: str) -> None:
        if self._pending_repair_rid == rid:
            self._pending_repair_rid = None
        if self._selected is not None and self._selected.rid == rid:
            idx = next(
                (i for i, r in enumerate(self.recipes) if r.rid == rid),
                -1,
            )
            if idx >= 0:
                self._on_select(idx)

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
                self._apply_discover_outcome(discover_recipes())
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
        clamp_restored_geometry(dlg, min_w=720, min_h=480)
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
        info = self._selected
        bundle_kw: dict = {}
        recipe_tag = ""
        data_root: Path | None = None
        if info is not None:
            data_root = resolve_data_root(info.meta, info.rid)
            recipe_tag = (info.meta.get("proton_ge_tag") or "").strip()
            bundle_kw["data_root"] = data_root
            bundle_kw["recipe_name"] = (info.meta.get("name") or "").strip()
            bundle_kw["version_guaranteed"] = (
                info.meta.get("version_guaranteed") or ""
            ).strip()
            bundle_kw["version_detected"] = (info.version_detected or "").strip()
            bundle_kw["recipe_proton_tag"] = recipe_tag
        report = collect_report_bundle(rid, self.session_id, **bundle_kw)
        clip = QApplication.clipboard()
        clip.setText(
            report_clipboard_text(
                rid,
                report,
                self.session_id,
                recipe_tag=recipe_tag,
                data_root=data_root,
            )
        )
        QDesktopServices.openUrl(
            QUrl(
                github_issue_url(
                    rid,
                    report,
                    recipe_tag=recipe_tag,
                    data_root=data_root,
                )
            )
        )
        box = QMessageBox(self)
        apply_fa_message_icon(box, "info")
        box.setWindowTitle(t("dialog.report_opened_title"))
        box.setText(
            t(
                "dialog.report_opened_body",
                name=report.name,
                folder=str(LOG_ROOT),
            )
        )
        open_folder = box.addButton(
            t("btn.open_log_folder"), QMessageBox.ButtonRole.ActionRole
        )
        copy_path = box.addButton(
            t("btn.copy_log_path"), QMessageBox.ButtonRole.ActionRole
        )
        box.addButton(QMessageBox.StandardButton.Ok)
        box.exec()
        clicked = box.clickedButton()
        if clicked == open_folder:
            self.open_log_folder()
        elif clicked == copy_path:
            clip.setText(str(report.resolve()))
            self._activity(
                "info", t("dialog.report_path_copied", path=str(report.resolve()))
            )
        self._activity("info", t("dialog.report_clipboard", name=report.name))

    def export_diagnose_zip(self) -> None:
        """Write allowlisted, sanitized logs into diagnose_<rid>_<ts>.zip under LOG_ROOT."""
        rid = self._selected.rid if self._selected else "launcher"
        if QMessageBox.question(
            self,
            t("dialog.diagnose_title"),
            t("dialog.diagnose_confirm"),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        info = self._selected
        data_root: Path | None = None
        recipe_name = ""
        recipe_tag = ""
        if info is not None:
            data_root = resolve_data_root(info.meta, info.rid)
            recipe_name = (info.meta.get("name") or "").strip()
            recipe_tag = (info.meta.get("proton_ge_tag") or "").strip()
        built = build_diagnose_zip(
            rid,
            self.session_id,
            data_root=data_root,
            recipe_name=recipe_name,
            recipe_proton_tag=recipe_tag,
        )
        if built is None:
            QMessageBox.information(
                self,
                t("dialog.diagnose_title"),
                t("dialog.diagnose_empty"),
            )
            return
        zip_path, count = built
        box = QMessageBox(self)
        apply_fa_message_icon(box, "info")
        box.setWindowTitle(t("dialog.diagnose_done_title"))
        box.setText(
            t(
                "dialog.diagnose_done_body",
                name=zip_path.name,
                count=count,
                folder=str(LOG_ROOT),
            )
        )
        open_folder = box.addButton(
            t("btn.open_log_folder"), QMessageBox.ButtonRole.ActionRole
        )
        copy_path = box.addButton(
            t("btn.copy_log_path"), QMessageBox.ButtonRole.ActionRole
        )
        box.addButton(QMessageBox.StandardButton.Ok)
        box.exec()
        clicked = box.clickedButton()
        clip = QApplication.clipboard()
        if clicked == open_folder:
            self.open_log_folder()
        elif clicked == copy_path:
            clip.setText(str(zip_path.resolve()))
            self._activity(
                "info",
                t("dialog.diagnose_path_copied", path=str(zip_path.resolve())),
            )
        self._activity("info", t("dialog.diagnose_activity", name=zip_path.name))
        self.populate_log_files()

    def _show_failure(self, done_label: str, code: int) -> None:
        box = QMessageBox(self)
        apply_fa_message_icon(box, "error")
        box.setWindowTitle(t("dialog.error"))
        box.setText(t("error.E_SCRIPT_FAILED", label=done_label, code=code))
        info = t("dialog.failure_info")
        err_path = getattr(self, "_last_error_log", "") or ""
        log_path = getattr(self, "_last_recipe_log", "") or ""
        extras: list[str] = []
        if err_path:
            extras.append(t("dialog.failure_error_log", path=err_path))
        if log_path:
            extras.append(t("dialog.failure_install_log", path=log_path))
        if extras:
            info = info + "\n\n" + "\n".join(extras)
        box.setInformativeText(info)
        open_folder = box.addButton(
            t("btn.open_log_folder"), QMessageBox.ButtonRole.ActionRole
        )
        copy_path = box.addButton(
            t("btn.copy_log_path"), QMessageBox.ButtonRole.ActionRole
        )
        report = box.addButton(
            t("btn.report_github"), QMessageBox.ButtonRole.ActionRole
        )
        box.addButton(QMessageBox.StandardButton.Ok)
        box.exec()
        clicked = box.clickedButton()
        if clicked == open_folder:
            self.open_log_folder()
        elif clicked == copy_path:
            path = err_path or log_path or str(LOG_ROOT)
            QApplication.clipboard().setText(path)
            self._activity("info", t("dialog.log_path_copied", path=path))
        elif clicked == report:
            self.report_bug()

    def _base_env(self) -> dict[str, str]:
        env = os.environ.copy()
        # Drop stale hook paths from parent shells/tests — scripts recompute them.
        for stale in ("CORE_DIR", "RECIPE_DIR", "RECIPE_YML", "RECIPE_HOOK_PROFILE"):
            env.pop(stale, None)
        env["PROJECT_ROOT"] = str(ROOT)
        env["LAUNCHER_GUI"] = "1"
        env["LAUNCHER_SESSION_ID"] = self.session_id
        loc = (get_locale() or "en").split("-", 1)[0].lower()
        env["RECIPE_UI_LANG"] = "de" if loc.startswith("de") else "en"
        if self._selected:
            env["RECIPE_ID"] = self._selected.rid
            rt = self._selected.meta.get("runtime", "proton-ge")
            if rt != "proton-ge":
                rt = "proton-ge"
            env["WINE_METHOD"] = rt
            env["RECIPE_RUNTIME"] = rt
            dr = resolve_data_root(
                self._selected.meta,
                self._selected.rid,
            )
            env["DATA_ROOT"] = str(dr)
            env["RECIPE_DATA_ROOT"] = str(dr)
            env["WINEPREFIX"] = f"{dr}/prefix"
            env["WINE_PREFIX"] = f"{dr}/prefix"
            rd = Path(self._selected.meta.get("_dir") or "")
            if rd.is_dir():
                env.update(
                    env_overrides_for_options(dr, load_options_from_recipe_dir(rd))
                )
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

        hidden = set(self._settings.hidden_recipe_ids or [])
        matched: list[tuple[int, RecipeInfo]] = []
        for i, info in enumerate(self.recipes):
            if info.rid in hidden:
                continue
            name = (info.meta.get("name") or info.rid).lower()
            side = sidebar_label_for_meta(info.meta, info.rid).lower()
            ver = (info.meta.get("version_guaranteed") or "").lower()
            if needle and needle not in name and needle not in info.rid.lower() and needle not in side and needle not in ver:
                continue
            matched.append((i, info))

        if needle and not matched:
            empty = QLabel(t("app.sidebar_search_empty", query=needle))
            empty.setObjectName("sidebarSearchEmpty")
            self.recipe_cards_layout.addWidget(empty)
            return

        overrides = dict(self._settings.recipe_category_overrides or {})
        grouped: dict[str, list[tuple[int, RecipeInfo]]] = {}
        for i, info in matched:
            cat = effective_category(info.rid, info.meta, overrides)
            grouped.setdefault(cat, []).append((i, info))

        order = list(self._settings.recipe_order or [])
        custom_cat_order = list(self._settings.custom_category_order or [])
        selected_rid = self._selected.rid if self._selected else None
        for cat in sort_categories(list(grouped.keys()), custom_cat_order):
            header = SidebarCategoryHeader(cat, label=category_label(cat))
            self.recipe_cards_layout.addWidget(header)
            cat_rows = sort_recipes_in_category(grouped[cat], order)
            side_texts = sidebar_card_texts(
                [(info.rid, info.meta) for _i, info in cat_rows]
            )
            for i, info in cat_rows:
                title, subtitle = side_texts.get(
                    info.rid,
                    (sidebar_label_for_meta(info.meta, info.rid), ""),
                )
                tip_bits = [info.meta.get("name") or info.rid]
                if subtitle:
                    tip_bits.append(subtitle)
                elif (info.meta.get("version_guaranteed") or "").strip():
                    tip_bits.append(info.meta["version_guaranteed"].strip())
                card = RecipeSidebarCard(
                    title,
                    info.state.value,
                    recipe_icon(info.meta),
                    recipe_id=info.rid,
                    subtitle=subtitle,
                )
                card.set_install_state(
                    info.state.value,
                    attention=_sidebar_attention(info),
                )
                card.setToolTip(" · ".join(tip_bits))
                card.apply_theme(getattr(self, "_theme", "dark"))
                card.set_selected(selected_rid is not None and info.rid == selected_rid)
                card.clicked.connect(
                    lambda idx=i: self._select_recipe_index(idx, user_initiated=True)
                )
                card.contextMenuRequested.connect(
                    lambda info=info: self._show_card_context_menu(info)
                )
                card.reorderRequested.connect(self._on_recipe_reorder)
                card.categoryDropRequested.connect(self._on_category_drop)
                self.recipe_cards_layout.addWidget(
                    card, 0, Qt.AlignmentFlag.AlignTop
                )
                self._recipe_cards.append((card, info))
        # No addStretch — list height is content-sized in _sync_sidebar_scroll_gap.
        QTimer.singleShot(0, self._sync_sidebar_scroll_gap)
        if self._selected is None:
            QTimer.singleShot(
                0, lambda: self._apply_content_window_height(allow_grow=False)
            )

    def _select_recipe_index(self, row: int, *, user_initiated: bool = False) -> None:
        if row < 0 or row >= len(self.recipes):
            return
        self._set_home_btn_active(False)
        if hasattr(self, "_detail_stack"):
            self._detail_stack.setCurrentIndex(1)
        self._selected_index = row
        for i, (card, info) in enumerate(self._recipe_cards):
            card.set_selected(info.rid == self.recipes[row].rid)
        self._on_select(row)
        QTimer.singleShot(0, lambda: self._apply_content_window_height(allow_grow=True))
        if user_initiated:
            QTimer.singleShot(0, self._maybe_steam_medicine_prompt)

    def _start_deferred_trust_verify(self) -> None:
        """After first paint: hash recipes + marker status (no validate.sh)."""
        self._begin_status_refresh(full_validate=False, announce=False)

    def refresh_statuses(self) -> None:
        self._begin_status_refresh(full_validate=True, announce=True)

    def _begin_status_refresh(self, *, full_validate: bool, announce: bool) -> None:
        if self._status_thread is not None and self._status_thread.isRunning():
            # Coalesce: prefer a pending full validate over a quick check.
            prev = self._status_refresh_pending
            if prev is None:
                self._status_refresh_pending = (full_validate, announce)
            else:
                self._status_refresh_pending = (
                    prev[0] or full_validate,
                    prev[1] or announce,
                )
            return
        self._status_refresh_announce = announce
        if announce:
            self._activity("info", t("menu.refresh_busy"))
        if hasattr(self, "action_refresh"):
            self.action_refresh.setEnabled(False)
        env = self._base_env()
        thread = QThread(self)
        worker = _RecipeStatusWorker(env, full_validate=full_validate)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.finished.connect(
            self._on_status_refresh_finished, Qt.ConnectionType.QueuedConnection
        )
        worker.failed.connect(
            self._on_status_refresh_failed, Qt.ConnectionType.QueuedConnection
        )
        worker.finished.connect(thread.quit)
        worker.failed.connect(thread.quit)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        thread.finished.connect(self._on_status_thread_finished)
        self._status_thread = thread
        self._status_worker = worker
        thread.start()

    def _on_status_thread_finished(self) -> None:
        self._status_thread = None
        self._status_worker = None
        if hasattr(self, "action_refresh"):
            self.action_refresh.setEnabled(True)
        pending = self._status_refresh_pending
        if pending is not None:
            self._status_refresh_pending = None
            full_validate, announce = pending
            QTimer.singleShot(
                0,
                lambda: self._begin_status_refresh(
                    full_validate=full_validate, announce=announce
                ),
            )

    def _on_status_refresh_failed(self, message: str) -> None:
        ev = LogEvent(
            level="warn",
            code=E_STATUS_QUERY,
            message_key="error.E_STATUS_QUERY",
            detail=message,
        )
        self._activity("warn", ev.display_text())
        # Don't leave the UI stuck on CHECKING — fall back to sync trust verify.
        try:
            outcome = _collect_recipe_statuses(self._base_env(), full_validate=False)
            self._on_status_refresh_finished(outcome)
        except Exception as exc:  # noqa: BLE001
            _debug_log(f"status fallback failed: {exc}")
            self._activity("warn", t("status.query_error", error=str(exc)))

    def _route_trust_notices(
        self, *, manifest_sync: str = "", trust_log: str = ""
    ) -> None:
        """Trust-Hinweise nur am gewählten Rezept (Statusleiste), nie global im Vorgang."""
        selected_rid = self._selected.rid if self._selected else None
        if not selected_rid:
            return
        if trust_log:
            for line in trust_log.splitlines():
                line = line.strip()
                if not line:
                    continue
                rid = line.split(":", 1)[0].strip()
                if rid == selected_rid:
                    self._flash_status(t("trust.hidden_warn", line=line))
                    break
        if manifest_sync and self._selected and _recipe_is_untrusted(self._selected):
            self._flash_status(t("trust.resync_needed", detail=manifest_sync))

    def _apply_discover_outcome(self, outcome: DiscoverOutcome) -> None:
        self.recipes = outcome.recipes
        self._route_trust_notices(
            manifest_sync=outcome.manifest_sync or "",
            trust_log=outcome.trust_log or "",
        )

    def _on_status_refresh_finished(self, refreshed: object) -> None:
        if not isinstance(refreshed, DiscoverOutcome):
            return
        self.recipes = refreshed.recipes
        # Stale status workers started before Freigabe can re-inject UNTRUSTED.
        # Pending repair must keep trust + CTA on „Jetzt aktualisieren“.
        pending = self._pending_repair_rid
        if pending:
            self._assert_recipe_trusted(pending)
        prev = self._selected_index
        was_home = self._selected is None
        self._populate_list()
        if was_home or prev < 0:
            self._show_home()
        elif self.recipes:
            self._select_recipe_index(prev if 0 <= prev < len(self.recipes) else 0)
        else:
            self._show_home()
        self._route_trust_notices(
            manifest_sync=refreshed.manifest_sync or "",
            trust_log=refreshed.trust_log or "",
        )
        if self._status_refresh_announce:
            self._activity("info", t("menu.refresh_done", n=len(self.recipes)))

    def _on_select(self, row: int) -> None:
        if row < 0 or row >= len(self.recipes):
            self._selected = None
            self.path_label.setText("")
            self._current_data_root = None
            self.open_path_btn.setEnabled(False)
            self.open_path_btn.setToolTip(t("tooltip.open_data_root"))
            self._sync_medizin_button()
            return
        self._selected = self.recipes[row]
        info = self._selected
        meta = info.meta
        dr = resolve_data_root(meta, info.rid)

        # Window/taskbar icon stays Rezeptor; header shows the recipe icon.
        if REZEPTOR_ICON.is_file():
            self.setWindowIcon(QIcon(str(REZEPTOR_ICON)))
        icon = recipe_icon(meta)
        pix = icon.pixmap(64, 64)
        if not pix.isNull():
            self.icon_label.setPixmap(rounded_pixmap(pix, 12))
        self._set_header_watermark(icon)
        self.name_label.setText(meta.get("name", info.rid))
        self._update_status_pills(info)
        self._update_version_header(info)
        self._set_path_row(dr, info)
        self._update_workspace_chips(info, dr)
        self._update_health_chip(info)
        self._update_progress_chip()
        self._remember_last_recipe(info.rid)

        checking = _recipe_is_checking(info)
        untrusted = _recipe_is_untrusted(info)
        pending_repair = self._pending_repair_rid == info.rid
        # After Freigabe/Medizin: keep a short stable line — long trust hints
        # + header refit made the primary CTA appear to “hop”.
        if pending_repair and not checking:
            hint = t("medizin.apply_repair_hint")
            self._status_detail_base = hint
            self.status_detail_label.setText(hint)
            self.status_detail_label.setVisible(True)
            self._info_raw = recipe_info_text(info.rid, Path(meta["_dir"]))
            self._render_info_markdown()
            can_launch = self._can_launch_recipe(info, dr)
            running = recipe_process_running(info.rid, info.meta)
            self._apply_primary_cta(
                info, can_launch=can_launch, running=running, busy=self._busy
            )
            self._sync_medizin_button()
            self._refresh_running_indicators()
            if info.state == RecipeState.NOT_INSTALLED and not self._busy:
                self._set_content_tab("overview")
            return
        if checking or untrusted:
            raw = info.trust_reason or info.status_detail or "?"
            reason_suffix = "checking" if checking else friendly_trust_reason(raw)
            reason_key = f"trust.reason_{reason_suffix}"
            reason = t(reason_key)
            if reason == reason_key:
                reason = t("trust.reason_changed")
            detail = t("trust.detail", reason=reason)
            if not checking:
                if (ROOT / ".git").is_dir():
                    detail = f"{detail}\n{t('trust.hint_dev')}"
                else:
                    detail = f"{detail}\n{t('trust.hint_user')}"
            self.status_detail_label.setText(detail)
            self.status_detail_label.setVisible(True)
            self._status_detail_base = detail
            self._info_raw = recipe_info_text(info.rid, Path(meta["_dir"]))
            self._render_info_markdown()
            # Pflicht-Freigabe = Kupfer-Primary (wie „Jetzt aktualisieren“), kein Nebenbutton.
            self._apply_primary_cta(
                info, can_launch=False, running=False, busy=self._busy
            )
            self._sync_medizin_button()
            self._refresh_running_indicators()
            self._schedule_header_refit()
            if info.state == RecipeState.NOT_INSTALLED and not self._busy:
                self._set_content_tab("overview")
            return

        if self._busy and self._busy_belongs_to_selected():
            detail = t("status.busy")
        elif self._busy:
            detail = t("status.busy_other", name=self._busy_recipe_label())
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
        self._schedule_header_refit()
        self._info_raw = recipe_info_text(info.rid, Path(meta["_dir"]))
        self._render_info_markdown()

        can_launch = self._can_launch_recipe(info, dr)
        running = recipe_process_running(info.rid, info.meta)
        self._apply_primary_cta(
            info, can_launch=can_launch, running=running, busy=self._busy
        )
        self._sync_medizin_button()
        if (not self._busy) and info.state == RecipeState.PARTIAL and can_launch:
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
        # Laufender Install/Repair gehört nur zu einem Rezept — anderswo Übersicht, nicht Vorgang.
        if self._busy:
            if self._busy_belongs_to_selected():
                self._switch_to_progress_tab()
            else:
                self._set_content_tab("overview")
        elif info.state == RecipeState.NOT_INSTALLED:
            # Empty Vorgang is noise before the first install — start on Übersicht.
            self._set_content_tab("overview")

    def _busy_belongs_to_selected(self) -> bool:
        return self._ops._busy_belongs_to_selected()

    def _busy_recipe_label(self) -> str:
        return self._ops._busy_recipe_label()

    def _refresh_running_indicators(self) -> None:
        for card, info in list(self._recipe_cards):
            try:
                running = recipe_process_running(info.rid, info.meta)
            except Exception as exc:  # noqa: BLE001 — Flatpak /proc quirks
                _debug_log(f"recipe_process_running({info.rid}): {exc}")
                continue
            was = self._running_prev.get(info.rid)
            self._running_prev[info.rid] = running
            # True→False: App beendet — unter Vorgang melden
            if was is True and not running:
                self._on_recipe_process_stopped(info)
            elif was is False and running:
                self._on_recipe_process_started(info)
            elif was is None and running:
                self._running_prev[info.rid] = True
            try:
                card.set_running(running)
                card.set_install_state(
                    info.state.value,
                    attention=_sidebar_attention(info),
                )
            except RuntimeError:
                # SIP: sidebar card already deleted mid-refresh
                continue
            if not (self._selected and self._selected.rid == info.rid):
                continue
            self._update_status_pills(info)
            base = getattr(self, "_status_detail_base", "") or ""
            if not base.strip() or base.strip() == " ":
                base = self._action_hint_for(info) or " "
            try:
                self.status_detail_label.setText(base if base.strip() else " ")
                self.status_detail_label.setVisible(bool(base.strip()))
            except RuntimeError:
                continue
            if not self._busy:
                dr = resolve_data_root(info.meta, info.rid)
                self._apply_primary_cta(
                    info,
                    can_launch=self._can_launch_recipe(info, dr),
                    running=running,
                    busy=False,
                )

    def _on_recipe_process_started(self, info: RecipeInfo) -> None:
        name = str(info.meta.get("name") or info.rid)
        watched = self._watched_launch_rid == info.rid
        selected = bool(self._selected and self._selected.rid == info.rid)
        if not (watched or selected):
            return
        if not self._busy:
            self.step_label.setText(t("status.app_running_step", name=name))
            self.step_label.setStyleSheet("")
        self._activity("ok", t("status.app_running_named", name=name))

    def _on_recipe_process_stopped(self, info: RecipeInfo) -> None:
        name = str(info.meta.get("name") or info.rid)
        watched = self._watched_launch_rid == info.rid
        selected = bool(self._selected and self._selected.rid == info.rid)
        if watched:
            self._watched_launch_rid = None
        skip_cleanup = info.rid in self._skip_exit_cleanup
        if skip_cleanup:
            self._skip_exit_cleanup.discard(info.rid)
        if not (watched or selected):
            # Still allow orphan cleanup when the recipe closed in the background.
            if not skip_cleanup:
                self._schedule_exit_cleanup(info)
            return
        if not self._busy:
            self.step_label.setText(t("status.app_stopped_step", name=name))
            self.step_label.setStyleSheet("")
        self._activity("info", t("status.app_stopped", name=name))
        self._switch_to_progress_tab()
        if not skip_cleanup:
            self._schedule_exit_cleanup(info)

    def _schedule_exit_cleanup(self, info: RecipeInfo) -> None:
        """After natural app exit, run recipe cleanup-orphans.sh if present (issue #10)."""
        rd = Path(info.meta.get("_dir") or "")
        script = rd / "cleanup-orphans.sh"
        if not script.is_file():
            return
        rid = info.rid
        # Activity is recipe-scoped UI — only when this recipe is selected.
        if self._selected and self._selected.rid == rid:
            self._activity(
                "info", t("status.exit_cleanup", name=str(info.meta.get("name") or rid))
            )
        QTimer.singleShot(300, lambda r=rid, s=script: self._spawn_exit_cleanup(r, s))

    def _spawn_exit_cleanup(self, rid: str, script: Path) -> None:
        if rid in self._skip_exit_cleanup:
            return
        info = next((i for i in self.recipes if i.rid == rid), None)
        if info is None:
            return
        # Relaunch raced cleanup — leave the new session alone.
        if recipe_process_running(rid, info.meta):
            return
        env = self._base_env()
        dr = resolve_data_root(info.meta, rid)
        env["RECIPE_ID"] = rid
        env["RECIPE_DIR"] = str(Path(info.meta.get("_dir") or script.parent))
        # Must match DATA_ROOT — stale RECIPE_DATA_ROOT from _base_env (other
        # selected recipe) would rewrite that recipe's data_root.path via recipe.sh.
        env["DATA_ROOT"] = str(dr)
        env["RECIPE_DATA_ROOT"] = str(dr)
        env["SCR_PATH"] = env["DATA_ROOT"]
        env["WINE_PREFIX"] = str(recipe_wine_prefix(info.meta, rid))
        env["WINEPREFIX"] = env["WINE_PREFIX"]
        log_path = LOG_ROOT / f"cleanup_{rid}_{self.session_id[:8]}.log"
        LOG_ROOT.mkdir(parents=True, exist_ok=True)
        try:
            log_f = open(log_path, "a", encoding="utf-8")  # noqa: SIM115
            log_f.write(f"\n--- {rid} exit cleanup ---\n")
            log_f.flush()
            subprocess.Popen(
                ["bash", str(script)],
                cwd=str(ROOT),
                env=env,
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=log_f,
                stderr=subprocess.STDOUT,
            )
        except OSError as exc:
            _debug_log(f"exit cleanup spawn failed for {rid}: {exc}")
            if self._selected and self._selected.rid == rid:
                self._activity("warn", t("status.exit_cleanup_fail", name=rid))
            return
        if self._selected and self._selected.rid == rid:
            self._activity("info", t("status.exit_cleanup_log", name=log_path.name))

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
        elif info.state == RecipeState.UNTRUSTED or _recipe_is_untrusted(info):
            self.status_pill.set_content(t("badge.untrusted"), "#d9a441")
            self.status_pill.setVisible(True)
        elif info.state == RecipeState.CHECKING or _recipe_is_checking(info):
            self.status_pill.set_content(t("badge.checking"), "#9ca3af")
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
        # Per-recipe pin (yml / Medizin), not the global AppImage default alone.
        ge_tag = effective_proton_ge_tag(
            recipe_tag=(meta.get("proton_ge_tag") or "").strip(),
            data_root=resolve_data_root(meta, info.rid),
        )
        proton_label = proton_ge_badge_label(ge_tag)
        if tag == "system" and steam_id:
            self.proton_pill.set_content(t("badge.runtime_steam"), COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_steam"))
        elif tag == "system":
            self.proton_pill.set_content(t("badge.runtime_system"), COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_system"))
        elif steam_id:
            self.proton_pill.set_content(proton_label, COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(
                t("tooltip.runtime_proton_steam", tag=ge_tag)
            )
        else:
            self.proton_pill.set_content(proton_label, COLOR_EXPERIMENTAL)
            self.proton_pill.setToolTip(t("tooltip.runtime_proton", tag=ge_tag))
        # Arrow + tooltip: WhatsThisCursor showed a stray "?" on some desktops.
        self.proton_pill.setCursor(Qt.CursorShape.ArrowCursor)

        tested_disp = format_tested_on_display(str(meta.get("tested_on") or ""))
        if tested_disp:
            self.tested_on_pill.set_content(
                t("badge.tested_on", date=tested_disp), MUTED
            )
            self.tested_on_pill.setToolTip(
                t("tooltip.tested_on", date=tested_disp)
            )
        else:
            self.tested_on_pill.set_content("", MUTED)
            self.tested_on_pill.setToolTip("")

        author = (meta.get("author") or "").strip()
        if author:
            self.author_pill.set_content(
                t("badge.author", author=author), MUTED
            )
        else:
            self.author_pill.set_content("", MUTED)

    def _set_path_row(self, dr: Path, info: RecipeInfo | None = None) -> None:
        """HEADER: Daten + Quelle/Ziel (installiert) or pending Quelle/Ziel."""
        self._current_data_root = dr
        self.path_label.setVisible(True)
        self.open_path_btn.setVisible(True)
        usable = data_root_browsable(dr)
        tok = theme_tokens(getattr(self, "_theme", None))
        path_color = tok["muted"]
        if info is not None and (
            usable
            or info.state in (RecipeState.INSTALLED, RecipeState.PARTIAL)
            or (dr / "recipe.env").is_file()
            or (dr / "portable.env").is_file()
        ):
            self.path_label.setText(installed_paths_text(info.meta, info.rid, dr))
        elif info is not None and info.state == RecipeState.NOT_INSTALLED:
            pending = load_recipe_install_env(self._settings, info.rid)
            if has_recipe_install_source(pending):
                self.path_label.setText(
                    pending_paths_text(info.meta, pending or {}, dr)
                )
                path_color = tok["tested"]
            else:
                self.path_label.setText("")
        else:
            self.path_label.setText(str(dr) if usable else "")
        self._style_secondary_label(self.path_label, path_color, size_px=11)
        has_path = bool((self.path_label.text() or "").strip())
        self.path_label.setVisible(has_path)
        self.open_path_btn.setVisible(has_path or usable)
        self.open_path_btn.setEnabled(usable)
        meta = info.meta if usable else None
        self.open_path_btn.setToolTip(
            open_data_root_tooltip(meta, dr)
            if usable
            else t("tooltip.open_data_root_missing")
        )
        self._schedule_header_refit()

    def _path_clipboard_targets(self) -> list[tuple[str, str]]:
        """(label, path) for path context menu — data root first."""
        out: list[tuple[str, str]] = []
        dr = getattr(self, "_current_data_root", None)
        if dr is not None:
            out.append((t("tooltip.path_data"), str(dr)))
        text = (self.path_label.text() or "").strip()
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            if ": " in line:
                label, _, path = line.partition(": ")
                path = path.strip()
                if not path:
                    continue
                if any(path == p for _l, p in out):
                    continue
                out.append((label.strip(), path))
                continue
            if ("/" in line or line.startswith("~")) and not any(
                line == p for _l, p in out
            ):
                out.append((t("tooltip.path_data"), line))
        return out

    def _recipe_context_text(self) -> str:
        """Titel, Version, Status, Runtime, Pfade — für „Daten kopieren“."""
        info = self._selected
        if info is None:
            return ""
        meta = info.meta
        name = (meta.get("name") or info.rid).strip()
        lines = [
            f"{t('logs.ctx_title')}: {name}",
            f"{t('logs.ctx_id')}: {info.rid}",
        ]
        guaranteed = (meta.get("version_guaranteed") or "").strip()
        if guaranteed:
            lines.append(f"{t('logs.ctx_version_guaranteed')}: {guaranteed}")
        detected = (info.version_detected or "").strip()
        if detected:
            lines.append(f"{t('logs.ctx_version_detected')}: {detected}")
        status = ""
        if hasattr(self, "status_pill") and self.status_pill.isVisible():
            status = (self.status_pill.text() or "").strip()
        if status:
            lines.append(f"{t('logs.ctx_status')}: {status}")
        runtime = ""
        if hasattr(self, "proton_pill"):
            runtime = (self.proton_pill.text() or "").strip()
        if not runtime:
            runtime = describe_runtime_for_report()
        lines.append(f"{t('logs.ctx_runtime')}: {runtime}")
        lines.append(f"{t('logs.ctx_launcher')}: v{read_version()}")
        author = (meta.get("author") or "").strip()
        if author:
            lines.append(f"{t('logs.ctx_author')}: {author}")
        lines.append(f"{t('logs.ctx_distro')}: {detect_distro()}")
        for label, path in self._path_clipboard_targets():
            lines.append(f"{label}: {path}")
        return "\n".join(lines)

    def _copy_path_to_clipboard(self, path: str) -> None:
        path = (path or "").strip()
        if not path:
            return
        QApplication.clipboard().setText(path)
        self._activity("info", t("logs.path_copied", path=path))

    def _copy_recipe_context(self) -> None:
        text = self._recipe_context_text()
        if not text:
            return
        QApplication.clipboard().setText(text)
        self._activity("info", t("status.data_copied"))

    def _show_title_context_menu(self, pos) -> None:  # noqa: ANN001
        text = (self.name_label.text() or "").strip()
        if not text:
            return
        # Immer QMenu (Host-QSS) — RoundMenu/LabelContextMenu doppelt und falsch.
        menu = QMenu(self)
        selected = ""
        if hasattr(self.name_label, "selectedText"):
            selected = (self.name_label.selectedText() or "").strip()
        if selected:
            self._add_menu_action(
                menu,
                t("logs.copy_selection"),
                lambda _c=False, p=selected: self._copy_path_to_clipboard(p),
            )
        self._add_menu_action(
            menu,
            t("logs.copy_title"),
            lambda _c=False, p=text: self._copy_path_to_clipboard(p),
        )
        self._add_menu_action(
            menu,
            t("status.copy_data"),
            lambda _c=False: self._copy_recipe_context(),
        )
        menu.exec(self.name_label.mapToGlobal(pos))

    def _show_path_context_menu(self, pos) -> None:  # noqa: ANN001
        targets = self._path_clipboard_targets()
        menu = QMenu(self)
        selected = ""
        if hasattr(self.path_label, "selectedText"):
            selected = (self.path_label.selectedText() or "").strip()
        if selected:
            self._add_menu_action(
                menu,
                t("logs.copy_selection"),
                lambda _c=False, p=selected: self._copy_path_to_clipboard(p),
            )
            menu.addSeparator()
        self._add_menu_action(
            menu,
            t("status.copy_data"),
            lambda _c=False: self._copy_recipe_context(),
        )
        if targets:
            menu.addSeparator()
        for label, path in targets:
            title = t("status.copy_labeled_path", label=label)
            self._add_menu_action(
                menu,
                title,
                lambda _c=False, p=path: self._copy_path_to_clipboard(p),
            )
        if not targets and not selected:
            text = (self.path_label.text() or "").strip()
            if text and text != self._recipe_context_text():
                self._add_menu_action(
                    menu,
                    t("logs.copy_path"),
                    lambda _c=False, p=text: self._copy_path_to_clipboard(p),
                )
        elif len(targets) > 1:
            all_text = "\n".join(p for _l, p in targets)
            self._add_menu_action(
                menu,
                t("status.copy_all_paths"),
                lambda _c=False, p=all_text: self._copy_path_to_clipboard(p),
            )
        menu.exec(self.path_label.mapToGlobal(pos))

    def _set_header_watermark(self, icon: QIcon | None) -> None:
        """Store recipe/home icon for the right-side faded header backdrop."""
        if icon is None or icon.isNull():
            self._header_watermark_src = None
            wm = getattr(self, "_header_watermark", None)
            if wm is not None:
                wm.clear()
                wm.setVisible(False)
            return
        # High-res source; scaled/faded on layout.
        pix = icon.pixmap(256, 256)
        if pix.isNull():
            pix = icon.pixmap(128, 128)
        self._header_watermark_src = pix if not pix.isNull() else None
        self._layout_header_watermark()

    def _layout_header_watermark(self) -> None:
        wm = getattr(self, "_header_watermark", None)
        header = getattr(self, "_header", None)
        if wm is None or header is None:
            return
        hr = header.rect()
        if hr.width() < 80 or hr.height() < 24:
            return
        # Full header bounds — radius clip is baked into the pixmap.
        wm.setGeometry(hr)
        src = getattr(self, "_header_watermark_src", None)
        if src is None or src.isNull():
            wm.clear()
            wm.setVisible(False)
            return
        wm.setPixmap(
            faded_header_watermark(
                src, hr.size(), radius=_HEADER_CARD_RADIUS
            )
        )
        wm.setVisible(True)
        wm.lower()
        # Keep interactive chrome above the backdrop.
        for w in (
            getattr(self, "icon_label", None),
            getattr(self, "name_label", None),
            getattr(self, "version_info_btn", None),
            getattr(self, "open_path_btn", None),
            getattr(self, "status_pill", None),
            getattr(self, "version_pill", None),
            getattr(self, "tested_pill", None),
            getattr(self, "proton_pill", None),
            getattr(self, "tested_on_pill", None),
            getattr(self, "author_pill", None),
            getattr(self, "path_label", None),
            getattr(self, "status_detail_label", None),
        ):
            if w is not None:
                w.raise_()

    def _schedule_header_refit(self) -> None:
        """Word-wrap QLabels need a deferred height pass after layout width is known."""
        QTimer.singleShot(0, self._refit_header_labels)

    def _refit_header_labels(self) -> None:
        header = getattr(self, "_header", None)
        if header is None:
            return
        for lab in (self.path_label, self.status_detail_label):
            if lab is None:
                continue
            if not lab.isVisible() or not lab.wordWrap() or not (lab.text() or "").strip():
                lab.setMinimumHeight(0)
                continue
            w = lab.width()
            if w < 40:
                # First layout pass: estimate from header minus icon/margins
                w = max(header.width() - 110, 200)
            h = lab.heightForWidth(w)
            if h > 0:
                lab.setMinimumHeight(h)
            else:
                lab.setMinimumHeight(0)
        header.updateGeometry()
        parent = header.parentWidget()
        if parent is not None:
            parent.updateGeometry()
        self._layout_header_watermark()

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:  # noqa: N802
        if (
            obj is getattr(self, "_header", None)
            and event.type() == QEvent.Type.Resize
        ):
            self._refit_header_labels()
            self._layout_header_watermark()
        scroll = getattr(self, "recipe_cards_scroll", None)
        if (
            scroll is not None
            and obj is scroll.viewport()
            and event.type() == QEvent.Type.Resize
            and not getattr(self, "_sidebar_syncing", False)
        ):
            self._sync_sidebar_scroll_gap()
        if (
            obj is getattr(self, "_sidebar", None)
            and event.type() == QEvent.Type.Resize
            and not getattr(self, "_sidebar_syncing", False)
        ):
            self._sync_sidebar_scroll_gap()
        return super().eventFilter(obj, event)

    def _action_hint_for(self, info: RecipeInfo) -> str:
        """Kurzer Hinweis — ergänzt Badge + CTA, ohne zu wiederholen."""
        if self._busy:
            return t("status.busy")
        if info.state == RecipeState.PARTIAL:
            return t("status.hint_partial")
        if info.state == RecipeState.NOT_INSTALLED:
            pending = load_recipe_install_env(self._settings, info.rid)
            if has_recipe_install_source(pending):
                return t("status.hint_source_ready")
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
        if not data_root_browsable(dr):
            self.open_path_btn.setEnabled(False)
            self.open_path_btn.setToolTip(t("tooltip.open_data_root_missing"))
            self._flash_status(t("tooltip.open_data_root_missing"))
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(dr.resolve())))

    def _maybe_offer_post_config(self) -> None:
        """Nach Halo-Install: Spielordner für Nickname/Sprache anbieten."""
        path = (self._post_config_dir or "").strip()
        self._post_config_dir = None
        if not path:
            return
        p = Path(path)
        if not p.is_dir():
            return
        box = QMessageBox(self)
        apply_fa_message_icon(box, "info")
        box.setWindowTitle(t("status.post_config_title"))
        box.setText(t("status.post_config_body"))
        open_btn = box.addButton(
            t("status.post_config_open"), QMessageBox.ButtonRole.AcceptRole
        )
        box.addButton(t("status.post_config_later"), QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if box.clickedButton() is open_btn:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(p.resolve())))

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
        self._sync_sidebar_busy_progress()
        if pct >= 100 and hasattr(self, "progress_busy"):
            self.progress_busy.stop()

    def _sync_sidebar_busy_progress(self) -> None:
        """Kupfer-Streifen nur auf der Sidebar-Karte des laufenden Rezepts."""
        rid = self._busy_rid if self._busy else ""
        pct = self._progress_pct if self._busy else None
        for card, info in list(getattr(self, "_recipe_cards", []) or []):
            try:
                if rid and info.rid == rid:
                    card.set_busy_progress(pct if pct is not None else 0)
                else:
                    card.set_busy_progress(None)
            except RuntimeError:
                continue

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
            line = sanitize_log_text(strip_ansi(part))
            if not line or SPINNER_RE.match(line):
                continue

            if line == "RECIPE_ERROR_LOG_TAIL_BEGIN":
                self._error_log_tail_mode = True
                self._activity("warn", t("status.error_log_tail"))
                continue
            if line == "RECIPE_ERROR_LOG_TAIL_END":
                self._error_log_tail_mode = False
                continue
            if getattr(self, "_error_log_tail_mode", False):
                self._append_raw_log(line)
                continue

            if line.startswith("RECIPE_ERROR_LOG="):
                self._last_error_log = line.split("=", 1)[-1].strip()
                continue
            if line.startswith("RECIPE_LOG_FILE="):
                self._last_recipe_log = line.split("=", 1)[-1].strip()
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
                elif tag == "info" and msg.startswith("POST_CONFIG:"):
                    path = msg.split(":", 1)[-1].strip()
                    if path:
                        self._post_config_dir = path
                    continue
                self._activity(tag, msg)
                continue

            human = humanize_log_line(line)
            if human is None:
                continue

            # Adobe/Wine „Progress: N%“ (oft \r) NICHT als Gesamtfortschritt —
            # sonst springt die Bar wild und flackert gegen @progress:-Tags.
            if PROGRESS_RE.search(line):
                if human and not human.startswith("Progress:"):
                    self._append_raw_log(human)
                continue

            if line.startswith("═══") or line.startswith("RECIPE_"):
                continue
            if "AKTION:" in line or line.startswith("USER:"):
                msg = line.replace("AKTION:", "").replace("USER:", "").strip()
                self._activity("warn", msg)
                self._set_step_text(msg)
                continue

            # Konsolen-/Rohzeilen → nur Live-Ausgabe (kein zweites Mal in Schritte)
            self._append_raw_log(human)

    def _append_raw_log(self, line: str) -> None:
        buf = self._raw_log_buffer
        if len(buf) >= _RAW_LOG_MAX_LINES:
            del buf[: len(buf) - _RAW_LOG_MAX_LINES + 1]
        buf.append(line)
        self.raw_log.append(line)
        self._fit_progress_panels()

    def _flash_status(self, text: str, ms: int = 4000) -> None:
        """Visible on every tab (status bar). Activity list is Vorgang-only."""
        text = (text or "").strip()
        if not text:
            return
        sb = self.statusBar()
        if sb is not None:
            sb.showMessage(text, ms)

    def _activity_fg(self, kind: str) -> str:
        """Foreground for Schritte rows — always from active theme tokens."""
        tok = theme_tokens(getattr(self, "_theme", None))
        return {
            "ok": tok["tested"],
            "error": tok["danger"],
            "warn": tok["experimental"],
            "step": tok["accent"],
            "info": tok["muted"],
            "log": tok["muted"],
        }.get(kind, tok["fg"])

    def _restyle_activity_list(self) -> None:
        """Re-tint existing Schritte rows after a theme switch."""
        if not hasattr(self, "activity_list"):
            return
        for i in range(self.activity_list.count()):
            item = self.activity_list.item(i)
            if item is None:
                continue
            kind = item.data(Qt.ItemDataRole.UserRole)
            if not isinstance(kind, str) or not kind:
                kind = "info"
            fg = self._activity_fg(kind)
            item.setForeground(QColor(fg))
            icon = fa_icon(kind, color=fg)
            if icon is not None and item.flags() != Qt.ItemFlag.NoItemFlags:
                item.setIcon(icon)

    def _show_activity_empty_hint(self) -> None:
        """Friendly placeholder when the Schritte list has no real events yet."""
        self.activity_list.clear()
        item = QListWidgetItem(t("progress.empty_hint"))
        item.setFlags(Qt.ItemFlag.NoItemFlags)
        item.setData(Qt.ItemDataRole.UserRole, "info")
        item.setForeground(QColor(self._activity_fg("info")))
        self.activity_list.addItem(item)
        self._activity_empty_shown = True
        self._fit_progress_panels()

    def _clear_activity_list(self) -> None:
        """Clear Schritte for a new run (no empty hint until idle again)."""
        self.activity_list.clear()
        self._activity_empty_shown = False
        self._fit_progress_panels()

    def _activity(self, kind: str, text: str) -> None:
        text = (text or "").strip()
        if not text:
            return
        if getattr(self, "_activity_empty_shown", False):
            self.activity_list.clear()
            self._activity_empty_shown = False
        key = (kind, text)
        # output::progress emits @step; callers sometimes also call output::step
        if kind == "step" and self._last_activity_key == key:
            return
        if kind in ("step", "ok", "warn", "error"):
            self._last_activity_key = key
        fg = self._activity_fg(kind)
        item = QListWidgetItem(text)
        item.setToolTip(text)
        item.setData(Qt.ItemDataRole.UserRole, kind)
        icon = fa_icon(kind, color=fg)
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
        item.setForeground(QColor(fg))
        self.activity_list.addItem(item)
        self.activity_list.scrollToBottom()
        self._fit_progress_panels()
        if kind in ("step", "ok", "warn", "error"):
            style = f"color: {fg}; font-weight: 600;"
            self._set_step_text(text, style=style)
        if kind == "info":
            self._flash_status(text)

    def _set_busy(self, busy: bool, *, rid: str | None = None) -> None:
        return self._ops._set_busy(busy, rid=rid)

    def _sync_cancel_install_btn(self) -> None:
        return self._ops._sync_cancel_install_btn()

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

    def _subprocess_running(self) -> bool:
        return self._ops._subprocess_running()

    def _reject_if_subprocess_busy(self) -> bool:
        return self._ops._reject_if_subprocess_busy()

    def _require_recipe(self) -> Path | None:
        if self._reject_if_subprocess_busy():
            return None
        if not self._selected:
            return None
        return Path(self._selected.meta["_dir"])

    def _require_trusted_recipe(self) -> Path | None:
        """Deny script runners when recipe integrity check failed (handler-level)."""
        rd = self._require_recipe()
        if rd is None:
            return None
        if self._selected and _recipe_is_checking(self._selected):
            QMessageBox.information(
                self,
                t("trust.title"),
                t("trust.detail", reason=t("trust.reason_checking")),
            )
            return None
        if self._selected and _recipe_is_untrusted(self._selected):
            QMessageBox.warning(
                self,
                t("trust.title"),
                t("trust.detail", reason=self._selected.trust_reason or "?"),
            )
            return None
        # Re-verify on disk before async/launch (catches tamper after selection).
        if self._selected and rd is not None and not rezeptor_dev_mode():
            ok, reason = verify_recipe_trust(rd, _recipe_manifest_path(rd))
            if not ok:
                self._selected.trust_ok = False
                self._selected.trust_reason = reason or ""
                self._selected.state = RecipeState.UNTRUSTED
                QMessageBox.warning(
                    self,
                    t("trust.title"),
                    t("trust.detail", reason=reason or "?"),
                )
                return None
        return rd

    def _finish_archive_password_files(
        self, extra: dict[str, str] | None, *, success: bool
    ) -> None:
        return self._ops._finish_archive_password_files(extra, success=success)

    def _run_async(
        self,
        script: Path,
        extra: dict[str, str] | None = None,
        done_label: str = "",
        dialog: bool = True,
        on_success: Callable[[], None] | None = None,
        *,
        op: str = "",
        recipe_dir: Path | None = None,
        script_args: list[str] | None = None,
    ) -> None:
        return self._ops._run_async(script, extra, done_label, dialog, on_success, op=op, recipe_dir=recipe_dir, script_args=script_args)

    def _cancel_current_install(self) -> None:
        return self._ops._cancel_current_install()

    def _force_kill_install(self, proc: QProcess, pid: int) -> None:
        return self._ops._force_kill_install(proc, pid)

    def _rollback_cancelled_install(self, recipe_dir: Path | None) -> None:
        return self._ops._rollback_cancelled_install(recipe_dir)

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
                timeout=_DESKTOP_SHORTCUT_TIMEOUT_SEC,
                check=False,
            )
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def _remove_desktop_shortcuts(self, recipe_dir: Path) -> bool:
        """Belt-and-suspenders after uninstall.sh — drop leftover Desktop icons."""
        cli = self._desktop_cli()
        if not cli.is_file():
            return False
        env = {**os.environ, **self._base_env()}
        try:
            result = subprocess.run(
                ["bash", str(cli), "remove", str(recipe_dir)],
                cwd=str(ROOT),
                env=env,
                capture_output=True,
                text=True,
                timeout=_DESKTOP_SHORTCUT_TIMEOUT_SEC,
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
                QMessageBox.StandardButton.No,
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
                QMessageBox.StandardButton.No,
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
            files = [
                f
                for f in LOG_ROOT.iterdir()
                if f.is_file() and f.suffix.lower() in {".log", ".txt"}
            ]
            for f in sorted(files, key=lambda p: p.stat().st_mtime, reverse=True)[:50]:
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

    def _selected_log_path(self) -> Path | None:
        p = self.log_combo.currentData()
        if not p:
            return None
        path = Path(str(p))
        return path if path.is_file() else None

    def open_log_folder(self) -> None:
        try:
            LOG_ROOT.mkdir(parents=True, exist_ok=True)
            os.chmod(LOG_ROOT, 0o700)
        except OSError:
            pass
        if not LOG_ROOT.is_dir():
            self._activity("warn", t("logs.folder_missing", path=str(LOG_ROOT)))
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(LOG_ROOT.resolve())))
        self._activity("info", t("logs.folder_opened", path=str(LOG_ROOT)))

    def copy_selected_log_path(self) -> None:
        path = self._selected_log_path()
        if path is None:
            self._activity("warn", t("logs.no_selection"))
            return
        QApplication.clipboard().setText(str(path.resolve()))
        self._activity("info", t("logs.path_copied", path=str(path.resolve())))

    def copy_selected_log_content(self) -> None:
        path = self._selected_log_path()
        if path is None:
            self._activity("warn", t("logs.no_selection"))
            return
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")[-200_000:]
        except OSError as exc:
            self._activity("warn", str(exc))
            return
        QApplication.clipboard().setText(sanitize_log_text(raw))
        self._activity("info", t("logs.content_copied", name=path.name))

    def _switch_to_logs_tab(self) -> None:
        self._set_content_tab("logs")

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

    def show_catalog_dialog(self) -> None:
        installed = {info.rid for info in self.recipes}
        dlg = CatalogDialog(
            self,
            recipes_dir=RECIPES_DIR,
            settings=self._settings,
            installed_ids=installed,
        )
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True)
        clamp_restored_geometry(dlg, min_w=560, min_h=420)
        dlg.exec()
        self._settings = load_settings()
        self._apply_discover_outcome(discover_recipes())
        self._populate_list()
        self.refresh_statuses()

    def show_hidden_recipes_dialog(self) -> None:
        names = {
            info.rid: str(info.meta.get("name") or info.rid) for info in self.recipes
        }
        for rid in self._settings.hidden_recipe_ids or []:
            names.setdefault(rid, rid)
        dlg = HiddenRecipesDialog(
            self, settings=self._settings, recipe_names=names
        )
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True)
        clamp_restored_geometry(dlg, min_w=420, min_h=360)
        dlg.exec()
        self._settings = load_settings()
        self._populate_list()

    def _official_catalog_ids(self) -> set[str]:
        try:
            from recipe_catalog import load_local_catalog

            return {
                e.id
                for e in load_local_catalog(RECIPES_DIR)
                if e.is_official and e.path and "community" not in e.path
            }
        except Exception as exc:  # noqa: BLE001
            _debug_log(f"official catalog load failed: {exc}")
            ids: set[str] = set()
            if RECIPES_DIR.is_dir():
                for yml in sorted(RECIPES_DIR.glob("*/recipe.yml")):
                    if yml.parent.name.startswith("_"):
                        continue
                    meta = parse_recipe_yml(yml)
                    ids.add(meta.get("id", yml.parent.name))
            return ids

    def _is_official_bundled_recipe(self, rid: str) -> bool:
        return rid in self._official_catalog_ids()

    def remove_recipe_definition(self, rid: str) -> None:
        """Delete a non-official recipe folder under recipes/ (QA / local drafts)."""
        rid = (rid or "").strip()
        if not rid:
            return
        if self._is_official_bundled_recipe(rid):
            QMessageBox.warning(
                self,
                t("recipe_remove.title"),
                t("recipe_remove.blocked_official", id=rid),
            )
            return
        meta_dir = next(
            (str(i.meta.get("_dir", "")) for i in self.recipes if i.rid == rid),
            "",
        )
        recipe_dir = Path(meta_dir) if meta_dir else RECIPES_DIR / rid
        try:
            recipe_dir.resolve().relative_to(RECIPES_DIR.resolve())
        except ValueError:
            QMessageBox.warning(
                self,
                t("recipe_remove.title"),
                t("recipe_remove.fail", err="invalid path"),
            )
            return
        if not recipe_dir.is_dir():
            QMessageBox.warning(
                self,
                t("recipe_remove.title"),
                t("recipe_remove.fail", err="missing folder"),
            )
            return
        if (
            QMessageBox.question(
                self,
                t("recipe_remove.title"),
                t("recipe_remove.confirm", path=str(recipe_dir)),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            != QMessageBox.StandardButton.Yes
        ):
            return
        try:
            shutil.rmtree(recipe_dir)
            generate_manifest(RECIPES_DIR, MANIFEST_PATH)
        except OSError as exc:
            QMessageBox.critical(
                self,
                t("recipe_remove.title"),
                t("recipe_remove.fail", err=str(exc)),
            )
            return
        hidden = [h for h in (self._settings.hidden_recipe_ids or []) if h != rid]
        if hidden != list(self._settings.hidden_recipe_ids or []):
            self._settings.hidden_recipe_ids = hidden
            save_settings(self._settings)
        self._activity("ok", t("recipe_remove.ok", id=rid))
        self._apply_discover_outcome(discover_recipes())
        self._populate_list()
        self.refresh_statuses()

    def hide_recipe(self, rid: str) -> None:
        rid = (rid or "").strip()
        if not rid:
            return
        hidden = list(self._settings.hidden_recipe_ids or [])
        if rid not in hidden:
            hidden.append(rid)
            self._settings.hidden_recipe_ids = hidden
            save_settings(self._settings)
            self._activity("info", t("hidden.hidden_ok", id=rid))
        if self._selected and self._selected.rid == rid:
            self._selected = None
            self._selected_index = -1
        self._populate_list()
        self._show_home()

    def _recipe_category(self, rid: str) -> str:
        overrides = dict(self._settings.recipe_category_overrides or {})
        for info in self.recipes:
            if info.rid == rid:
                return effective_category(info.rid, info.meta, overrides)
        return ""

    def _ids_in_category(self, category: str) -> list[str]:
        """Visible recipe ids in sidebar order for one category."""
        overrides = dict(self._settings.recipe_category_overrides or {})
        out: list[str] = []
        for _card, info in self._recipe_cards:
            if effective_category(info.rid, info.meta, overrides) == category:
                out.append(info.rid)
        return out

    def _set_category_override(self, rid: str, category: str) -> None:
        """Persist user category; clear override when it matches recipe.yml default."""
        overrides = dict(self._settings.recipe_category_overrides or {})
        meta = next((i.meta for i in self.recipes if i.rid == rid), None)
        default = default_category(meta)
        category = (category or "").strip() or "Sonstige"
        if category == default:
            overrides.pop(rid, None)
        else:
            overrides[rid] = category
        self._settings.recipe_category_overrides = overrides

    def reset_recipe_category(self, rid: str) -> None:
        overrides = dict(self._settings.recipe_category_overrides or {})
        if rid not in overrides:
            return
        overrides.pop(rid, None)
        self._settings.recipe_category_overrides = overrides
        save_settings(self._settings)
        self._populate_list()
        self._activity("info", t("menu.category_reset", id=rid))

    def _persist_recipe_order(self, order: list[str]) -> None:
        self._settings.recipe_order = order
        save_settings(self._settings)
        prev = self._selected.rid if self._selected else ""
        self._populate_list()
        if prev:
            for i, info in enumerate(self.recipes):
                if info.rid == prev and info.rid not in set(
                    self._settings.hidden_recipe_ids or []
                ):
                    self._select_recipe_index(i)
                    break
        self._activity("info", t("menu.reorder_saved"))

    def _move_recipe(self, rid: str, delta: int) -> None:
        """Move up/down within the same category only (sidebar groups are fixed)."""
        cat = self._recipe_category(rid)
        if not cat:
            return
        siblings = self._ids_in_category(cat)
        if rid not in siblings or len(siblings) < 2:
            self._flash_status(t("menu.reorder_need_siblings"))
            return
        idx = siblings.index(rid)
        new_idx = idx + delta
        if new_idx < 0 or new_idx >= len(siblings):
            return
        siblings[idx], siblings[new_idx] = siblings[new_idx], siblings[idx]
        order = list(self._settings.recipe_order or [])
        for other in siblings:
            if other not in order:
                order.append(other)
        remaining = [r for r in order if r not in siblings]
        self._persist_recipe_order(siblings + remaining)

    def _on_category_drop(self, source_id: str, category: str) -> None:
        """Drop onto a category header → move recipe into that category (override)."""
        category = (category or "").strip()
        if not source_id or not category:
            return
        if self._recipe_category(source_id) == category:
            return
        self._set_category_override(source_id, category)
        siblings = [r for r in self._ids_in_category(category) if r != source_id]
        siblings.insert(0, source_id)
        order = list(self._settings.recipe_order or [])
        remaining = [r for r in order if r not in siblings]
        save_settings(self._settings)
        self._persist_recipe_order(siblings + remaining)
        self._flash_status(
            t("menu.category_moved", id=source_id, cat=category_label(category))
        )

    def _on_recipe_reorder(
        self, source_id: str, target_id: str, place: str = "before"
    ) -> None:
        if not source_id or not target_id or source_id == target_id:
            return
        if place not in ("before", "after"):
            place = "before"
        target_cat = self._recipe_category(target_id)
        if not target_cat:
            return
        # Cross-category: user override (recipe.yml stays default until reset)
        if self._recipe_category(source_id) != target_cat:
            self._set_category_override(source_id, target_cat)
            save_settings(self._settings)
        siblings = [
            r for r in self._ids_in_category(target_cat) if r != source_id
        ]
        if target_id not in siblings:
            siblings.append(target_id)
        idx = siblings.index(target_id)
        if place == "after":
            idx += 1
        siblings.insert(idx, source_id)
        order = list(self._settings.recipe_order or [])
        remaining = [r for r in order if r not in siblings]
        self._persist_recipe_order(siblings + remaining)

    def show_settings(self) -> None:
        dlg = SettingsDialog(self, self._settings)
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True)
        restore_geometry(dlg, self._settings.settings_geometry)
        clamp_restored_geometry(dlg, min_w=520, min_h=520)
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
        try:
            dlg = RecipeViewDialog(
                self,
                recipe_dir=recipe_dir,
                project_root=ROOT,
                editable=editable,
                icon=icon,
            )
            apply_tool_window(
                dlg, icon=icon if not icon.isNull() else self.windowIcon()
            )
            restore_geometry(dlg, self._settings.recipe_view_geometry)
            clamp_restored_geometry(dlg, min_w=560, min_h=420)
            if editable:
                dlg.focus_source_tab()
            dlg.finished.connect(self._on_recipe_view_closed)
            self._recipe_view_dlg = dlg
            dlg.show()
            dlg.raise_()
            dlg.activateWindow()
        except Exception as exc:
            self._recipe_view_dlg = None
            QMessageBox.critical(
                self,
                t("dialog.error"),
                t("recipe_view.open_fail", err=str(exc)),
            )

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
            # Kaputte Geometrie verwerfen — sonst „startet nicht“ / Offscreen.
            if (s.window_geometry or "").strip():
                s.window_geometry = ""
                save_settings(s)
            self.resize(1000, 560)
        clamp_restored_geometry(self, min_w=880, min_h=480)
        ensure_on_screen(self)
        if s.window_maximized:
            self.showMaximized()
        self._suppress_tab_persist = True
        try:
            self._set_content_tab(s.content_tab or "overview")
        finally:
            self._suppress_tab_persist = False
        if self._selected is None and not s.window_maximized:
            QTimer.singleShot(
                0, lambda: self._apply_content_window_height(allow_grow=False)
            )

    def showEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        super().showEvent(event)
        QTimer.singleShot(0, self._sync_sidebar_scroll_gap)
        if not self._ui_restored:
            self._ui_restored = True
            # Nach erstem Show — sonst speichert der WM falsche Größen
            QTimer.singleShot(0, self._restore_ui_layout)
            QTimer.singleShot(200, self._startup_prompts)

    def _sidebar_scroll_max_height(self) -> int:
        """Space left in the sidebar for the recipe list (below home/search)."""
        scroll = getattr(self, "recipe_cards_scroll", None)
        sidebar = getattr(self, "_sidebar", None)
        if scroll is None or sidebar is None:
            return 480
        lay = sidebar.layout()
        if lay is None:
            return max(80, sidebar.height() - 120)
        margins = lay.contentsMargins()
        used = margins.top() + margins.bottom()
        spacing = lay.spacing()
        for i in range(lay.count()):
            item = lay.itemAt(i)
            if item is None:
                continue
            w = item.widget()
            if w is None or w is scroll or not w.isVisible():
                continue
            used += w.sizeHint().height() + spacing
        return max(80, sidebar.height() - used)

    def _sync_sidebar_scroll_gap(self) -> None:
        """List height = content until it hits the sidebar budget, then scroll."""
        scroll = getattr(self, "recipe_cards_scroll", None)
        host = getattr(self, "recipe_cards_host", None)
        lay = getattr(self, "recipe_cards_layout", None)
        if scroll is None or host is None or lay is None:
            return
        if getattr(self, "_sidebar_syncing", False):
            return
        self._sidebar_syncing = True
        try:
            max_h = self._sidebar_scroll_max_height()
            # Width pass: prefer viewport, else sidebar inner width.
            vw = scroll.viewport().width()
            if vw <= 0:
                side = getattr(self, "_sidebar", None)
                if side is not None:
                    sm = side.layout().contentsMargins() if side.layout() else None
                    vw = side.width() - (
                        (sm.left() + sm.right()) if sm is not None else 24
                    )
            vw = max(int(vw), 200)
            host.setFixedWidth(vw)
            host.adjustSize()
            content_h = max(host.sizeHint().height(), 1)

            need_scroll = content_h > max_h
            right = (
                (scroll.verticalScrollBar().sizeHint().width() + 6)
                if need_scroll
                else 4
            )
            lay.setContentsMargins(0, 0, right, 0)
            vw2 = scroll.viewport().width()
            if vw2 > 0:
                host.setFixedWidth(vw2)
                host.adjustSize()
                content_h = max(host.sizeHint().height(), 1)

            target = min(content_h, max_h)
            if abs(scroll.height() - target) > 1:
                scroll.setFixedHeight(target)
            host.resize(host.width(), content_h)
            scroll.setVerticalScrollBarPolicy(
                Qt.ScrollBarPolicy.ScrollBarAsNeeded
                if content_h > target
                else Qt.ScrollBarPolicy.ScrollBarAlwaysOff
            )
        finally:
            self._sidebar_syncing = False

    def _preferred_window_height(self) -> int:
        """Height that fits chrome + sidebar list + home/recipe body (no dead void)."""
        mb = self.menuBar().sizeHint().height() if self.menuBar() else 0
        stb = self.statusBar().sizeHint().height() if self.statusBar() else 0
        frame = self.frameGeometry().height() - self.geometry().height()
        if frame < 0 or frame > 100:
            frame = 36

        header_h = 0
        if hasattr(self, "_header") and self._header is not None:
            header_h = max(self._header.sizeHint().height(), self._header.height(), 72)

        bar_h = 0
        bar = getattr(self, "primary_btn", None)
        if bar is not None:
            parent = bar.parentWidget()
            if parent is not None and parent.isVisible():
                bar_h = max(parent.sizeHint().height(), 36)

        if self._selected is None:
            page = getattr(self, "_home_page", None)
            if page is not None:
                page.adjustSize()
                body_h = max(page.sizeHint().height(), 200)
            else:
                body_h = 280
        else:
            body_h = 440

        main_chrome = 14 + 12 + 16 + 12  # margins + spacings in main column
        main_need = header_h + bar_h + body_h + main_chrome

        side_need = 160
        side = getattr(self, "_sidebar", None)
        scroll = getattr(self, "recipe_cards_scroll", None)
        if side is not None and side.layout() is not None:
            lay = side.layout()
            m = lay.contentsMargins()
            side_need = m.top() + m.bottom()
            for i in range(lay.count()):
                item = lay.itemAt(i)
                if item is None:
                    continue
                w = item.widget()
                if w is None or not w.isVisible():
                    continue
                if w is scroll:
                    side_need += max(w.height(), 48)
                else:
                    side_need += w.sizeHint().height()
                side_need += lay.spacing()

        return mb + stb + frame + max(main_need, side_need)

    def _apply_content_window_height(self, *, allow_grow: bool = False) -> None:
        """Shrink (or grow) the window to content — kills empty Startseite/Sidebar voids."""
        if self.isMaximized() or self.isFullScreen():
            return
        self._sync_sidebar_scroll_gap()
        prefer = self._preferred_window_height()
        prefer = max(prefer, self.minimumHeight())
        scr = self.screen()
        if scr is not None:
            prefer = min(prefer, scr.availableGeometry().height() - 24)
        cur = self.height()
        if prefer < cur - 20:
            self.resize(self.width(), prefer)
        elif allow_grow and prefer > cur + 20:
            self.resize(self.width(), prefer)

    def _startup_prompts(self) -> None:
        self._maybe_host_deps_first_run()
        self._maybe_startup_validate()

    def _maybe_host_deps_first_run(self) -> None:
        # Re-prompt whenever required packages are missing (issue #11 follow-up),
        # not only on the very first launch.
        if has_required_gaps():
            dlg = HostDepsDialog(self, first_run=not self._settings.host_deps_prompt_done)
            dlg.exec()
            mark_host_deps_prompt_done(self._settings)
            return
        if not self._settings.host_deps_prompt_done:
            if has_gaps():
                dlg = HostDepsDialog(self, first_run=True)
                dlg.exec()
            mark_host_deps_prompt_done(self._settings)

    def ensure_host_wow64_for_install(self, meta: dict[str, str]) -> bool:
        """Show system check and block install when WoW64 host libs are missing."""
        if not recipe_needs_host_wow64(meta):
            return True
        if not missing_wow64_deps():
            return True
        dlg = HostDepsDialog(self, block_install=True)
        dlg.exec()
        if missing_wow64_deps():
            show_warning(self, t("deps.title"), t("deps.block_install"))
            return False
        return True

    def _maybe_startup_validate(self) -> None:
        """Hinweisdialog + optionale validate.sh-Runde beim Start."""
        if not self._settings.validate_on_startup:
            return
        dlg = QDialog(self)
        dlg.setWindowTitle(t("settings.startup_check_title"))
        dlg.setModal(True)
        # Nicht windowIcon() vom Hauptfenster — das wechselt mit dem Rezept.
        if REZEPTOR_ICON.is_file():
            dlg.setWindowIcon(QIcon(str(REZEPTOR_ICON)))
        root = QVBoxLayout(dlg)
        root.setContentsMargins(20, 16, 20, 16)
        root.setSpacing(12)
        body = QLabel(t("settings.startup_check_body"))
        body.setWordWrap(True)
        body.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        root.addWidget(body)
        skip_next = QCheckBox(t("settings.startup_check_skip_next"))
        root.addWidget(skip_next)
        buttons = QDialogButtonBox()
        run_btn = buttons.addButton(
            t("settings.startup_check_run"),
            QDialogButtonBox.ButtonRole.AcceptRole,
        )
        skip_btn = buttons.addButton(
            t("settings.startup_check_skip_once"),
            QDialogButtonBox.ButtonRole.RejectRole,
        )
        root.addWidget(buttons)
        run_btn.clicked.connect(dlg.accept)
        skip_btn.clicked.connect(dlg.reject)
        dlg.setMinimumWidth(420)
        accepted = dlg.exec() == QDialog.DialogCode.Accepted
        if skip_next.isChecked():
            self._settings.validate_on_startup = False
            save_settings(self._settings)
        if accepted:
            self.refresh_statuses()

    def show_host_deps_check(self) -> None:
        dlg = HostDepsDialog(self, first_run=False)
        dlg.exec()
        mark_host_deps_prompt_done(self._settings)

    def _visible_tool_windows(self) -> list[QWidget]:
        out: list[QWidget] = []
        for dlg in (self._recipe_view_dlg, self._docs_dlg):
            if dlg is not None and dlg.isVisible():
                out.append(dlg)
        return out

    def _bring_app_to_front(self) -> None:
        """Taskleiste/WM: Fenster sichtbar machen bevor wir nachfragen."""
        self.showNormal()
        self.raise_()
        self.activateWindow()
        for dlg in self._visible_tool_windows():
            dlg.raise_()
        self.raise_()
        self.activateWindow()

    def _show_quit_confirm(self, body: str) -> bool:
        """Stay-on-top — sonst hinter modalem Quellen-Dialog / Wine unsichtbar."""
        self._bring_app_to_front()
        box = QMessageBox(self)
        apply_fa_message_icon(box, "question")
        box.setWindowTitle(t("dialog.quit_title"))
        box.setText(body)
        box.setStandardButtons(
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        box.setDefaultButton(QMessageBox.StandardButton.Yes)
        box.setWindowModality(Qt.WindowModality.ApplicationModal)
        box.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint, True)
        box.setWindowFlag(Qt.WindowType.Dialog, True)
        box.show()
        box.raise_()
        box.activateWindow()
        app = QApplication.instance()
        if app is not None:
            app.setActiveWindow(box)
        return box.exec() == QMessageBox.StandardButton.Yes

    def _confirm_busy_quit(self) -> bool:
        return self._show_quit_confirm(t("dialog.quit_busy_body"))

    def _confirm_app_quit(self) -> bool:
        """Vorgang/Nebenfenster: App nach vorne, dann eine klare Beenden-Frage."""
        busy = bool(self._busy and self._subprocess_running())
        tools = self._visible_tool_windows()
        dirty = any(
            hasattr(w, "is_dirty") and w.is_dirty()  # type: ignore[misc]
            for w in tools
        )
        if busy:
            return self._show_quit_confirm(t("dialog.quit_busy_body"))
        if tools:
            body = t("dialog.quit_windows_body")
            if dirty:
                body = f"{body}\n\n{t('dialog.quit_dirty_extra')}"
            return self._show_quit_confirm(body)
        return True

    def report_internal_error(self, summary: str, _detail: str) -> None:
        """Unbehandelte Exception: melden statt sterben — PyQt6 würde den Prozess abbrechen."""
        ev = LogEvent(
            level="error",
            code=E_UNCAUGHT,
            message_key="error.E_UNCAUGHT",
            detail=summary,
            session_id=self.session_id,
            recipe_id=(self._selected.rid if self._selected else ""),
        )
        self._activity("error", ev.display_text())
        if self._internal_error_shown:
            return
        self._internal_error_shown = True
        QMessageBox.warning(
            self, t("dialog.error"), f"{ev.display_text()}\n\n{DIAG_LOG}"
        )

    def request_quit_from_wm(self, *, from_wm: bool = False) -> None:
        """Taskleiste / „Alle schließen“ / Fenster-X — zentraler Quit-Pfad."""
        if getattr(self, "_force_quitting", False):
            return
        if getattr(self, "_quit_pending", False):
            return
        log_call_site("QUIT", f"from_wm={from_wm} busy={self._busy} op={self._current_op}")
        self._quit_pending = True
        try:
            busy = bool(self._busy and self._subprocess_running())
            if busy and not self._confirm_busy_quit():
                return
            if not from_wm and not busy and not self._confirm_app_quit():
                self._bring_app_to_front()
                return

            self._force_quitting = True
            unwind_modal_dialogs(self, force=True)
            dismiss_all_top_level_windows(self, force=True)
            unwind_modal_dialogs(self, force=True)
            self._persist_ui_layout()
            self._terminate_busy_subprocess()
            self.close()
            app = QApplication.instance()
            if app is not None:
                app.processEvents()
                app.quit()
        finally:
            self._quit_pending = False

    def _terminate_busy_subprocess(self) -> None:
        """Taskleisten-Quit / Alles schließen: laufenden Vorgang (inkl. GenP/Wine) beenden."""
        proc = self._process
        if proc is None or proc.state() == QProcess.ProcessState.NotRunning:
            return
        self._cancel_requested = True
        pid = int(proc.processId())
        _signal_qprocess_tree(proc, signal.SIGTERM)
        if pid > 0:
            QTimer.singleShot(1500, lambda p=proc, i=pid: self._force_kill_install(p, i))

    def closeEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if getattr(self, "_force_quitting", False):
            event.accept()
            super().closeEvent(event)
            return
        event.ignore()
        self.request_quit_from_wm(from_wm=True)
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
        tid = normalize_theme(getattr(self._settings, "theme", None))
        self._settings.theme = tid
        host = apply_rezeptor_theme(tid)
        self._theme = tid
        tok = theme_tokens(tid)
        tabs_qss = segment_tab_styles(tid)
        app = QApplication.instance()
        if app is not None:
            app.setStyleSheet((host or "") + tabs_qss)
        if hasattr(self, "segment_tabs"):
            self.segment_tabs.apply_theme(tid)
        if hasattr(self, "name_label"):
            self.name_label.setStyleSheet(
                f"font-size: 20px; font-weight: 600; color: {tok['fg']}; "
                "background: transparent;"
            )
        if hasattr(self, "path_label"):
            self._style_secondary_label(self.path_label, tok["muted"], size_px=11)
        if hasattr(self, "status_detail_label"):
            self._style_secondary_label(
                self.status_detail_label, tok["muted"], size_px=12
            )
        for pill in (
            getattr(self, "status_pill", None),
            getattr(self, "version_pill", None),
            getattr(self, "tested_pill", None),
            getattr(self, "proton_pill", None),
            getattr(self, "tested_on_pill", None),
            getattr(self, "author_pill", None),
        ):
            if pill is not None and hasattr(pill, "apply_theme"):
                pill.apply_theme(tid)
        # Header chrome icons follow theme fg (not fixed parchment).
        chrome_fg = tok["fg"]
        for btn, kind in (
            (getattr(self, "version_info_btn", None), "info"),
            (getattr(self, "open_path_btn", None), "folder"),
        ):
            if btn is None:
                continue
            ic = fa_icon(kind, 14, color=chrome_fg)
            if ic is not None:
                btn.setIcon(ic)
        self._restyle_activity_list()
        for card, _info in getattr(self, "_recipe_cards", []) or []:
            if hasattr(card, "apply_theme"):
                card.apply_theme(tid)
        self._sync_theme_toggle()
        self._refresh_home_link_icons()
        self._refresh_home_activity()
        self._refresh_status_footer(self._update_available or "")
        if self._selected is not None:
            self._render_info_markdown()
        # Watermark alpha depends on theme contrast — rebuild if present.
        if getattr(self, "_header_watermark_src", None) is not None:
            self._layout_header_watermark()
        wm = getattr(self, "_header_watermark", None)
        if wm is not None:
            wm.lower()

    def retranslate_ui(self) -> None:
        self._build_menus()
        self._sync_lang_toggle()
        self.setWindowTitle(
            self._window_title(
                read_version(), self._update_available or ""
            )
        )
        self._refresh_status_footer(self._update_available)
        if hasattr(self, "_sidebar_title"):
            self._sidebar_title.setText(t("app.sidebar_title"))
        if hasattr(self, "_home_btn"):
            self._home_btn.setText(t("app.home_sidebar"))
            self._home_btn.setToolTip(t("menu.home"))
        if hasattr(self, "sidebar_search"):
            self.sidebar_search.setPlaceholderText(t("app.sidebar_search"))
        if hasattr(self, "_home_intro"):
            self._home_intro.setText(t("app.home_intro"))
        if hasattr(self, "_home_tip"):
            self._home_tip.setText(t("app.home_tip"))
        if hasattr(self, "_home_activity_title"):
            self._home_activity_title.setText(t("home.activity_title"))
        self._refresh_home_activity()
        if hasattr(self, "_home_links_hint"):
            self._home_links_hint.setText(t("app.home_links_hint"))
        if hasattr(self, "_home_github_btn"):
            self._home_github_btn.setToolTip(t("app.home_link_github_tip"))
            self._home_github_btn.setAccessibleName(t("app.home_link_github"))
        if hasattr(self, "_home_github_title"):
            self._home_github_title.setText(t("app.home_link_github"))
        if hasattr(self, "_home_github_sub"):
            self._home_github_sub.setText(t("app.home_link_github_sub"))
        if hasattr(self, "_home_wiki_btn"):
            self._home_wiki_btn.setToolTip(t("app.home_link_wiki_tip"))
            self._home_wiki_btn.setAccessibleName(t("app.home_link_wiki"))
        if hasattr(self, "_home_wiki_title"):
            self._home_wiki_title.setText(t("app.home_link_wiki"))
        if hasattr(self, "_home_wiki_sub"):
            self._home_wiki_sub.setText(t("app.home_link_wiki_sub"))
        if hasattr(self, "_home_reddit_btn"):
            self._home_reddit_btn.setToolTip(t("app.home_link_reddit_tip"))
            self._home_reddit_btn.setAccessibleName(t("app.home_link_reddit"))
        if hasattr(self, "_home_reddit_title"):
            self._home_reddit_title.setText(t("app.home_link_reddit"))
        if hasattr(self, "_home_reddit_sub"):
            self._home_reddit_sub.setText(t("app.home_link_reddit_sub"))
        for prefix in ("linuxchooser", "cachyos", "linuxguides"):
            btn = getattr(self, f"_home_{prefix}_btn", None)
            title = getattr(self, f"_home_{prefix}_title", None)
            sub = getattr(self, f"_home_{prefix}_sub", None)
            if btn is not None:
                btn.setToolTip(t(f"app.home_link_{prefix}_tip"))
                btn.setAccessibleName(t(f"app.home_link_{prefix}"))
            if title is not None:
                title.setText(t(f"app.home_link_{prefix}"))
            if sub is not None:
                sub.setText(t(f"app.home_link_{prefix}_sub"))
        self._sync_theme_toggle()
        for key in ("recipes", "installed", "attention", "hidden"):
            cap = getattr(self, f"_home_stat_caption_{key}", None)
            if cap is not None:
                cap.setText(t(f"app.home_stat_{key}"))
        if hasattr(self, "_overview_hint"):
            self._overview_hint.setText(t("overview.hint"))
        if hasattr(self, "_progress_steps_label"):
            self._progress_steps_label.setText(t("progress.steps"))
        if hasattr(self, "_progress_live_label"):
            self._progress_live_label.setText(t("progress.live"))
        if hasattr(self, "raw_log"):
            self.raw_log.setPlaceholderText(t("progress.live_placeholder"))
        if getattr(self, "_activity_empty_shown", False):
            self._show_activity_empty_hint()
            if hasattr(self, "step_label") and not self._busy:
                self.step_label.setText(t("status.no_process"))
                self.step_label.setStyleSheet("")
        if hasattr(self, "_logs_file_label"):
            self._logs_file_label.setText(t("logs.label"))
        if hasattr(self, "_logs_refresh_btn"):
            self._logs_refresh_btn.setText(t("logs.refresh"))
        if hasattr(self, "_logs_open_folder_btn"):
            self._logs_open_folder_btn.setText(t("logs.open_folder"))
        if hasattr(self, "_logs_copy_path_btn"):
            self._logs_copy_path_btn.setText(t("logs.copy_path"))
        if hasattr(self, "_logs_copy_content_btn"):
            self._logs_copy_content_btn.setText(t("logs.copy_content"))
        self.more_btn.setText(t("btn.more"))
        self.more_btn.setToolTip(t("tooltip.more"))
        if hasattr(self, "medizin_btn"):
            self.medizin_btn.setText(t("btn.medizin"))
            self.medizin_btn.setToolTip(t("tooltip.medizin"))
            self._sync_medizin_button()
        if hasattr(self, "cancel_install_btn"):
            self.cancel_install_btn.setText(t("btn.cancel_install"))
            self.cancel_install_btn.setToolTip(t("tooltip.cancel_install"))
        if hasattr(self, "_rebuild_more_menu"):
            self._rebuild_more_menu()
        if hasattr(self, "segment_tabs"):
            self.segment_tabs.set_labels(
                [
                    ("overview", t("tab.overview")),
                    ("progress", t("tab.progress")),
                    ("logs", t("tab.logs")),
                ]
            )
        # Rebuild sidebar so category headers / card tips follow the locale.
        prev = self._selected.rid if self._selected else ""
        if hasattr(self, "recipe_cards_layout"):
            self._populate_list()
            if prev:
                for i, info in enumerate(self.recipes):
                    if info.rid == prev:
                        self._select_recipe_index(i)
                        break
                else:
                    self._show_home()
            else:
                self._show_home()
        elif self._selected:
            self._on_select(self._selected_index)
        else:
            self._show_home()

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

    def _prompt_and_save_source(self, *, title_key: str = "dialog.source_pick_title") -> dict[str, str] | None:
        """Quelle/Ziel-Dialog → pending Env speichern. None = Abbruch."""
        if self._selected is None:
            return None
        meta = self._selected.meta
        rid = self._selected.rid
        pending = load_recipe_install_env(self._settings, rid)
        dlg = RecipeSourceDialog(
            self,
            rid=rid,
            meta=meta,
            root=ROOT,
            title=t(title_key, name=meta.get("name", rid)),
            pending_env=pending,
        )
        apply_tool_window(dlg, icon=self.windowIcon(), modal=True)
        # Parent-modaler Dialog (kein Window-Flag): Wayland/KDE ignoriert sonst oft
        # MinimumSize — nach Ordnerwahl überlappen Wählen/OK.
        dlg._fit_to_content()
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return None
        dr = resolve_data_root(meta, rid)
        try:
            extra = dlg.build_env(dr)
        except OSError as exc:
            QMessageBox.critical(
                self,
                t("dialog.source_label"),
                t("dialog.source_invalid", error=exc),
            )
            return None
        if not has_recipe_install_source(extra):
            clear_recipe_install_env(self._settings, rid)
            self._activity("info", t("source.cleared"))
            if self._selected_index >= 0:
                self._on_select(self._selected_index)
            return None
        save_recipe_install_env(self._settings, rid, extra)
        self._activity("info", t("source.saved_ready"))
        if self._selected_index >= 0:
            self._on_select(self._selected_index)
        return dict(extra)

    def _prepare_install_env(self, extra: dict[str, str]) -> bool:
        return self._ops._prepare_install_env(extra)

    def run_install(self) -> None:
        return self._ops.run_install()

    def run_source_configure(self) -> None:
        """Nur Quelle/Ziel speichern — startet keine Installation."""
        if self._require_recipe() is None or not self._selected:
            return
        meta = self._selected.meta
        if not needs_source_dialog(meta):
            return
        self._prompt_and_save_source(title_key="dialog.source_title")

    def run_genp_from_pack(self) -> None:
        return self._ops.run_genp_from_pack()

    def _genp_target_wine_path(self) -> str:
        return self._ops._genp_target_wine_path()

    def run_repair(self) -> None:
        return self._ops.run_repair()

    def run_update(self) -> None:
        return self._ops.run_update()

    def run_relocate(self) -> None:
        return self._ops.run_relocate()

    def _repair_message(self, rid: str) -> str:
        return self._ops._repair_message(rid)

    def _spawn_detached(self, cmd: list[str], env: dict[str, str]) -> Path:
        return self._ops._spawn_detached(cmd, env)

    def _check_launch_alive(
        self, rid: str, log_path: Path, attempt: int = 0
    ) -> None:
        return self._ops._check_launch_alive(rid, log_path, attempt)

    def run_launch(self) -> None:
        return self._ops.run_launch()

    def run_validate(self) -> None:
        return self._ops.run_validate()

    def run_kill(self) -> None:
        return self._ops.run_kill()

    def run_uninstall(self) -> None:
        return self._ops.run_uninstall()


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
    app.setQuitOnLastWindowClosed(True)
    log_session_start(read_version())
    install_signal_logging()
    install_exit_logging()
    ensure_fa_font()
    ensure_fa_brands_font()
    # Fusion für Host-Widgets (Combo/Listen) — sonst KDE-Blau statt Kupfer
    app.setStyle("Fusion")
    boot_settings = load_settings()
    host = apply_rezeptor_theme(boot_settings.theme)
    app.setStyleSheet((host or "") + segment_tab_styles(boot_settings.theme))
    try:
        w = RezeptorWindow()
        install_application_close_guard(w)
        install_exception_logging(w.report_internal_error)
        w.show()
        QTimer.singleShot(0, w._apply_theme)
        # Volle validate.sh: Hinweisdialog in _startup_prompts (nach erstem Show).
        return app.exec()
    except Exception as exc:  # noqa: BLE001 — startup must not hang silently
        print(f"rezeptor: fatal startup error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
