"""Deklarative Versionserkennung aus recipe.yml → version_detect.

Rezeptor-Kern: jedes Rezept mit version_guaranteed soll version_detect angeben.
Signale werden der Reihe nach versucht; erstes Treffer-Ergebnis gewinnt
(außer kind: stack, das selbst Teil-/Voll-Ergebnisse liefert).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def load_recipe_mapping(recipe_yml: Path) -> dict[str, Any]:
    """recipe.yml als Mapping (PyYAML oder Minimalparser).

    AppImage und Checkout müssen sich identisch verhalten: Wenn PyYAML
    installiert ist und strict-YAML scheitert, Fallback auf denselben
    Minimalparser wie ohne PyYAML — nie ungefilterte Parse-Exceptions.
    """
    text = recipe_yml.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(text)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return _load_recipe_mapping_minimal(text)


def _load_recipe_mapping_minimal(text: str) -> dict[str, Any]:
    # Minimal: top-level Skalare + version_detect-Liste
    data: dict[str, Any] = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        raw = lines[i]
        if not raw.strip() or raw.lstrip().startswith("#"):
            i += 1
            continue
        if raw.startswith(" ") or raw.startswith("\t"):
            i += 1
            continue
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", raw)
        if not m:
            i += 1
            continue
        key, rest = m.group(1), m.group(2).strip()
        if key == "version_detect":
            items, i = _parse_version_detect_block(lines, i + 1)
            data[key] = items
            continue
        if rest.startswith("[") and rest.endswith("]"):
            data[key] = [
                _unquote(x) for x in rest[1:-1].split(",") if x.strip()
            ]
            i += 1
            continue
        if rest == "" or rest in ("|", ">"):
            i += 1
            while i < len(lines) and (
                not lines[i].strip()
                or lines[i].startswith((" ", "\t"))
                or lines[i].lstrip().startswith("#")
            ):
                i += 1
            data[key] = rest
            continue
        data[key] = _unquote(rest)
        i += 1
    return data


def _parse_version_detect_block(
    lines: list[str], start: int
) -> tuple[list[dict[str, Any]], int]:
    """Parst version_detect: - kind: … Blöcke ohne PyYAML."""
    items: list[dict[str, Any]] = []
    i = start
    current: dict[str, Any] | None = None
    while i < len(lines):
        raw = lines[i]
        if raw.strip() and not raw.startswith((" ", "\t")) and not raw.lstrip().startswith("#"):
            break
        if not raw.strip() or raw.lstrip().startswith("#"):
            i += 1
            continue
        # "- kind: foo" oder "  key: value"
        stripped = raw.strip()
        if stripped.startswith("- "):
            if current:
                items.append(current)
            current = {}
            rest = stripped[2:].strip()
            if ":" in rest:
                k, _, v = rest.partition(":")
                current[k.strip()] = _parse_scalar(v.strip())
            i += 1
            continue
        if current is not None and ":" in stripped:
            k, _, v = stripped.partition(":")
            key = k.strip()
            val = v.strip()
            if val.startswith("[") and val.endswith("]"):
                current[key] = [
                    _unquote(x) for x in val[1:-1].split(",") if x.strip()
                ]
            elif val == "":
                # nested map or list
                nested, i = _parse_nested_map_or_list(lines, i + 1)
                current[key] = nested
                continue
            else:
                current[key] = _parse_scalar(val)
        i += 1
    if current:
        items.append(current)
    return items, i


def _parse_nested_map_or_list(
    lines: list[str], start: int
) -> tuple[Any, int]:
    i = start
    # detect list vs map by first item
    while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("#")):
        i += 1
    if i >= len(lines):
        return {}, i
    first = lines[i]
    if not first.startswith((" ", "\t")):
        return {}, i
    if first.strip().startswith("- "):
        items: list[str] = []
        while i < len(lines):
            raw = lines[i]
            if raw.strip() and not raw.startswith((" ", "\t")):
                break
            if not raw.strip() or raw.lstrip().startswith("#"):
                i += 1
                continue
            st = raw.strip()
            if st.startswith("- "):
                items.append(_parse_scalar(st[2:].strip()))
                i += 1
                continue
            break
        return items, i
    mapping: dict[str, str] = {}
    while i < len(lines):
        raw = lines[i]
        if raw.strip() and not raw.startswith((" ", "\t")):
            break
        if not raw.strip() or raw.lstrip().startswith("#"):
            i += 1
            continue
        st = raw.strip()
        if st.startswith("- "):
            break
        if ":" in st:
            k, _, v = st.partition(":")
            mapping[k.strip()] = _parse_scalar(v.strip())
        i += 1
    return mapping, i


def _parse_scalar(val: str) -> Any:
    val = _unquote(val)
    if val.lower() in ("true", "false"):
        return val.lower() == "true"
    return val


def _pe_field(exe: Path, field: str) -> str:
    try:
        data = exe.read_bytes()
    except OSError:
        return ""
    marker = f"{field}\x00".encode("utf-16le")
    i = data.find(marker)
    if i < 0:
        return ""
    chunk = data[i + len(marker) : i + len(marker) + 160]
    try:
        s = chunk.decode("utf-16le", errors="ignore")
    except Exception:
        return ""
    return s.split("\x00", 1)[0].strip()


def _pe_contains(exe: Path, needles: list[str]) -> bool:
    try:
        data = exe.read_bytes()
    except OSError:
        return False
    low = data.lower()
    return all(n.encode("utf-8", errors="ignore").lower() in low for n in needles)


def _resolve_globs(root: Path, pattern: str) -> list[Path]:
    pattern = pattern.strip()
    if not pattern:
        return []
    # "." = der Root selbst (PE/Trainer-Regeln); pathlib 3.14 lehnt glob(".") ab
    if pattern in (".", "./"):
        return [root] if root.exists() else []
    if root.is_file():
        # selected installer EXE: match against file itself or siblings
        if pattern in ("", Path(pattern).name) or root.match(pattern) or root.name == pattern:
            return [root]
        parent = root.parent
        try:
            return sorted(parent.glob(pattern)) + sorted(parent.glob("*/" + pattern))
        except ValueError:
            return [root] if root.name == pattern else []
    try:
        hits = sorted(root.glob(pattern))
    except ValueError:
        return []
    if not hits and "**" not in pattern:
        try:
            hits = sorted(root.glob("**/" + pattern.lstrip("/")))
        except ValueError:
            hits = []
    return [p for p in hits if p.is_file() or p.is_dir()]


def _run_signal(root: Path, rule: dict[str, Any], guaranteed: str) -> str:
    kind = str(rule.get("kind", "")).strip()
    if not kind:
        return ""

    if kind == "json_key":
        key = str(rule.get("key", "")).strip()
        glob_pat = str(rule.get("glob") or rule.get("file") or "").strip()
        if not key or not glob_pat:
            return ""
        for path in _resolve_globs(root, glob_pat):
            if not path.is_file():
                continue
            try:
                data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(data, dict) and key in data and data[key] is not None:
                return str(data[key]).strip()
        return ""

    if kind == "text_regex":
        glob_pat = str(rule.get("glob") or rule.get("file") or "").strip()
        regex = str(rule.get("regex", "")).strip()
        if not glob_pat or not regex:
            return ""
        cre = re.compile(regex)
        for path in _resolve_globs(root, glob_pat):
            if not path.is_file():
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for line in text.splitlines():
                m = cre.search(line.strip())
                if m:
                    return (m.group(1) if m.lastindex else m.group(0)).strip()
        return ""

    if kind == "path_regex":
        regex = str(rule.get("regex", "")).strip()
        if not regex:
            return ""
        cre = re.compile(regex)
        candidates = [root.name, str(root)]
        if root.is_dir():
            candidates.extend(p.name for p in root.iterdir() if p.is_dir())
        for name in candidates:
            m = cre.search(name)
            if m:
                return (m.group(1) if m.lastindex else m.group(0)).strip()
        return ""

    if kind == "pe_field":
        field = str(rule.get("field", "FileVersion")).strip() or "FileVersion"
        glob_pat = str(rule.get("glob") or rule.get("file") or "*.exe").strip()
        for path in _resolve_globs(root, glob_pat):
            if path.is_file() and path.suffix.lower() == ".exe":
                ver = _pe_field(path, field)
                if ver and not ver.startswith("\\"):
                    return ver
        return ""

    if kind == "pe_contains":
        needles = rule.get("contains") or rule.get("any_of") or []
        if isinstance(needles, str):
            needles = [needles]
        needles = [str(n) for n in needles if str(n).strip()]
        glob_pat = str(rule.get("glob") or rule.get("file") or "*.exe").strip()
        label = str(rule.get("value") or rule.get("label") or guaranteed).strip()
        if not needles or not label:
            return ""
        targets = _resolve_globs(root, glob_pat)
        if root.is_file() and root.suffix.lower() == ".exe":
            targets = [root] + targets
        for path in targets:
            if path.is_file() and _pe_contains(path, needles):
                return label
        return ""

    if kind == "filename_regex":
        regex = str(rule.get("regex", "")).strip()
        label = str(rule.get("value") or rule.get("label") or guaranteed).strip()
        if not regex:
            return ""
        cre = re.compile(regex)
        names = [root.name]
        if root.is_dir():
            names.extend(p.name for p in root.iterdir() if p.is_file())
        for name in names:
            if cre.search(name):
                return label or name
        return ""

    if kind == "stack":
        return _run_stack(root, rule, guaranteed)

    return ""


def _read_ini_map(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";", "[")):
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


def _run_stack(root: Path, rule: dict[str, Any], guaranteed: str) -> str:
    """Mehrere Dateien + optional INI-Keys → ok_label oder partial_label."""
    if not root.is_dir():
        return ""
    require_files = rule.get("require_files") or []
    if isinstance(require_files, str):
        require_files = [require_files]
    missing = [f for f in require_files if not (root / str(f)).is_file()]
    ini_rel = str(rule.get("ini", "")).strip()
    require_ini = rule.get("require_ini") or {}
    if not isinstance(require_ini, dict):
        require_ini = {}
    ini_map: dict[str, str] = {}
    if ini_rel and (root / ini_rel).is_file():
        ini_map = _read_ini_map(root / ini_rel)
    appids_ok = all(str(ini_map.get(k, "")) == str(v) for k, v in require_ini.items())
    files_ok = not missing

    identity = str(rule.get("identity_file", "")).strip()
    if identity and not (root / identity).is_file():
        return ""

    ok_label = str(rule.get("ok_label") or guaranteed).strip()
    build_key = str(rule.get("build_key", "")).strip()
    if files_ok and appids_ok and ok_label:
        if build_key and ini_map.get(build_key):
            return f"{ok_label} (Build {ini_map[build_key]})"
        return ok_label

    partial = str(rule.get("partial_label") or "").strip()
    if not partial:
        return ""
    parts = [partial]
    if missing:
        parts.append("Dateien unvollständig")
    elif require_ini and not appids_ok:
        got = "/".join(f"{k}={ini_map.get(k, '?')}" for k in require_ini)
        parts.append(f"INI abweichend ({got})")
    return " — ".join(parts)


def detect_with_rules(
    path: str,
    rules: list[dict[str, Any]],
    *,
    guaranteed: str = "",
) -> str:
    root = Path(path)
    if not path or (not root.exists()):
        return ""
    for rule in rules:
        if not isinstance(rule, dict):
            continue
        hit = _run_signal(root, rule, guaranteed)
        if hit:
            return hit
    return ""


def detect_recipe_version(
    path: str,
    recipe_yml: Path | None,
    *,
    rid: str = "",
    guaranteed: str = "",
) -> str:
    """Haupt-API: Regeln aus recipe.yml, sonst leerer String."""
    rules: list[dict[str, Any]] = []
    g = guaranteed
    if recipe_yml is not None and recipe_yml.is_file():
        data = load_recipe_mapping(recipe_yml)
        g = g or str(data.get("version_guaranteed") or "").strip()
        raw = data.get("version_detect")
        if isinstance(raw, list):
            rules = [r for r in raw if isinstance(r, dict)]
    if rules:
        return detect_with_rules(path, rules, guaranteed=g)
    return ""
