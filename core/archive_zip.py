#!/usr/bin/env python3
"""Zip test/extract with password without putting the secret on argv.

Usage:
  archive_zip.py test  <archive> [password_file]
  archive_zip.py extract <archive> <dest> [password_file]

Password is read from password_file (or empty if omitted). Never pass the
password as a CLI argument — /proc cmdline must not see it.
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path


def _read_password(path: str | None) -> bytes | None:
    if not path:
        return None
    p = Path(path)
    if not p.is_file():
        return None
    raw = p.read_bytes()
    # Strip a single trailing newline (common for password files).
    if raw.endswith(b"\n"):
        raw = raw[:-1]
    if raw.endswith(b"\r"):
        raw = raw[:-1]
    return raw or None


def _test(archive: Path, pwd: bytes | None) -> int:
    try:
        with zipfile.ZipFile(archive) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                zf.read(info.filename, pwd=pwd)
                return 0
            # Empty archive — treat as openable.
            return 0
    except (OSError, RuntimeError, zipfile.BadZipFile, NotImplementedError):
        return 1


def _extract(archive: Path, dest: Path, pwd: bytes | None) -> int:
    try:
        dest.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(dest, pwd=pwd)
        return 0
    except (OSError, RuntimeError, zipfile.BadZipFile, NotImplementedError):
        return 1


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: archive_zip.py test|extract ...", file=sys.stderr)
        return 2
    cmd = argv[1]
    archive = Path(argv[2])
    if cmd == "test":
        pwd = _read_password(argv[3] if len(argv) > 3 else None)
        return _test(archive, pwd)
    if cmd == "extract":
        if len(argv) < 4:
            return 2
        dest = Path(argv[3])
        pwd = _read_password(argv[4] if len(argv) > 4 else None)
        return _extract(archive, dest, pwd)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
