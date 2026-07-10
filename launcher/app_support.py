"""Version, Updates, Log-Sanitisierung, GitHub-Issue-Hilfe."""

from __future__ import annotations

import json
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
LOG_ROOT = Path.home() / ".local/share/wine-software/logs"
LOG_RETENTION_DAYS = 14
LOG_MAX_FILES = 50

SENSITIVE_PATTERNS = [
    (re.compile(r"/home/[^/\s]+", re.I), "/home/<USER>"),
    (re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "<EMAIL>"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"), "<IP>"),
    (re.compile(r"(?i)(token|api[_-]?key|password|secret)\s*[:=]\s*\S+"), r"\1=<REDACTED>"),
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


VERSION_OK_RE = re.compile(
    r"^OK: .+?:\s*(.+?)\s*\(getestet & garantiert\)\s*$"
)


def parse_wiso_portable_version(path: str) -> str:
    root = Path(path)
    for sw in sorted(root.glob("Steuersoftware*")):
        if not sw.is_dir():
            continue
        for wcrc in sorted(sw.glob("wcrc32list*.txt")):
            for line in wcrc.read_text(encoding="utf-8", errors="replace").splitlines():
                line = line.strip()
                if line.upper().startswith("VERSION"):
                    ver = line.split("=", 1)[-1].strip()
                    if ver:
                        return ver
    name = root.name
    m = re.match(r"^WISO\.([0-9]+(?:\.[0-9]+){0,3})\.Portable$", name)
    return m.group(1) if m else ""


def detect_source_version(rid: str, path: str) -> str:
    if rid == "wiso-steuer":
        return parse_wiso_portable_version(path)
    return ""


def parse_validate_version_fields(output: str) -> tuple[str, str]:
    detected = ""
    version_warn = ""
    for line in output.splitlines():
        m = VERSION_OK_RE.match(line.strip())
        if m:
            detected = m.group(1).strip()
            continue
        if line.startswith("WARN:") and "garantiert" in line:
            version_warn = line[5:].strip()
    return detected, version_warn


def version_guarantee_mismatch(guaranteed: str, detected: str) -> bool:
    if not guaranteed or not detected:
        return False
    return guaranteed.strip() != detected.strip()


def prune_old_logs(
    log_root: Path = LOG_ROOT,
    *,
    retention_days: int | None = None,
    max_files: int | None = None,
) -> int:
    """Alte Log-Dateien entfernen (Retention). Returns count deleted."""
    if not log_root.is_dir():
        return 0

    days = LOG_RETENTION_DAYS if retention_days is None else retention_days
    cap = LOG_MAX_FILES if max_files is None else max_files
    cutoff = time.time() - days * 86400
    files = sorted(
        (p for p in log_root.iterdir() if p.is_file()),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
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
    return removed


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


def collect_report_bundle(recipe_id: str, session_id: str = "") -> Path:
    LOG_ROOT.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
    out = LOG_ROOT / f"github-report_{recipe_id}_{ts}.txt"
    lines: list[str] = [
        "Rezeptor — Fehlerbericht (sanitisiert)",
        f"Zeit (UTC): {datetime.now(timezone.utc).isoformat()}",
        f"Rezept: {recipe_id}",
        f"Version: {read_version()}",
        f"Distro: {detect_distro()}",
        "",
    ]
    if session_id:
        lines.append(f"Interne Session-ID (Support): {session_id}")
        lines.append("")

    try:
        uname = subprocess.run(["uname", "-a"], capture_output=True, text=True, timeout=5)
        if uname.stdout:
            lines.append(f"Kernel: {sanitize_log_text(uname.stdout.strip())}")
    except OSError:
        pass
    lines.append("")

    if LOG_ROOT.is_dir():
        pattern = f"*{recipe_id}*" if recipe_id != "launcher" else "*.log"
        logs = sorted(LOG_ROOT.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)[:3]
        if not logs:
            logs = sorted(LOG_ROOT.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)[:3]
        for lf in logs:
            lines.append(f"--- {lf.name} ---")
            try:
                raw = lf.read_text(encoding="utf-8", errors="replace").splitlines()[-60:]
                cleaned: list[str] = []
                for ln in raw:
                    h = humanize_log_line(ln) if ln.startswith("@") else ln
                    if h is None or LOG_NOISE_RE.search(h):
                        continue
                    cleaned.append(sanitize_log_text(h))
                lines.extend(cleaned or ["(keine lesbaren Zeilen)"])
            except OSError as exc:
                lines.append(f"(Lesefehler: {exc})")
            lines.append("")

    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def build_issue_body(recipe_id: str, report_path: Path, session_id: str = "") -> str:
    """Markdown gemäß .github/ISSUE_TEMPLATE/bug_report.md"""
    log_excerpt = sanitize_log_text(
        report_path.read_text(encoding="utf-8", errors="replace")[-8000:]
    )
    recipe_label = recipe_id if recipe_id != "launcher" else "Rezeptor (allgemein)"
    ps_line = f"- **Photoshop:** CC 2021\n" if recipe_id == "photoshop" else ""
    session_note = f"\n- **Support-Session:** `{session_id}` (nur intern)" if session_id else ""

    return f"""## 🐛 Problem

(Kurz beschreiben — was ist schiefgelaufen?)

## 📋 System

- **Distro:** {detect_distro()}
- **Runtime:** Proton-GE (`core/runtime.lock`) — run: `source core/wine-runtime.sh && wine_runtime::describe`
- **Rezept:** {recipe_label}
- **Launcher-Version:** v{read_version()}{session_note}
{ps_line}
## 🔍 Schritte zum Reproduzieren

1. Rezeptor starten
2. Rezept „{recipe_label}" wählen
3. (Aktion: Installieren / Reparieren / …)

## ✅ Erwartetes Verhalten

Was sollte passieren?

## ❌ Tatsächliches Verhalten

Was passiert stattdessen?

## 📸 Logs

```bash
# Relevante Logs (sanitisiert)
{log_excerpt}
```

Vollständiger Report: `~/.local/share/wine-software/logs/{report_path.name}`

## 🔧 Bereits versucht

- [ ] `./pre-check.sh` ausgeführt
- [ ] `./core/troubleshoot.sh` ausgeführt
- [ ] GPU in Photoshop deaktiviert
- [ ] Logs geprüft
"""


def report_clipboard_text(recipe_id: str, report_path: Path, session_id: str = "") -> str:
    return build_issue_body(recipe_id, report_path, session_id)


def github_issue_url(recipe_id: str, report_path: Path | None = None) -> str:
    from urllib.parse import quote

    recipe_label = recipe_id if recipe_id != "launcher" else "launcher"
    title = f"[BUG] {recipe_label} — Rezeptor"
    # Kurzer Body in URL — volles Template kommt aus Zwischenablage (Strg+V)
    body = (
        "## 🐛 Problem\n\n"
        "(Details und Logs aus der Zwischenablage unten einfügen — Strg+V)\n\n"
        f"## 📋 System\n\n"
        f"- **Distro:** {detect_distro()}\n"
        f"- **Rezept:** {recipe_label}\n"
        f"- **Launcher-Version:** v{read_version()}\n"
    )
    if report_path is not None:
        body += f"\nReport-Datei: `{report_path.name}`\n"

    return (
        f"https://github.com/{GITHUB_REPO}/issues/new"
        f"?template=bug_report.md"
        f"&labels=bug"
        f"&title={quote(title)}"
        f"&body={quote(body)}"
    )
