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


def test_packages_wine_i386_freetype_gcc_per_family() -> None:
    assert host_deps._packages_for("pacman", "wine_i386_freetype") == ("lib32-freetype2",)
    assert host_deps._packages_for("pacman", "wine_i386_gcc") == ("lib32-gcc-libs",)
    assert host_deps._packages_for("apt", "wine_i386_freetype") == ("libfreetype6:i386",)
    assert host_deps._packages_for("apt", "wine_i386_gcc") == ("libgcc-s1:i386",)
    assert host_deps._packages_for("dnf", "wine_i386_freetype") == ("freetype.i686",)
    assert host_deps._packages_for("dnf", "wine_i386_gcc") == ("libgcc.i686",)


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
    assert "wine_i386_freetype" in ids
    assert "wine_i386_gcc" in ids
    for dep_id in ("wine_i386", "wine_i386_freetype", "wine_i386_gcc"):
        dep = next(d for d in deps if d.id == dep_id)
        assert dep.required is True


def test_scan_skips_wine_i386_in_flatpak() -> None:
    with mock.patch.object(host_deps, "_in_flatpak", return_value=True):
        deps = host_deps.scan_host_deps()
    ids = [d.id for d in deps]
    assert "wine_i386" not in ids
    assert "wine_i386_freetype" not in ids
    assert "wine_i386_gcc" not in ids


def test_recipe_needs_host_wow64() -> None:
    assert host_deps.recipe_needs_host_wow64(
        {"runtime": "proton-ge", "install_type": "installer_offline"}
    )
    assert host_deps.recipe_needs_host_wow64(
        {"runtime": "proton-ge", "winetricks": "corefonts"}
    )
    assert not host_deps.recipe_needs_host_wow64(
        {"runtime": "steam", "install_type": "installer_offline"}
    )
    assert not host_deps.recipe_needs_host_wow64(
        {"runtime": "proton-ge", "install_type": "portable_launch"}
    )


def test_missing_wow64_deps_filters() -> None:
    deps = [
        host_deps.HostDep("download", True, True, ()),
        host_deps.HostDep("wine_i386", True, False, ("lib32-glibc",)),
        host_deps.HostDep("wine_i386_freetype", True, False, ("lib32-freetype2",)),
        host_deps.HostDep("sevenzip", False, False, ("p7zip",)),
    ]
    wow = host_deps.missing_wow64_deps(deps)
    assert [d.id for d in wow] == ["wine_i386", "wine_i386_freetype"]


if __name__ == "__main__":
    test_packages_qt_xcb_cursor_per_family()
    test_packages_wine_i386_per_family()
    test_packages_wine_i386_freetype_gcc_per_family()
    test_install_command_includes_qt_when_missing()
    test_zypper_install_argv()
    test_scan_includes_qt_xcb_cursor()
    test_scan_includes_wine_i386_outside_flatpak()
    test_scan_skips_wine_i386_in_flatpak()
    test_recipe_needs_host_wow64()
    test_missing_wow64_deps_filters()
    print("OK")
