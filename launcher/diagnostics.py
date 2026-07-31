"""Exit-Diagnose: warum endet Rezeptor? Signal, Exception oder Qt-Quit."""

from __future__ import annotations

import atexit
import os
import signal
import sys
import threading
import traceback
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

from app_support import LOG_ROOT

DIAG_LOG = LOG_ROOT / "rezeptor-exit-diagnostics.log"
_MAX_BYTES = 512 * 1024
_EXIT_SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


def log_line(kind: str, text: str = "") -> None:
    """Eine Zeile ins Exit-Log — darf niemals selbst werfen."""
    try:
        LOG_ROOT.mkdir(parents=True, exist_ok=True)
        if DIAG_LOG.is_file() and DIAG_LOG.stat().st_size > _MAX_BYTES:
            DIAG_LOG.unlink()
        stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        body = text.strip().replace("\n", "\n    ")
        with DIAG_LOG.open("a", encoding="utf-8") as fh:
            fh.write(f"[{stamp}] pid={os.getpid()} {kind}: {body}\n")
    except OSError:
        pass


def log_call_site(kind: str, note: str = "", *, depth: int = 6) -> None:
    """Aufrufkette mitschreiben — zeigt, welcher Pfad den Quit ausgelöst hat."""
    frames = traceback.extract_stack(limit=depth + 1)[:-1]
    chain = " <- ".join(
        f"{Path(f.filename).name}:{f.lineno} {f.name}" for f in reversed(frames)
    )
    log_line(kind, f"{note} | {chain}" if note else chain)


def log_session_start(version: str) -> None:
    args = " ".join(sys.argv[1:])
    log_line(
        "START",
        f"version={version} pgid={os.getpgrp()} ppid={os.getppid()} argv={args}",
    )


def install_exception_logging(
    on_error: Callable[[str, str], None] | None = None,
) -> None:
    """PyQt6 bricht den Prozess bei Exceptions in Slots ab — hier abfangen statt sterben."""

    def hook(exc_type, exc, tb) -> None:  # type: ignore[no-untyped-def]
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc, tb)
            return
        text = "".join(traceback.format_exception(exc_type, exc, tb))
        log_line("UNCAUGHT", text)
        print(text, file=sys.stderr)
        if on_error is None:
            return
        try:
            on_error(f"{exc_type.__name__}: {exc}", text)
        except Exception:  # noqa: BLE001 — Melder darf den Hook nicht sprengen
            log_line("UNCAUGHT", "Fehleranzeige selbst fehlgeschlagen")

    sys.excepthook = hook

    def thread_hook(args) -> None:  # type: ignore[no-untyped-def]
        if args.exc_type is SystemExit:
            return
        text = "".join(
            traceback.format_exception(
                args.exc_type, args.exc_value, args.exc_traceback
            )
        )
        log_line("UNCAUGHT-THREAD", text)
        print(text, file=sys.stderr)

    threading.excepthook = thread_hook


def install_signal_logging() -> None:
    """SIGTERM/SIGINT/SIGHUP protokollieren, dann Standardverhalten wiederherstellen."""

    def handler(sig: int, _frame) -> None:  # type: ignore[no-untyped-def]
        name = signal.Signals(sig).name
        log_line("SIGNAL", f"{name} ppid={os.getppid()} pgid={os.getpgrp()}")
        signal.signal(sig, signal.SIG_DFL)
        os.kill(os.getpid(), sig)

    for sig in _EXIT_SIGNALS:
        try:
            signal.signal(sig, handler)
        except (OSError, ValueError):
            pass


def install_exit_logging() -> None:
    atexit.register(log_line, "EXIT", "Interpreter beendet")
