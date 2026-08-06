"""Version, Updates, Log-Sanitisierung, GitHub-Issue-Hilfe."""

from __future__ import annotations

import json
import os
import platform
import re
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GITHUB_REPO = "benjarogit/rezeptor"
DOCS_SITE = "https://benjarogit.github.io/rezeptor"
# Public user report (r/photoshop) — amplify only; support stays on GitHub Issues
COMMUNITY_REDDIT_URL = (
    "https://www.reddit.com/r/photoshop/comments/1vau4wh/"
    "fyi_photoshop_cc_2021_on_ubuntu_finally/"
)
LOG_ROOT = Path.home() / ".local/share/wine-software/logs"
LOG_RETENTION_DAYS = 14
LOG_MAX_FILES = 50

SENSITIVE_PATTERNS = [
    (re.compile(r"/home/[^/\s]+", re.I), "/home/<USER>"),
    (re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "<EMAIL>"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"), "<IP>"),
    (re.compile(r"(?i)(token|api[_-]?key|password|secret)\s*[:=]\s*\S+"), r"\1=<REDACTED>"),
    # 7z -pSECRET / unzip -P SECRET (no space after -p is common for 7z)
    (re.compile(r"(?i)(\s-p)(\S+)"), r"\1<REDACTED>"),
    (re.compile(r"(?i)(\s-P\s+)\S+"), r"\1<REDACTED>"),
    (re.compile(r"(?i)(Authorization:\s*Bearer\s+)\S+"), r"\1<REDACTED>"),
    (re.compile(r"(?i)(Bearer\s+)[A-Za-z0-9._\-+=/]+"), r"\1<REDACTED>"),
]

# Bash/Shell-Rauschen — nicht in GUI oder Issue-Body
LOG_NOISE_RE = re.compile(
    r"Speicherzugriffsfehler|Memory dump written|install\.sh: Zeile \d+:|"
    r"^\s*\( set \+e; winetricks",
    re.I,
)


def read_version() -> str:
    vf = ROOT / "VERSION"
    if vf.is_file():
        return vf.read_text(encoding="utf-8").strip()
    return "unknown"


def detect_distro() -> str:
    try:
        os_release = Path("/etc/os-release")
        if os_release.is_file():
            data: dict[str, str] = {}
            for line in os_release.read_text(encoding="utf-8").splitlines():
                if "=" in line:
                    k, _, v = line.partition("=")
                    data[k.strip()] = v.strip().strip('"')
            if data.get("PRETTY_NAME"):
                return data["PRETTY_NAME"]
            if data.get("NAME"):
                return data["NAME"]
    except OSError:
        pass
    return platform.platform() or "Linux"


def github_repo_url() -> str:
    """Canonical GitHub repository URL."""
    return f"https://github.com/{GITHUB_REPO}"


def public_docs_url(locale: str = "de") -> str:
    """Public docs/wiki (GitHub Pages). EN uses /en/; DE is the site root."""
    code = (locale or "de").split("-", 1)[0].lower()
    if code.startswith("en"):
        return f"{DOCS_SITE}/en/"
    return f"{DOCS_SITE}/"


def community_reddit_url() -> str:
    """User report on Reddit (amplify only — support stays on GitHub)."""
    return COMMUNITY_REDDIT_URL


def github_doc_url(rel_path: str, branch: str = "main") -> str:
    """GitHub-URL für eine Datei unter docs/."""
    return f"https://github.com/{GITHUB_REPO}/blob/{branch}/docs/{rel_path}"


def fetch_latest_release() -> tuple[str, str]:
    url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
        tag = str(data.get("tag_name", "")).lstrip("v")
        link = str(data.get("html_url", f"https://github.com/{GITHUB_REPO}/releases"))
        return tag, link
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return "", f"https://github.com/{GITHUB_REPO}/releases"


def version_compare(current: str, latest: str) -> bool:
    def norm(v: str) -> tuple[int, ...]:
        parts = re.findall(r"\d+", v)
        return tuple(int(p) for p in parts[:3]) + (0,) * (3 - len(parts[:3]))

    return norm(latest) > norm(current)


UPDATE_CHANNELS = frozenset({"flatpak", "appimage", "git", "tarball"})


def detect_update_channel() -> str:
    """How rezeptor-update.sh will apply updates (single source of truth)."""
    script = ROOT / "scripts" / "rezeptor-update.sh"
    if not script.is_file():
        return "tarball"
    try:
        proc = subprocess.run(
            ["bash", str(script), "detect"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        mode = (proc.stdout or "").strip().lower()
        if mode in UPDATE_CHANNELS:
            return mode
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "tarball"


def update_auto_supported(channel: str) -> bool:
    """In-app apply is disabled for Flatpak (read-only /app; host flatpak required)."""
    return channel != "flatpak"


VERSION_OK_RE = re.compile(
    r"^OK: .+?:\s*(.+?)\s*\((?:getestet & garantiert|getestete Heilung)\)\s*$"
)


def detect_source_version(
    rid: str,
    path: str,
    *,
    recipe_dir: str | Path | None = None,
    guaranteed: str = "",
) -> str:
    """Versionserkennung über recipe.yml version_detect (Rezeptor-Kern)."""
    from version_detect import detect_recipe_version

    yml: Path | None = None
    if recipe_dir:
        yml = Path(recipe_dir) / "recipe.yml"
    elif rid:
        cand = ROOT / "recipes" / rid / "recipe.yml"
        if cand.is_file():
            yml = cand
    try:
        return detect_recipe_version(
            path, yml, rid=rid, guaranteed=guaranteed
        )
    except (OSError, ValueError, TypeError):
        return ""


def parse_validate_version_fields(output: str) -> tuple[str, str]:
    detected = ""
    version_warn = ""
    for line in output.splitlines():
        m = VERSION_OK_RE.match(line.strip())
        if m:
            detected = m.group(1).strip()
            continue
        if line.startswith("WARN:") and ("garantiert" in line or "Heilung" in line):
            version_warn = line[5:].strip()
    return detected, version_warn


def version_guarantee_mismatch(guaranteed: str, detected: str) -> bool:
    if not guaranteed or not detected:
        return False
    g, d = guaranteed.strip(), detected.strip()
    if g == d:
        return False
    # Detail-Suffix erlaubt: "… (Build 7575778)"
    if d.startswith(g + " ") or d.startswith(g + " ("):
        return False
    return True


def prune_old_logs(
    log_root: Path = LOG_ROOT,
    *,
    retention_days: int | None = None,
    max_files: int | None = None,
) -> int:
    """Alte Log-Dateien entfernen (Retention). Returns count deleted.

    Berücksichtigt alle regulären Dateien unter log_root (auch Unterordner).
    Neueste max_files bleiben; ältere als retention_days fliegen raus.
    """
    if not log_root.is_dir():
        return 0

    days = LOG_RETENTION_DAYS if retention_days is None else retention_days
    cap = LOG_MAX_FILES if max_files is None else max_files
    cutoff = time.time() - days * 86400
    files: list[Path] = []
    for path in log_root.rglob("*"):
        try:
            if path.is_file():
                files.append(path)
        except OSError:
            continue
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    removed = 0
    for i, path in enumerate(files):
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        if mtime < cutoff or i >= cap:
            try:
                path.unlink()
                removed += 1
            except OSError:
                pass
    # Leere Unterordner aufräumen (z. B. full-qa-*)
    for path in sorted(log_root.rglob("*"), reverse=True):
        if not path.is_dir() or path == log_root:
            continue
        try:
            next(path.iterdir())
        except StopIteration:
            try:
                path.rmdir()
            except OSError:
                pass
        except OSError:
            pass
    return removed


def log_dir_stats(log_root: Path = LOG_ROOT) -> tuple[int, str]:
    """Anzahl + menschenlesbare Größe aller Log-Dateien (rekursiv)."""
    if not log_root.is_dir():
        return 0, "0 B"
    total = 0
    count = 0
    for path in log_root.rglob("*"):
        try:
            if path.is_file():
                total += path.stat().st_size
                count += 1
        except OSError:
            continue
    units = ("B", "KB", "MB", "GB")
    size = float(total)
    unit = units[0]
    for u in units:
        unit = u
        if size < 1024 or u == units[-1]:
            break
        size /= 1024
    if unit == "B":
        human = f"{int(size)} {unit}"
    else:
        human = f"{size:.1f} {unit}"
    return count, human


def sanitize_log_text(text: str) -> str:
    out = text
    for pat, repl in SENSITIVE_PATTERNS:
        out = pat.sub(repl, out)
    lines = [ln for ln in out.splitlines() if not LOG_NOISE_RE.search(ln)]
    return "\n".join(lines)


def humanize_log_line(line: str) -> str | None:
    """GUI-Tags → lesbare Zeile; Rauschen → None."""
    line = line.strip()
    if not line or LOG_NOISE_RE.search(line):
        return None
    m = re.match(r"^@(step|ok|warn|error|info|progress):(.+)$", line)
    if m:
        tag, msg = m.group(1), m.group(2).strip()
        labels = {
            "step": "→",
            "ok": "✓",
            "warn": "⚠",
            "error": "✗",
            "info": "ℹ",
            "progress": "▰",
        }
        return f"{labels.get(tag, '·')} {msg}"
    if line.startswith("RECIPE_"):
        return None
    return line


def _ui_locale() -> str:
    try:
        from i18n import get_locale

        code = (get_locale() or "en").split("-", 1)[0].lower()
        return "de" if code.startswith("de") else "en"
    except Exception:
        return "en"


def read_proton_ge_tag() -> str:
    """Pinned Proton-GE tag from core/runtime.lock (no shell)."""
    lock = ROOT / "core" / "runtime.lock"
    if not lock.is_file():
        return ""
    try:
        for line in lock.read_text(encoding="utf-8", errors="replace").splitlines():
            raw = line.strip()
            if not raw or raw.startswith("#") or "=" not in raw:
                continue
            key, _, val = raw.partition("=")
            if key.strip() == "PROTON_GE_TAG":
                return val.strip().strip('"').strip("'")
    except OSError:
        return ""
    return ""


def describe_runtime_for_report() -> str:
    tag = read_proton_ge_tag()
    return f"Proton-GE {tag}" if tag else "Proton-GE (unknown — core/runtime.lock)"


def proton_ge_short_tag() -> str:
    """GE-Proton11-3 → 11-3 for compact UI badges."""
    tag = read_proton_ge_tag()
    if tag.startswith("GE-Proton"):
        return tag[len("GE-Proton") :] or tag
    return tag


def proton_ge_badge_label() -> str:
    short = proton_ge_short_tag()
    return f"Proton-GE {short}" if short else "Proton-GE"


def bug_report_template_name() -> str:
    """GitHub ISSUE_TEMPLATE filename matching UI locale."""
    return "bug_report_de.md" if _ui_locale() == "de" else "bug_report.md"


def collect_report_bundle(
    recipe_id: str,
    session_id: str = "",
    *,
    data_root: Path | None = None,
    recipe_name: str = "",
    version_guaranteed: str = "",
    version_detected: str = "",
) -> Path:
    from i18n import t

    LOG_ROOT.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(LOG_ROOT, 0o700)
    except OSError:
        pass
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
    out = LOG_ROOT / f"github-report_{recipe_id}_{ts}.txt"
    runtime = describe_runtime_for_report()
    locale = _ui_locale()
    lines: list[str] = [
        t("dialog.report_file_title"),
        t("dialog.report_file_time", time=datetime.now(timezone.utc).isoformat()),
        t("dialog.report_file_recipe", recipe=recipe_id),
    ]
    if recipe_name.strip():
        lines.append(t("dialog.report_file_recipe_name", name=recipe_name.strip()))
    if version_guaranteed.strip():
        lines.append(
            t("dialog.report_file_recipe_version", version=version_guaranteed.strip())
        )
    if version_detected.strip():
        lines.append(
            t("dialog.report_file_recipe_detected", version=version_detected.strip())
        )
    lines.extend(
        [
            t("dialog.report_file_version", version=read_version()),
            t("dialog.report_file_distro", distro=detect_distro()),
            t("dialog.report_file_runtime", runtime=runtime),
            t("dialog.report_file_locale", locale=locale),
            "",
        ]
    )
    if data_root is not None:
        lines.append(
            t("dialog.report_file_data_root", path=sanitize_log_text(str(data_root)))
        )
        lines.append("")
    if session_id:
        lines.append(t("dialog.report_file_session", session=session_id))
        lines.append("")

    try:
        uname = subprocess.run(["uname", "-a"], capture_output=True, text=True, timeout=5)
        if uname.stdout:
            lines.append(
                t(
                    "dialog.report_file_kernel",
                    kernel=sanitize_log_text(uname.stdout.strip()),
                )
            )
    except OSError:
        pass
    lines.append("")

    def _append_log_files(
        files: list[Path], *, section: str, per_file_lines: int
    ) -> None:
        if not files:
            return
        lines.append(section)
        lines.append("")
        for lf in files:
            lines.append(f"--- {lf.name} ---")
            try:
                raw = lf.read_text(encoding="utf-8", errors="replace").splitlines()[
                    -per_file_lines:
                ]
                cleaned: list[str] = []
                for ln in raw:
                    h = humanize_log_line(ln) if ln.startswith("@") else ln
                    if h is None or LOG_NOISE_RE.search(h):
                        continue
                    cleaned.append(sanitize_log_text(h))
                lines.extend(cleaned or [t("dialog.report_file_empty")])
            except OSError as exc:
                lines.append(t("dialog.report_file_read_error", error=exc))
            lines.append("")

    def _rank_log(path: Path) -> tuple[int, float]:
        name = path.name.lower()
        try:
            mtime = path.stat().st_mtime
        except OSError:
            mtime = 0.0
        if "_errors" in name or name.endswith("_errors.log"):
            tier = 0
        elif name.startswith("install") or "install" in name:
            tier = 1
        elif any(k in name for k in ("repair", "validate", "launch", "winetricks")):
            tier = 2
        else:
            tier = 3
        return (tier, -mtime)

    # 1) Logs im Rezept-Datenordner (install.log, …)
    if data_root is not None and data_root.is_dir():
        seen: set[Path] = set()
        data_logs: list[Path] = []
        for pat in ("*.log", "install*.log", "*_errors.log"):
            for p in data_root.glob(pat):
                if p.is_file() and p not in seen:
                    seen.add(p)
                    data_logs.append(p)
        data_logs = sorted(data_logs, key=_rank_log)[:10]
        _append_log_files(
            data_logs,
            section=t("dialog.report_file_section_data_logs"),
            per_file_lines=200,
        )

    # 2) Globale Launcher-Logs
    if LOG_ROOT.is_dir():
        by_mtime: dict[Path, float] = {}
        patterns = (
            ["*.log"]
            if recipe_id == "launcher"
            else [f"*{recipe_id}*", "winetricks_*.log", "*_errors.log"]
        )
        for pat in patterns:
            for p in LOG_ROOT.glob(pat):
                if not p.is_file() or p.name.startswith("github-report_"):
                    continue
                try:
                    by_mtime[p] = p.stat().st_mtime
                except OSError:
                    continue
        if not by_mtime:
            for p in LOG_ROOT.glob("*.log"):
                if p.is_file() and not p.name.startswith("github-report_"):
                    try:
                        by_mtime[p] = p.stat().st_mtime
                    except OSError:
                        continue
        global_logs = sorted(by_mtime.keys(), key=_rank_log)[:12]
        _append_log_files(
            global_logs,
            section=t("dialog.report_file_section_global_logs"),
            per_file_lines=160,
        )

    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    try:
        os.chmod(out, 0o600)
    except OSError:
        pass
    return out


def build_issue_body(recipe_id: str, report_path: Path, session_id: str = "") -> str:
    """Markdown matching locale-specific GitHub bug_report template."""
    from i18n import t

    log_excerpt = sanitize_log_text(
        report_path.read_text(encoding="utf-8", errors="replace")[-24000:]
    )
    recipe_label = (
        recipe_id if recipe_id != "launcher" else t("dialog.issue_recipe_general")
    )
    runtime = describe_runtime_for_report()
    locale = _ui_locale()
    parts = [
        t("dialog.issue_problem_h"),
        "",
        t("dialog.issue_problem_hint"),
        "",
        t("dialog.issue_system_h"),
        "",
        t("dialog.issue_distro", distro=detect_distro()),
        t("dialog.issue_runtime", runtime=runtime),
        t("dialog.issue_recipe", recipe=recipe_label),
        t("dialog.issue_launcher", version=read_version()),
        t("dialog.issue_ui_locale", locale=locale),
    ]
    if session_id:
        parts.append(t("dialog.issue_session", session=session_id))
    if recipe_id in ("photoshop", "photoshop-m0nkrus"):
        parts.append(t("dialog.issue_photoshop"))
    parts.extend(
        [
            "",
            t("dialog.issue_steps_h"),
            "",
            t("dialog.issue_steps_body", recipe=recipe_label),
            "",
            t("dialog.issue_expected_h"),
            "",
            t("dialog.issue_expected_hint"),
            "",
            t("dialog.issue_actual_h"),
            "",
            t("dialog.issue_actual_hint"),
            "",
            t("dialog.issue_logs_h"),
            "",
            "```bash",
            t("dialog.issue_logs_intro"),
            log_excerpt,
            "```",
            "",
            t("dialog.issue_logs_note", name=report_path.name),
        ]
    )
    script_note = t("dialog.issue_logs_script_note").strip()
    if script_note:
        parts.extend(["", script_note])
    parts.extend(
        [
            "",
            t("dialog.issue_tried_h"),
            "",
            t("dialog.issue_tried_body"),
            "",
        ]
    )
    return "\n".join(parts)


def report_clipboard_text(recipe_id: str, report_path: Path, session_id: str = "") -> str:
    return build_issue_body(recipe_id, report_path, session_id)


def github_issue_url(recipe_id: str, report_path: Path | None = None) -> str:
    from urllib.parse import quote

    from i18n import t

    recipe_label = recipe_id if recipe_id != "launcher" else "launcher"
    title = f"[BUG] {recipe_label} — Rezeptor"
    # Short URL body — full clipboard paste fills the form
    body = (
        f"{t('dialog.issue_problem_h')}\n\n"
        f"{t('dialog.issue_url_paste_hint')}\n\n"
        f"{t('dialog.issue_system_h')}\n\n"
        f"{t('dialog.issue_distro', distro=detect_distro())}\n"
        f"{t('dialog.issue_runtime', runtime=describe_runtime_for_report())}\n"
        f"{t('dialog.issue_recipe', recipe=recipe_label)}\n"
        f"{t('dialog.issue_launcher', version=read_version())}\n"
        f"{t('dialog.issue_ui_locale', locale=_ui_locale())}\n"
    )
    if report_path is not None:
        body += f"\n{t('dialog.issue_report_file', name=report_path.name)}\n"

    template = bug_report_template_name()
    return (
        f"https://github.com/{GITHUB_REPO}/issues/new"
        f"?template={quote(template)}"
        f"&labels=bug"
        f"&title={quote(title)}"
        f"&body={quote(body)}"
    )
