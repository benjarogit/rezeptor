"""Steam library helpers (App-Installpfad für Trainer-Rezepte)."""

from __future__ import annotations

import re
from pathlib import Path


def steam_roots() -> list[Path]:
    home = Path.home()
    roots: list[Path] = []
    for cand in (
        home / ".local" / "share" / "Steam",
        home / ".steam" / "steam",
        home / ".steam" / "root",
        home / ".var" / "app" / "com.valvesoftware.Steam" / "data" / "Steam",
    ):
        if cand.is_dir() and cand not in roots:
            roots.append(cand)
    return roots


def _parse_library_folders(vdf: Path) -> list[Path]:
    """libraryfolders.vdf → Library-Roots (mit steamapps/)."""
    try:
        text = vdf.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    paths: list[Path] = []
    # "path"		"/mnt/ssd2/SteamLibrary"
    for m in re.finditer(r'"path"\s+"([^"]+)"', text):
        p = Path(m.group(1))
        if p.is_dir():
            paths.append(p)
    # Fallback: Ordner der VDF-Datei
    parent = vdf.parent.parent  # …/steamapps → library root
    if parent.is_dir() and parent not in paths:
        paths.insert(0, parent)
    return paths


def steam_library_roots() -> list[Path]:
    libs: list[Path] = []
    seen: set[str] = set()
    for root in steam_roots():
        vdf = root / "steamapps" / "libraryfolders.vdf"
        candidates = _parse_library_folders(vdf) if vdf.is_file() else [root]
        for lib in candidates:
            key = str(lib.resolve()) if lib.exists() else str(lib)
            if key in seen:
                continue
            seen.add(key)
            libs.append(lib)
    return libs


def steam_app_install_dir(appid: str) -> Path | None:
    """Installationsordner des Spiels (steamapps/common/…)."""
    appid = (appid or "").strip()
    if not appid:
        return None
    for lib in steam_library_roots():
        acf = lib / "steamapps" / f"appmanifest_{appid}.acf"
        if not acf.is_file():
            continue
        try:
            text = acf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = re.search(r'"installdir"\s+"([^"]+)"', text)
        if not m:
            continue
        install = lib / "steamapps" / "common" / m.group(1)
        if install.is_dir():
            return install.resolve()
    return None


def steam_compatdata_dir(appid: str) -> Path | None:
    appid = (appid or "").strip()
    if not appid:
        return None
    for lib in steam_library_roots():
        p = lib / "steamapps" / "compatdata" / appid
        if p.is_dir():
            return p.resolve()
    return None


def default_trainer_target(appid: str, folder_name: str = "ZA4-Trainer") -> str:
    """Spielordner/<folder_name> wenn gefunden, sonst compatdata-Documents, sonst leer."""
    game = steam_app_install_dir(appid)
    if game is not None:
        return str(game / folder_name)
    compat = steam_compatdata_dir(appid)
    if compat is not None:
        docs = (
            compat
            / "pfx"
            / "drive_c"
            / "users"
            / "steamuser"
            / "Documents"
            / folder_name
        )
        return str(docs)
    return ""
