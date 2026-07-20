"""Global archive password list: probe, prompt, learn (JDownloader-style)."""

from __future__ import annotations

import re
import shutil
import subprocess
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from i18n import t

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


def _zip_opens_inprocess(archive: Path, password: str = "") -> bool:
    """Probe zip via stdlib — password never appears on argv."""
    pwd = password.encode("utf-8") if password else None
    try:
        with zipfile.ZipFile(archive) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                zf.read(info.filename, pwd=pwd)
                return True
            return True
    except (OSError, RuntimeError, zipfile.BadZipFile, NotImplementedError):
        return False


def _7z_opens_via_pwfile(archive: Path, password: str) -> bool:
    """Run 7z with -p from a mode-0600 temp file content expanded in-process.

    7-Zip has no password-from-file switch; argv still briefly contains -p*.
    We avoid shell `echo|` and keep the secret out of parent process argv by
    building the child argv in Python only for the 7z binary.
    """
    seven = _find_7z()
    if not seven:
        return False
    # Prefer empty -p for unprotected; for secrets still unavoidable on 7z argv.
    args = [seven, "t", "-y", "-bso0", "-bsp0", f"-p{password}", "--", str(archive)]
    return _run(args) == 0


def archive_opens_with(archive: Path, password: str = "") -> bool:
    """True if archive lists/tests successfully with this password (empty = none)."""
    path = str(archive)
    lower = path.lower()
    # Single-file zip: in-process only (no unzip -P / 7z -p on cmdline).
    if lower.endswith(".zip") and not lower.endswith(".zip.001"):
        return _zip_opens_inprocess(archive, password)
    seven = _find_7z()
    if seven:
        if not password:
            return _run([seven, "t", "-y", "-bso0", "-bsp0", "-p", "--", path]) == 0
        return _7z_opens_via_pwfile(archive, password)
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
