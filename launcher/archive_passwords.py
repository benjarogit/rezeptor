"""Global archive password list: probe, prompt, learn (JDownloader-style)."""

from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from PyQt6.QtWidgets import QInputDialog, QLineEdit, QMessageBox, QWidget

from i18n import t
from settings import load_settings, prepend_archive_password, save_settings

_MAX_PASSWORD_LEN = 512
# Control chars except tab (tab → space).
_CTRL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


@dataclass
class PasswordListResult:
    passwords: list[str]
    errors: list[str] = field(default_factory=list)
    auto_fixed: bool = False
    # None = cannot produce a safe corrected text (blocking errors remain)
    corrected_text: str | None = None


def normalize_password_list_text(raw: str) -> PasswordListResult:
    """
    Parse one-password-per-line text.

    Auto-fix when possible: strip lines, drop empties/#comments, drop NULs via
    reject, tabs→space, trim, dedupe (first wins), truncate overlong with error
    if still too long after strip.
    """
    errors: list[str] = []
    auto_fixed = False
    out: list[str] = []
    seen: set[str] = set()
    corrected_lines: list[str] = []

    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    if "\r" in raw:
        auto_fixed = True

    for i, line in enumerate(text.split("\n"), start=1):
        if "\x00" in line:
            errors.append(t("settings.pw_err_null", line=i))
            continue
        if "\t" in line:
            line = line.replace("\t", " ")
            auto_fixed = True
        if _CTRL_RE.search(line):
            cleaned = _CTRL_RE.sub("", line)
            if cleaned == line:
                errors.append(t("settings.pw_err_control", line=i))
                continue
            line = cleaned
            auto_fixed = True
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            corrected_lines.append(stripped)
            continue
        if len(stripped) > _MAX_PASSWORD_LEN:
            errors.append(
                t("settings.pw_err_too_long", line=i, max=_MAX_PASSWORD_LEN)
            )
            continue
        if stripped in seen:
            auto_fixed = True
            continue
        seen.add(stripped)
        out.append(stripped)
        corrected_lines.append(stripped)

    corrected = "\n".join(corrected_lines)
    if corrected:
        corrected += "\n"

    raw_norm = "\n".join(
        ln.strip()
        for ln in text.split("\n")
        if ln.strip() and not ln.strip().startswith("#")
    )
    if raw_norm != "\n".join(out):
        auto_fixed = True

    if errors:
        return PasswordListResult(
            passwords=out,
            errors=errors,
            auto_fixed=True,
            corrected_text=corrected if corrected_lines else None,
        )

    return PasswordListResult(
        passwords=out,
        errors=[],
        auto_fixed=auto_fixed,
        corrected_text=corrected,
    )


def _find_7z() -> str | None:
    return shutil.which("7z") or shutil.which("7za")


def _run(argv: list[str], *, timeout: int = 120) -> int:
    try:
        proc = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
        return int(proc.returncode)
    except (OSError, subprocess.TimeoutExpired):
        return 1


def archive_opens_with(archive: Path, password: str = "") -> bool:
    """True if archive lists/tests successfully with this password (empty = none)."""
    path = str(archive)
    seven = _find_7z()
    if seven:
        args = [seven, "t", "-y", "-bso0", "-bsp0"]
        if password:
            args.append(f"-p{password}")
        else:
            # Explicit empty — 7z may still prompt otherwise on some builds.
            args.append("-p")
        args.extend(["--", path])
        return _run(args) == 0
    lower = path.lower()
    if lower.endswith(".zip") and shutil.which("unzip"):
        if password:
            return _run(["unzip", "-tqq", "-P", password, path]) == 0
        return _run(["unzip", "-tqq", path]) == 0
    if lower.endswith((".tar.gz", ".tgz")):
        return _run(["tar", "-tzf", path]) == 0
    return False


def archive_needs_password(archive: Path) -> bool:
    """True when archive appears encrypted (opens without password fails, with probe)."""
    if archive_opens_with(archive, ""):
        return False
    # If we cannot probe at all, do not force a prompt.
    if not _find_7z() and not str(archive).lower().endswith(".zip"):
        return False
    return True


def ensure_archive_passwords(
    parent: QWidget | None,
    archive: Path,
    *,
    extra: list[str] | None = None,
) -> list[str] | None:
    """
    Return password candidates for extract (global list, working first).

    - Unencrypted: return global list (may be empty).
    - Encrypted: try global + extra; if none work, ask until OK or cancel.
    - Working password is prepended to the global settings list.
    - Returns None if the user cancels the prompt.
    """
    settings = load_settings()
    candidates: list[str] = []
    seen: set[str] = set()
    for pw in list(extra or []) + list(settings.archive_passwords):
        p = (pw or "").strip()
        if not p or p in seen:
            continue
        seen.add(p)
        candidates.append(p)

    if not archive.is_file():
        return candidates

    if not archive_needs_password(archive):
        return candidates

    for pw in candidates:
        if archive_opens_with(archive, pw):
            if prepend_archive_password(settings, pw):
                save_settings(settings)
            # Working password first for extract order.
            rest = [c for c in candidates if c != pw]
            return [pw, *rest]

    # Not in list — ask (retry until success or cancel).
    while True:
        pw, ok = QInputDialog.getText(
            parent,
            t("source.password_ask_title"),
            t("source.password_ask_body", name=archive.name),
            QLineEdit.EchoMode.Password,
        )
        if not ok:
            return None
        pw = (pw or "").strip()
        if not pw:
            QMessageBox.warning(
                parent,
                t("source.password_ask_title"),
                t("source.password_empty"),
            )
            continue
        if archive_opens_with(archive, pw):
            if prepend_archive_password(settings, pw):
                save_settings(settings)
            rest = [c for c in candidates if c != pw]
            return [pw, *rest]
        QMessageBox.warning(
            parent,
            t("source.password_ask_title"),
            t("source.password_wrong"),
        )
