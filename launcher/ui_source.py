"""Unified recipe source picker (folder / installer / archive)."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlparse

from PyQt6.QtCore import QEvent, QObject, QSize, Qt, QTimer
from PyQt6.QtGui import QCloseEvent
from PyQt6.QtWidgets import (
    QButtonGroup,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)

from recipe_discovery import (
    is_adobe_offline_recipe,
    source_hints_from_meta,
)
from app_support import detect_source_version, version_guarantee_mismatch
from archive_passwords import normalize_password_list_text
from ui_archive_passwords import ensure_archive_passwords
from i18n import t
from settings import is_recipe_install_cleared, load_settings, save_settings
from steam_paths import default_trainer_target, steam_app_install_dir

# Default when recipe.yml omits/extends source_formats (7z covers multipart volumes).
DEFAULT_ARCHIVE_FORMATS = "zip,tar.gz,tgz,7z,rar"
_MULTIPART_GLOBS = (
    "*.7z.001",
    "*.zip.001",
    "*.z01",
    "*.part01.rar",
    "*.part1.rar",
    "*.001",
)

# Qt nur als Notfall — und dann nativer Systemdialog (kein DontUseNativeDialog).
_NATIVE_QT_OPTS = QFileDialog.Option(0)


def _resolve_bin(*candidates: str) -> str | None:
    """PATH + feste Pfade (AppImage/Sandbox: which allein reicht oft nicht)."""
    bases: list[str] = []
    seen: set[str] = set()
    for c in candidates:
        c = (c or "").strip()
        if not c:
            continue
        base = os.path.basename(c)
        if base not in seen:
            seen.add(base)
            bases.append(base)
        if c.startswith("/") and c not in seen:
            seen.add(c)
    for base in bases:
        for prefix in ("/usr/bin", "/usr/local/bin", "/bin"):
            path = f"{prefix}/{base}"
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        found = shutil.which(base)
        if found and os.path.isfile(found) and os.access(found, os.X_OK):
            return found
    return None


def _desktop_env_prefer_kdialog() -> bool:
    desk = (
        os.environ.get("XDG_CURRENT_DESKTOP", "")
        + ";"
        + os.environ.get("DESKTOP_SESSION", "")
    ).upper()
    return any(m in desk for m in ("KDE", "PLASMA", "LXQT"))


def _kdialog_cmd(kdialog: str, *args: str, title: str = "") -> list[str]:
    """kdialog: --title vor dem Dialog-Typ — sonst landet es als Start/Filter-Arg."""
    cmd = [kdialog]
    if title:
        cmd.extend(["--title", title])
    cmd.extend(args)
    return cmd


def _run_picker(cmd: list[str]) -> str | None:
    """None = Tool-Fehler (nächstes versuchen); '' = Abbruch; sonst Pfad."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=600
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode == 0:
        return (proc.stdout or "").strip()
    return ""


def _qt_filter_to_globs(file_filter: str) -> str:
    """Qt filter 'Label (*.exe *.EXE)' → kdialog/zenity Glob-Liste."""
    if "(" not in file_filter or ")" not in file_filter:
        return ""
    inner = file_filter[file_filter.find("(") + 1 : file_filter.find(")")]
    parts = [
        p.strip()
        for p in inner.replace(" ", "\n").split()
        if p.strip().startswith("*")
    ]
    return " ".join(parts)


def _desktop_pick_directory(title: str, start_dir: str) -> str | None:
    """System-Dateibrowser (Pflicht): kdialog/zenity — gleicher Pfad für Quelle und Ziel."""
    start = start_dir or str(Path.home())
    kdialog = _resolve_bin("kdialog", "/usr/bin/kdialog")
    zenity = _resolve_bin("zenity", "/usr/bin/zenity")
    tools: list[tuple[str, list[str]]] = []
    if kdialog and zenity:
        order = (kdialog, zenity) if _desktop_env_prefer_kdialog() else (zenity, kdialog)
    elif kdialog:
        order = (kdialog,)
    elif zenity:
        order = (zenity,)
    else:
        order = ()
    for tool in order:
        if os.path.basename(tool) == "kdialog" or tool.endswith("/kdialog"):
            tools.append(
                (
                    tool,
                    _kdialog_cmd(
                        tool, "--getexistingdirectory", start, title=title
                    ),
                )
            )
        else:
            tools.append(
                (
                    tool,
                    [
                        tool,
                        "--file-selection",
                        "--directory",
                        f"--title={title}",
                        f"--filename={start.rstrip('/')}/",
                    ],
                )
            )
    for _tool, cmd in tools:
        result = _run_picker(cmd)
        if result is not None:
            return result  # Pfad oder "" bei Abbruch — kein Qt-Zweitdialog
    return None


def _desktop_pick_open_file(title: str, start_dir: str, file_filter: str) -> str | None:
    """System-Dateibrowser (Pflicht) — identische Tool-Reihenfolge wie Ordnerwahl."""
    start = start_dir or str(Path.home())
    filt = _qt_filter_to_globs(file_filter)
    kdialog = _resolve_bin("kdialog", "/usr/bin/kdialog")
    zenity = _resolve_bin("zenity", "/usr/bin/zenity")
    tools: list[list[str]] = []
    if kdialog and zenity:
        order = (kdialog, zenity) if _desktop_env_prefer_kdialog() else (zenity, kdialog)
    elif kdialog:
        order = (kdialog,)
    elif zenity:
        order = (zenity,)
    else:
        order = ()
    for tool in order:
        if os.path.basename(tool) == "kdialog" or tool.endswith("/kdialog"):
            args = ["--getopenfilename", start]
            if filt:
                args.append(filt)
            tools.append(_kdialog_cmd(tool, *args, title=title))
        else:
            cmd = [
                tool,
                "--file-selection",
                f"--title={title}",
                f"--filename={start.rstrip('/')}/",
            ]
            if file_filter.strip():
                cmd.append(f"--file-filter={file_filter}")
            tools.append(cmd)
    for cmd in tools:
        result = _run_picker(cmd)
        if result is not None:
            return result
    return None


def documents_dir() -> Path:
    """XDG-Dokumente (de: ~/Dokumente)."""
    try:
        proc = subprocess.run(
            ["xdg-user-dir", "DOCUMENTS"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            p = Path(proc.stdout.strip())
            if p.is_dir():
                return p
    except (OSError, subprocess.TimeoutExpired):
        pass
    for cand in (Path.home() / "Dokumente", Path.home() / "Documents"):
        if cand.is_dir():
            return cand
    return Path.home()


def normalize_user_path(raw: str, root: Path | None = None) -> str:
    """~, {repo}, file://, //Dokumente/… und doppelte Slashes bereinigen."""
    text = (raw or "").strip()
    if not text:
        return text
    if root is not None:
        text = text.replace("{repo}", str(root))
    # Portal/Qt manchmal als file://-URL
    if text.startswith("file://"):
        parsed = urlparse(text)
        text = unquote(parsed.path or "")
        if parsed.netloc and not text.startswith("//"):
            # file://hostname/path (selten)
            text = f"/{parsed.netloc}{text}" if text.startswith("/") else f"/{parsed.netloc}/{text}"
    expanded = os.path.expanduser(text)
    # KDE/Hand-Eingabe: //Dokumente/… ohne Home → ~/Dokumente/…
    # Aber //mnt/… bzw. existierende Absolutpfade nicht nach $HOME schieben
    if expanded.startswith("//") and not expanded.startswith("///"):
        rest = expanded[2:]
        first = rest.split("/", 1)[0]
        abs_candidate = Path("/") / rest
        if first in {"mnt", "run", "media", "home", "opt", "var"} or abs_candidate.exists():
            expanded = str(abs_candidate)
        elif rest and not rest.startswith("/"):
            expanded = str(Path.home() / rest)
        else:
            expanded = "/" + expanded.lstrip("/")
    return os.path.normpath(expanded)


def dialog_start_dir(raw: str, fallback: Path | None = None) -> str:
    """Startverzeichnis für QFileDialog — nur existierende Ordner."""
    fb = fallback or documents_dir()
    if not raw.strip():
        return str(fb)
    p = Path(normalize_user_path(raw))
    if p.is_dir():
        return str(p)
    if p.parent.is_dir():
        return str(p.parent)
    return str(fb)


def pick_directory(parent: QWidget, title: str, start: str) -> str:
    """Ordner wählen — immer System-Dateibrowser (kdialog/zenity); Qt nur Notfall."""
    start_dir = dialog_start_dir(start)
    desktop = _desktop_pick_directory(title, start_dir)
    if desktop is not None:
        return normalize_user_path(desktop) if desktop else ""
    # Kein kdialog/zenity: nativer Qt-Dialog (kein eingebetteter Fluent-Picker).
    chosen = QFileDialog.getExistingDirectory(
        parent,
        title,
        start_dir,
        options=_NATIVE_QT_OPTS,
    )
    return normalize_user_path(chosen) if chosen else ""


def pick_open_file(
    parent: QWidget,
    title: str,
    start: str,
    file_filter: str,
) -> str:
    """Datei wählen — gleicher System-Dateibrowser wie pick_directory."""
    start_dir = dialog_start_dir(start)
    desktop = _desktop_pick_open_file(title, start_dir, file_filter)
    if desktop is not None:
        return normalize_user_path(desktop) if desktop else ""
    path, _ = QFileDialog.getOpenFileName(
        parent,
        title,
        start_dir,
        file_filter,
        options=_NATIVE_QT_OPTS,
    )
    return normalize_user_path(path) if path else ""


def needs_target_dir(meta: dict[str, str]) -> bool:
    """Zielordner: Portable-Apps und jedes Rezept mit target_* (z. B. Photoshop-Datenordner)."""
    if meta.get("deploy_mode", "copy") == "link":
        return False
    if (meta.get("target_default") or "").strip() or (meta.get("target_label") or "").strip():
        return True
    return meta.get("install_type", "") in (
        "portable_launch",
        "portable_bootstrap",
        "game_portable",
    )


def fix_kind_category(kind: str) -> str:
    """none | updates | online_fix"""
    k = (kind or "none").strip()
    if k in ("optional", "required"):
        return "updates"
    if k in ("online_fix_optional", "online_fix_required"):
        return "online_fix"
    return "none"


def fix_is_required(kind: str) -> bool:
    return (kind or "none") in ("required", "online_fix_required")


def shows_fix_field(meta: dict[str, str]) -> bool:
    return fix_kind_category(meta.get("fix_kind", "none")) != "none"


def fix_field_label(meta: dict[str, str]) -> str:
    custom = (meta.get("fix_label") or "").strip()
    if custom:
        return custom
    if fix_kind_category(meta.get("fix_kind", "")) == "online_fix":
        return t("source.online_fix")
    return t("source.fix")


def is_steam_link_recipe(meta: dict[str, str]) -> bool:
    return (
        meta.get("deploy_mode", "copy") == "link"
        and bool((meta.get("steam_appid") or "").strip())
    )


def make_info_button(
    parent: QWidget,
    *,
    tooltip: str,
    title: str,
    body: str,
) -> QPushButton:
    btn = QPushButton("?")
    btn.setFixedWidth(28)
    btn.setToolTip(tooltip)
    btn.clicked.connect(
        lambda: QMessageBox.information(parent, title, body)
    )
    return btn


def primary_help_text(meta: dict[str, str]) -> tuple[str, str]:
    if is_steam_link_recipe(meta):
        return t("source.steam_link_info_title"), t("source.steam_link_info_body")
    if meta.get("install_type") == "installer_offline":
        return t("source.installer_source_info_title"), t(
            "source.installer_source_info_body"
        )
    return t("source.primary_info_title"), t("source.primary_info_body")


def fix_help_text(meta: dict[str, str]) -> tuple[str, str]:
    if fix_kind_category(meta.get("fix_kind", "")) == "online_fix":
        return t("source.online_fix_info_title"), t("source.online_fix_info_body")
    return t("source.updates_info_title"), t("source.updates_info_body")


def is_portable_install(meta: dict[str, str]) -> bool:
    return meta.get("install_type", "") in (
        "portable_launch",
        "portable_bootstrap",
        "game_portable",
    )


def default_target_dir(
    meta: dict[str, str], rid: str = "", data_root: Path | None = None
) -> str:
    """Nur zuvor gewählte / erkannte Ziele — kein YAML- oder Home-Zwangspfad.

    Leer = User muss beim Install selbst wählen (außer Steam-Auto / gespeicherter Pfad).
    """
    # Trainer / Steam: Spielordner automatisch, manuell überschreibbar
    appid = (meta.get("steam_appid") or "").strip()
    if appid:
        folder = (meta.get("steam_target_folder") or "Trainer").strip() or "Trainer"
        auto = default_trainer_target(appid, folder)
        if auto:
            return normalize_user_path(auto)
    if rid == "wiso-steuer" and data_root is not None:
        env_path = data_root / "portable.env"
        if env_path.is_file():
            for line in env_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line.startswith("WISO_PORTABLE_ROOT="):
                    continue
                val = line.split("=", 1)[1].strip().strip('"')
                if val and Path(val).is_dir():
                    return normalize_user_path(val)
    if data_root is not None:
        pointer = data_root / "data_root.path"
        if pointer.is_file():
            val = pointer.read_text(encoding="utf-8").strip()
            if val:
                target = Path(normalize_user_path(val))
                # Existiert oder Parent da (wird bei Install angelegt) → Vorschlag behalten
                if target.is_dir() or target.parent.is_dir():
                    return str(target)
    # Kein Prefill aus target_default / kanonischem data_root / Dokumente.
    return ""


def discover_update_units(root: str | Path) -> list[tuple[str, str]]:
    """Leichter Scan wie core/recipe-updates.sh — (id, path), sortiert numerisch."""
    base = Path(root)
    if not base.is_dir():
        return []
    try:
        base = base.resolve()
    except OSError:
        return []

    def _unit_id(name: str) -> str:
        digits = ""
        for ch in name:
            if ch.isdigit():
                digits += ch
            else:
                break
        return digits or "1"

    def _is_numbered(name: str) -> bool:
        i = 0
        while i < len(name) and name[i].isdigit():
            i += 1
        if i == 0:
            return False
        rest = name[i:].lstrip()
        return rest.startswith("-")

    def _dir_is_unit(d: Path) -> bool:
        if not d.is_dir():
            return False
        try:
            for child in d.iterdir():
                if child.is_file() and child.suffix.lower() == ".exe":
                    return True
        except OSError:
            return False
        return False

    def _scan_numbered(scan: Path) -> list[tuple[str, str]]:
        out: list[tuple[str, str]] = []
        try:
            entries = list(scan.iterdir())
        except OSError:
            return out
        for path in entries:
            if path.is_dir() and _is_numbered(path.name) and _dir_is_unit(path):
                out.append((_unit_id(path.name), str(path)))
            elif path.is_file() and path.suffix.lower() == ".exe":
                out.append((_unit_id(path.stem), str(path)))
        out.sort(key=lambda t: (int(t[0]) if t[0].isdigit() else 10**9, t[0], t[1]))
        return out

    for sub in ("updates", "Updates", "update"):
        nested = base / sub
        if nested.is_dir():
            return _scan_numbered(nested)

    try:
        children = [p for p in base.iterdir() if p.is_dir()]
    except OSError:
        return []
    if any(_is_numbered(p.name) and _dir_is_unit(p) for p in children):
        return _scan_numbered(base)
    return []


def _adobe_pack_name_bits(d: Path) -> list[str]:
    try:
        return [c.name.lower() for c in d.iterdir()]
    except OSError:
        return []


def _adobe_pack_has_extras(names: list[str]) -> bool:
    return any(
        "neural" in n or "missing_libs" in n or "genp" in n for n in names
    )


def _looks_like_adobe_pack_root(d: Path) -> bool:
    """m0nkrus-style: ISO + Neural Filters / missing_libs / GenP siblings."""
    if not d.is_dir():
        return False
    names = _adobe_pack_name_bits(d)
    has_iso = any(n.endswith(".iso") for n in names)
    return has_iso and _adobe_pack_has_extras(names)


def _looks_like_adobe_iso_only_pack(d: Path) -> bool:
    """ISO pack without Neural/GenP/missing_libs (e.g. Photoshop.2021)."""
    if not d.is_dir():
        return False
    names = _adobe_pack_name_bits(d)
    has_iso = any(n.endswith(".iso") for n in names)
    return has_iso and not _adobe_pack_has_extras(names)


def _matches_m0nkrus_220_pack(path: Path) -> bool:
    """Pack Photoshop.2021 / Adobe.Photoshop.2021.Multilingual — not 22.1.1.138."""
    n = path.name.lower()
    if "22.1.1.138" in n:
        return False
    return (
        n == "photoshop.2021"
        or "adobe.photoshop.2021.multilingual" in n
        or "photoshop.2021" in n
    )


def adobe_pack_root_for_source(path: str) -> str:
    """If source is ISO or pack folder, return pack root for extras (or \"\")."""
    p = Path(path)
    if p.is_file() and p.suffix.lower() == ".iso":
        parent = p.parent
        return str(parent.resolve()) if _looks_like_adobe_pack_root(parent) else ""
    if p.is_dir() and _looks_like_adobe_pack_root(p):
        return str(p.resolve())
    return ""


def _adobe_iso_in_pack_dir(p: Path, version_hint: str = "") -> Path | None:
    """Pack root with *.iso — pick best match (version hint, then mtime)."""
    try:
        isos = [
            c
            for c in p.iterdir()
            if c.is_file() and c.suffix.lower() == ".iso"
        ]
    except OSError:
        return None
    if not isos:
        return None
    hint = (version_hint or "").strip()
    if hint:
        matched = [c for c in isos if hint in c.name]
        if matched:
            isos = matched
    isos.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return isos[0]


def normalize_folder_source(
    rid: str, raw: str, *, version_hint: str = ""
) -> str:
    p = Path(raw)
    if p.is_file() and p.suffix.lower() == ".iso":
        return str(p.resolve())
    if not p.is_dir():
        return raw
    if is_adobe_offline_recipe(rid):
        if (p / "Set-up.exe").is_file():
            return str(p.resolve())
        try:
            for child in p.iterdir():
                if child.is_dir() and (child / "Set-up.exe").is_file():
                    return str(child.resolve())
        except OSError:
            pass
        # Pack-Ordner (ISO + Neural Filters / GenP / 7z) → Installer-ISO
        iso = _adobe_iso_in_pack_dir(p, version_hint)
        if iso is not None:
            return str(iso.resolve())
    if rid == "wiso-steuer" and p.name.startswith("Steuersoftware"):
        return str(p.parent.resolve())
    return str(p.resolve())


def default_folder_source(
    rid: str,
    data_root: Path,
    repo_root: Path | None = None,
    *,
    meta: dict[str, str] | None = None,
) -> str:
    meta = meta or {}
    # Steam-Spielordner (z. B. house-of-ashes mit deploy_mode: link)
    appid = (meta.get("steam_appid") or "").strip()
    if appid and meta.get("deploy_mode", "copy") == "link":
        game = steam_app_install_dir(appid)
        if game is not None and game.is_dir():
            return str(game)
    if is_adobe_offline_recipe(rid):
        # Nur das kanonische Drop-Verzeichnis zum Standard-Rezept —
        # Pack-Varianten (m0nkrus) erben nicht recipes/photoshop/.
        drop = {"photoshop": "photoshop", "premiere": "premiere"}.get(rid)
        candidates: list[Path] = []
        pack_candidates: list[Path] = []
        iso_only_candidates: list[Path] = []
        ver = (meta.get("version_guaranteed") or "").strip()
        if drop and repo_root is not None:
            candidates.append(repo_root / drop)

        def _adobe_setup_dir(p: Path) -> Path | None:
            if p.is_file() and p.suffix.lower() == ".iso":
                return p
            if not p.is_dir():
                return None
            if (p / "Set-up.exe").is_file():
                return p
            try:
                for child in p.iterdir():
                    if child.is_dir() and (child / "Set-up.exe").is_file():
                        return child
            except OSError:
                return None
            # Pack-Root with ISO (extras optional)
            return _adobe_iso_in_pack_dir(p, ver)

        def _shallow_isos_and_setups(root: Path) -> None:
            """Nur 1–2 Ebenen — kein rglob (friert die GUI auf großen Bäumen ein)."""
            try:
                entries = sorted(
                    root.iterdir(),
                    key=lambda x: x.stat().st_mtime,
                    reverse=True,
                )
            except OSError:
                return
            for p in entries:
                if p.is_file() and p.suffix.lower() == ".iso":
                    candidates.append(p)
                    continue
                if not p.is_dir():
                    continue
                if _looks_like_adobe_pack_root(p):
                    pack_candidates.append(p)
                elif _looks_like_adobe_iso_only_pack(p):
                    iso_only_candidates.append(p)
                found = _adobe_setup_dir(p)
                if found is not None:
                    candidates.append(found)
                try:
                    for child in p.iterdir():
                        if child.is_file() and child.suffix.lower() == ".iso":
                            candidates.append(child)
                except OSError:
                    continue

        for base in (Path.home() / "Downloads", Path.home() / "Dokumente"):
            if base.is_dir():
                _shallow_isos_and_setups(base)

        # m0nkrus 22.0 ISO-only Pack (Photoshop.2021) — nicht 22.1.1.138
        if rid == "photoshop-m0nkrus-220":
            for pack in iso_only_candidates:
                if _matches_m0nkrus_220_pack(pack):
                    iso = _adobe_iso_in_pack_dir(pack, "")
                    if iso is not None:
                        return str(iso.resolve())
            for cand in candidates:
                if _matches_m0nkrus_220_pack(cand):
                    resolved = (
                        _adobe_setup_dir(cand) if cand.is_dir() else cand
                    )
                    if resolved is None:
                        continue
                    if resolved.is_file() and resolved.suffix.lower() == ".iso":
                        return str(resolved.resolve())
            return ""

        # Empfohlen: kompletter Pack-Ordner (ISO + Neural Filters + missing_libs),
        # aber nur wenn Versions-Hinweis im Ordnernamen passt (sonst falsches Pack).
        if rid == "photoshop-m0nkrus" and pack_candidates and ver:
            matched = [p for p in pack_candidates if ver in p.name]
            if matched:
                return str(matched[0].resolve())

        # Standard-photoshop: Drop-Dir zuerst; m0nkrus-Packs nicht bevorzugen
        if rid == "photoshop" and drop and repo_root is not None:
            drop_path = repo_root / drop
            setup = _adobe_setup_dir(drop_path)
            if setup is not None and setup.is_dir() and (setup / "Set-up.exe").is_file():
                return str(setup.resolve())

        for cand in candidates:
            # Cross-Pack: Standard und 220 nicht den 138-Pack nehmen
            if rid in ("photoshop", "photoshop-m0nkrus-220") and "22.1.1.138" in cand.name:
                continue
            if rid == "photoshop-m0nkrus" and _matches_m0nkrus_220_pack(cand):
                continue
            resolved = _adobe_setup_dir(cand) if cand.is_dir() else cand
            if resolved is None:
                continue
            if resolved.is_file() and resolved.suffix.lower() == ".iso":
                return str(resolved.resolve())
            if resolved.is_dir() and (resolved / "Set-up.exe").is_file():
                return str(resolved.resolve())
        return ""
    if rid == "wiso-steuer":
        # WISO_PORTABLE_ROOT in portable.env = installiertes Ziel (Laufzeit), nie Quelle.
        target = ""
        env_path = data_root / "portable.env"
        if env_path.is_file():
            for line in env_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line.startswith("WISO_PORTABLE_ROOT="):
                    target = line.split("=", 1)[1].strip().strip('"')
                    break
        for base in (Path.home() / "Downloads", Path.home() / "Dokumente"):
            if not base.is_dir():
                continue
            try:
                candidates = sorted(
                    (
                        p
                        for p in base.iterdir()
                        if p.is_dir() and "wiso" in p.name.lower()
                    ),
                    key=lambda p: p.stat().st_mtime,
                    reverse=True,
                )
            except OSError:
                continue
            for cand in candidates:
                if not (
                    (cand / "start.exe").is_file() or list(cand.glob("Steuersoftware*"))
                ):
                    continue
                # Installiertes Ziel nicht als „Quelle“ vorschlagen.
                try:
                    if target and cand.resolve() == Path(target).resolve():
                        continue
                except OSError:
                    pass
                return str(cand.resolve())
    return ""


def archive_filter(formats: str) -> str:
    parts = [p.strip() for p in formats.split(",") if p.strip()]
    if not parts:
        parts = [p.strip() for p in DEFAULT_ARCHIVE_FORMATS.split(",") if p.strip()]
    labels: list[str] = []
    for p in parts:
        labels.append(f"*.{p}")
    for g in _MULTIPART_GLOBS:
        if g not in labels:
            labels.append(g)
    return f"Archive ({' '.join(labels)});;All (*)"


def attach_archive_password_files(
    extra: dict[str, str], passwords: list[str]
) -> None:
    """Write temp password list files into ``extra`` for install.sh."""
    lines = [p.strip() for p in passwords if (p or "").strip()]
    if not lines:
        return
    pw_fd, pw_path = tempfile.mkstemp(prefix="rezeptor-archive-pw-", suffix=".txt")
    used_fd, used_path = tempfile.mkstemp(
        prefix="rezeptor-archive-pw-used-", suffix=".txt"
    )
    os.close(used_fd)
    try:
        with os.fdopen(pw_fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))
            fh.write("\n")
        os.chmod(pw_path, 0o600)
        Path(used_path).write_text("", encoding="utf-8")
        os.chmod(used_path, 0o600)
    except OSError:
        try:
            os.unlink(pw_path)
        except OSError:
            pass
        try:
            os.unlink(used_path)
        except OSError:
            pass
        return
    extra["RECIPE_ARCHIVE_PASSWORD_FILE"] = pw_path
    extra["RECIPE_ARCHIVE_PASSWORD_USED_FILE"] = used_path


class _ParentCloseDismissesDialog(QObject):
    """Wenn das Hauptfenster schließt: modales Kind zuerst beenden (KDE-Taskleiste)."""

    def __init__(self, dialog: QDialog) -> None:
        super().__init__(dialog)
        self._dialog = dialog

    def eventFilter(self, watched: QObject, event: QEvent) -> bool:  # noqa: N802
        if (
            watched is self._dialog.parent()
            and event.type() == QEvent.Type.Close
            and self._dialog.isVisible()
        ):
            self._dialog.setProperty("rezeptor_force_close", True)
            if self._dialog.isModal():
                self._dialog.done(QDialog.DialogCode.Rejected)
            else:
                self._dialog.reject()
        return super().eventFilter(watched, event)


def _prepare_modal_source_dialog(dialog: QDialog) -> None:
    """WindowModal + kein App-Quit — Hauptfenster darf Taskleisten-Close verarbeiten."""
    dialog.setWindowModality(Qt.WindowModality.WindowModal)
    dialog.setAttribute(Qt.WidgetAttribute.WA_QuitOnClose, False)
    parent = dialog.parentWidget()
    if parent is not None:
        parent.installEventFilter(_ParentCloseDismissesDialog(dialog))


class RecipeSourceDialog(QDialog):
    """Meta-driven source picker for install / reconfigure."""

    def __init__(
        self,
        parent: QWidget | None,
        *,
        rid: str,
        meta: dict[str, str],
        root: Path,
        title: str = "",
        pending_env: dict[str, str] | None = None,
    ) -> None:
        super().__init__(parent)
        _prepare_modal_source_dialog(self)
        self._rid = rid
        self._meta = meta
        self._root = root
        self._pending_env = dict(pending_env or {})
        self._paths_cleared = is_recipe_install_cleared(self._pending_env)
        self._source_kind = meta.get("source_kind", "folder")
        self._fix_kind = meta.get("fix_kind", "none")
        self._fix_category = fix_kind_category(self._fix_kind)
        self._shows_fix = shows_fix_field(meta)
        self._version_guaranteed = meta.get("version_guaranteed", "").strip()
        self._show_target = needs_target_dir(meta)
        self._allow_archive = bool((meta.get("source_formats") or "").strip())
        self._pick_archive = self._source_kind == "archive"
        self._pw_file: str | None = None
        self._pw_used_file: str | None = None
        self._resolved_passwords: list[str] | None = None

        self.setWindowTitle(title or t("source.title"))
        # Kompakt: Breite fest, Höhe folgt dem Inhalt (kein Leerraum).
        self._default_w = 640
        self._sizing = False
        self.setMinimumWidth(520)
        self.setMinimumHeight(160)

        layout = QVBoxLayout(self)
        layout.setSpacing(6)
        layout.setContentsMargins(12, 12, 12, 12)

        label = meta.get("source_label") or t("source.label")
        intro = QLabel(label)
        intro.setObjectName("muted")
        intro.setWordWrap(True)
        layout.addWidget(intro)

        if self._allow_archive and self._source_kind == "folder":
            mode_row = QHBoxLayout()
            self._mode_folder = QRadioButton(t("source.mode_folder"))
            self._mode_archive = QRadioButton(t("source.mode_archive"))
            self._mode_folder.setChecked(True)
            mode_group = QButtonGroup(self)
            mode_group.addButton(self._mode_folder)
            mode_group.addButton(self._mode_archive)
            self._mode_folder.toggled.connect(self._on_source_mode_changed)
            mode_row.addWidget(self._mode_folder)
            mode_row.addWidget(self._mode_archive)
            mode_row.addStretch(1)
            layout.addLayout(mode_row)

        # Nur sichtbar wenn Version erkannt — sonst kein leerer Platz.
        self.version_hint = QLabel("")
        self.version_hint.setObjectName("muted")
        self.version_hint.setWordWrap(True)
        self.version_hint.setVisible(False)
        layout.addWidget(self.version_hint)

        hints = source_hints_from_meta(meta)
        if hints:
            hints_title = QLabel(t("source.hints_title"))
            hints_title.setWordWrap(True)
            layout.addWidget(hints_title)
            hints_body = QLabel("\n".join(f"• {h}" for h in hints))
            hints_body.setObjectName("muted")
            hints_body.setWordWrap(True)
            hints_body.setTextInteractionFlags(
                Qt.TextInteractionFlag.TextSelectableByMouse
            )
            layout.addWidget(hints_body)
            hints_note = QLabel(t("source.hints_note"))
            hints_note.setObjectName("muted")
            hints_note.setWordWrap(True)
            layout.addWidget(hints_note)

        form = QFormLayout()
        form.setSpacing(8)
        form.setContentsMargins(0, 4, 0, 0)
        form.setFieldGrowthPolicy(
            QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow
        )
        self.primary_edit = QLineEdit()
        self.target_edit = QLineEdit()
        self.fix_edit = QLineEdit()
        self.primary_btn = QPushButton(t("source.pick"))
        self.target_btn = QPushButton(t("source.pick"))
        self.fix_btn = QPushButton(t("source.pick"))
        self.primary_clear = QPushButton(t("source.clear"))
        self.target_clear = QPushButton(t("source.clear"))

        self.primary_btn.clicked.connect(self._pick_primary)
        self.target_btn.clicked.connect(self._pick_target)
        self.fix_btn.clicked.connect(self._pick_fix)
        self.primary_clear.clicked.connect(self._clear_primary)
        self.target_clear.clicked.connect(self._clear_target)

        # QFormLayout + nested QHBoxLayout: Höhen falsch → Buttons überlappen.
        # Zeilen in QWidget wrappen (Qt-Empfehlung).
        primary_row = QHBoxLayout()
        primary_row.setSpacing(6)
        primary_row.setContentsMargins(0, 0, 0, 0)
        primary_row.addWidget(self.primary_edit, stretch=1)
        primary_row.addWidget(self.primary_btn)
        primary_row.addWidget(self.primary_clear)
        p_title, p_body = primary_help_text(meta)
        primary_row.addWidget(
            make_info_button(
                self,
                tooltip=t("source.primary_info_tip"),
                title=p_title,
                body=p_body,
            )
        )
        # Parent = self: wraps that stay out of the form must not be GC'd
        # (otherwise QLineEdit C++ objects die → crash in build_env on Wayland).
        primary_wrap = QWidget(self)
        primary_wrap.setLayout(primary_row)

        target_row = QHBoxLayout()
        target_row.setSpacing(6)
        target_row.setContentsMargins(0, 0, 0, 0)
        target_row.addWidget(self.target_edit, stretch=1)
        target_row.addWidget(self.target_btn)
        target_row.addWidget(self.target_clear)
        target_row.addWidget(
            make_info_button(
                self,
                tooltip=t("source.target_info_tip"),
                title=t("source.target_info_title"),
                body=t("source.target_help") + "\n\n" + t("source.space_hint"),
            )
        )
        target_wrap = QWidget(self)
        target_wrap.setLayout(target_row)

        fix_row = QHBoxLayout()
        fix_row.setContentsMargins(0, 0, 0, 0)
        fix_row.addWidget(self.fix_edit, stretch=1)
        fix_row.addWidget(self.fix_btn)
        fix_wrap = QWidget(self)
        fix_wrap.setLayout(fix_row)

        # Einheitlich: Quelle / Ziel (Rezept-Details stehen im Intro oben).
        form.addRow(t("source.label") + ":", primary_wrap)
        self.update_status = QLabel("")
        self.update_status.setObjectName("muted")
        self.update_status.setWordWrap(True)
        self.update_status.setVisible(False)
        form.addRow("", self.update_status)
        if is_steam_link_recipe(meta) and self._fix_category == "online_fix":
            steam_hint = QLabel(t("source.steam_link_hint"))
            steam_hint.setObjectName("muted")
            steam_hint.setWordWrap(True)
            form.addRow("", steam_hint)

        if self._show_target:
            form.addRow(t("source.target") + ":", target_wrap)
            tip = meta.get("target_label") or t("source.target_tip")
            self.target_edit.setToolTip(tip)
            self.target_btn.setToolTip(tip)
            self.target_clear.setToolTip(t("source.clear_tip"))
            self.target_help = QLabel(
                t("source.target_help") + " " + t("source.space_hint")
            )
            self.target_help.setObjectName("muted")
            self.target_help.setWordWrap(True)
            form.addRow("", self.target_help)
        else:
            self.target_edit.hide()
            self.target_btn.hide()
            self.target_clear.hide()
            target_wrap.hide()
        if self._shows_fix:
            f_title, f_body = fix_help_text(meta)
            fix_row.addWidget(
                make_info_button(
                    self,
                    tooltip=t("source.fix_info_tip"),
                    title=f_title,
                    body=f_body,
                )
            )
            form.addRow(fix_field_label(meta) + ":", fix_wrap)
            if self._fix_category == "online_fix":
                self.fix_edit.setPlaceholderText(t("source.online_fix_ph"))
                self.fix_btn.setToolTip(t("source.pick_online_fix_dir"))
            else:
                self.fix_edit.setPlaceholderText(t("source.fix_ph"))
        else:
            self.fix_edit.hide()
            self.fix_btn.hide()
            fix_wrap.hide()

        self._result_primary: str | None = None
        self._result_target: str | None = None
        self._result_fix: str | None = None

        layout.addLayout(form)
        self._sync_primary_tips()
        self.primary_clear.setToolTip(t("source.clear_tip"))
        self.primary_edit.textChanged.connect(self._on_primary_changed)
        self.fix_edit.textChanged.connect(self._refresh_update_status)

        self.passwords_label = QLabel(t("source.passwords"))
        self.passwords_label.setToolTip(t("source.passwords_tip"))
        self.passwords_edit = QPlainTextEdit()
        self.passwords_edit.setPlaceholderText(t("source.passwords_hint"))
        self.passwords_edit.setToolTip(t("source.passwords_tip"))
        self.passwords_edit.setMaximumHeight(72)
        try:
            self.passwords_edit.setPlainText(
                "\n".join(load_settings().archive_passwords)
            )
        except OSError:
            pass
        layout.addWidget(self.passwords_label)
        layout.addWidget(self.passwords_edit)
        self._sync_password_widgets()

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        self._apply_defaults()
        self._fit_to_content()

    def sizeHint(self) -> QSize:  # noqa: N802 — Qt API
        lay = self.layout()
        if lay is not None:
            lay.activate()
            hint = lay.sizeHint()
            if hint.isValid() and hint.height() > 0:
                return QSize(max(self._default_w, hint.width()), hint.height())
        return QSize(self._default_w, 220)

    def minimumSizeHint(self) -> QSize:  # noqa: N802 — Qt API
        hint = self.sizeHint()
        return QSize(520, max(160, min(hint.height(), 900)))

    def showEvent(self, event) -> None:  # noqa: N802 — Qt API
        super().showEvent(event)
        self._fit_to_content()
        QTimer.singleShot(0, self._fit_to_content)

    def force_close(self) -> None:
        """Hauptfenster-Quit: ohne zweite Nachfrage."""
        self.setProperty("rezeptor_force_close", True)
        self.done(QDialog.DialogCode.Rejected)

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802 — Qt API
        if self.property("rezeptor_force_close"):
            event.accept()
            super().closeEvent(event)
            return
        self.reject()
        event.accept()
        super().closeEvent(event)

    def _fit_to_content(self) -> None:
        """Fensterhöhe an Inhalt — weder Leerraum noch Überlappung."""
        if self._sizing:
            return
        self._sizing = True
        try:
            lay = self.layout()
            if lay is not None:
                lay.activate()
            hint = self.sizeHint()
            w = max(520, self._default_w, hint.width())
            h = max(160, hint.height())
            if self._archive_mode_active():
                h = max(h, 280)
            if self.version_hint.isVisible():
                h = max(h, hint.height() + 8)
            self.setMinimumHeight(min(h, 200))
            # Nicht höher als Inhalt + kleiner Puffer; Breite stabil.
            self.resize(w, h + 4)
        finally:
            self._sizing = False

    def _archive_mode_active(self) -> bool:
        return self._pick_archive or self._source_kind == "archive"

    def _sync_password_widgets(self) -> None:
        show = self._archive_mode_active()
        self.passwords_label.setVisible(show)
        self.passwords_edit.setVisible(show)
        self._fit_to_content()

    def _on_source_mode_changed(self) -> None:
        self._pick_archive = self._mode_archive.isChecked()
        self._sync_password_widgets()
        self._sync_primary_tips()
        if self._pick_archive:
            self.primary_edit.clear()
            self.primary_edit.setPlaceholderText(t("source.archive_ph"))
            self._update_version_hint("")
        else:
            self._apply_defaults()
        self._fit_to_content()

    def _sync_primary_tips(self) -> None:
        if self._archive_mode_active():
            tip = t("source.archive_tip")
        elif self._source_kind == "installer":
            tip = t("source.installer_tip")
        else:
            tip = t("source.folder_tip")
        self.primary_edit.setToolTip(tip)
        self.primary_btn.setToolTip(tip)

    def _clear_primary(self) -> None:
        self.primary_edit.clear()
        self._update_version_hint("")
        self._refresh_update_status()

    def _clear_target(self) -> None:
        self.target_edit.clear()

    def _on_primary_changed(self, _text: str = "") -> None:
        self._refresh_update_status()

    def _show_fix_info(self) -> None:
        title, body = fix_help_text(self._meta)
        QMessageBox.information(self, title, body)

    def _online_fix_folder_ok(self, path: Path) -> bool:
        if not path.is_dir():
            return False
        try:
            return any(path.glob("*.dll")) or any(path.glob("*.ini"))
        except OSError:
            return False

    def _refresh_update_status(self) -> None:
        """Zeigt erkannte Updates (Halo) oder Online-Fix-Ordner-Status."""
        label = getattr(self, "update_status", None)
        if label is None:
            return
        primary = self._edit_text(self.primary_edit)
        parts: list[str] = []
        cares_updates = (
            recipe_supports_update(self._meta) or self._fix_category == "updates"
        )
        if cares_updates:
            units: list[tuple[str, str]] = []
            scan_root = ""
            if primary and not self._archive_mode_active():
                p = Path(normalize_user_path(primary, self._root))
                if p.is_dir():
                    scan_root = str(p)
                    units = discover_update_units(p)
                elif p.is_file() and p.suffix.lower() == ".iso":
                    parent = p.parent
                    units = discover_update_units(parent)
                    scan_root = str(parent)
            fix = self._edit_text(self.fix_edit) if self._shows_fix else ""
            fix_units: list[tuple[str, str]] = []
            if fix and self._fix_category == "updates":
                fp = Path(normalize_user_path(fix, self._root))
                if fp.is_dir():
                    fix_units = discover_update_units(fp)
                elif fp.is_file() and fp.suffix.lower() == ".exe":
                    fix_units = [("1", str(fp))]
            if units:
                parts.append(t("source.updates_found", n=len(units)))
            elif scan_root:
                parts.append(t("source.updates_none"))
            if fix_units:
                parts.append(t("source.updates_fix_found", n=len(fix_units)))
            elif fix and self._fix_category == "updates":
                parts.append(t("source.updates_fix_none"))
        elif self._fix_category == "online_fix":
            fix = self._edit_text(self.fix_edit)
            if fix:
                fp = Path(normalize_user_path(fix, self._root))
                if self._online_fix_folder_ok(fp):
                    parts.append(t("source.online_fix_status_ok"))
                else:
                    parts.append(t("source.online_fix_status_check"))

        if parts:
            label.setText(" · ".join(parts))
            label.setVisible(True)
        else:
            label.clear()
            label.setVisible(False)
        self._fit_to_content()

    def _apply_defaults(self) -> None:
        dr = Path(
            os.path.expanduser(
                self._meta.get("data_root", f"~/.local/share/wine-software/{self._rid}")
                .replace("{repo}", str(self._root))
            )
        )
        if self._source_kind == "installer":
            self.primary_edit.setPlaceholderText(t("source.installer_ph"))
        elif self._source_kind == "archive" or self._pick_archive:
            self.primary_edit.setPlaceholderText(t("source.archive_ph"))
        if self._show_target:
            if (self._meta.get("steam_appid") or "").strip():
                ph = t("source.steam_target_ph")
            elif is_portable_install(self._meta):
                ph = t("source.portable_ph")
            else:
                ph = t("source.data_root_ph")
            self.target_edit.setPlaceholderText(ph)
        # Nutzer hat geleert → keine Heuristik / portable.env wieder einfüllen.
        if self._paths_cleared:
            self._refresh_update_status()
            return
        if self._source_kind == "folder" and not self._pick_archive:
            default = default_folder_source(self._rid, dr, self._root, meta=self._meta)
            if default:
                self.primary_edit.setText(default)
                self._update_version_hint(default)
        if self._show_target:
            saved = default_target_dir(self._meta, self._rid, dr)
            if saved:
                self.target_edit.setText(saved)
            else:
                self.target_edit.clear()
        self._apply_pending_env()
        self._refresh_update_status()

    def _apply_pending_env(self) -> None:
        """Overlay previously saved source/target from settings."""
        pe = self._pending_env
        if not pe:
            return
        archive = (pe.get("RECIPE_ARCHIVE_PATH") or "").strip()
        source = (pe.get("RECIPE_SOURCE_ROOT") or "").strip()
        installer = (pe.get("RECIPE_INSTALLER_PATH") or "").strip()
        if archive and self._allow_archive:
            self._pick_archive = True
            if hasattr(self, "_mode_archive"):
                self._mode_archive.blockSignals(True)
                self._mode_archive.setChecked(True)
                self._mode_archive.blockSignals(False)
            self._sync_password_widgets()
            self._sync_primary_tips()
            self.primary_edit.setText(archive)
            self._update_version_hint(archive)
        elif installer and self._source_kind == "installer":
            self.primary_edit.setText(installer)
            self._update_version_hint(installer)
        elif source:
            self._pick_archive = False
            if hasattr(self, "_mode_folder"):
                self._mode_folder.blockSignals(True)
                self._mode_folder.setChecked(True)
                self._mode_folder.blockSignals(False)
            self._sync_password_widgets()
            self._sync_primary_tips()
            self.primary_edit.setText(source)
            self._update_version_hint(source)
        target = (
            (pe.get("RECIPE_TARGET_DIR") or "").strip()
            or (pe.get("WISO_TARGET_DIR") or "").strip()
            or (pe.get("RECIPE_DATA_ROOT") or "").strip()
        )
        if target and self._show_target:
            self.target_edit.setText(target)
        fix = (pe.get("RECIPE_FIX_ROOT") or pe.get("WISO_FIX_ROOT") or "").strip()
        if fix and self._shows_fix:
            self.fix_edit.setText(fix)

    def _pick_primary(self) -> None:
        start = self.primary_edit.text() or str(documents_dir())
        if self._pick_archive:
            fmts = self._meta.get("source_formats") or DEFAULT_ARCHIVE_FORMATS
            path = pick_open_file(
                self, t("source.pick_archive"), start, archive_filter(fmts)
            )
            if path:
                self.primary_edit.setText(path)
                self._update_version_hint(path)
            self._fit_to_content()
            return
        kind = self._source_kind
        if kind == "folder":
            title = (self._meta.get("source_label") or "").strip() or t(
                "source.pick_folder"
            )
            start_dir = dialog_start_dir(start)
            # Adobe / Spiel-ISO: Ordner ODER .iso
            if allows_iso_folder_source(self._meta, self._rid):
                box = QMessageBox(self)
                box.setWindowTitle(title)
                box.setText(
                    t("source.adobe_pick_kind")
                    if is_adobe_offline_recipe(self._rid)
                    else t("source.game_pick_kind")
                )
                iso_btn = box.addButton(
                    t("source.pick_iso"), QMessageBox.ButtonRole.AcceptRole
                )
                dir_btn = box.addButton(
                    t("source.pick_folder"), QMessageBox.ButtonRole.AcceptRole
                )
                box.addButton(QMessageBox.StandardButton.Cancel)
                box.exec()
                clicked = box.clickedButton()
                if clicked is iso_btn:
                    filt = (
                        t("source.adobe_filter")
                        if is_adobe_offline_recipe(self._rid)
                        else t("source.game_filter")
                    )
                    iso = pick_open_file(self, title, start_dir, filt)
                    if iso:
                        if is_adobe_offline_recipe(self._rid):
                            normalized = normalize_folder_source(
                                self._rid, iso, version_hint=self._version_guaranteed
                            )
                        else:
                            normalized = normalize_user_path(iso, self._root)
                        self.primary_edit.setText(normalized)
                        self._update_version_hint(normalized)
                elif clicked is dir_btn:
                    d = pick_directory(self, title, start_dir)
                    if d:
                        pd = Path(d)
                        if is_adobe_offline_recipe(self._rid) and (
                            _looks_like_adobe_pack_root(pd)
                            or _looks_like_adobe_iso_only_pack(pd)
                        ):
                            shown = str(pd.resolve())
                        elif is_adobe_offline_recipe(self._rid):
                            shown = normalize_folder_source(
                                self._rid, d, version_hint=self._version_guaranteed
                            )
                        else:
                            shown = normalize_user_path(d, self._root)
                        self.primary_edit.setText(shown)
                        self._update_version_hint(shown)
                self._fit_to_content()
                return
            d = pick_directory(self, title, start)
            if d:
                normalized = normalize_folder_source(
                    self._rid, d, version_hint=self._version_guaranteed
                )
                self.primary_edit.setText(normalized)
                self._update_version_hint(normalized)
            self._fit_to_content()
            return
        if kind == "installer":
            fmts = (self._meta.get("source_formats") or "").strip()
            if fmts:
                parts = [p.strip() for p in fmts.split(",") if p.strip()]
                globs = " ".join(f"*.{p}" for p in parts)
                file_filter = f"{t('source.file_filter_label')} ({globs});;{t('source.all_files')}"
            else:
                file_filter = t("source.exe_filter")
            exe = pick_open_file(
                self, t("source.pick_installer"), start, file_filter
            )
            if exe:
                self.primary_edit.setText(exe)
                self._update_version_hint(exe)
            self._fit_to_content()
            return
        if kind == "archive":
            fmts = self._meta.get("source_formats") or DEFAULT_ARCHIVE_FORMATS
            path = pick_open_file(
                self, t("source.pick_archive"), start, archive_filter(fmts)
            )
            if path:
                self.primary_edit.setText(path)
                self._update_version_hint(path)
        self._fit_to_content()

    def _pick_target(self) -> None:
        d = pick_directory(
            self,
            t("source.pick_target_dir"),
            self.target_edit.text() or str(documents_dir()),
        )
        if d:
            self.target_edit.setText(d)
        self._fit_to_content()

    def _pick_fix(self) -> None:
        """Update/Fix: Ordner oder .exe (nummerierte Update-Pakete); Online-Fix nur Ordner."""
        start = self.fix_edit.text() or str(documents_dir())
        if self._fix_category == "online_fix":
            d = pick_directory(self, t("source.pick_online_fix_dir"), start)
            if d:
                self.fix_edit.setText(d)
            self._fit_to_content()
            return
        box = QMessageBox(self)
        box.setWindowTitle(t("source.fix"))
        box.setText(t("source.pick_update_kind"))
        dir_btn = box.addButton(
            t("source.pick_update_folder"), QMessageBox.ButtonRole.AcceptRole
        )
        file_btn = box.addButton(
            t("source.pick_fix_exe"), QMessageBox.ButtonRole.AcceptRole
        )
        box.addButton(QMessageBox.StandardButton.Cancel)
        box.exec()
        clicked = box.clickedButton()
        if clicked is dir_btn:
            d = pick_directory(self, t("source.pick_fix_dir"), start)
            if d:
                self.fix_edit.setText(d)
        elif clicked is file_btn:
            exe = pick_open_file(
                self, t("source.pick_fix_exe"), start, t("source.exe_filter")
            )
            if exe:
                self.fix_edit.setText(exe)
        self._fit_to_content()

    @staticmethod
    def _edit_text(edit: QLineEdit) -> str:
        try:
            return edit.text().strip()
        except RuntimeError:
            # SIP: C++ widget already deleted (orphaned wrap GC, Wayland teardown)
            return ""

    def _normalize_primary(self) -> str:
        raw = self._edit_text(self.primary_edit)
        if self._source_kind == "folder" and raw and not self._pick_archive:
            path = normalize_user_path(raw, self._root)
            # Pack-Root sichtbar/als Quelle behalten — ISO wird in build_env aufgelöst
            if is_adobe_offline_recipe(self._rid):
                pp = Path(path)
                if _looks_like_adobe_pack_root(pp) or _looks_like_adobe_iso_only_pack(
                    pp
                ):
                    return str(pp.resolve())
            return normalize_folder_source(
                self._rid,
                path,
                version_hint=self._version_guaranteed,
            )
        return normalize_user_path(raw, self._root) if raw else raw

    def _normalize_target(self) -> str:
        return normalize_user_path(self._edit_text(self.target_edit), self._root)

    def _commit_paths(self, *, primary: str, target: str = "", fix: str = "") -> None:
        """Freeze paths before accept() — never re-read widgets after the dialog closes."""
        self._result_primary = primary
        self._result_target = target
        self._result_fix = fix

    def _update_version_hint(self, path: str) -> None:
        """Show version/guarantee feedback only after a source path is set."""
        path = (path or "").strip()
        if not path:
            self.version_hint.clear()
            self.version_hint.setStyleSheet("")
            self.version_hint.setVisible(False)
            self._fit_to_content()
            return
        guaranteed = self._version_guaranteed
        if not guaranteed:
            self.version_hint.setVisible(False)
            self.version_hint.clear()
            self._fit_to_content()
            return
        probe = path
        if self._source_kind == "folder" and not self._pick_archive:
            probe = normalize_folder_source(
                self._rid, path, version_hint=guaranteed
            )
        detected = detect_source_version(
            self._rid,
            probe,
            recipe_dir=self._meta.get("_dir"),
            guaranteed=guaranteed,
        )
        if not detected:
            self.version_hint.setText(
                t("source.version_unknown", guaranteed=guaranteed)
            )
            self.version_hint.setStyleSheet("color: #fbbf24")
        elif version_guarantee_mismatch(guaranteed, detected):
            self.version_hint.setText(
                t(
                    "source.version_mismatch",
                    detected=detected,
                    guaranteed=guaranteed,
                )
            )
            self.version_hint.setStyleSheet("color: #fbbf24")
        else:
            self.version_hint.setText(
                t("source.version_ok", detected=detected, guaranteed=guaranteed)
            )
            self.version_hint.setStyleSheet("color: #86efac")
        self.version_hint.setVisible(True)
        self._fit_to_content()

    def _password_lines(self) -> list[str]:
        return normalize_password_list_text(
            self.passwords_edit.toPlainText()
        ).passwords

    def _persist_password_list(self, lines: list[str]) -> None:
        try:
            settings = load_settings()
            result = normalize_password_list_text("\n".join(lines))
            cleaned = result.passwords
            if cleaned != settings.archive_passwords:
                settings.archive_passwords = cleaned
                save_settings(settings)
        except OSError:
            pass

    def _resolve_archive_passwords(self, archive: str) -> bool:
        """Sync global list, probe archive, prompt if needed. False = user cancelled."""
        lines = self._password_lines()
        self._persist_password_list(lines)
        resolved = ensure_archive_passwords(
            self, Path(archive), extra=lines
        )
        if resolved is None:
            return False
        self._resolved_passwords = resolved
        try:
            self.passwords_edit.setPlainText(
                "\n".join(load_settings().archive_passwords)
            )
        except OSError:
            pass
        return True

    def _on_accept(self) -> None:
        kind = self._source_kind
        if kind == "folder" and self._pick_archive:
            primary = normalize_user_path(self._edit_text(self.primary_edit), self._root)
        else:
            primary = self._normalize_primary()
        # Leer = Konfiguration verwerfen / Dialog schließen (kein Zwang zur Quelle).
        if not primary:
            try:
                self.primary_edit.clear()
                if self._show_target:
                    self.target_edit.clear()
            except RuntimeError:
                pass
            self._commit_paths(primary="", target="", fix="")
            self.accept()
            return
        if kind == "folder":
            if self._pick_archive and not Path(primary).is_file():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_archive")
                )
                return
            if self._pick_archive and not self._resolve_archive_passwords(primary):
                return
            if not self._pick_archive:
                pp = Path(primary)
                adobe_iso_ok = (
                    allows_iso_folder_source(self._meta, self._rid)
                    and pp.is_file()
                    and pp.suffix.lower() == ".iso"
                )
                if not pp.is_dir() and not adobe_iso_ok:
                    QMessageBox.warning(
                        self,
                        t("source.folder_missing_title"),
                        t("source.need_folder", path=primary),
                    )
                    return
            fix_raw = (
                self._edit_text(self.fix_edit) if self._shows_fix else ""
            )
            if fix_is_required(self._fix_kind) and not fix_raw:
                need = (
                    t("source.need_online_fix")
                    if self._fix_category == "online_fix"
                    else t("source.need_fix")
                )
                QMessageBox.warning(self, t("dialog.missing"), need)
                return
            target = ""
            if self._show_target:
                target = self._normalize_target()
                if not target:
                    QMessageBox.warning(
                        self, t("dialog.missing"), t("source.need_target")
                    )
                    return
                parent = Path(target).parent
                if not parent.is_dir():
                    QMessageBox.warning(
                        self,
                        t("source.target_invalid_title"),
                        t("source.target_invalid", parent=parent),
                    )
                    return
                try:
                    self.target_edit.setText(target)
                except RuntimeError:
                    pass
            try:
                self.primary_edit.setText(primary)
            except RuntimeError:
                pass
            fix = normalize_user_path(fix_raw, self._root) if fix_raw else ""
            self._commit_paths(primary=primary, target=target, fix=fix)
            self.accept()
            return
        primary = normalize_user_path(self._edit_text(self.primary_edit), self._root)
        if kind == "installer":
            if not Path(primary).is_file():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_exe")
                )
                return
            target = ""
            if self._show_target:
                target = self._normalize_target()
                if not target:
                    QMessageBox.warning(
                        self, t("dialog.missing"), t("source.need_target")
                    )
                    return
                parent = Path(target).parent
                if not parent.is_dir():
                    QMessageBox.warning(
                        self,
                        t("source.target_invalid_title"),
                        t("source.target_invalid", parent=parent),
                    )
                    return
                try:
                    self.target_edit.setText(target)
                except RuntimeError:
                    pass
            try:
                self.primary_edit.setText(primary)
            except RuntimeError:
                pass
            self._commit_paths(primary=primary, target=target)
            self.accept()
            return
        if kind == "archive":
            if not Path(primary).is_file():
                QMessageBox.warning(
                    self, t("dialog.missing"), t("source.need_archive")
                )
                return
            if not self._resolve_archive_passwords(primary):
                return
            target = ""
            if self._show_target:
                target = self._normalize_target()
                if not target:
                    QMessageBox.warning(
                        self, t("dialog.missing"), t("source.need_target")
                    )
                    return
                try:
                    self.target_edit.setText(target)
                except RuntimeError:
                    pass
            try:
                self.primary_edit.setText(primary)
            except RuntimeError:
                pass
            self._commit_paths(primary=primary, target=target)
            self.accept()
            return
        self.reject()

    def primary_path(self) -> str:
        if self._result_primary is not None:
            return self._result_primary
        return self._normalize_primary()

    def fix_path(self) -> str:
        if self._result_fix is not None:
            return self._result_fix
        if not self._shows_fix:
            return ""
        raw = self._edit_text(self.fix_edit)
        return normalize_user_path(raw, self._root) if raw else ""

    def target_path(self) -> str:
        if self._result_target is not None:
            return self._result_target
        return self._normalize_target()

    def _attach_archive_passwords(self, extra: dict[str, str]) -> None:
        lines = list(self._resolved_passwords or self._password_lines())
        self._persist_password_list(lines)
        attach_archive_password_files(extra, lines)
        self._pw_file = extra.get("RECIPE_ARCHIVE_PASSWORD_FILE")
        self._pw_used_file = extra.get("RECIPE_ARCHIVE_PASSWORD_USED_FILE")

    def build_env(self, data_root: Path) -> dict[str, str]:
        """Return env vars for install.sh (Archiv-Entpacken erfolgt in prepare_source)."""
        kind = self._source_kind
        extra: dict[str, str] = {}
        deploy = self._meta.get("deploy_mode", "copy")
        if deploy:
            extra["RECIPE_DEPLOY_MODE"] = deploy
        if self._show_target:
            tgt = self.target_path()
            extra["RECIPE_TARGET_DIR"] = tgt
            if is_portable_install(self._meta):
                if self._rid == "wiso-steuer":
                    extra["WISO_TARGET_DIR"] = tgt
            else:
                # Installer / native: Ziel = Datenordner (Prefix darunter)
                extra["RECIPE_DATA_ROOT"] = tgt
                extra["DATA_ROOT"] = tgt
                extra["WINEPREFIX"] = f"{tgt}/prefix"
                extra["WINE_PREFIX"] = f"{tgt}/prefix"
        if kind == "folder":
            if self._pick_archive:
                extra["RECIPE_ARCHIVE_PATH"] = self.primary_path()
                self._attach_archive_passwords(extra)
            else:
                root = self.primary_path()
                pack = adobe_pack_root_for_source(root)
                if pack:
                    extra["RECIPE_PACK_ROOT"] = pack
                if root.lower().endswith(".iso"):
                    # ISO: Adobe extrahiert; Spiele mounten in prepare_source
                    extra["RECIPE_INSTALLER_PATH"] = root
                else:
                    # Pack-Ordner ohne Normierung auf ISO, oder Set-up-Baum
                    if pack and not (Path(root) / "Set-up.exe").is_file():
                        iso = _adobe_iso_in_pack_dir(
                            Path(root), self._version_guaranteed
                        )
                        if iso is not None:
                            extra["RECIPE_INSTALLER_PATH"] = str(iso)
                        extra["RECIPE_SOURCE_ROOT"] = root
                    else:
                        # Spiel-Pack mit .iso im Ordner → Source-Root (Mount in prepare_source)
                        extra["RECIPE_SOURCE_ROOT"] = root
                        if (
                            not is_adobe_offline_recipe(self._rid)
                            and allows_iso_folder_source(self._meta, self._rid)
                        ):
                            iso = None
                            try:
                                for c in sorted(Path(root).glob("*.iso")) + sorted(
                                    Path(root).glob("*.ISO")
                                ):
                                    if c.is_file():
                                        iso = c
                                        break
                            except OSError:
                                iso = None
                            if iso is not None and not (
                                Path(root) / "setup.exe"
                            ).is_file() and not (Path(root) / "Setup.exe").is_file():
                                # Keep SOURCE_ROOT; prepare_source mounts ISO inside
                                pass
                    if self._rid == "wiso-steuer":
                        extra["WISO_PORTABLE_ROOT"] = root
            fix = self.fix_path()
            if fix:
                extra["RECIPE_FIX_ROOT"] = fix
                if self._fix_category == "updates":
                    extra["RECIPE_UPDATE_ROOT"] = fix
                elif self._fix_category == "online_fix":
                    merge = (self._meta.get("fix_merge_path") or "").strip()
                    if merge:
                        extra["RECIPE_FIX_MERGE_PATH"] = merge
                if self._rid == "wiso-steuer":
                    extra["WISO_FIX_ROOT"] = fix
            return extra
        if kind == "installer":
            extra["RECIPE_INSTALLER_PATH"] = self.primary_path()
            pack = adobe_pack_root_for_source(self.primary_path())
            if pack:
                extra["RECIPE_PACK_ROOT"] = pack
            return extra
        if kind == "archive":
            extra["RECIPE_ARCHIVE_PATH"] = self.primary_path()
            self._attach_archive_passwords(extra)
            return extra
        return extra


def allows_iso_folder_source(meta: dict[str, str], rid: str = "") -> bool:
    """Folder source may also pick a .iso (Adobe or games with iso in source_formats)."""
    if is_adobe_offline_recipe(rid or meta.get("id", "")):
        return True
    fmts = (meta.get("source_formats") or "").lower()
    return "iso" in {p.strip() for p in fmts.replace(";", ",").split(",") if p.strip()}


def recipe_supports_update(meta: dict[str, str]) -> bool:
    """fix_kind optional/required and update.sh hook present."""
    if fix_kind_category(meta.get("fix_kind", "none")) != "updates":
        return False
    upd = (meta.get("update") or "").strip()
    if not upd:
        return False
    d = (meta.get("_dir") or "").strip()
    if not d:
        return True
    return (Path(d) / upd).is_file()


def needs_source_dialog(meta: dict[str, str]) -> bool:
    return meta.get("source_kind", "") not in ("", "fixed_path")


def source_configure_label(meta: dict[str, str]) -> str:
    """One clear menu label. Long recipe ``source_label`` stays in the dialog only."""
    _ = meta  # kind-specific wording lives in recipe.yml → dialog fields
    return t("source.configure")


class UpdateSourceDialog(QDialog):
    """Update-only source picker (Mehr → Update anwenden)."""

    def __init__(
        self,
        parent: QWidget | None,
        *,
        rid: str,
        meta: dict[str, str],
        root: Path,
        title: str = "",
    ) -> None:
        super().__init__(parent)
        _prepare_modal_source_dialog(self)
        self._rid = rid
        self._meta = meta
        self._root = root
        self._result: str = ""
        self.setWindowTitle(title or t("source.update_title"))
        self.setMinimumWidth(520)

        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.setContentsMargins(12, 12, 12, 12)

        intro = QLabel(t("source.update_label"))
        intro.setObjectName("muted")
        intro.setWordWrap(True)
        layout.addWidget(intro)

        row = QHBoxLayout()
        self.path_edit = QLineEdit()
        self.path_edit.setPlaceholderText(t("source.update_label"))
        pick = QPushButton(t("source.pick_update"))
        pick.clicked.connect(self._pick)
        clear = QPushButton(t("source.clear"))
        clear.clicked.connect(self.path_edit.clear)
        row.addWidget(self.path_edit, stretch=1)
        row.addWidget(pick)
        row.addWidget(clear)
        layout.addLayout(row)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def force_close(self) -> None:
        self.setProperty("rezeptor_force_close", True)
        self.done(QDialog.DialogCode.Rejected)

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802 — Qt API
        if self.property("rezeptor_force_close"):
            event.accept()
            super().closeEvent(event)
            return
        self.reject()
        event.accept()
        super().closeEvent(event)

    def _pick(self) -> None:
        start = self.path_edit.text() or str(documents_dir())
        box = QMessageBox(self)
        box.setWindowTitle(t("source.update_title"))
        box.setText(t("source.pick_update_kind"))
        dir_btn = box.addButton(
            t("source.pick_update_folder"), QMessageBox.ButtonRole.AcceptRole
        )
        file_btn = box.addButton(
            t("source.pick_update_file"), QMessageBox.ButtonRole.AcceptRole
        )
        box.addButton(QMessageBox.StandardButton.Cancel)
        box.exec()
        clicked = box.clickedButton()
        if clicked is dir_btn:
            d = pick_directory(self, t("source.pick_update_folder"), start)
            if d:
                self.path_edit.setText(d)
        elif clicked is file_btn:
            filt = (
                f"{t('source.file_filter_label')} "
                "(*.exe *.iso *.zip *.7z *.rar *.tar.gz);;"
                f"{t('source.all_files')}"
            )
            f = pick_open_file(self, t("source.pick_update_file"), start, filt)
            if f:
                self.path_edit.setText(f)

    def _on_accept(self) -> None:
        raw = self.path_edit.text().strip()
        if not raw:
            QMessageBox.warning(self, t("dialog.missing"), t("source.update_need"))
            return
        path = normalize_user_path(raw, self._root)
        p = Path(path)
        if not p.exists():
            QMessageBox.warning(
                self,
                t("source.folder_missing_title"),
                t("source.need_folder", path=path),
            )
            return
        self._result = path
        self.accept()

    def update_path(self) -> str:
        return self._result

    def build_env(self) -> dict[str, str]:
        path = self.update_path()
        if not path:
            return {}
        extra = {
            "RECIPE_UPDATE_ROOT": path,
            "RECIPE_FIX_ROOT": path,
        }
        if Path(path).is_file() and path.lower().endswith(
            (".zip", ".7z", ".rar", ".tar.gz", ".tgz")
        ):
            # Archive: install path uses RECIPE_ARCHIVE for extract elsewhere —
            # update hook expects a root; leave as path for apply to treat as file/exe.
            pass
        return extra
