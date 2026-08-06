#!/usr/bin/env python3
"""Register Halo CE as a Steam Non-Steam shortcut with Proton + launch options.

Writes (Steam must be closed):
  - userdata/<id>/config/shortcuts.vdf
  - config/config.vdf  → CompatToolMapping
  - symlink steamapps/compatdata/<appid> → Rezeptor steam-compat (pfx→prefix)

Prints: APPID=<u32> on success (stdout). Other info on stderr.
"""
from __future__ import annotations

import argparse
import binascii
import os
import shutil
import struct
import sys
import time
from pathlib import Path

try:
    import vdf
except ImportError as e:
    print(f"error: python module 'vdf' required ({e})", file=sys.stderr)
    raise SystemExit(2)

STEAM_ID64_BASE = 76561197960265728
SHORTCUT_NAME = "Halo Campaign Evolved (Rezeptor)"
DEFAULT_TOOL_NAME = "GE-Proton11-3"
STEAM_DEFAULT_ALIASES = frozenset(
    {"steam_default", "steam-default", "global", "none"}
)


def _is_steam_default(tool: str) -> bool:
    return (tool or "").strip().lower() in STEAM_DEFAULT_ALIASES


def resolve_tool_name(tool: str) -> str:
    """Map Medizin placeholders to a real CompatToolMapping name."""
    t = (tool or "").strip() or DEFAULT_TOOL_NAME
    low = t.lower()
    if low in STEAM_DEFAULT_ALIASES:
        return "steam_default"
    if low == "system":
        # Late import path: scan compatibilitytools.d like the launcher catalog.
        try:
            import sys

            launcher = Path(__file__).resolve().parents[3] / "launcher"
            if launcher.is_dir() and str(launcher) not in sys.path:
                sys.path.insert(0, str(launcher))
            from steam_proton_catalog import best_system_proton

            best = best_system_proton()
            if best:
                return best[0]
        except Exception as exc:
            eprint(f"warning: could not resolve system Proton: {exc}")
        eprint("warning: no system Proton found — falling back to Rezeptor GE")
        return DEFAULT_TOOL_NAME
    return t


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def to_i32(u: int) -> int:
    return struct.unpack("i", struct.pack("I", u & 0xFFFFFFFF))[0]


def shortcut_appid_u32(exe_field: str, name: str) -> int:
    # Steam CRC of Exe string (incl. quotes) + AppName, high bit set.
    return (binascii.crc32((exe_field + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def shortcut_bpid(appid_u32: int) -> int:
    """64-bit ID for steam://rungameid/… (not the 32-bit shortcuts.vdf appid)."""
    return ((appid_u32 & 0xFFFFFFFF) << 32) | 0x02000000


def steam_root(override: str | None = None) -> Path:
    if override:
        p = Path(override)
        if not (p / "config").is_dir():
            raise SystemExit(f"error: invalid --steam-root {p}")
        return p
    for p in (
        Path(os.environ.get("STEAM_COMPAT_CLIENT_INSTALL_PATH", "")),
        Path.home() / ".local/share/Steam",
        Path.home() / ".steam/steam",
    ):
        if p and (p / "config").is_dir():
            return p
    raise SystemExit("error: Steam root not found")


def _userdata_account_ids(root: Path) -> list[int]:
    ud = root / "userdata"
    ids: list[int] = []
    if not ud.is_dir():
        return ids
    for child in ud.iterdir():
        if child.name.isdigit() and (child / "config").is_dir():
            ids.append(int(child.name))
    return sorted(ids)


def active_account_id(root: Path) -> int:
    """Resolve userdata/<id>. Prefer loginusers, fall back to on-disk userdata.

    loginusers.vdf can be briefly unreadable while Steam is shutting down — never
    fail hard if userdata/*/config exists.
    """
    on_disk = _userdata_account_ids(root)
    login = root / "config/loginusers.vdf"
    if login.is_file():
        try:
            data = vdf.loads(login.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            data = {}
        users = data.get("users") or {}
        best_id = None
        best_ts = -1
        best_auto = None
        for sid, meta in users.items():
            if not isinstance(meta, dict):
                continue
            try:
                sid64 = int(sid)
                acc = sid64 - STEAM_ID64_BASE
            except ValueError:
                continue
            if on_disk and acc not in on_disk:
                continue
            ts = int(meta.get("Timestamp") or 0)
            if meta.get("MostRecent") in ("1", 1, True):
                return acc
            if meta.get("AutoLogin") in ("1", 1, True):
                best_auto = acc
            if ts >= best_ts:
                best_ts = ts
                best_id = acc
        if best_auto is not None:
            return best_auto
        if best_id is not None:
            return best_id
    if on_disk:
        # Prefer the userdata folder with the newest config mtime.
        def mtime(acc: int) -> float:
            p = root / "userdata" / str(acc) / "config"
            try:
                return p.stat().st_mtime
            except OSError:
                return 0.0

        return max(on_disk, key=mtime)
    raise SystemExit("error: no Steam userdata")


def backup(path: Path) -> None:
    if not path.is_file():
        return
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bak = path.with_suffix(path.suffix + f".rezeptor_bak.{stamp}")
    shutil.copy2(path, bak)
    eprint(f"backup: {bak}")


def ensure_ge_proton_tool(root: Path, proton_dir: Path, tool_name: str) -> None:
    if not (proton_dir / "proton").is_file():
        raise SystemExit(f"error: proton script missing in {proton_dir}")
    # Only manage a symlink when the selected tool is our Rezeptor GE tree.
    if tool_name != DEFAULT_TOOL_NAME and tool_name not in str(proton_dir):
        eprint(
            f"compat tool: skip Steam link for {tool_name!r} "
            f"(proton-dir is {proton_dir.name})"
        )
        return
    dest = root / "compatibilitytools.d" / tool_name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink() or dest.exists():
        if dest.resolve() == proton_dir.resolve():
            eprint(f"compat tool ok: {dest}")
            return
        if dest.is_symlink():
            dest.unlink()
        else:
            eprint(f"warning: {dest} exists and is not our symlink — leaving it")
            return
    dest.symlink_to(proton_dir, target_is_directory=True)
    eprint(f"compat tool linked: {dest} → {proton_dir}")


def load_shortcuts(path: Path) -> dict:
    if not path.is_file() or path.stat().st_size == 0:
        return {"shortcuts": {}}
    raw = path.read_bytes()
    data = vdf.binary_loads(raw)
    if "shortcuts" not in data or not isinstance(data["shortcuts"], dict):
        data = {"shortcuts": {}}
    return data


def stage_shortcut_icon(compat_dir: Path, icon_src: str) -> str:
    """Copy icon into steam-compat so Steam keeps a stable absolute path."""
    src = Path(icon_src.strip().strip('"')) if icon_src else None
    if src is None or not src.is_file():
        return ""
    compat_dir.mkdir(parents=True, exist_ok=True)
    dest = compat_dir / "shortcut-icon.png"
    try:
        if not dest.is_file() or dest.stat().st_mtime < src.stat().st_mtime:
            shutil.copy2(src, dest)
    except OSError as exc:
        eprint(f"warning: could not stage icon: {exc}")
        return str(src.resolve())
    return str(dest.resolve())


def _copy_if_newer(src: Path, dest: Path) -> bool:
    try:
        if dest.is_file() and dest.stat().st_mtime >= src.stat().st_mtime:
            return False
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        return True
    except OSError as exc:
        eprint(f"warning: grid copy {src.name}: {exc}")
        return False


def stage_grid_artwork(
    grid_dir: Path,
    appid_u32: int,
    assets_dir: str = "",
) -> int:
    """Install Library cover/wide/hero/logo under userdata/.../config/grid/.

    Steam naming (Non-Steam unsigned appid):
      {appid}p.png  portrait cover
      {appid}.png   wide capsule
      {appid}_hero.png
      {appid}_logo.png
    """
    src_root = Path(assets_dir) if assets_dir else None
    if src_root is None or not src_root.is_dir():
        # Default: next to this script …/assets/steam-grid
        here = Path(__file__).resolve().parent / "steam-grid"
        src_root = here if here.is_dir() else None
    if src_root is None:
        eprint("warning: no steam-grid assets dir — skip Library art")
        return 0
    mapping = {
        "cover.png": f"{appid_u32}p.png",
        "wide.png": f"{appid_u32}.png",
        "hero.png": f"{appid_u32}_hero.png",
        "logo.png": f"{appid_u32}_logo.png",
    }
    n = 0
    grid_dir.mkdir(parents=True, exist_ok=True)
    for src_name, dest_name in mapping.items():
        src = src_root / src_name
        if not src.is_file():
            eprint(f"warning: missing grid asset {src}")
            continue
        dest = grid_dir / dest_name
        if _copy_if_newer(src, dest) or dest.is_file():
            n += 1
            eprint(f"grid: {dest_name}")
    return n


def grid_artwork_ok(grid_dir: Path, appid_u32: int) -> bool:
    """Portrait cover is the minimum Steam shows in Starting-game / Customization."""
    cover = grid_dir / f"{appid_u32}p.png"
    if cover.is_file() and cover.stat().st_size > 0:
        return True
    # jpg fallback
    cover_j = grid_dir / f"{appid_u32}p.jpg"
    return cover_j.is_file() and cover_j.stat().st_size > 0


def upsert_shortcut(
    data: dict,
    *,
    name: str,
    exe_field: str,
    start_dir_field: str,
    launch_options: str,
    appid_i32: int,
    icon: str = "",
) -> dict:
    sc = data.setdefault("shortcuts", {})
    found_key = None
    for key, entry in sc.items():
        if not isinstance(entry, dict):
            continue
        if entry.get("AppName") == name or entry.get("Exe") == exe_field:
            found_key = key
            break
    if found_key is None:
        idxs = []
        for key in sc:
            try:
                idxs.append(int(key))
            except ValueError:
                pass
        found_key = str(max(idxs) + 1 if idxs else 0)
    prev = sc.get(found_key) if isinstance(sc.get(found_key), dict) else {}
    last_play = int(prev.get("LastPlayTime") or 0)
    sc[found_key] = {
        "appid": appid_i32,
        "AppName": name,
        "Exe": exe_field,
        "StartDir": start_dir_field,
        "icon": icon,
        "ShortcutPath": "",
        "LaunchOptions": launch_options,
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 0,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": last_play,
        "FlatpakAppID": "",
        "tags": {},
    }
    return data


def set_compat_mapping(config_path: Path, appid_u32: int, tool: str) -> None:
    """Force a specific Steam Play tool (Properties → Compatibility checkbox on)."""
    if not config_path.is_file():
        raise SystemExit(f"error: missing {config_path}")
    backup(config_path)
    text = config_path.read_text(encoding="utf-8", errors="replace")
    data = vdf.loads(text)
    steam = (
        data.setdefault("InstallConfigStore", {})
        .setdefault("Software", {})
        .setdefault("Valve", {})
        .setdefault("Steam", {})
    )
    mapping = steam.setdefault("CompatToolMapping", {})
    mapping[str(appid_u32)] = {
        "name": tool,
        "config": "",
        "priority": "250",
    }
    out = vdf.dumps(data, pretty=True)
    tmp = config_path.with_suffix(".vdf.rezeptor_tmp")
    tmp.write_text(out, encoding="utf-8")
    tmp.replace(config_path)
    eprint(f"CompatToolMapping[{appid_u32}] = {tool}")


def clear_compat_mapping(config_path: Path, appid_u32: int) -> None:
    """Remove per-app Force tool → Steam uses global Steam Play default."""
    if not config_path.is_file():
        eprint(f"warning: missing {config_path} — cannot clear CompatToolMapping")
        return
    backup(config_path)
    text = config_path.read_text(encoding="utf-8", errors="replace")
    data = vdf.loads(text)
    steam = (
        data.get("InstallConfigStore", {})
        .get("Software", {})
        .get("Valve", {})
        .get("Steam", {})
    )
    if not isinstance(steam, dict):
        eprint("warning: Steam config shape unexpected — skip clear mapping")
        return
    mapping = steam.get("CompatToolMapping")
    if not isinstance(mapping, dict):
        eprint(f"CompatToolMapping[{appid_u32}] already unset (Steam default)")
        return
    key = str(appid_u32)
    if key not in mapping:
        eprint(f"CompatToolMapping[{appid_u32}] already unset (Steam default)")
        return
    del mapping[key]
    out = vdf.dumps(data, pretty=True)
    tmp = config_path.with_suffix(".vdf.rezeptor_tmp")
    tmp.write_text(out, encoding="utf-8")
    tmp.replace(config_path)
    eprint(f"CompatToolMapping[{appid_u32}] cleared (Steam global Steam Play)")


def apply_compat_tool(config_path: Path, appid_u32: int, tool: str) -> None:
    """tool=steam_default → clear Force; else set CompatToolMapping name."""
    if _is_steam_default(tool):
        clear_compat_mapping(config_path, appid_u32)
        return
    set_compat_mapping(config_path, appid_u32, (tool or "").strip())


def ensure_compatdata_link(root: Path, appid_u32: int, compat_dir: Path) -> None:
    compat_dir.mkdir(parents=True, exist_ok=True)
    dest = root / "steamapps" / "compatdata" / str(appid_u32)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink():
        if dest.resolve() == compat_dir.resolve():
            eprint(f"compatdata ok: {dest}")
            return
        dest.unlink()
    elif dest.exists():
        eprint(f"warning: {dest} exists — not replacing; set STEAM_COMPAT_DATA_PATH in LaunchOptions")
        return
    dest.symlink_to(compat_dir, target_is_directory=True)
    eprint(f"compatdata linked: {dest} → {compat_dir}")


# Native vkd3d/DXVK — without this Steam/Wine uses builtins → Halo
# "Your GPU or driver isn't supported."
_HALO_WINEDLLOVERRIDES = (
    "d3d12,d3d12core,dxgi,d3d11,d3d10core,steam_api64,RUNE64,"
    "libHttpClient.Win32=n;"
    "msvcp140,msvcp140_1,msvcp140_2,msvcp140_atomic_wait,msvcp140_codecvt_ids,"
    "vcruntime140,vcruntime140_1,concrt140=n,b;"
    "winhttp=n,b;gameinput=;nvapi64,nvapi=n"
)


def _steam_env_assign(key: str, value: str) -> str:
    """Format KEY=value for Steam Launch Options (/bin/sh).

    Unquoted ';' is a shell command separator — WINEDLLOVERRIDES must be quoted
    or Steam runs fragments as commands and the game exits instantly.
    """
    if any(ch in value for ch in (";", " ", "\t", '"', "'", "&", "|", "<", ">")):
        esc = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'{key}="{esc}"'
    return f"{key}={value}"


def build_launch_options(
    *,
    steam_compatdata: Path,
    exe_path: Path,
    gamescope: bool,
    extra: str,
) -> str:
    # Steam runs Launch Options via /bin/sh with %command% → proton+exe.
    # Env vars MUST come before any wrapper's "--".
    #
    # STEAM_COMPAT_DATA_PATH must stay under the Steam tree (symlink ok) so
    # pressure-vessel shares it. Extra mounts expose the game on /mnt/ssd2.
    mount = "/mnt/ssd2"
    parts: list[str] = [
        _steam_env_assign("WINEDLLOVERRIDES", _HALO_WINEDLLOVERRIDES),
        # 2 = safer under Steam's compositor; 1 often yields a black window.
        "VKD3D_SWAPCHAIN_LATENCY_FRAMES=2",
        # Same XAL in-process path as launch.sh (Proton issue 8814).
        "SteamDeck=1",
        "DXVK_ENABLE_NVAPI=1",
        "PROTON_HIDE_NVIDIA_GPU=0",
        "PROTON_USE_WINED3D=0",
        # CachyOS/Proton otherwise spawn xalia UI helpers (~200–250 MiB each).
        "PROTON_USE_XALIA=0",
        _steam_env_assign("STEAM_COMPAT_DATA_PATH", str(steam_compatdata)),
        _steam_env_assign("STEAM_COMPAT_MOUNTS", mount),
        _steam_env_assign("PRESSURE_VESSEL_FILESYSTEMS_RW", mount),
    ]
    if gamescope:
        parts.append("ENABLE_GAMESCOPE_WSI=0")
        parts.append(
            "gamescope -f -b --force-grab-cursor --force-windows-fullscreen "
            "--immediate-flips --rt --"
        )
    # No PROTON_ENABLE_WAYLAND here: Steam + winewayland often yields a black
    # window. Low-latency Wayland stays on the non-Steam Rezeptor path.
    if extra.strip():
        parts.append(extra.strip())
    parts.append("%command%")
    return " ".join(parts)


def find_halo_shortcut(data: dict) -> tuple[str | None, dict | None]:
    sc = data.get("shortcuts") or {}
    for key, entry in sc.items():
        if isinstance(entry, dict) and entry.get("AppName") == SHORTCUT_NAME:
            return str(key), entry
    return None, None


def appid_u32_from_entry(entry: dict) -> int:
    raw = entry.get("appid", 0)
    try:
        n = int(raw)
    except (TypeError, ValueError):
        return 0
    if n < 0:
        return n + 0x100000000
    return n & 0xFFFFFFFF


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default="", help="Absolute path to HaloCampaignEvolved.exe")
    ap.add_argument("--proton-dir", default="", help="GE-Proton11-3 directory (Rezeptor tool)")
    ap.add_argument(
        "--tool-name",
        default=DEFAULT_TOOL_NAME,
        help="Steam CompatToolMapping name (e.g. GE-Proton11-3, proton-cachyos-slr)",
    )
    ap.add_argument("--compat-dir", required=True, help="Rezeptor steam-compat dir (has pfx→prefix)")
    ap.add_argument("--gamescope", action="store_true")
    ap.add_argument("--extra-launch", default="", help="Extra launch-option fragment")
    ap.add_argument("--icon", default="")
    ap.add_argument(
        "--grid-assets",
        default="",
        help="Dir with cover.png/wide.png/hero.png/logo.png for Library art",
    )
    ap.add_argument("--steam-root", default="", help="Override Steam install (tests)")
    ap.add_argument("--account-id", type=int, default=0, help="Override userdata account id")
    ap.add_argument(
        "--resync",
        action="store_true",
        help="Re-read shortcut after Steam sanitize; refresh mapping/symlink/LaunchOptions",
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="Exit 0 if Non-Steam entry/compat/options already match --exe; print APPID/BPID",
    )
    ap.add_argument(
        "--dump-ids",
        action="store_true",
        help="Print APPID/BPID if Halo Non-Steam shortcut exists for --exe (no rewrite)",
    )
    args = ap.parse_args()

    tool_name = resolve_tool_name(args.tool_name or DEFAULT_TOOL_NAME)

    compat_dir = Path(args.compat_dir).resolve()
    root = steam_root(args.steam_root or None)
    acc = int(args.account_id) if args.account_id else active_account_id(root)
    shortcuts_path = root / "userdata" / str(acc) / "config" / "shortcuts.vdf"
    shortcuts_path.parent.mkdir(parents=True, exist_ok=True)
    config_path = root / "config" / "config.vdf"

    eprint(f"steam root: {root}")
    eprint(f"userdata: {acc}")
    if not args.dump_ids:
        eprint(f"compat tool: {tool_name}")

    if args.dump_ids:
        if not args.exe:
            eprint("error: --dump-ids needs --exe")
            return 1
        exe_path = Path(args.exe).resolve()
        exe_field = f'"{exe_path}"'
        data = load_shortcuts(shortcuts_path)
        _key, entry = find_halo_shortcut(data)
        if not entry:
            eprint("dump-ids: missing shortcut")
            return 1
        if str(entry.get("Exe") or "") != exe_field:
            eprint("dump-ids: Exe mismatch")
            return 1
        appid_u = appid_u32_from_entry(entry)
        if not appid_u:
            eprint("dump-ids: no appid")
            return 1
        bpid = shortcut_bpid(appid_u)
        print(f"APPID={appid_u}")
        print(f"BPID={bpid}")
        print(f"NAME={SHORTCUT_NAME}")
        return 0

    if args.check:
        if not args.exe:
            eprint("error: --check needs --exe")
            return 1
        exe_path = Path(args.exe).resolve()
        exe_field = f'"{exe_path}"'
        data = load_shortcuts(shortcuts_path)
        _key, entry = find_halo_shortcut(data)
        if not entry:
            eprint("check: missing shortcut")
            return 1
        if str(entry.get("Exe") or "") != exe_field:
            eprint("check: Exe mismatch")
            return 1
        appid_u = appid_u32_from_entry(entry)
        if not appid_u:
            eprint("check: no appid")
            return 1
        opts = str(entry.get("LaunchOptions") or "")
        # Unquoted WINEDLLOVERRIDES=…;… is split by /bin/sh → "command not found".
        if 'WINEDLLOVERRIDES="' not in opts:
            eprint("check: WINEDLLOVERRIDES must be quoted (contains ';')")
            return 1
        if "PROTON_ENABLE_WAYLAND=" in opts:
            eprint("check: LaunchOptions still enable Wayland (black window under Steam)")
            return 1
        if "VKD3D_SWAPCHAIN_LATENCY_FRAMES=1" in opts:
            eprint("check: LaunchOptions still use VKD3D latency 1 (black window under Steam)")
            return 1
        if "VKD3D_SWAPCHAIN_LATENCY_FRAMES=2" not in opts:
            eprint("check: LaunchOptions missing VKD3D_SWAPCHAIN_LATENCY_FRAMES=2")
            return 1
        if "SteamDeck=1" not in opts:
            eprint("check: LaunchOptions missing SteamDeck=1")
            return 1
        if "PROTON_USE_XALIA=0" not in opts:
            eprint("check: LaunchOptions missing PROTON_USE_XALIA=0")
            return 1
        icon = str(entry.get("icon") or "").strip().strip('"')
        if not icon or not Path(icon).is_file():
            eprint("check: shortcut icon missing or not a file")
            return 1
        grid_dir = shortcuts_path.parent / "grid"
        if not grid_artwork_ok(grid_dir, appid_u):
            eprint("check: Library grid art missing (cover)")
            return 1
        start = str(entry.get("StartDir") or "")
        if "/Binaries/Win64" in start:
            eprint("check: StartDir is Win64 — want Meteorite/ project root")
            return 1
        for needle in (
            "WINEDLLOVERRIDES=",
            "PROTON_USE_WINED3D=0",
            "PROTON_USE_XALIA=0",
            "STEAM_COMPAT_MOUNTS=",
            str(root / "steamapps" / "compatdata" / str(appid_u)),
            "%command%",
        ):
            if needle not in opts:
                eprint(f"check: LaunchOptions missing {needle}")
                return 1
        try:
            cfg = vdf.loads(config_path.read_text(encoding="utf-8", errors="replace"))
            mapping = (
                cfg.get("InstallConfigStore", {})
                .get("Software", {})
                .get("Valve", {})
                .get("Steam", {})
                .get("CompatToolMapping", {})
            )
            tool = (mapping.get(str(appid_u)) or {}).get("name") if mapping else None
        except Exception:
            tool = None
        want_default = _is_steam_default(tool_name)
        if want_default:
            if tool:
                eprint(
                    f"check: CompatToolMapping={tool!r} but want Steam default (Force off)"
                )
                return 1
        elif tool != tool_name:
            eprint(f"check: CompatToolMapping={tool!r} want {tool_name}")
            return 1
        link = root / "steamapps" / "compatdata" / str(appid_u)
        if not link.exists():
            eprint("check: compatdata link missing")
            return 1
        bpid = shortcut_bpid(appid_u)
        print(f"APPID={appid_u}")
        print(f"BPID={bpid}")
        print(f"NAME={SHORTCUT_NAME}")
        print(f"TOOL={tool_name}")
        return 0

    if args.resync:
        data = load_shortcuts(shortcuts_path)
        _key, entry = find_halo_shortcut(data)
        if not entry:
            eprint("error: Halo Non-Steam shortcut missing — run without --resync first")
            return 1
        appid_u = appid_u32_from_entry(entry)
        if not appid_u:
            eprint("error: shortcut has no appid")
            return 1
        appid_i = to_i32(appid_u)
        exe_field = str(entry.get("Exe") or "")
        start_field = str(entry.get("StartDir") or "")
        # Prefer path from shortcut Exe (quoted)
        exe_path = Path(exe_field.strip('"'))
        if args.proton_dir and tool_name == DEFAULT_TOOL_NAME:
            ensure_ge_proton_tool(root, Path(args.proton_dir).resolve(), tool_name)
        ensure_compatdata_link(root, appid_u, compat_dir)
        steam_cd = root / "steamapps" / "compatdata" / str(appid_u)
        launch = build_launch_options(
            steam_compatdata=steam_cd,
            exe_path=exe_path,
            gamescope=args.gamescope,
            extra=args.extra_launch,
        )
        icon_path = stage_shortcut_icon(
            compat_dir, args.icon or str(entry.get("icon") or "")
        )
        backup(shortcuts_path)
        data = upsert_shortcut(
            data,
            name=SHORTCUT_NAME,
            exe_field=exe_field,
            start_dir_field=start_field,
            launch_options=launch,
            appid_i32=appid_i,
            icon=icon_path or str(entry.get("icon") or args.icon or ""),
        )
        tmp = shortcuts_path.with_suffix(".vdf.rezeptor_tmp")
        tmp.write_bytes(vdf.binary_dumps(data))
        tmp.replace(shortcuts_path)
        apply_compat_tool(config_path, appid_u, tool_name)
        stage_grid_artwork(
            shortcuts_path.parent / "grid",
            appid_u,
            assets_dir=args.grid_assets or "",
        )
        bpid = shortcut_bpid(appid_u)
        eprint(f"resync appid={appid_u} bpid={bpid}")
        print(f"APPID={appid_u}")
        print(f"BPID={bpid}")
        print(f"NAME={SHORTCUT_NAME}")
        print(f"TOOL={tool_name}")
        return 0

    if not args.exe:
        eprint("error: --exe required unless --resync/--check")
        return 1
    want_default = _is_steam_default(tool_name)
    if tool_name == DEFAULT_TOOL_NAME and not args.proton_dir:
        eprint("error: --proton-dir required for Rezeptor GE tool")
        return 1
    if want_default:
        eprint("compat tool: Steam global Steam Play (Force off)")

    exe_path = Path(args.exe).resolve()
    if not exe_path.is_file():
        eprint(f"error: exe not found: {exe_path}")
        return 1
    # UE content is resolved from the project root (Meteorite/), not Win64/.
    start_dir = exe_path.parent
    for _ in range(3):
        if (start_dir / "Content").is_dir() or (start_dir / "Meteorite").is_dir():
            break
        if start_dir.parent == start_dir:
            break
        start_dir = start_dir.parent
    if (start_dir / "Meteorite" / "Content").is_dir():
        start_dir = start_dir / "Meteorite"

    # Steam stores Exe/StartDir with surrounding quotes.
    exe_field = f'"{exe_path}"'
    start_field = f'"{start_dir}/"'
    appid_u = shortcut_appid_u32(exe_field, SHORTCUT_NAME)
    appid_i = to_i32(appid_u)

    eprint(f"appid: {appid_u} (i32 {appid_i})")

    if args.proton_dir and tool_name == DEFAULT_TOOL_NAME:
        ensure_ge_proton_tool(root, Path(args.proton_dir).resolve(), tool_name)
    ensure_compatdata_link(root, appid_u, compat_dir)
    steam_cd = root / "steamapps" / "compatdata" / str(appid_u)

    launch = build_launch_options(
        steam_compatdata=steam_cd,
        exe_path=exe_path,
        gamescope=args.gamescope,
        extra=args.extra_launch,
    )
    eprint(f"LaunchOptions: {launch}")

    icon_path = stage_shortcut_icon(compat_dir, args.icon or "")
    if icon_path:
        eprint(f"shortcut icon: {icon_path}")

    backup(shortcuts_path)
    data = load_shortcuts(shortcuts_path)
    data = upsert_shortcut(
        data,
        name=SHORTCUT_NAME,
        exe_field=exe_field,
        start_dir_field=start_field,
        launch_options=launch,
        appid_i32=appid_i,
        icon=icon_path,
    )
    blob = vdf.binary_dumps(data)
    tmp = shortcuts_path.with_suffix(".vdf.rezeptor_tmp")
    tmp.write_bytes(blob)
    tmp.replace(shortcuts_path)
    eprint(f"shortcuts written: {shortcuts_path}")

    apply_compat_tool(config_path, appid_u, tool_name)
    stage_grid_artwork(
        shortcuts_path.parent / "grid",
        appid_u,
        assets_dir=args.grid_assets or "",
    )

    bpid = shortcut_bpid(appid_u)
    print(f"APPID={appid_u}")
    print(f"BPID={bpid}")
    print(f"NAME={SHORTCUT_NAME}")
    print(f"TOOL={tool_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
