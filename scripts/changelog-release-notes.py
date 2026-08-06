#!/usr/bin/env python3
"""Extract CHANGELOG.md section for GitHub Release notes (English bullets)."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: changelog-release-notes.py <version> [CHANGELOG.md]", file=sys.stderr)
        return 2
    ver = sys.argv[1]
    path = Path(sys.argv[2] if len(sys.argv) > 2 else "CHANGELOG.md")
    if not path.is_file():
        return 0
    text = path.read_text(encoding="utf-8")
    pat = rf"(?ms)^## \[{re.escape(ver)}\][^\n]*\n(.*?)(?=^## \[|\Z)"
    m = re.search(pat, text)
    if not m:
        return 0
    body = m.group(1).strip()
    if len(body) < 40:
        return 0
    print("## What's Changed / Änderungen\n")
    print(body)
    print()
    print(f"**Full Changelog / Vollständiger Changelog**: see `CHANGELOG.md` ({ver})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
