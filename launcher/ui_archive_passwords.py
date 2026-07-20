"""PyQt prompts for archive password resolution (domain logic in archive_passwords.py)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtWidgets import QInputDialog, QLineEdit, QMessageBox, QWidget

from archive_passwords import archive_needs_password, archive_opens_with
from i18n import t
from settings import load_settings, prepend_archive_password, save_settings


def ensure_archive_passwords(
    parent: QWidget | None,
    archive: Path,
    *,
    extra: list[str] | None = None,
) -> list[str] | None:
    """
    Return password candidates for extract (global list, working first).

    - Unencrypted: return global list (may be empty).
    - Encrypted: try global + extra; if none work, ask until OK or cancel.
    - Working password is prepended to the global settings list.
    - Returns None if the user cancels the prompt.
    """
    settings = load_settings()
    candidates: list[str] = []
    seen: set[str] = set()
    for pw in list(extra or []) + list(settings.archive_passwords):
        p = (pw or "").strip()
        if not p or p in seen:
            continue
        seen.add(p)
        candidates.append(p)

    if not archive.is_file():
        return candidates

    if not archive_needs_password(archive):
        return candidates

    for pw in candidates:
        if archive_opens_with(archive, pw):
            if prepend_archive_password(settings, pw):
                save_settings(settings)
            rest = [c for c in candidates if c != pw]
            return [pw, *rest]

    while True:
        pw, ok = QInputDialog.getText(
            parent,
            t("source.password_ask_title"),
            t("source.password_ask_body", name=archive.name),
            QLineEdit.EchoMode.Password,
        )
        if not ok:
            return None
        pw = (pw or "").strip()
        if not pw:
            QMessageBox.warning(
                parent,
                t("source.password_ask_title"),
                t("source.password_empty"),
            )
            continue
        if archive_opens_with(archive, pw):
            if prepend_archive_password(settings, pw):
                save_settings(settings)
            rest = [c for c in candidates if c != pw]
            return [pw, *rest]
        QMessageBox.warning(
            parent,
            t("source.password_ask_title"),
            t("source.password_wrong"),
        )
