"""Host tool checks for Rezeptor (curl/unzip/7z/Qt xcb/…) + optional pkexec install."""

from __future__ import annotations

import ctypes.util
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class HostDep:
    """One host dependency check."""

    id: str  # stable id: download | tar | … | qt_xcb_cursor | wine_i386
    required: bool
    present: bool
    # Human label keys resolved by UI via t(f"deps.item_{id}")
    packages: tuple[str, ...]  # distro packages to install when missing


def _which_any(*names: str) -> bool:
    return any(shutil.which(n) for n in names)


def _in_flatpak() -> bool:
    return bool(os.environ.get("FLATPAK_ID")) or Path("/.flatpak-info").is_file()


def _i386_loader_present() -> bool:
    """True if the host can exec 32-bit ELF (needed for Wine WoW64 / syswow64)."""
    for path in (
        Path("/lib/ld-linux.so.2"),
        Path("/lib32/ld-linux.so.2"),
        Path("/usr/lib32/ld-linux.so.2"),
        Path("/lib/i386-linux-gnu/ld-linux.so.2"),
        Path("/usr/lib/i386-linux-gnu/ld-linux.so.2"),
    ):
        if path.is_file():
            return True
    return False


def _i386_lib_dirs() -> list[Path]:
    """Directories where 32-bit shared libs usually live."""
    return [
        Path("/usr/lib32"),
        Path("/lib32"),
        Path("/usr/lib/i386-linux-gnu"),
        Path("/lib/i386-linux-gnu"),
        Path("/usr/lib/i686-linux-gnu"),
        Path("/lib/i686-linux-gnu"),
    ]


def _i386_soname_present(name: str) -> bool:
    """True if lib{name}.so* exists in a 32-bit library directory (issue #11)."""
    pattern = f"lib{name}.so*"
    for base in _i386_lib_dirs():
        try:
            if any(base.glob(pattern)):
                return True
        except OSError:
            continue
    return False


def recipe_needs_host_wow64(meta: dict[str, str] | None) -> bool:
    """True when install/winetricks will exercise 32-bit Wine (syswow64)."""
    if not meta:
        return False
    runtime = (meta.get("runtime") or "").strip().lower()
    if runtime in ("steam", "steam-proton"):
        return False
    if meta.get("steam_appid"):
        return False
    if runtime not in ("proton-ge", "proton", "wine", "system", ""):
        # Empty runtime still often uses Proton via defaults — treat offline installers.
        if runtime:
            return False
    install_type = (meta.get("install_type") or "").strip().lower()
    if install_type in (
        "installer_offline",
        "installer",
        "archive",
        "adobe_offline",
    ):
        return True
    tricks = meta.get("winetricks")
    if tricks:
        return True
    return False


def _soname_present(name: str) -> bool:
    """True if lib{name}.so* is loadable (ldconfig / ctypes / LD_LIBRARY_PATH)."""
    if ctypes.util.find_library(name):
        return True
    bases: list[Path] = []
    for part in (os.environ.get("LD_LIBRARY_PATH") or "").split(":"):
        if part:
            bases.append(Path(part))
    bases.extend(
        (
            Path("/usr/lib"),
            Path("/usr/lib64"),
            Path("/usr/lib/x86_64-linux-gnu"),
            Path("/lib"),
            Path("/lib64"),
            Path("/lib/x86_64-linux-gnu"),
        )
    )
    for base in bases:
        try:
            if any(base.glob(f"lib{name}.so*")):
                return True
        except OSError:
            continue
    return False


def detect_family() -> str:
    """Return pacman | apt | dnf | zypper | unknown."""
    if shutil.which("pacman"):
        return "pacman"
    if shutil.which("apt-get") or shutil.which("apt"):
        return "apt"
    if shutil.which("dnf"):
        return "dnf"
    if shutil.which("zypper"):
        return "zypper"
    return "unknown"


def is_immutable_host() -> bool:
    if Path("/run/ostree-booted").is_file() or shutil.which("rpm-ostree"):
        return True
    try:
        text = Path("/etc/os-release").read_text(encoding="utf-8")
    except OSError:
        text = ""
    lower = text.lower()
    for marker in (
        "bazzite",
        "bluefin",
        "ublue",
        "aurora",
        "silverblue",
        "kinoite",
        "sericea",
    ):
        if marker in lower:
            return True
    return False


def _packages_for(family: str, dep_id: str) -> tuple[str, ...]:
    # Maps check id → package names per family.
    table: dict[str, dict[str, tuple[str, ...]]] = {
        "pacman": {
            "download": ("curl",),
            "tar": ("tar",),
            "unzip": ("unzip",),
            "sevenzip": ("p7zip",),
            "winetricks": ("winetricks",),
            # Qt6 xcb platform (AppImage/pip PyQt6); Arch package name = libxcb-cursor
            "qt_xcb_cursor": ("libxcb-cursor",),
            # 32-bit dynamic linker for Wine syswow64 (needs [multilib] enabled)
            "wine_i386": ("lib32-glibc",),
            "wine_i386_freetype": ("lib32-freetype2",),
            "wine_i386_gcc": ("lib32-gcc-libs",),
        },
        "apt": {
            "download": ("curl",),
            "tar": ("tar",),
            "unzip": ("unzip",),
            "sevenzip": ("p7zip-full",),
            "winetricks": ("winetricks",),
            "qt_xcb_cursor": ("libxcb-cursor0",),
            "wine_i386": ("libc6-i386",),
            "wine_i386_freetype": ("libfreetype6:i386",),
            "wine_i386_gcc": ("libgcc-s1:i386",),
        },
        "dnf": {
            "download": ("curl",),
            "tar": ("tar",),
            "unzip": ("unzip",),
            "sevenzip": ("p7zip", "p7zip-plugins"),
            "winetricks": ("winetricks",),
            "qt_xcb_cursor": ("libxcb-cursor",),
            "wine_i386": ("glibc.i686",),
            "wine_i386_freetype": ("freetype.i686",),
            "wine_i386_gcc": ("libgcc.i686",),
        },
        "zypper": {
            "download": ("curl",),
            "tar": ("tar",),
            "unzip": ("unzip",),
            "sevenzip": ("p7zip",),
            "winetricks": ("winetricks",),
            "qt_xcb_cursor": ("libxcb-cursor0",),
            "wine_i386": ("glibc-32bit",),
            "wine_i386_freetype": ("libfreetype6-32bit",),
            "wine_i386_gcc": ("libgcc_s1-32bit",),
        },
    }
    fam = table.get(family) or table["pacman"]
    return fam.get(dep_id, ())


def scan_host_deps() -> list[HostDep]:
    family = detect_family()
    checks: list[tuple[str, bool, bool]] = [
        ("download", True, _which_any("curl", "wget")),
        ("tar", True, _which_any("tar")),
        ("unzip", True, _which_any("unzip")),
        ("sevenzip", False, _which_any("7z", "7za")),
        ("winetricks", False, _which_any("winetricks")),
        # Required for GUI: Qt xcb plugin loads libxcb-cursor.so.0 (often missing on minimal Ubuntu)
        ("qt_xcb_cursor", True, _soname_present("xcb-cursor")),
    ]
    # Flatpak ships its own i386 runtime; native hosts need multilib for Photoshop WoW64.
    if not _in_flatpak():
        checks.append(("wine_i386", True, _i386_loader_present()))
        # Loader alone is not enough (issue #11): IE8 / Adobe Setup need FreeType + libgcc.
        checks.append(("wine_i386_freetype", True, _i386_soname_present("freetype")))
        checks.append(("wine_i386_gcc", True, _i386_soname_present("gcc_s")))
    out: list[HostDep] = []
    for dep_id, required, present in checks:
        out.append(
            HostDep(
                id=dep_id,
                required=required,
                present=present,
                packages=_packages_for(family, dep_id),
            )
        )
    return out


def missing_deps(deps: list[HostDep] | None = None) -> list[HostDep]:
    items = deps if deps is not None else scan_host_deps()
    return [d for d in items if not d.present]


def missing_required_deps(deps: list[HostDep] | None = None) -> list[HostDep]:
    return [d for d in missing_deps(deps) if d.required]


def missing_wow64_deps(deps: list[HostDep] | None = None) -> list[HostDep]:
    """Required 32-bit Wine host gaps (loader + common Adobe/winetricks libs)."""
    wow64_ids = frozenset({"wine_i386", "wine_i386_freetype", "wine_i386_gcc"})
    return [d for d in missing_required_deps(deps) if d.id in wow64_ids]


def has_gaps(deps: list[HostDep] | None = None) -> bool:
    return bool(missing_deps(deps))


def has_required_gaps(deps: list[HostDep] | None = None) -> bool:
    return bool(missing_required_deps(deps))


def install_command(missing: list[HostDep]) -> str:
    """Shell command users can copy; also used as pkexec argv base."""
    family = detect_family()
    pkgs: list[str] = []
    seen: set[str] = set()
    for dep in missing:
        for p in dep.packages:
            if p not in seen:
                seen.add(p)
                pkgs.append(p)
    if not pkgs:
        return ""
    joined = " ".join(pkgs)
    if family == "pacman":
        return f"sudo pacman -S --needed --noconfirm {joined}"
    if family == "apt":
        return f"sudo apt-get install -y {joined}"
    if family == "dnf":
        return f"sudo dnf install -y {joined}"
    if family == "zypper":
        return f"sudo zypper --non-interactive install {joined}"
    return (
        f"# Install manually ({joined}). Examples:\n"
        f"#   Debian/Ubuntu: sudo apt install libxcb-cursor0\n"
        f"#   Arch/CachyOS:  sudo pacman -S libxcb-cursor\n"
        f"#   Fedora:        sudo dnf install libxcb-cursor\n"
        f"#   openSUSE:      sudo zypper install libxcb-cursor0"
    )


def install_argv(missing: list[HostDep]) -> list[str] | None:
    """Argv for pkexec (without sudo). None if unsupported family / nothing to install."""
    family = detect_family()
    pkgs: list[str] = []
    seen: set[str] = set()
    for dep in missing:
        for p in dep.packages:
            if p not in seen:
                seen.add(p)
                pkgs.append(p)
    if not pkgs:
        return None
    if family == "pacman":
        return ["pacman", "-S", "--needed", "--noconfirm", *pkgs]
    if family == "apt":
        return ["apt-get", "install", "-y", *pkgs]
    if family == "dnf":
        return ["dnf", "install", "-y", *pkgs]
    if family == "zypper":
        return ["zypper", "--non-interactive", "install", *pkgs]
    return None


def run_install(missing: list[HostDep], *, timeout: int = 600) -> tuple[bool, str]:
    """
    Try pkexec package install. Returns (ok, message).
    Does not attempt install on immutable hosts.
    """
    if is_immutable_host():
        return False, "immutable"
    argv = install_argv(missing)
    if not argv:
        return False, "unsupported"
    pkexec = shutil.which("pkexec")
    if not pkexec:
        return False, "no_pkexec"
    try:
        proc = subprocess.run(
            [pkexec, *argv],
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "LC_ALL": "C"},
        )
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except OSError as exc:
        return False, str(exc)
    if proc.returncode == 0:
        return True, "ok"
    err = (proc.stderr or proc.stdout or "").strip()
    return False, err or f"exit {proc.returncode}"
