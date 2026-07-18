"""Host tool checks for Rezeptor (curl/unzip/7z/…) + optional pkexec install."""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class HostDep:
    """One host dependency check."""

    id: str  # stable id: download | tar | unzip | sevenzip | winetricks
    required: bool
    present: bool
    # Human label keys resolved by UI via t(f"deps.item_{id}")
    packages: tuple[str, ...]  # distro packages to install when missing


def _which_any(*names: str) -> bool:
    return any(shutil.which(n) for n in names)


def detect_family() -> str:
    """Return pacman | apt | dnf | unknown."""
    if shutil.which("pacman"):
        return "pacman"
    if shutil.which("apt-get") or shutil.which("apt"):
        return "apt"
    if shutil.which("dnf"):
        return "dnf"
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
        },
        "apt": {
            "download": ("curl",),
            "tar": ("tar",),
            "unzip": ("unzip",),
            "sevenzip": ("p7zip-full",),
            "winetricks": ("winetricks",),
        },
        "dnf": {
            "download": ("curl",),
            "tar": ("tar",),
            "unzip": ("unzip",),
            "sevenzip": ("p7zip", "p7zip-plugins"),
            "winetricks": ("winetricks",),
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
    ]
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


def has_gaps(deps: list[HostDep] | None = None) -> bool:
    return bool(missing_deps(deps))


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
    return f"# Install manually: {joined}"


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
