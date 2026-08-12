"""Recipe process / install orchestration (extracted from RezeptorWindow)."""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING, Any

from PyQt6.QtCore import QProcess, QProcessEnvironment, QTimer
from PyQt6.QtWidgets import QApplication, QDialog, QMessageBox

from activity_history import append_activity, is_tracked_op
from diagnostics import log_call_site, log_line
from i18n import t
from ui_dialogs import ask_yes_no
from log_context import E_LAUNCH_NO_PROCESS, E_SCRIPT_FAILED, LogEvent
from recipe_discovery import RecipeState
from settings import (
    clear_recipe_install_env,
    has_recipe_install_source,
    load_recipe_install_env,
    prepend_archive_password,
    save_settings,
)
from ui_archive_passwords import ensure_archive_passwords
from ui_source import (
    UpdateSourceDialog,
    attach_archive_password_files,
    needs_source_dialog,
    pick_directory,
    recipe_supports_update,
)
from ui_window import apply_tool_window

if TYPE_CHECKING:
    from PyQt6.QtWidgets import QMainWindow


class RecipeProcessOps:
    """Host-bound helpers: state and widgets live on the window (`_w`)."""

    def __init__(self, window: "QMainWindow") -> None:
        self._w = window
        # Launcher module globals (ROOT, InfoConfirmDialog, …) — avoid import cycles.
        self._L: Any = sys.modules[type(window).__module__]

    def _busy_belongs_to_selected(self) -> bool:
        if not self._w._busy or not self._w._selected:
            return False
        if not self._w._busy_rid:
            return False
        return self._w._selected.rid == self._w._busy_rid

    def _busy_recipe_label(self) -> str:
        rid = self._w._busy_rid
        if not rid:
            return "Rezeptor"
        for info in self._w.recipes:
            if info.rid == rid:
                return (
                    (info.meta.get("notify_title") or "").strip()
                    or (info.meta.get("name") or "").strip()
                    or rid
                )
        return rid

    def _set_busy(self, busy: bool, *, rid: str | None = None) -> None:
        self._w._busy = busy
        if busy:
            if rid is not None:
                self._w._busy_rid = rid
            elif self._w._selected is not None:
                self._w._busy_rid = self._w._selected.rid
            else:
                self._w._busy_rid = ""
            self._w.progress.setVisible(True)
            if hasattr(self._w, "progress_pct_label"):
                self._w.progress_pct_label.setVisible(True)
            self._w._progress_changed_at = time.monotonic()
            if hasattr(self._w, "progress_busy"):
                self._w.progress_busy.start()
            if not self._w._progress_stall_timer.isActive():
                self._w._progress_stall_timer.start()
            if self._busy_belongs_to_selected():
                self._w.status_detail_label.setText(t("status.busy"))
            elif self._w._selected is not None:
                self._w.status_detail_label.setText(
                    t("status.busy_other", name=self._busy_recipe_label())
                )
            else:
                self._w.status_detail_label.setText(t("status.busy"))
            self._w.status_detail_label.setVisible(True)
            self._w._update_progress_chip()
            for b in (
                self._w.primary_btn,
                self._w.more_btn,
                getattr(self._w, "medizin_btn", None),
            ):
                if b is not None:
                    b.setEnabled(False)
            self._w.action_refresh.setEnabled(False)
            self._sync_cancel_install_btn()
            self._w._sync_sidebar_busy_progress()
            return
        self._w._busy_rid = ""
        self._w._progress_stall_timer.stop()
        if hasattr(self._w, "progress_busy"):
            self._w.progress_busy.stop()
        self._w.progress.setRange(0, 100)
        self._w.progress.setValue(100)
        if hasattr(self._w, "progress_pct_label"):
            self._w.progress_pct_label.setText("100%")
            self._w.progress_pct_label.setVisible(True)
        self._w._update_progress_chip()
        self._w._set_step_text(t("status.done"))
        self._w.action_refresh.setEnabled(True)
        # busy=True deaktiviert Mehr — hier wieder an (CTA folgt über _select_recipe_index).
        if hasattr(self._w, "more_btn"):
            self._w.more_btn.setEnabled(True)
        self._w._sync_medizin_button()
        self._sync_cancel_install_btn()
        self._w._sync_sidebar_busy_progress()
        if self._w._selected:
            self._w._select_recipe_index(self._w._selected_index)

    def _sync_cancel_install_btn(self) -> None:
        btn = getattr(self._w, "cancel_install_btn", None)
        if btn is None:
            return
        show = bool(
            self._w._busy
            and self._busy_belongs_to_selected()
            and self._w._current_op in ("install", "reinstall")
            and not self._w._cancel_requested
        )
        btn.setVisible(show)
        btn.setEnabled(show)

    def _subprocess_running(self) -> bool:
        proc = self._w._process
        return (
            proc is not None
            and proc.state() != QProcess.ProcessState.NotRunning
        )

    def _reject_if_subprocess_busy(self) -> bool:
        """Return True when a QProcess op is already running (caller should abort)."""
        if self._subprocess_running():
            QMessageBox.warning(self._w, t("dialog.running"), t("dialog.busy_warn"))
            return True
        return False

    def _finish_archive_password_files(
        self, extra: dict[str, str] | None, *, success: bool
    ) -> None:
        """Learn working archive password (JDownloader-style) and scrub temp files."""
        if not extra:
            return
        used = (extra.get("RECIPE_ARCHIVE_PASSWORD_USED_FILE") or "").strip()
        pw_list = (extra.get("RECIPE_ARCHIVE_PASSWORD_FILE") or "").strip()
        if success and used:
            try:
                used_path = Path(used)
                if used_path.is_file():
                    pw = used_path.read_text(encoding="utf-8")
                    if prepend_archive_password(self._w._settings, pw):
                        save_settings(self._w._settings)
            except OSError:
                pass
        for path in (used, pw_list):
            if not path:
                continue
            try:
                Path(path).unlink(missing_ok=True)
            except OSError:
                pass

    def _run_async(
        self,
        script: Path,
        extra: dict[str, str] | None = None,
        done_label: str = "",
        dialog: bool = True,
        on_success: Callable[[], None] | None = None,
        *,
        op: str = "",
        recipe_dir: Path | None = None,
        script_args: list[str] | None = None,
    ) -> None:
        if self._reject_if_subprocess_busy():
            return
        if not done_label:
            done_label = t("action.done")
        env = QProcessEnvironment.systemEnvironment()
        for k, v in self._w._base_env().items():
            env.insert(k, v)
        if extra:
            for k, v in extra.items():
                env.insert(k, v)

        self._w.raw_log.clear()
        self._w._clear_activity_list()
        self._w._raw_log_buffer.clear()
        self._w._last_activity_key = None
        self._w._last_error_log = ""
        self._w._last_recipe_log = ""
        self._w._error_log_tail_mode = False
        self._w._post_config_dir = None
        self._w._progress_pct = 0
        self._w._progress_anchor = 0
        self._w._progress_pulse = 0
        self._w._progress_got_tick = False
        self._w._progress_changed_at = time.monotonic()
        self._w.progress.setValue(0)
        self._w.progress.setRange(0, 100)
        self._w.progress_pct_label.setText("0%")
        self._w.progress_pct_label.setVisible(True)
        self._w.progress_busy.start()
        self._w.progress.setVisible(True)
        self._w._switch_to_progress_tab()
        self._w._set_step_text(t("status.op_starting"))
        self._w.status_detail_label.setText(t("status.busy"))
        self._w._activity("step", f"{script.name} (Session {self._w.session_id[:8]})")
        self._w._cancel_requested = False
        self._w._current_op = op or script.stem
        self._w._install_recipe_dir = (
            recipe_dir if self._w._current_op in ("install", "reinstall") else None
        )
        busy_rid = self._w._selected.rid if self._w._selected else ""
        self._set_busy(True, rid=busy_rid)

        proc = QProcess(self._w)
        self._w._process = proc
        proc.setProcessEnvironment(env)
        proc.setWorkingDirectory(str(self._L.ROOT))
        bash_args = [str(script), *(script_args or [])]
        # Neue Session → Cancel kann die Prozessgruppe inkl. Wine-Kinder killen.
        if shutil.which("setsid"):
            proc.setProgram("setsid")
            proc.setArguments(["bash", *bash_args])
        else:
            proc.setProgram("bash")
            proc.setArguments(bash_args)
        def on_started() -> None:
            pid = int(proc.processId())
            self._w._install_pgid = self._L.own_process_group(pid)
            log_line(
                "PROC-START",
                f"{script.name} pid={pid} pgid={self._w._install_pgid} own={os.getpgrp()}",
            )

        proc.started.connect(on_started)
        proc.readyReadStandardOutput.connect(
            lambda: self._w._feed_line(bytes(proc.readAllStandardOutput()).decode("utf-8", errors="replace"))
        )
        proc.readyReadStandardError.connect(
            lambda: self._w._feed_line(bytes(proc.readAllStandardError()).decode("utf-8", errors="replace"))
        )

        def done(code: int, _s: QProcess.ExitStatus) -> None:
            if self._w._process is not proc:
                return
            cancelled = self._w._cancel_requested
            op_kind = self._w._current_op
            busy_rid = self._w._busy_rid
            install_dir = self._w._install_recipe_dir
            log_line("PROC-DONE", f"{script.name} code={code} cancelled={cancelled}")
            self._w._install_pgid = 0
            self._w._current_op = ""
            self._w._install_recipe_dir = None
            self._w._cancel_requested = False
            self._set_busy(False)
            self._w.populate_log_files()
            self._finish_archive_password_files(
                extra, success=code == 0 and not cancelled
            )
            if cancelled and op_kind in ("install", "reinstall"):
                self._w._activity("warn", t("status.install_cancelled"))
                self._rollback_cancelled_install(install_dir)
                self._w.refresh_statuses()
                if self._w._process is proc:
                    self._w._process = None
                return
            self._record_home_activity(op_kind, busy_rid, ok=code == 0)
            if code == 0:
                self._w._activity(
                    "ok",
                    t("status.exit_code", label=done_label, code=code),
                )
                if op_kind == "repair" and busy_rid:
                    self._w._clear_pending_repair(busy_rid)
            else:
                ev = LogEvent(
                    level="error",
                    code=E_SCRIPT_FAILED,
                    message_key="error.E_SCRIPT_FAILED",
                    extras={"label": done_label, "code": code},
                    session_id=self._w.session_id,
                    recipe_id=(self._w._selected.rid if self._w._selected else ""),
                )
                self._w._activity("error", ev.display_text())
            self._w.refresh_statuses()
            if code != 0 and dialog:
                self._w._show_failure(done_label, code)
            elif code == 0 and on_success is not None:
                on_success()
            elif code == 0 and dialog:
                QMessageBox.information(
                    self._w,
                    t("status.done"),
                    t("status.done_body", label=done_label),
                )
            if code == 0 and op_kind in ("install", "reinstall"):
                self._w._maybe_offer_post_config()
            if self._w._process is proc:
                self._w._process = None

        def on_install_error(err: QProcess.ProcessError) -> None:
            # PyQt6 ProcessError is not always int()-able; use .value when present.
            err_code = int(getattr(err, "value", err))
            ev = LogEvent(
                level="error",
                code=E_SCRIPT_FAILED,
                message_key="error.E_SCRIPT_FAILED",
                detail=f"QProcess error: {err}",
                extras={"label": done_label, "code": err_code},
                session_id=self._w.session_id,
                recipe_id=(self._w._selected.rid if self._w._selected else ""),
            )
            self._w._activity("error", ev.display_text())

        proc.errorOccurred.connect(on_install_error)
        proc.finished.connect(done)
        proc.start()

    def _cancel_current_install(self) -> None:
        if not self._w._busy or self._w._current_op not in ("install", "reinstall"):
            return
        if self._w._cancel_requested:
            return
        log_call_site("CANCEL", f"op={self._w._current_op} pgid={self._w._install_pgid}")
        self._w._cancel_requested = True
        self._sync_cancel_install_btn()
        self._w._activity("warn", t("status.install_cancelled"))
        self._w._set_step_text(t("status.install_cancelled"))
        proc = self._w._process
        if proc is None or proc.state() == QProcess.ProcessState.NotRunning:
            return
        pid = int(proc.processId())
        self._L._signal_qprocess_tree(proc, signal.SIGTERM)
        if pid > 0:
            QTimer.singleShot(2500, lambda p=proc, i=pid: self._force_kill_install(p, i))

    def _force_kill_install(self, proc: QProcess, pid: int) -> None:
        if proc.state() == QProcess.ProcessState.NotRunning:
            return
        self._L.signal_subprocess_tree(pid, signal.SIGKILL)
        if proc.state() != QProcess.ProcessState.NotRunning:
            proc.kill()

    def _rollback_cancelled_install(self, recipe_dir: Path | None) -> None:
        """Nach Abbruch: uninstall.sh / Purge — Portable außerhalb DATA_ROOT bleibt."""
        if recipe_dir is None or not recipe_dir.is_dir():
            QMessageBox.information(
                self._w, t("status.done"), t("status.install_cancelled")
            )
            return
        uninstall = recipe_dir / "uninstall.sh"
        ok = False
        if uninstall.is_file():
            env = {**os.environ, **self._w._base_env()}
            self._w._set_step_text(t("status.install_rollback_running"))
            app = QApplication.instance()
            if app is not None:
                app.processEvents()
            try:
                # start_new_session: eigene Prozessgruppe, damit ein pkill/kill im
                # Rezept-Skript nicht die GUI-Gruppe trifft.
                result = subprocess.run(
                    ["bash", str(uninstall)],
                    cwd=str(self._L.ROOT),
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=self._L._ROLLBACK_UNINSTALL_TIMEOUT_SEC,
                    check=False,
                    start_new_session=True,
                )
                ok = result.returncode == 0
                if result.stdout:
                    self._w._feed_line(result.stdout)
                if result.stderr:
                    self._w._feed_line(result.stderr)
            except (OSError, subprocess.TimeoutExpired) as exc:
                self._w._activity("error", str(exc))
                ok = False
        if ok:
            self._w._activity("ok", t("status.install_rolled_back"))
            QMessageBox.information(
                self._w, t("status.done"), t("status.install_rolled_back")
            )
        else:
            self._w._activity("error", t("status.install_rollback_fail"))
            QMessageBox.warning(
                self._w, t("dialog.error"), t("status.install_rollback_fail")
            )

    def _prepare_install_env(self, extra: dict[str, str]) -> bool:
        """Archiv-Passwort-Tempdateien für den Install-Lauf nachziehen."""
        archive = (extra.get("RECIPE_ARCHIVE_PATH") or "").strip()
        if not archive:
            return True
        path = Path(archive)
        passwords = ensure_archive_passwords(self._w, path)
        if passwords is None:
            return False
        attach_archive_password_files(extra, passwords)
        return True

    def run_install(self) -> None:
        rd = self._w._require_trusted_recipe()
        if rd is None:
            return
        install = rd / "install.sh"
        if not install.is_file():
            QMessageBox.critical(self._w, t("dialog.missing"), str(install))
            return

        meta = self._w._selected.meta
        rid = self._w._selected.rid
        if not self._w.ensure_host_wow64_for_install(meta):
            return
        extra: dict[str, str] = {}

        if needs_source_dialog(meta):
            pending = load_recipe_install_env(self._w._settings, rid)
            if not has_recipe_install_source(pending):
                # Install-CTA: Quelle wählen, dann direkt weiterinstallieren.
                saved = self._w._prompt_and_save_source()
                if not saved:
                    return
                extra = dict(saved)
            else:
                extra = dict(pending or {})
            if not self._prepare_install_env(extra):
                return

        info = self._L.recipe_info_text(rid, rd)
        name = meta.get("name", rid)
        if self._w._selected.state == RecipeState.INSTALLED:
            if QMessageBox.question(
                self._w,
                t("dialog.install_title"),
                t("dialog.install_reconfirm", name=name),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            ) != QMessageBox.StandardButton.Yes:
                return
        else:
            html = self._L.format_recipe_info_html(
                info,
                theme=getattr(self._w, "_theme", "dark"),
                author=(meta.get("author") or ""),
            )
            dlg = self._L.InfoConfirmDialog(
                self._w,
                title=t("dialog.install_title"),
                html=html,
                question=t("dialog.install_question"),
            )
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return

        self._w._maybe_wine_dialog_hint("install")
        is_reinstall = self._w._selected.state == RecipeState.INSTALLED
        label = t("action.reinstall") if is_reinstall else t("action.install")
        op = "reinstall" if is_reinstall else "install"

        def _after_ok() -> None:
            clear_recipe_install_env(self._w._settings, rid)
            self._w._offer_desktop_shortcuts(label)

        self._run_async(
            install,
            extra,
            label,
            on_success=_after_ok,
            op=op,
            recipe_dir=rd,
        )

    def run_genp_from_pack(self) -> None:
        """GenP/Cure-GUI aus dem Pack unter Proton (m0nkrus, Acrobat, …)."""
        rd = self._w._require_trusted_recipe()
        if rd is None or not self._w._selected:
            return
        script = rd / "genp.sh"
        if not script.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), str(script))
            return
        if self._w._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.warning(
                self._w, t("dialog.not_installed_title"), t("dialog.install_first")
            )
            return
        if QMessageBox.question(
            self._w,
            t("dialog.genp_title"),
            t("dialog.genp_body"),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        wine_path = self._genp_target_wine_path()
        if wine_path:
            clip = QApplication.clipboard()
            if clip is not None:
                clip.setText(wine_path)
            self._w._activity("info", t("status.genp_path_clipboard", path=wine_path))
        self._run_async(
            script,
            None,
            t("status.genp_done"),
            op="genp",
            recipe_dir=rd,
        )

    def _genp_target_wine_path(self) -> str:
        """Wine-Pfad für GenP-Dateidialog (Zwischenablage — GenP setzt InitialDir selbst)."""
        if not self._w._selected:
            return ""
        rid = self._w._selected.rid
        dr = self._L.resolve_data_root(self._w._selected.meta, rid)
        prefix = dr / "prefix"
        for rel in (
            "drive_c/Program Files/Adobe/Adobe Photoshop 2021/Photoshop.exe",
            "drive_c/Program Files (x86)/Adobe/Adobe Photoshop 2021/Photoshop.exe",
        ):
            if (prefix / rel).is_file():
                return "C:\\" + rel[len("drive_c/") :].replace("/", "\\")
        return (
            "C:\\Program Files\\Adobe\\Adobe Photoshop 2021\\Photoshop.exe"
        )

    def run_repair(self) -> None:
        rd = self._w._require_trusted_recipe()
        if rd is None:
            return
        repair = rd / "repair.sh"
        if not repair.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), t("dialog.no_repair"))
            return
        if self._w._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.warning(
                self._w, t("dialog.not_installed_title"), t("dialog.install_first")
            )
            return
        if not self._w.ensure_host_wow64_for_install(self._w._selected.meta):
            return
        if QMessageBox.question(
            self._w,
            t("dialog.repair_title"),
            self._repair_message(self._w._selected.rid),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._w._maybe_wine_dialog_hint("repair")
        self._run_async(repair, done_label=t("action.repair"))

    def run_update(self) -> None:
        """Mehr → Update anwenden — nur Update-Quelle, kein Reinstall."""
        rd = self._w._require_trusted_recipe()
        if rd is None or not self._w._selected:
            return
        meta = self._w._selected.meta
        if not recipe_supports_update(meta):
            return
        update_script = rd / (meta.get("update") or "update.sh")
        if not update_script.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), str(update_script))
            return
        if self._w._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.warning(
                self._w, t("dialog.not_installed_title"), t("dialog.install_first")
            )
            return
        dlg = UpdateSourceDialog(
            self._w,
            rid=self._w._selected.rid,
            meta=meta,
            root=Path.home(),
            title=t("dialog.update_title"),
        )
        apply_tool_window(dlg, icon=self._w.windowIcon(), modal=True)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        extra = dlg.build_env()
        if not extra.get("RECIPE_UPDATE_ROOT"):
            return
        if QMessageBox.question(
            self._w,
            t("dialog.update_title"),
            t("dialog.update_body"),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        self._w._maybe_wine_dialog_hint("install")
        self._run_async(
            update_script,
            extra,
            t("action.update"),
            op="update",
            recipe_dir=rd,
        )

    def run_relocate(self) -> None:
        """Mehr → Ziel verschieben — DATA_ROOT inkl. Prefix umziehen."""
        rd = self._w._require_trusted_recipe()
        if rd is None or not self._w._selected:
            return
        if self._w._selected.state == RecipeState.NOT_INSTALLED:
            QMessageBox.warning(
                self._w, t("dialog.not_installed_title"), t("dialog.install_first")
            )
            return
        if self._L.recipe_process_running(self._w._selected.rid, self._w._selected.meta):
            QMessageBox.warning(
                self._w, t("dialog.relocate_title"), t("dialog.relocate_running")
            )
            return
        old = self._L.resolve_data_root(self._w._selected.meta, self._w._selected.rid)
        if not old.is_dir():
            QMessageBox.warning(
                self._w, t("dialog.relocate_title"), t("dialog.relocate_need_target")
            )
            return
        new = pick_directory(
            self._w,
            t("dialog.relocate_pick"),
            str(old.parent if old.parent.is_dir() else old),
        )
        if not new:
            return
        new_p = Path(new)
        try:
            if old.resolve() == new_p.resolve():
                QMessageBox.information(
                    self._w, t("dialog.relocate_title"), t("dialog.relocate_same")
                )
                return
        except OSError:
            pass
        name = self._w._selected.meta.get("name", self._w._selected.rid)
        if QMessageBox.question(
            self._w,
            t("dialog.relocate_title"),
            t("dialog.relocate_body", name=name, old=str(old), new=str(new_p)),
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        ) != QMessageBox.StandardButton.Yes:
            return
        script = self._L.ROOT / "scripts" / "recipe-relocate.sh"
        if not script.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), str(script))
            return

        def _after_ok() -> None:
            self._w.refresh_statuses()
            self._w._activity("ok", t("dialog.relocate_title") + f": {new_p}")
            QMessageBox.information(
                self._w,
                t("dialog.relocate_title"),
                t("status.done_body", label=t("action.relocate")),
            )

        self._run_async(
            script,
            {
                "RECIPE_RELOCATE_TO": str(new_p),
                "RECIPE_DIR": str(rd),
            },
            t("action.relocate"),
            op="relocate",
            recipe_dir=rd,
            script_args=[str(rd)],
            on_success=_after_ok,
        )

    def _repair_message(self, rid: str) -> str:
        if rid == "wiso-steuer":
            return t("dialog.repair_wiso")
        return t("dialog.repair_default")

    def _record_home_activity(self, op: str, rid: str, *, ok: bool) -> None:
        """Persist completed recipe ops for the home-page history (not launch/kill)."""
        rid = (rid or "").strip()
        op = (op or "").strip()
        if not rid or not is_tracked_op(op):
            return
        name = rid
        if self._w._selected and self._w._selected.rid == rid:
            name = str(self._w._selected.meta.get("name") or rid)
        else:
            for info in getattr(self._w, "recipes", []) or []:
                if getattr(info, "rid", "") == rid:
                    name = str(getattr(info, "meta", {}).get("name") or rid)
                    break
        try:
            append_activity(rid=rid, name=name, op=op, ok=ok)
        except OSError:
            return
        refresh = getattr(self._w, "_refresh_home_activity", None)
        if callable(refresh):
            refresh()

    def _uninstall_confirm_message(self, rid: str, name: str) -> str:
        base = t("dialog.uninstall_confirm", name=name)
        if rid == "wiso-steuer":
            return f"{base}\n\n{t('dialog.uninstall_backup_wiso')}"
        return f"{base}\n\n{t('dialog.uninstall_backup_hint')}"

    def _spawn_detached(self, cmd: list[str], env: dict[str, str]) -> Path:
        rid = env.get("RECIPE_ID", "app")
        log_path = self._L.LOG_ROOT / f"launch_{rid}_{self._w.session_id[:8]}.log"
        self._L.LOG_ROOT.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self._L.LOG_ROOT, 0o700)
        except OSError:
            pass
        log_f = open(log_path, "a", encoding="utf-8")  # noqa: SIM115
        try:
            os.chmod(log_path, 0o600)
        except OSError:
            pass
        log_f.write(f"\n--- {rid} launch ---\n")
        log_f.flush()
        subprocess.Popen(
            cmd,
            cwd=str(self._L.ROOT),
            env=env,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=log_f,
            stderr=subprocess.STDOUT,
        )
        self._w._activity("info", f"Log: {log_path.name}")
        return log_path

    def _check_launch_alive(
        self, rid: str, log_path: Path, attempt: int = 0
    ) -> None:
        # launch.sh kann sofort abbrechen („Läuft bereits“) — Log prüfen.
        try:
            log_tail = log_path.read_text(encoding="utf-8", errors="replace")[-4000:]
        except OSError:
            log_tail = ""
        if "Läuft bereits:" in log_tail:
            name = self._w._selected.meta.get("name", rid) if self._w._selected else rid
            self._w._activity(
                "warn",
                t("dialog.launch_already", name=name),
            )
            return
        if "Hängende unsichtbare" in log_tail and attempt == 0:
            self._w._activity("info", t("dialog.launch_hung"))
        meta = self._w._selected.meta if self._w._selected else None
        if not self._L.launch_process_patterns(rid, meta):
            return
        if self._L.recipe_process_running(rid, meta):
            # „läuft“ / später „beendet“ meldet _refresh_running_indicators unter Vorgang.
            self._w._launch_alive_reported = True
            self._w._running_prev[rid] = True
            return
        # Photoshop/Premiere: Launch macht Prefs/Fonts vor wine — erster Start oft >20s.
        # Halo via Steam Non-Steam: wait for client + proton/shaders (log line marks wait).
        if rid == "halo-campaign-evolved" and "warte auf Halo unter Steam" in log_tail:
            max_attempts = 100  # ~4 min @ 2.5s
        elif rid.startswith("photoshop") or rid == "premiere" or rid == "halo-campaign-evolved":
            max_attempts = 35
        else:
            max_attempts = 7
        if (
            "Steam-Client abgestürzt" in log_tail
            or "Steam ist nicht hochgekommen" in log_tail
            or "steam nicht installiert" in log_tail
        ):
            max_attempts = min(max_attempts, attempt)
        if attempt < max_attempts:
            QTimer.singleShot(
                2500,
                lambda: self._check_launch_alive(rid, log_path, attempt + 1),
            )
            return
        name = self._w._selected.meta.get("name", rid) if self._w._selected else rid
        tips = (
            t("dialog.launch_tips_wiso")
            if rid == "wiso-steuer"
            else t("dialog.launch_tips_default")
        )
        QMessageBox.warning(
            self._w,
            t("status.app_not_running"),
            t("dialog.launch_not_alive", name=name, log=log_path, tips=tips),
        )
        ev = LogEvent(
            level="warn",
            code=E_LAUNCH_NO_PROCESS,
            message_key="error.E_LAUNCH_NO_PROCESS",
            detail=log_path.name,
            session_id=self._w.session_id,
            recipe_id=rid,
        )
        self._w._activity("warn", ev.display_text())
        self._w._switch_to_logs_tab()
        self._w.populate_log_files()

    def run_launch(self) -> None:
        rd = self._w._require_trusted_recipe()
        if rd is None:
            return
        if self._w._selected and self._w._selected.version_warning:
            if QMessageBox.warning(
                self._w,
                t("dialog.version_warn_title"),
                t(
                    "dialog.version_warn_body",
                    warning=self._w._selected.version_warning,
                ),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            ) != QMessageBox.StandardButton.Yes:
                return
        env = self._w._base_env()
        if self._w._selected and self._w._selected.rid == "wiso-steuer":
            env.pop("WINE_DISABLE_WOW64", None)
        meta = self._w._selected.meta
        launch = rd / "launch.sh"
        if not launch.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), t("dialog.no_launch"))
            return
        log_path = self._spawn_detached(["bash", str(launch)], env)
        self._w._switch_to_progress_tab()
        self._w._clear_activity_list()
        self._w.raw_log.clear()
        self._w._launch_alive_reported = False
        name = meta.get("name", self._w._selected.rid)
        rid = self._w._selected.rid
        self._w._watched_launch_rid = rid
        self._w._running_prev[rid] = False
        self._w.step_label.setText(t("status.starting", name=name))
        self._w.step_label.setStyleSheet("")
        self._w._activity("step", t("status.start_triggered", name=name))
        self._w._activity("info", t("status.window_soon", name=name))
        if self._L.launch_process_patterns(rid, meta):
            QTimer.singleShot(
                2500, lambda: self._check_launch_alive(rid, log_path, 0)
            )

    def run_validate(self) -> None:
        rd = self._w._require_trusted_recipe()
        if rd is None:
            return
        v = rd / "validate.sh"
        if v.is_file():
            # No error dialog: FAIL lines belong in Vorgang (e.g. not installed → expected).
            self._run_async(v, done_label=t("action.validate"), dialog=False)

    def run_kill(self) -> None:
        rd = self._w._require_recipe()
        if rd is None:
            return
        kill = rd / "kill.sh"
        if not kill.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), t("dialog.no_kill"))
            return
        name = self._w._selected.meta.get("name", self._w._selected.rid)
        if not ask_yes_no(
            self._w,
            t("dialog.kill_title"),
            t("dialog.kill_body", name=name),
        ):
            return
        # kill.sh already cleans orphans — do not schedule cleanup-orphans.sh on stop.
        self._w._skip_exit_cleanup.add(self._w._selected.rid)
        self._w._switch_to_progress_tab()
        self._run_async(kill, done_label=t("action.kill"), dialog=False)

    def run_uninstall(self) -> None:
        rd = self._w._require_trusted_recipe()
        if rd is None:
            return
        un = rd / "uninstall.sh"
        if not un.is_file():
            QMessageBox.warning(self._w, t("dialog.missing"), t("dialog.no_uninstall"))
            return
        rid = self._w._selected.rid
        name = self._w._selected.meta.get("name", rid)
        if not ask_yes_no(
            self._w,
            t("dialog.uninstall_title"),
            self._uninstall_confirm_message(rid, name),
            default_yes=False,
        ):
            return
        extra = {"PHOTOSHOP_UNINSTALL_YES": "1", "UNINSTALL_YES": "1"}
        recipe_dir = rd

        def _after_uninstall() -> None:
            # Purge already removes shortcuts; re-run in GUI env (correct HOME/XDG).
            if self._w._remove_desktop_shortcuts(recipe_dir):
                self._w._activity("ok", t("dialog.shortcuts_removed"))
            QMessageBox.information(
                self._w,
                t("status.done"),
                t("status.done_body", label=t("action.uninstall")),
            )

        self._run_async(
            un,
            extra,
            t("action.uninstall"),
            on_success=_after_uninstall,
        )

