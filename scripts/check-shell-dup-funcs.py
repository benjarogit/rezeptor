#!/usr/bin/env python3
"""Warn when recipe hook scripts redefine core shell function names.

Scope (by design):
  - core/*.sh
  - recipes/*/*.sh and recipes/community/*/*.sh (hook scripts only)
  - skips _template* / _* recipe dirs
  - does not scan recipes/*/assets/ (standalone helpers)

Collision rules:
  - exact: same full name (incl. namespace::) in core and a recipe → error
  - bare: same trailing name after :: (e.g. log_err vs recipe_hooks::log_err) → error
    unless listed in scripts/shell-dup-allowlist.txt

Not part of make validate (opt-in via make shell-dup-check).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

FUNC_DEF = re.compile(
    r"(?m)^(?:function\s+)?([A-Za-z_][A-Za-z0-9_:]*)\s*\(\)\s*\{"
)


def _bare(name: str) -> str:
    return name.rsplit("::", 1)[-1]


def _load_allowlist(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    out: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.split("#", 1)[0].strip()
        if s:
            out.add(s)
    return out


def _collect(paths: list[Path]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"ERROR: cannot read {path}: {exc}", file=sys.stderr)
            raise SystemExit(2) from exc
        for match in FUNC_DEF.finditer(text):
            name = match.group(1)
            line = text.count("\n", 0, match.start()) + 1
            found.setdefault(name, []).append(f"{path}:{line}")
    return found


def _recipe_hook_scripts(root: Path) -> list[Path]:
    out: list[Path] = []
    for pattern in ("recipes/*/*.sh", "recipes/community/*/*.sh"):
        for path in sorted(root.glob(pattern)):
            if not path.is_file():
                continue
            # Skip template / private recipe dirs (_template, _foo).
            if any(part.startswith("_") for part in path.parts):
                continue
            out.append(path)
    return out


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    allow = _load_allowlist(root / "scripts" / "shell-dup-allowlist.txt")

    core_paths = sorted(p for p in (root / "core").glob("*.sh") if p.is_file())
    recipe_paths = _recipe_hook_scripts(root)
    if not core_paths:
        print("ERROR: no core/*.sh found", file=sys.stderr)
        return 2

    core = _collect(core_paths)
    recipes = _collect(recipe_paths)

    core_bare: dict[str, set[str]] = {}
    for name in core:
        core_bare.setdefault(_bare(name), set()).add(name)

    errors: list[str] = []
    for name, locs in sorted(recipes.items()):
        bare = _bare(name)
        if name in allow or bare in allow:
            continue

        if name in core:
            errors.append(
                f"exact: recipe defines {name!r} also in core/\n"
                + "\n".join(f"  recipe: {x}" for x in locs)
                + "\n"
                + "\n".join(f"  core:   {x}" for x in core[name])
            )
            continue

        if bare in core_bare:
            cores = ", ".join(sorted(core_bare[bare]))
            errors.append(
                f"bare-name: recipe defines {name!r} overlapping core {cores}\n"
                + "\n".join(f"  recipe: {x}" for x in locs)
                + "\n"
                + "  hint: move shared logic into core/ or add the bare name to "
                "scripts/shell-dup-allowlist.txt if the overlap is intentional"
            )

    if errors:
        print(
            f"ERROR: shell function overlap (core/ vs recipe hooks) — {len(errors)}",
            file=sys.stderr,
        )
        for block in errors:
            print(block, file=sys.stderr)
            print(file=sys.stderr)
        return 1

    print(
        f"OK: no unallowlisted shell function overlap "
        f"(core={len(core)} names, recipe-hooks={len(recipes)} names, "
        f"allowlist={len(allow)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
