"""Steam medicine Proton choices — three slots, distro-agnostic discovery.

1. steam_default — Steam global Steam Play (Force tool OFF)
2. system        — best Proton from distro/host compatibilitytools.d
3. rezeptor      — GE-Proton11-3 (same stack as without Steam medicine)
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from steam_paths import steam_roots

# Internal id → clear CompatToolMapping (Steam uses global Steam Play default).
STEAM_DEFAULT_TOOL = "steam_default"

# Default / recipe-tested Proton for Halo CE (DXCore path).
REZEPTOR_GE_TOOL = "GE-Proton11-3"

# Valve runtimes / Proton names that are NOT "distro system Proton".
_SKIP_TOOL_NAMES = frozenset(
    {
        STEAM_DEFAULT_TOOL,
        REZEPTOR_GE_TOOL,
        "proton_experimental",
        "proton_hotfix",
        "proton_next",
        "proton_next_beta",
        "LegacyRuntime",
        "SteamLinuxRuntime",
        "SteamLinuxRuntime_soldier",
        "SteamLinuxRuntime_sniper",
        "SteamLinuxRuntime_4",
    }
)

# Prefer these when several system tools exist (distro-packaged forks).
# Do NOT use bare "ge-proton" — it matches GloriousEggroll "GE-Proton10-34".
_DISTRO_HINTS = (
    "cachyos",
    "nobara",
    "bazzite",
    "garuda",
    "chimera",
    "vaporeon",
    "protonplus",
    "proton-plus",
    "proton-cachy",
    "wine-proton",
)

_DISPLAY_NAME_RE = re.compile(
    r'"display_name"\s+"([^"]+)"', re.IGNORECASE | re.MULTILINE
)
_TOOL_KEY_RE = re.compile(
    r'"compat_tools"\s*\{[^}]*?"([A-Za-z0-9._+-]+)"\s*\{',
    re.IGNORECASE | re.DOTALL,
)
_FROM_WINDOWS_RE = re.compile(
    r'"from_oslist"\s+"([^"]*)"', re.IGNORECASE | re.MULTILINE
)


@dataclass(frozen=True)
class SteamProtonChoice:
    """One selectable Steam CompatToolMapping name (or steam_default)."""

    tool: str
    label_de: str
    label_en: str
    kind: str  # steam_default | system | rezeptor


def _compat_tool_dirs() -> list[Path]:
    """All places Steam / distros drop custom compat tools."""
    home = Path.home()
    roots: list[Path] = []
    for r in steam_roots():
        roots.append(r / "compatibilitytools.d")
    roots.extend(
        [
            home / ".steam" / "root" / "compatibilitytools.d",
            home / ".steam" / "steam" / "compatibilitytools.d",
            home / ".var" / "app" / "com.valvesoftware.Steam" / "data" / "Steam" / "compatibilitytools.d",
            home / "snap" / "steam" / "common" / ".steam" / "steam" / "compatibilitytools.d",
            Path("/usr/share/steam/compatibilitytools.d"),
            Path("/usr/lib/steam/compatibilitytools.d"),
            # Some distros (e.g. older layouts)
            Path("/usr/share/proton"),
        ]
    )
    out: list[Path] = []
    seen: set[str] = set()
    for d in roots:
        try:
            key = str(d.resolve()) if d.exists() else str(d)
        except OSError:
            key = str(d)
        if key in seen:
            continue
        seen.add(key)
        out.append(d)
    return out


def _is_system_packaged_dir(base: Path) -> bool:
    s = str(base)
    return s.startswith("/usr/") or "/share/steam/compatibilitytools" in s


def _parse_tool_vdf(vdf_path: Path) -> tuple[str, str, bool]:
    """Return (tool_id, display_name, from_windows)."""
    try:
        text = vdf_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return "", "", False
    display = ""
    m = _DISPLAY_NAME_RE.search(text)
    if m:
        display = m.group(1).strip()
    tool_id = ""
    m2 = _TOOL_KEY_RE.search(text)
    if m2:
        tool_id = m2.group(1).strip()
    if not tool_id:
        tool_id = vdf_path.parent.name
    from_win = True
    m3 = _FROM_WINDOWS_RE.search(text)
    if m3:
        from_win = "windows" in m3.group(1).lower()
    return tool_id, display or tool_id, from_win


def _looks_like_proton_tool(tool_dir: Path) -> bool:
    if (tool_dir / "proton").is_file():
        return True
    # Symlink to a proton tree
    if tool_dir.is_symlink():
        try:
            target = tool_dir.resolve()
        except OSError:
            return False
        return (target / "proton").is_file()
    return False


def discover_system_proton_tools() -> list[tuple[str, str, bool]]:
    """List (tool_id, display_name, is_distro_packaged) for host Proton tools."""
    found: list[tuple[str, str, bool]] = []
    seen: set[str] = set()
    for base in _compat_tool_dirs():
        if not base.is_dir():
            continue
        packaged = _is_system_packaged_dir(base)
        try:
            children = list(base.iterdir())
        except OSError:
            continue
        for child in children:
            vdf = child / "compatibilitytool.vdf"
            if not vdf.is_file():
                continue
            if not _looks_like_proton_tool(child):
                continue
            tool_id, display, from_win = _parse_tool_vdf(vdf)
            if not tool_id or not from_win:
                continue
            if tool_id in _SKIP_TOOL_NAMES:
                continue
            # Skip Rezeptor's GE tree / plain GE-Proton* we manage as slot 3
            # unless it is clearly a distro fork (cachyos etc.).
            low = f"{tool_id} {display}".lower()
            if tool_id.startswith("GE-Proton") and not any(
                h in low for h in _DISTRO_HINTS
            ):
                # User-installed GE via ProtonUp is not "distro system" —
                # still allow if under /usr (packaged).
                if not packaged:
                    continue
            if tool_id in seen:
                continue
            seen.add(tool_id)
            found.append((tool_id, display, packaged))
    return found


def _rank_system_tool(item: tuple[str, str, bool]) -> tuple:
    tool_id, display, packaged = item
    low = f"{tool_id} {display}".lower()
    hint_rank = 99
    for i, h in enumerate(_DISTRO_HINTS):
        if h in low:
            hint_rank = i
            break
    # Prefer SLR-labelled forks, then packaged under /usr
    slr = 0 if "steam linux runtime" in low or low.endswith("-slr") or "-slr" in low else 1
    pkg = 0 if packaged else 1
    # Prefer newer-looking version tokens (lexicographic on id as weak signal)
    return (hint_rank, slr, pkg, -len(tool_id), tool_id.lower())


def best_system_proton() -> tuple[str, str] | None:
    """Best distro/host Proton for slot 2, or None if nothing found."""
    tools = discover_system_proton_tools()
    if not tools:
        return None
    tools.sort(key=_rank_system_tool)
    tool_id, display, _pkg = tools[0]
    return tool_id, display


def curated_steam_proton_choices() -> list[SteamProtonChoice]:
    """Exactly the three product slots (system omitted if none installed)."""
    choices: list[SteamProtonChoice] = [
        SteamProtonChoice(
            tool=STEAM_DEFAULT_TOOL,
            label_de="Steam-Standard (global Steam Play, Force aus)",
            label_en="Steam default (global Steam Play, Force off)",
            kind="steam_default",
        )
    ]
    system = best_system_proton()
    if system is not None:
        tool_id, display = system
        choices.append(
            SteamProtonChoice(
                tool=tool_id,
                label_de=f"System-Proton — {display}",
                label_en=f"System Proton — {display}",
                kind="system",
            )
        )
    choices.append(
        SteamProtonChoice(
            tool=REZEPTOR_GE_TOOL,
            label_de="Rezeptor Proton (GE-Proton11-3, getestet)",
            label_en="Rezeptor Proton (GE-Proton11-3, tested)",
            kind="rezeptor",
        )
    )
    return choices


def is_steam_default_tool(tool: str) -> bool:
    t = (tool or "").strip().lower()
    return t in (
        STEAM_DEFAULT_TOOL,
        "steam-default",
        "steam_play_default",
        "global",
        "none",
        "",
    )


def label_for_tool(tool: str, locale: str) -> str:
    code = (locale or "de").split("-", 1)[0].lower()
    for c in curated_steam_proton_choices():
        if c.tool == tool:
            return c.label_de if code == "de" else c.label_en
    return tool


def is_steam_medicine_option(opt) -> bool:  # noqa: ANN001
    if getattr(opt, "type", "bool") != "bool":
        return False
    oid = (getattr(opt, "id", "") or "").strip().lower()
    env = (getattr(opt, "env", "") or "").strip().upper()
    if oid == "launch_via_steam":
        return True
    return env.endswith("_LAUNCH_VIA_STEAM") or env == "LAUNCH_VIA_STEAM"


def is_steam_proton_option(opt) -> bool:  # noqa: ANN001
    if getattr(opt, "type", "") != "choice":
        return False
    oid = (getattr(opt, "id", "") or "").strip().lower()
    env = (getattr(opt, "env", "") or "").strip().upper()
    if oid in ("steam_proton", "steam_compat_tool"):
        return True
    return env.endswith("_STEAM_PROTON") or env == "STEAM_COMPAT_TOOL"
