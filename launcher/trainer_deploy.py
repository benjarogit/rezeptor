"""Deploy a BYOS trainer (single EXE or pack folder) into <data_root>/trainer/."""

from __future__ import annotations

import re
import shutil
from pathlib import Path

_KEEP_NAMES = frozenset({"readme.txt"})
_PACK_NAME_RE = re.compile(r"(trainer|fling|cheat|hack)", re.IGNORECASE)
_SIDECAR_SUFFIXES = frozenset({".dll", ".ini", ".cfg", ".txt", ".json"})
_MAX_PACK_ENTRIES = 15
_BUSY_PARENT_ENTRIES = 25


class TrainerDeployError(ValueError):
    """Invalid source or empty pack."""


def trainer_dir(data_root: Path) -> Path:
    return Path(data_root) / "trainer"


def find_primary_exe(directory: Path) -> Path | None:
    """Prefer *Trainer* / *Plus* EXE, else first .exe (sorted, maxdepth 2)."""
    if not directory.is_dir():
        return None
    prefer: Path | None = None
    any_exe: Path | None = None
    for f in sorted(directory.rglob("*")):
        if not f.is_file():
            continue
        try:
            rel = f.relative_to(directory)
        except ValueError:
            continue
        if len(rel.parts) > 2:
            continue
        if f.suffix.lower() != ".exe":
            continue
        name = f.name
        if prefer is None and (
            "trainer" in name.lower() or "plus" in name.lower()
        ):
            prefer = f
        if any_exe is None:
            any_exe = f
    return prefer or any_exe


def _is_pack_parent(parent: Path, exe: Path) -> bool:
    """True when parent looks like a dedicated trainer pack (not Downloads)."""
    if _PACK_NAME_RE.search(parent.name):
        return True
    try:
        entries = list(parent.iterdir())
    except OSError:
        return False
    if len(entries) > _MAX_PACK_ENTRIES:
        return False
    has_dll = False
    for p in entries:
        if not p.is_file():
            continue
        if p.resolve() == exe.resolve():
            continue
        if p.suffix.lower() == ".dll":
            has_dll = True
            break
    return has_dll


def _sidecar_files(exe: Path) -> list[Path]:
    """Companion files next to exe when parent is a pack folder."""
    parent = exe.parent
    if not _is_pack_parent(parent, exe):
        return []
    stem = exe.stem
    stem_l = stem.lower()
    out: list[Path] = []
    try:
        entries = list(parent.iterdir())
    except OSError:
        return []
    for p in entries:
        if not p.is_file():
            continue
        if p.resolve() == exe.resolve():
            continue
        name_l = p.name.lower()
        suf = p.suffix.lower()
        if name_l.startswith("trspeedhack"):
            out.append(p)
            continue
        if p.stem.lower() == stem_l or p.stem.lower().startswith(stem_l):
            out.append(p)
            continue
        if suf in _SIDECAR_SUFFIXES and len(entries) <= _MAX_PACK_ENTRIES:
            # Whole-pack mode: small dedicated folder → take payload files
            if suf == ".txt" and name_l == "readme.txt":
                continue
            if suf in (".dll", ".ini", ".cfg") or (
                suf == ".txt" and "trainer" in name_l
            ):
                out.append(p)
    return out


def _clear_trainer_dir(dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for p in dest.iterdir():
        if p.name.lower() in _KEEP_NAMES:
            continue
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)
        else:
            try:
                p.unlink()
            except OSError:
                pass


def _copy_file(src: Path, dest_dir: Path) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    target = dest_dir / src.name
    shutil.copy2(src, target)
    return target


def _copy_tree_contents(src: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dest / item.name
        if item.is_dir():
            if target.exists():
                shutil.rmtree(target, ignore_errors=True)
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)


def deploy_trainer_source(data_root: Path, source: Path | str) -> Path:
    """Copy trainer from *source* (exe or folder) into ``data_root/trainer``.

    Returns the path of the primary trainer EXE under ``trainer/``.
    """
    src = Path(source).expanduser().resolve()
    if not src.exists():
        raise TrainerDeployError(f"not found: {src}")

    dest = trainer_dir(data_root)
    _clear_trainer_dir(dest)

    if src.is_dir():
        primary = find_primary_exe(src)
        if primary is None:
            raise TrainerDeployError("no .exe in folder")
        _copy_tree_contents(src, dest)
        deployed = dest / primary.relative_to(src)
        if not deployed.is_file():
            # Flat fallback if relative layout odd
            deployed = dest / primary.name
            if not deployed.is_file():
                deployed = find_primary_exe(dest)  # type: ignore[assignment]
        if deployed is None or not Path(deployed).is_file():
            raise TrainerDeployError("copy failed: primary exe missing")
        return Path(deployed)

    if not src.is_file() or src.suffix.lower() != ".exe":
        raise TrainerDeployError("expected .exe or folder")

    # Lone EXE in a busy directory (e.g. Downloads): copy only the exe.
    parent = src.parent
    try:
        parent_count = sum(1 for _ in parent.iterdir())
    except OSError:
        parent_count = 0

    sidecars = _sidecar_files(src)
    if sidecars and parent_count <= _BUSY_PARENT_ENTRIES:
        _copy_file(src, dest)
        for side in sidecars:
            _copy_file(side, dest)
    else:
        _copy_file(src, dest)

    deployed = dest / src.name
    if not deployed.is_file():
        raise TrainerDeployError("copy failed")
    return deployed


def installed_trainer_exe(data_root: Path) -> Path | None:
    """Primary EXE currently under trainer/, if any."""
    d = trainer_dir(data_root)
    if not d.is_dir():
        return None
    return find_primary_exe(d)
