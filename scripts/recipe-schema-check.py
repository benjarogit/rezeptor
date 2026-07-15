#!/usr/bin/env python3
"""Validate recipe.yml against recipes/recipe.schema.json (embedded + optional jsonschema)."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "recipes" / "recipe.schema.json"

REQUIRED = (
    "id",
    "name",
    "icon",
    "data_root",
    "runtime",
    "install_type",
    "source_kind",
    "fix_kind",
    "install",
    "launch",
    "validate",
    "repair",
    "kill",
    "install_steps",
)
RUNTIMES = {"proton-ge", "system"}
INSTALL_TYPES = {
    "installer_offline",
    "portable_launch",
    "portable_bootstrap",
    "game_install",
    "game_portable",
    "adobe_offline",
    "portable",
}
SOURCE_KINDS = {"folder", "installer", "archive", "fixed_path"}
FIX_KINDS = {"none", "optional", "required"}
PLAIN_STEPS = {
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
}
OBJECT_STEP_KEYS = {
    "module",
    "copy_asset",
    "env_set",
    "progress",
    "winetricks",
    "vcrun",
    "dotnet",
}


def load_recipe(path: Path) -> dict:
    """Load via recipe-yaml-read logic (inline import of module file)."""
    import importlib.util

    mod_path = ROOT / "scripts" / "recipe-yaml-read.py"
    spec = importlib.util.spec_from_file_location("recipe_yaml_read", mod_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"ERROR: cannot load {mod_path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod._load_yaml(path)


def validate_embedded(data: dict, label: str) -> list[str]:
    errs: list[str] = []
    for key in REQUIRED:
        if key not in data or data[key] in (None, ""):
            errs.append(f"{label}: Pflichtfeld fehlt: {key}")

    rid = str(data.get("id", ""))
    if rid and not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", rid):
        errs.append(f"{label}: ungültige id: {rid}")

    runtime = data.get("runtime")
    if runtime is not None and runtime not in RUNTIMES:
        errs.append(f"{label}: runtime muss proton-ge oder system sein (ist: {runtime})")

    it = data.get("install_type")
    if it is not None and it not in INSTALL_TYPES:
        errs.append(f"{label}: unbekannter install_type: {it}")
    if it in ("adobe_offline", "portable"):
        errs.append(f"{label}: WARN install_type '{it}' ist deprecated")

    sk = data.get("source_kind")
    if sk is not None and sk not in SOURCE_KINDS:
        errs.append(f"{label}: unbekannter source_kind: {sk}")
    fk = data.get("fix_kind")
    if fk is not None and fk not in FIX_KINDS:
        errs.append(f"{label}: unbekannter fix_kind: {fk}")

    if sk == "archive" and not data.get("source_formats"):
        errs.append(f"{label}: source_kind=archive erfordert source_formats")
    if sk == "fixed_path" and not data.get("installer_dir"):
        errs.append(f"{label}: fixed_path erfordert installer_dir")

    steps = data.get("install_steps")
    if steps is None:
        return errs
    if not isinstance(steps, list) or len(steps) < 1:
        errs.append(f"{label}: install_steps muss nicht-leere Liste sein")
        return errs

    for idx, step in enumerate(steps):
        if isinstance(step, str):
            if step not in PLAIN_STEPS:
                errs.append(f"{label}: install_steps[{idx}]: unbekannter Schritt '{step}'")
            continue
        if isinstance(step, dict):
            if len(step) != 1:
                errs.append(f"{label}: install_steps[{idx}]: Objekt braucht genau einen Key")
                continue
            key = next(iter(step))
            val = step[key]
            if key in PLAIN_STEPS and (val is True or val is None or val == ""):
                continue
            if key == "winetricks" and isinstance(val, list):
                continue
            if key == "module" and isinstance(val, str) and "::" in val:
                continue
            if key == "copy_asset" and isinstance(val, dict):
                if not val.get("src") or not val.get("dest"):
                    errs.append(f"{label}: install_steps[{idx}]: copy_asset braucht src+dest")
                continue
            if key == "env_set" and isinstance(val, dict):
                if not val.get("key"):
                    errs.append(f"{label}: install_steps[{idx}]: env_set braucht key")
                continue
            if key == "progress":
                continue
            if key in OBJECT_STEP_KEYS:
                continue
            # Allow recipe-specific typed steps (vcrun, dotnet, …) as string or object
            if isinstance(val, (str, dict, list, bool)) or val is None:
                continue
            errs.append(f"{label}: install_steps[{idx}]: ungültiger Schritt {key!r}")
            continue
        errs.append(f"{label}: install_steps[{idx}]: ungültiger Typ")
    return errs


def validate_jsonschema(data: dict, label: str) -> list[str]:
    try:
        import jsonschema  # type: ignore
    except ImportError:
        return []
    if not SCHEMA_PATH.is_file():
        return [f"{label}: Schema fehlt: {SCHEMA_PATH}"]
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)
    return [f"{label}: {e.message}" for e in sorted(validator.iter_errors(data), key=lambda e: list(e.path))]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("recipes", nargs="*", type=Path, help="recipe.yml paths (default: all)")
    ap.add_argument("--strict-jsonschema", action="store_true")
    args = ap.parse_args()

    paths = args.recipes
    if not paths:
        recipes_root = ROOT / "recipes"
        paths = sorted(recipes_root.glob("*/recipe.yml"))
        community = recipes_root / "community"
        if community.is_dir():
            paths.extend(sorted(community.glob("*/recipe.yml")))

    errors = 0
    warnings = 0
    for yml in paths:
        if not yml.is_file():
            print(f"ERROR: fehlt {yml}", file=sys.stderr)
            errors += 1
            continue
        if yml.parent.name.startswith("_"):
            continue
        if yml.parent.name == "community":
            continue
        label = yml.parent.name
        try:
            data = load_recipe(yml)
        except SystemExit as exc:
            print(str(exc), file=sys.stderr)
            errors += 1
            continue
        except Exception as exc:  # noqa: BLE001
            print(f"ERROR: {label}: parse failed: {exc}", file=sys.stderr)
            errors += 1
            continue

        for msg in validate_embedded(data, label):
            if msg.startswith(f"{label}: WARN"):
                print(f"WARN: {msg}", file=sys.stderr)
                warnings += 1
            else:
                print(f"ERROR: {msg}", file=sys.stderr)
                errors += 1

        # jsonschema is optional (no PyPI requirement); use when installed
        for msg in validate_jsonschema(data, label):
            print(f"ERROR: {msg}", file=sys.stderr)
            errors += 1

    if errors:
        print(f"recipe-schema-check: {errors} Fehler, {warnings} Warnungen", file=sys.stderr)
        return 1
    print(f"recipe-schema-check: OK ({warnings} Warnungen)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
