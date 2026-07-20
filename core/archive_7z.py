#!/usr/bin/env python3
"""7z extract with password read from a file (never on parent shell argv).

Usage:
  archive_7z.py extract <7z_bin> <archive> <dest> [password_file]

The password file path may appear in argv; the secret itself must not.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _read_password(path: str | None) -> str | None:
    if not path:
        return None
    p = Path(path)
    if not p.is_file():
        return None
    raw = p.read_bytes()
    if raw.endswith(b"\n"):
        raw = raw[:-1]
    if raw.endswith(b"\r"):
        raw = raw[:-1]
    if not raw:
        return None
    return raw.decode("utf-8", errors="surrogateescape")


def _extract(seven: str, archive: Path, dest: Path, password: str | None) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    args = [seven, "x", "-y", f"-o{dest}"]
    if password is not None:
        args.append(f"-p{password}")
    args.extend(["--", str(archive)])
    try:
        proc = subprocess.run(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return proc.returncode
    except OSError:
        return 1


def main(argv: list[str]) -> int:
    if len(argv) < 5 or argv[1] != "extract":
        print("usage: archive_7z.py extract <7z_bin> <archive> <dest> [password_file]", file=sys.stderr)
        return 2
    seven = argv[2]
    archive = Path(argv[3])
    dest = Path(argv[4])
    pwd = _read_password(argv[5] if len(argv) > 5 else None)
    return _extract(seven, archive, dest, pwd)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
