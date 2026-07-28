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


if __name__ == "__main__":
    test_packages_qt_xcb_cursor_per_family()
    test_install_command_includes_qt_when_missing()
    test_zypper_install_argv()
    test_scan_includes_qt_xcb_cursor()
    print("OK")
