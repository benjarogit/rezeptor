#!/usr/bin/env python3
"""host_deps: Qt xcb-cursor mapping covers major package families."""

from __future__ import annotations

import sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "launcher"))

import host_deps  # noqa: E402


def test_packages_qt_xcb_cursor_per_family() -> None:
    assert host_deps._packages_for("apt", "qt_xcb_cursor") == ("libxcb-cursor0",)
    assert host_deps._packages_for("pacman", "qt_xcb_cursor") == ("libxcb-cursor",)
    assert host_deps._packages_for("dnf", "qt_xcb_cursor") == ("libxcb-cursor",)
    assert host_deps._packages_for("zypper", "qt_xcb_cursor") == ("libxcb-cursor0",)


def test_packages_wine_i386_per_family() -> None:
    assert host_deps._packages_for("pacman", "wine_i386") == ("lib32-glibc",)
    assert host_deps._packages_for("apt", "wine_i386") == ("libc6-i386",)
    assert host_deps._packages_for("dnf", "wine_i386") == ("glibc.i686",)
    assert host_deps._packages_for("zypper", "wine_i386") == ("glibc-32bit",)


def test_install_command_includes_qt_when_missing() -> None:
    missing = [
        host_deps.HostDep(
            id="qt_xcb_cursor",
            required=True,
            present=False,
            packages=("libxcb-cursor0",),
        )
    ]
    with mock.patch.object(host_deps, "detect_family", return_value="apt"):
        cmd = host_deps.install_command(missing)
    assert "libxcb-cursor0" in cmd
    assert "apt-get" in cmd


def test_zypper_install_argv() -> None:
    missing = [
        host_deps.HostDep(
            id="qt_xcb_cursor",
            required=True,
            present=False,
            packages=("libxcb-cursor0",),
        )
    ]
    with mock.patch.object(host_deps, "detect_family", return_value="zypper"):
        argv = host_deps.install_argv(missing)
    assert argv is not None
    assert argv[0] == "zypper"
    assert "libxcb-cursor0" in argv


def test_scan_includes_qt_xcb_cursor() -> None:
    deps = host_deps.scan_host_deps()
    ids = [d.id for d in deps]
    assert "qt_xcb_cursor" in ids
    qt = next(d for d in deps if d.id == "qt_xcb_cursor")
    assert qt.required is True


def test_scan_includes_wine_i386_outside_flatpak() -> None:
    with mock.patch.object(host_deps, "_in_flatpak", return_value=False):
        deps = host_deps.scan_host_deps()
    ids = [d.id for d in deps]
    assert "wine_i386" in ids
    dep = next(d for d in deps if d.id == "wine_i386")
    assert dep.required is True


def test_scan_skips_wine_i386_in_flatpak() -> None:
    with mock.patch.object(host_deps, "_in_flatpak", return_value=True):
        deps = host_deps.scan_host_deps()
    assert "wine_i386" not in [d.id for d in deps]


if __name__ == "__main__":
    test_packages_qt_xcb_cursor_per_family()
    test_packages_wine_i386_per_family()
    test_install_command_includes_qt_when_missing()
    test_zypper_install_argv()
    test_scan_includes_qt_xcb_cursor()
    test_scan_includes_wine_i386_outside_flatpak()
    test_scan_skips_wine_i386_in_flatpak()
    print("OK")
