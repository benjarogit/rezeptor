#!/usr/bin/env python3
"""Unit tests: subprocess tree signal must not kill our process group."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "launcher"))

from launcher import own_process_group, signal_subprocess_tree  # noqa: E402


def test_own_process_group_rejects_shared_group() -> None:
    """Kind ohne setsid: PGID ist unsere — killpg darauf wuerde Rezeptor beenden."""
    proc = subprocess.Popen(["sleep", "30"], start_new_session=False)
    try:
        time.sleep(0.15)
        assert os.getpgid(proc.pid) == os.getpgrp()
        assert own_process_group(proc.pid) == 0
    finally:
        proc.kill()
        proc.wait(timeout=2)


def test_own_process_group_accepts_group_leader() -> None:
    """Eigene Session: PGID == PID, killpg trifft nur den Install-Baum."""
    proc = subprocess.Popen(["sleep", "30"], start_new_session=True)
    try:
        time.sleep(0.15)
        assert own_process_group(proc.pid) == proc.pid
    finally:
        proc.kill()
        proc.wait(timeout=2)


def test_signal_tree_does_not_kill_own_group() -> None:
    """Child in new session dies; this process stays alive."""
    # setsid -w: waiter in our group, bash child in new session
    proc = subprocess.Popen(
        ["setsid", "-w", "bash", "-c", "sleep 30"],
        start_new_session=False,
    )
    time.sleep(0.15)
    assert proc.poll() is None
    us = os.getpid()
    signal_subprocess_tree(proc.pid, signal.SIGTERM)
    # Wait for child tree to exit
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
        raise AssertionError("sleep child should have been signaled")
    # We are still here
    assert os.getpid() == us


def test_cancel_pending_quit_ignores_wm_armed() -> None:
    from PyQt6.QtWidgets import QApplication, QWidget

    from ui_window import ApplicationCloseGuard

    app = QApplication.instance() or QApplication([])
    main = QWidget()
    guard = ApplicationCloseGuard(main)
    guard._wm_quit_armed = True
    guard._quit_scheduled = True
    token_before = guard._quit_token
    guard.cancel_pending_quit()
    assert guard._quit_token == token_before
    assert guard._quit_scheduled is True
    guard._wm_quit_armed = False
    guard.cancel_pending_quit()
    assert guard._quit_token == token_before + 1
    assert guard._quit_scheduled is False
    main.close()
    del app


if __name__ == "__main__":
    test_own_process_group_rejects_shared_group()
    test_own_process_group_accepts_group_leader()
    test_signal_tree_does_not_kill_own_group()
    test_cancel_pending_quit_ignores_wm_armed()
    print("ok")
