"""Deklarative Versionserkennung aus recipe.yml → version_detect.

Rezeptor-Kern: jedes Rezept mit version_guaranteed soll version_detect angeben.
Signale werden der Reihe nach versucht; erstes Treffer-Ergebnis gewinnt
(außer kind: stack, das selbst Teil-/Voll-Ergebnisse liefert).
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
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


# Version/resource strings live well below this; avoid loading multi-hundred-MB EXEs.
_PE_SCAN_MAX = 32 * 1024 * 1024


def _pe_read_capped(exe: Path, limit: int = _PE_SCAN_MAX) -> bytes:
    with exe.open("rb") as f:
        return f.read(limit)


def _pe_field(exe: Path, field: str) -> str:
    try:
        data = _pe_read_capped(exe)
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


def _bytes_contains_ci(haystack: bytes, needle: bytes) -> bool:
    """Case-insensitive ASCII substring search without lowercasing the whole file."""
    if not needle:
        return True
    nlen = len(needle)
    if nlen > len(haystack):
        return False
    # Sliding window: compare lowered needle to each window (ASCII fold only).
    first = needle[0:1]
    first_alt = bytes([first[0] ^ 0x20]) if 65 <= first[0] <= 90 or 97 <= first[0] <= 122 else first
    start = 0
    while True:
        i = haystack.find(first, start)
        j = haystack.find(first_alt, start) if first_alt != first else -1
        if i < 0 and j < 0:
            return False
        if i < 0:
            i = j
        elif j >= 0:
            i = min(i, j)
        window = haystack[i : i + nlen]
        if len(window) == nlen and window.lower() == needle:
            return True
        start = i + 1


def _pe_contains(exe: Path, needles: list[str]) -> bool:
    if not needles:
        return True
    try:
        data = _pe_read_capped(exe)
    except OSError:
        return False
    encoded = [n.encode("utf-8", errors="ignore").lower() for n in needles]
    return all(_bytes_contains_ci(data, n) for n in encoded)


def _find_7z() -> str | None:
    return shutil.which("7z") or shutil.which("7za") or shutil.which("7zz")


def _archive_list_members(archive: Path) -> list[str]:
    """Mitglieder einer ISO/ZIP/7z über 7z auflisten (relativ, / normalisiert)."""
    seven = _find_7z()
    if seven is None or not archive.is_file():
        return []
    try:
        proc = subprocess.run(
            [seven, "l", "-ba", "-slt", str(archive)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if proc.returncode != 0:
        return []
    members: list[str] = []
    for line in proc.stdout.splitlines():
        if line.startswith("Path = "):
            rel = line[7:].strip().replace("\\", "/")
            if rel and rel != str(archive) and not rel.endswith("/"):
                members.append(rel)
    return members


def _archive_extract_text(archive: Path, member: str, *, max_bytes: int = 512_000) -> str:
    """Einzelne Textdatei aus Archiv lesen (stdout von 7z x -so)."""
    seven = _find_7z()
    if seven is None:
        return ""
    member = member.replace("\\", "/").lstrip("/")
    try:
        proc = subprocess.run(
            [seven, "x", "-so", "-y", str(archive), member],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if proc.returncode != 0 or not proc.stdout:
        return ""
    data = proc.stdout[:max_bytes]
    return data.decode("utf-8", errors="replace")


def _glob_match_member(member: str, pattern: str) -> bool:
    """pathlib-ähnliches Glob-Match für Archiv-Pfade (POSIX)."""
    from fnmatch import fnmatch

    pattern = pattern.replace("\\", "/").lstrip("./")
    member = member.replace("\\", "/").lstrip("./")
    if fnmatch(member, pattern):
        return True
    if pattern.startswith("**/"):
        return fnmatch(member, pattern[3:]) or fnmatch(member, pattern)
    # products/PPRO/application.json ↔ Adobe 2024/products/PPRO/application.json
    if fnmatch(member, "*/" + pattern) or fnmatch(member, "*/" + pattern.lstrip("*")):
        return True
    return member.endswith("/" + pattern) or member.endswith(pattern)


def _resolve_globs(root: Path, pattern: str) -> list[Path]:
    pattern = pattern.strip()
    if not pattern:
        return []
    # "." = der Root selbst (PE/Trainer-Regeln); pathlib 3.14 lehnt glob(".") ab
    if pattern in (".", "./"):
        return [root] if root.exists() else []
    if root.is_file():
        # Archiv/ISO: Treffer als virtuelle Pfade markieren (siehe _run_signal json_key)
        suf = root.suffix.lower()
        if suf in (".iso", ".zip", ".7z", ".rar"):
            hits: list[Path] = []
            for member in _archive_list_members(root):
                if _glob_match_member(member, pattern):
                    # sentinel: archive!member — nur für Archiv-Lesewege
                    hits.append(Path(f"{root}!{member}"))
            return hits
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
            text = ""
            # Archiv-Sentinel: /path/to.iso!Adobe 2024/products/PPRO/application.json
            s = str(path)
            if "!" in s and root.is_file() and root.suffix.lower() in (
                ".iso",
                ".zip",
                ".7z",
                ".rar",
            ):
                member = s.split("!", 1)[1]
                text = _archive_extract_text(root, member)
            elif path.is_file():
                try:
                    text = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
            else:
                continue
            if not text:
                continue
            try:
                data = json.loads(text)
            except json.JSONDecodeError:
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
            m = cre.search(name)
            if not m:
                continue
            if m.lastindex:
                return m.group(1).strip()
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
