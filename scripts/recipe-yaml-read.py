#!/usr/bin/env python3
"""Read recipe.yml fields — especially nested install_steps.

Usage:
  recipe-yaml-read.py <recipe.yml> --json
  recipe-yaml-read.py <recipe.yml> --key id
  recipe-yaml-read.py <recipe.yml> --install-steps
  recipe-yaml-read.py <recipe.yml> --install-steps-lines
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def _load_yaml(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(text)
        if not isinstance(data, dict):
            raise SystemExit(f"ERROR: {path}: root must be a mapping")
        return data
    except ImportError:
        return _load_yaml_minimal(text, path)


def _load_yaml_minimal(text: str, path: Path) -> dict[str, Any]:
    """Subset parser for recipe.yml when PyYAML is unavailable."""
    data: dict[str, Any] = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        raw = lines[i]
        if not raw.strip() or raw.lstrip().startswith("#"):
            i += 1
            continue
        if raw.startswith(" ") or raw.startswith("\t"):
            raise SystemExit(
                f"ERROR: {path}:{i + 1}: unexpected indent (install PyYAML for nested YAML)"
            )
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", raw)
        if not m:
            i += 1
            continue
        key, rest = m.group(1), m.group(2).strip()
        if key == "install_steps":
            steps, i = _parse_install_steps(lines, i + 1)
            data[key] = steps
            continue
        if key == "env":
            env, i = _parse_simple_map(lines, i + 1)
            data[key] = env
            continue
        if key == "winetricks" and rest.startswith("["):
            data[key] = _parse_flow_list(rest)
            i += 1
            continue
        if rest == "" or rest == "|" or rest == ">":
            # block scalar / empty — skip nested until next top-level
            i += 1
            while i < len(lines) and (
                not lines[i].strip()
                or lines[i].startswith(" ")
                or lines[i].startswith("\t")
                or lines[i].lstrip().startswith("#")
            ):
                i += 1
            data[key] = rest
            continue
        data[key] = _unquote(rest)
        i += 1
    return data


def _parse_flow_list(s: str) -> list[str]:
    s = s.strip()
    if s.startswith("[") and s.endswith("]"):
        s = s[1:-1]
    out: list[str] = []
    for part in s.split(","):
        part = _unquote(part.strip())
        if part:
            out.append(part)
    return out


def _unquote(s: str) -> str:
    if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
        return s[1:-1]
    return s


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _parse_simple_map(lines: list[str], start: int) -> tuple[dict[str, str], int]:
    out: dict[str, str] = {}
    i = start
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if _indent(line) == 0:
            break
        m = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        out[m.group(1)] = _unquote(m.group(2).strip())
        i += 1
    return out, i


def _parse_install_steps(lines: list[str], start: int) -> tuple[list[Any], int]:
    steps: list[Any] = []
    i = start
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if _indent(line) == 0:
            break
        stripped = line.strip()
        if not stripped.startswith("- "):
            raise SystemExit(f"ERROR: install_steps line {i + 1}: expected list item")
        item = stripped[2:].strip()
        # Nested object: "- copy_asset:" then indented keys
        if item.endswith(":") and not item.startswith("["):
            step_key = item[:-1].strip()
            props: dict[str, Any] = {}
            i += 1
            while i < len(lines):
                sub = lines[i]
                if not sub.strip() or sub.lstrip().startswith("#"):
                    i += 1
                    continue
                if _indent(sub) <= _indent(line):
                    break
                sm = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*)$", sub)
                if not sm:
                    i += 1
                    continue
                val = sm.group(2).strip()
                if val.startswith("["):
                    props[sm.group(1)] = _parse_flow_list(val)
                else:
                    props[sm.group(1)] = _unquote(val)
                i += 1
            steps.append({step_key: props if props else True})
            continue
        # Inline object: "- module: recipe_wiso::foo"
        if ":" in item and not item.startswith("["):
            k, _, v = item.partition(":")
            k, v = k.strip(), v.strip()
            if v.startswith("["):
                steps.append({k: _parse_flow_list(v)})
            else:
                steps.append({k: _unquote(v)})
            i += 1
            continue
        # Plain string step
        steps.append(_unquote(item))
        i += 1
    return steps, i


def normalize_step(step: Any) -> dict[str, Any]:
    """Normalize one install_steps entry to {type, ...}."""
    if isinstance(step, str):
        return {"type": step}
    if isinstance(step, dict):
        if len(step) != 1:
            raise SystemExit(f"ERROR: install_steps object must have one key: {step!r}")
        key, val = next(iter(step.items()))
        if key in (
            "prepare_source",
            "require_portable",
            "prefix",
            "winetricks",
            "deploy_graphics",
            "run_installer",
            "stabilize_prefix",
            "win10",
            "fonts_registry",
            "emit_log_paths",
        ) and (val is True or val is None or val == ""):
            return {"type": key}
        if key == "winetricks":
            pkgs = val if isinstance(val, list) else [str(val)]
            return {"type": "winetricks", "packages": pkgs}
        if key == "module":
            return {"type": "module", "name": str(val)}
        if key == "copy_asset":
            if not isinstance(val, dict):
                raise SystemExit("ERROR: copy_asset needs src/dest mapping")
            return {
                "type": "copy_asset",
                "src": str(val.get("src", "")),
                "dest": str(val.get("dest", "")),
                "mode": str(val.get("mode", "755")),
            }
        if key == "env_set":
            if not isinstance(val, dict):
                raise SystemExit("ERROR: env_set needs key/value mapping")
            return {
                "type": "env_set",
                "file": str(val.get("file", "portable.env")),
                "key": str(val.get("key", "")),
                "value": str(val.get("value", "")),
            }
        if key == "progress":
            if isinstance(val, dict):
                return {
                    "type": "progress",
                    "pct": int(val.get("pct", 0)),
                    "label": str(val.get("label", "")),
                }
            return {"type": "progress", "pct": int(val), "label": ""}
        # Generic module-like: unknown key with string → treat as typed step with arg
        if isinstance(val, str):
            return {"type": key, "arg": val}
        if isinstance(val, dict):
            out = {"type": key}
            out.update(val)
            return out
        if isinstance(val, list):
            return {"type": key, "packages": val}
        return {"type": key}
    raise SystemExit(f"ERROR: invalid install_steps entry: {step!r}")


def steps_as_lines(steps: list[Any]) -> list[str]:
    """Emit one JSON object per line for bash consumption."""
    return [json.dumps(normalize_step(s), ensure_ascii=False) for s in steps]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("recipe_yml", type=Path)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--json", action="store_true", help="Dump full recipe as JSON")
    g.add_argument("--key", help="Print a top-level scalar key")
    g.add_argument("--install-steps", action="store_true", help="JSON array of steps")
    g.add_argument(
        "--install-steps-lines",
        action="store_true",
        help="One normalized JSON step per line",
    )
    args = ap.parse_args()
    if not args.recipe_yml.is_file():
        print(f"ERROR: missing {args.recipe_yml}", file=sys.stderr)
        return 1
    data = _load_yaml(args.recipe_yml)
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return 0
    if args.key:
        val = data.get(args.key)
        if val is None:
            return 1
        if isinstance(val, (dict, list)):
            print(json.dumps(val, ensure_ascii=False))
        else:
            print(val)
        return 0
    steps = data.get("install_steps")
    if steps is None:
        print("ERROR: install_steps missing", file=sys.stderr)
        return 1
    if not isinstance(steps, list):
        print("ERROR: install_steps must be a list", file=sys.stderr)
        return 1
    if args.install_steps:
        print(json.dumps([normalize_step(s) for s in steps], ensure_ascii=False, indent=2))
        return 0
    for line in steps_as_lines(steps):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
