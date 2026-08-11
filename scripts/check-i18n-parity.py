#!/usr/bin/env python3
"""Fail if launcher locale key sets differ between de.json and en.json."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def _flatten(obj: object, prefix: str = "") -> dict[str, object]:
    out: dict[str, object] = {}
    if not isinstance(obj, dict):
        if prefix:
            out[prefix] = obj
        return out
    for key, val in obj.items():
        if not isinstance(key, str):
            raise TypeError(f"non-string locale key under {prefix or '<root>'}: {key!r}")
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(val, dict):
            out.update(_flatten(val, path))
        else:
            out[path] = val
    return out


def _load(path: Path) -> dict[str, object]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"ERROR: cannot read {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"ERROR: {path} root must be a JSON object")
    return _flatten(data)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    de_path = root / "launcher" / "locales" / "de.json"
    en_path = root / "launcher" / "locales" / "en.json"
    for path in (de_path, en_path):
        if not path.is_file():
            print(f"ERROR: missing {path}", file=sys.stderr)
            return 1

    de_keys = set(_load(de_path))
    en_keys = set(_load(en_path))
    only_de = sorted(de_keys - en_keys)
    only_en = sorted(en_keys - de_keys)

    if not only_de and not only_en:
        print(f"OK: launcher i18n key parity ({len(de_keys)} keys)")
        return 0

    print("ERROR: launcher locale key mismatch (de.json vs en.json)", file=sys.stderr)
    if only_de:
        print(f"  only in de.json ({len(only_de)}):", file=sys.stderr)
        for key in only_de:
            print(f"    - {key}", file=sys.stderr)
    if only_en:
        print(f"  only in en.json ({len(only_en)}):", file=sys.stderr)
        for key in only_en:
            print(f"    - {key}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
