"""Fenster-Hilfen: Taskleisten-Schließbarkeit + Geometrie speichern/laden."""

from __future__ import annotations

import base64
import time
from typing import Literal

from PyQt6.QtCore import QByteArray, QEvent, QObject, Qt, QTimer
from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QApplication, QDialog, QMessageBox, QSplitter, QWidget

from diagnostics import log_call_site
from i18n import t

UnsavedChoice = Literal["save", "discard", "cancel"]


def confirm_unsaved_changes(
    parent: QWidget | None,
    *,
    title: str = "",
    body: str = "",
) -> UnsavedChoice:
    """Speichern / Schließen ohne Speichern / Abbrechen."""
    box = QMessageBox(parent)
    box.setIcon(QMessageBox.Icon.Warning)
    box.setWindowTitle(title or t("dialog.unsaved_title"))
    box.setText(body or t("dialog.unsaved_body"))
    save_btn = box.addButton(
        t("dialog.unsaved_save"), QMessageBox.ButtonRole.AcceptRole
    )
    discard_btn = box.addButton(
        t("dialog.unsaved_discard"), QMessageBox.ButtonRole.DestructiveRole
    )
    box.addButton(t("dialog.unsaved_cancel"), QMessageBox.ButtonRole.RejectRole)
    box.setDefaultButton(save_btn)
    box.exec()
    clicked = box.clickedButton()
    if clicked is save_btn:
        return "save"
    if clicked is discard_btn:
        return "discard"
    return "cancel"


def geometry_to_b64(widget: QWidget) -> str:
    raw = bytes(widget.saveGeometry())
    if not raw:
        return ""
    return base64.b64encode(raw).decode("ascii")


def restore_geometry(widget: QWidget, b64: str) -> bool:
    text = (b64 or "").strip()
    if not text:
        return False
    try:
        data = QByteArray(base64.b64decode(text))
    except Exception:
        return False
    if data.isEmpty():
        return False
    return bool(widget.restoreGeometry(data))


def splitter_to_b64(splitter: QSplitter) -> str:
    raw = bytes(splitter.saveState())
    if not raw:
        return ""
    return base64.b64encode(raw).decode("ascii")


def restore_splitter(splitter: QSplitter, b64: str) -> bool:
    text = (b64 or "").strip()
    if not text:
        return False
    try:
        data = QByteArray(base64.b64decode(text))
    except Exception:
        return False
    if data.isEmpty():
        return False
    return bool(splitter.restoreState(data))


def widget_belongs_to_main(w: QWidget | None, main: QWidget) -> bool:
    """Hauptfenster oder Kind-/Tool-Fenster der App (nicht fremde Top-Level)."""
    if w is None:
        return False
    if w is main:
        return True
    p = w.parentWidget()
    while p is not None:
        if p is main:
            return True
        p = p.parentWidget()
    return False


def mark_user_dismiss(dialog: QWidget) -> None:
    """OK/Abbrechen — Close-Guard darf keinen App-Quit planen."""
    dialog._rezeptor_user_dismiss = True  # type: ignore[attr-defined]
    dialog.setProperty("rezeptor_user_dismiss", True)
    main = dialog.parentWidget()
    while main is not None:
        guard = getattr(main, "_rezeptor_close_guard", None)
        if guard is not None:
            cancel = getattr(guard, "cancel_pending_quit", None)
            if callable(cancel):
                cancel()
            break
        main = main.parentWidget()


def mark_force_close(dialog: QWidget) -> None:
    dialog._rezeptor_force_close = True  # type: ignore[attr-defined]
    dialog.setProperty("rezeptor_force_close", True)


def _force_dismiss_dialog(dlg: QDialog, *, force: bool = True) -> None:
    """Modale exec()-Schleifen zuverlässig beenden (KDE Taskleiste / Alle schließen)."""
    if force:
        dlg.setProperty("rezeptor_force_close", True)
    force_fn = getattr(dlg, "force_close", None)
    if callable(force_fn):
        force_fn()
        return
    if dlg.isModal():
        dlg.done(QDialog.DialogCode.Rejected)
    else:
        dlg.reject()
    dlg.close()


def unwind_modal_dialogs(main: QWidget, *, force: bool = True, rounds: int = 12) -> int:
    """Geschachtelte exec()-Schleifen (Hilfe-QMessageBox über Quellen-Dialog) auflösen."""
    n = 0
    app = QApplication.instance()
    for _ in range(rounds):
        modal = QApplication.activeModalWidget()
        if modal is None or not widget_belongs_to_main(modal, main):
            break
        if not isinstance(modal, QDialog):
            break
        _force_dismiss_dialog(modal, force=force)
        n += 1
        if app is not None:
            app.processEvents()
    n += dismiss_child_dialogs(main, force=force)
    if app is not None:
        app.processEvents()
    return n


def visible_child_dialogs(parent: QWidget) -> list[QDialog]:
    """Sichtbare Kind-Dialoge (Quelle, Einstellungen, …), nicht das Parent selbst."""
    out: list[QDialog] = []
    for w in parent.findChildren(QDialog):
        if w is parent or not w.isVisible():
            continue
        out.append(w)
    return out


def dismiss_child_dialogs(parent: QWidget, *, force: bool = True) -> int:
    """Modale Kinder schließen — Taskleisten-„Schließen“ am Hauptfenster sonst no-op."""
    n = 0
    app = QApplication.instance()
    if app is not None:
        for _ in range(8):
            modal = QApplication.activeModalWidget()
            if modal is None or not widget_belongs_to_main(modal, parent):
                break
            if isinstance(modal, QDialog):
                _force_dismiss_dialog(modal, force=force)
                n += 1
                app.processEvents()
            else:
                break
    for dlg in list(visible_child_dialogs(parent)):
        _force_dismiss_dialog(dlg, force=force)
        n += 1
    if app is not None:
        app.processEvents()
    return n


def dismiss_all_top_level_windows(main: QWidget, *, force: bool = True) -> None:
    """Alle sichtbaren Rezeptor-Fenster schließen (KDE „Alle schließen“ / Taskleiste)."""
    app = QApplication.instance()
    # Zuerst innere Modals (QMessageBox über Quellen-Dialog), sonst hängt exec().
    unwind_modal_dialogs(main, force=force)
    if app is None:
        return
    for w in list(app.topLevelWidgets()):
        if w is main or not w.isVisible():
            continue
        if not widget_belongs_to_main(w, main):
            continue
        if force:
            w.setProperty("rezeptor_force_close", True)
        if hasattr(w, "force_close"):
            w.force_close()
            app.processEvents()
            continue
        if isinstance(w, QDialog):
            _force_dismiss_dialog(w, force=force)
            app.processEvents()
            continue
        w.close()
    unwind_modal_dialogs(main, force=force)
    dismiss_child_dialogs(main, force=force)


class ApplicationCloseGuard(QObject):
    """Fängt WM-/Taskleisten-Close ab — vor modalen exec()-Blockern und für „Alle schließen“."""

    _BURST_SEC = 0.85

    def __init__(self, main: QWidget) -> None:
        super().__init__(main)
        self._main = main
        self._quit_scheduled = False
        self._wm_quit_armed = False
        self._quit_token = 0
        self._close_burst: list[float] = []
        self._main_close_at: float | None = None
        app = QApplication.instance()
        if app is not None:
            app.installEventFilter(self)

    def _main_close_armed(self) -> bool:
        if self._main_close_at is None:
            return False
        return time.monotonic() - self._main_close_at < self._BURST_SEC

    def _secondary_has_unsaved(self, w: QWidget) -> bool:
        dirty_fn = getattr(w, "is_dirty", None)
        return callable(dirty_fn) and bool(dirty_fn())

    @staticmethod
    def _flag(w: QWidget, name: str) -> bool:
        if bool(getattr(w, f"_{name}", False)):
            return True
        v = w.property(name)
        return v is True or v == 1

    def eventFilter(self, watched: QObject, event: QEvent) -> bool:  # noqa: N802
        if event.type() == QEvent.Type.Quit:
            if watched is QApplication.instance():
                self._schedule_quit()
                return True
            return False

        if event.type() != QEvent.Type.Close:
            return False
        w = watched
        if not isinstance(w, QWidget) or not w.isWindow():
            return False
        if not widget_belongs_to_main(w, self._main):
            return False
        if getattr(self._main, "_force_quitting", False):
            return False
        # OK/Abbrechen / force_close — niemals App-Quit (sonst stirbt Install nach Quellen-OK).
        if self._flag(w, "rezeptor_force_close") or self._flag(
            w, "rezeptor_user_dismiss"
        ):
            return False

        now = time.monotonic()
        self._close_burst = [
            t for t in self._close_burst if now - t < self._BURST_SEC
        ]
        self._close_burst.append(now)

        wm_close = bool(event.spontaneous())

        if w is self._main:
            self._main_close_at = now
            unwind_modal_dialogs(self._main, force=True)
            self._schedule_quit()
            event.ignore()
            return True

        # Hilfe-QMessageBox: nur die Box schließen (kein App-Quit).
        if isinstance(w, QMessageBox) and not wm_close:
            return False

        if self._secondary_has_unsaved(w) and not wm_close:
            return False

        # Taskleisten-/WM-Close: alle Fenster beenden.
        # force_close setzen, sonst ruft Dialog.closeEvent mark_user_dismiss auf
        # und cancel_pending_quit verwirft den geplanten Quit (→ „Schließen tut nichts“).
        if wm_close:
            if isinstance(w, QDialog):
                mark_force_close(w)
            self._schedule_quit()
            return False

        return False

    def _schedule_quit(self) -> None:
        if self._quit_scheduled:
            return
        log_call_site("QUIT-SCHEDULED")
        self._quit_scheduled = True
        self._wm_quit_armed = True
        self._quit_token += 1
        token = self._quit_token

        def _run() -> None:
            self._quit_scheduled = False
            if token != self._quit_token:
                return
            self._close_burst.clear()
            fn = getattr(self._main, "request_quit_from_wm", None)
            if callable(fn):
                fn(from_wm=True)
            self._wm_quit_armed = False

        QTimer.singleShot(0, _run)

    def cancel_pending_quit(self) -> None:
        """Quellen-OK / Nutzer-Dismiss: geplanten Fehl-Quit verwerfen — nicht bei WM-Quit."""
        if getattr(self, "_wm_quit_armed", False):
            return
        self._quit_token += 1
        self._quit_scheduled = False
        self._close_burst.clear()


def install_application_close_guard(main: QWidget) -> ApplicationCloseGuard:
    """In main() nach dem Hauptfenster aufrufen."""
    guard = ApplicationCloseGuard(main)
    main.setAttribute(Qt.WidgetAttribute.WA_QuitOnClose, True)
    main._rezeptor_close_guard = guard  # type: ignore[attr-defined]
    return guard


def apply_tool_window(
    widget: QWidget,
    *,
    icon: QIcon | None = None,
    modal: bool = False,
    delete_on_close: bool | None = None,
) -> None:
    """Eigenständiges Fenster: Taskleisten-Eintrag, Schließen per RMB funktioniert.

    Parent-modale Dialoge ohne Window-Flag fehlen oft in der Taskleiste und
    blockieren „Schließen“ am Hauptfenster.

    WA_DeleteOnClose: nur bei nicht-modalen show()-Fenstern (default).
    Bei modal=True + exec() muss das Objekt nach return noch lesbar sein
    (Geometrie, result_settings) — sonst RuntimeError/SIGABRT.
    """
    flags = (
        Qt.WindowType.Window
        | Qt.WindowType.WindowTitleHint
        | Qt.WindowType.WindowSystemMenuHint
        | Qt.WindowType.WindowMinMaxButtonsHint
        | Qt.WindowType.WindowCloseButtonHint
    )
    widget.setWindowFlags(flags)
    # Taskleisten-Schließen beendet nur dieses Fenster; App-Quit über Hauptfenster.
    if delete_on_close is None:
        delete_on_close = not modal
    widget.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose, delete_on_close)
    widget.setAttribute(Qt.WidgetAttribute.WA_QuitOnClose, False)
    if icon is not None and not icon.isNull():
        widget.setWindowIcon(icon)
    if isinstance(widget, QDialog):
        widget.setWindowModality(
            Qt.WindowModality.WindowModal if modal else Qt.WindowModality.NonModal
        )
        widget.setSizeGripEnabled(True)
    # Nie kleiner als schon gesetztes Minimum (Settings/Rezept-View sonst gequetscht).
    floor_w, floor_h = 480, 360
    cur = widget.minimumSize()
    widget.setMinimumSize(max(floor_w, cur.width()), max(floor_h, cur.height()))
    # __init__-resize als Standard halten (WM/adjustSize darf nicht dauerhaft schrumpfen).
    ensure_usable_size(
        widget,
        min_w=widget.minimumWidth(),
        min_h=widget.minimumHeight(),
        default_w=max(widget.width(), widget.minimumWidth()),
        default_h=max(widget.height(), widget.minimumHeight()),
    )


def _available_screen_size(widget: QWidget) -> tuple[int, int]:
    screen = widget.screen()
    if screen is None:
        app = QApplication.instance()
        screen = app.primaryScreen() if app is not None else None
    if screen is None:
        return 1600, 900
    ag = screen.availableGeometry()
    return max(640, ag.width() - 48), max(480, ag.height() - 48)


def ensure_usable_size(
    widget: QWidget,
    *,
    min_w: int = 520,
    min_h: int = 360,
    default_w: int | None = None,
    default_h: int | None = None,
) -> None:
    """Mindestgröße + Standard; sizeHint als Wunschgröße, nicht als harte Min."""
    floor_w = max(min_w, widget.minimumWidth())
    floor_h = max(min_h, widget.minimumHeight())
    widget.setMinimumSize(floor_w, floor_h)

    hint = widget.sizeHint()
    hint_w = hint.width() if hint.isValid() else 0
    hint_h = hint.height() if hint.isValid() else 0
    max_w, max_h = _available_screen_size(widget)
    want_w = max(widget.width(), floor_w, default_w or 0, hint_w)
    want_h = max(widget.height(), floor_h, default_h or 0, hint_h)
    want_w = min(want_w, max_w)
    want_h = min(want_h, max_h)
    if widget.width() != want_w or widget.height() != want_h:
        widget.resize(want_w, want_h)


def clamp_restored_geometry(
    widget: QWidget, *, min_w: int = 520, min_h: int = 360
) -> None:
    """Nach restoreGeometry: zu kleine Fenster auf nutzbare Größe anheben."""
    ensure_usable_size(widget, min_w=min_w, min_h=min_h)


def ensure_on_screen(widget: QWidget) -> None:
    """Fenster sichtbar im verfügbaren Bildschirm halten (Wayland/Multi-Monitor)."""
    screen = widget.screen()
    if screen is None:
        app = QApplication.instance()
        screen = app.primaryScreen() if app is not None else None
    if screen is None:
        return
    ag = screen.availableGeometry()
    g = widget.frameGeometry() if widget.isWindow() else widget.geometry()
    w = min(max(widget.width(), widget.minimumWidth()), ag.width())
    h = min(max(widget.height(), widget.minimumHeight()), ag.height())
    x = g.x()
    y = g.y()
    if x + w < ag.left() + 40 or x > ag.right() - 40:
        x = ag.left() + max(0, (ag.width() - w) // 2)
    if y + h < ag.top() + 40 or y > ag.bottom() - 40:
        y = ag.top() + max(0, (ag.height() - h) // 2)
    x = max(ag.left(), min(x, ag.right() - w))
    y = max(ag.top(), min(y, ag.bottom() - h))
    widget.setGeometry(x, y, w, h)
