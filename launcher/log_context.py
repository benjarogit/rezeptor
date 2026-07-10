"""Structured activity / error events for Rezeptor launcher."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from i18n import t


@dataclass
class LogEvent:
    level: str  # step|ok|warn|error|info|log
    code: str = ""
    message_key: str = ""
    detail: str = ""
    session_id: str = ""
    recipe_id: str = ""
    extras: dict[str, Any] = field(default_factory=dict)

    def display_text(self) -> str:
        if self.message_key:
            try:
                msg = t(self.message_key, **self.extras)
            except Exception:
                msg = self.message_key
        else:
            msg = self.detail or self.code or ""
        if self.detail and self.message_key and self.detail not in msg:
            return f"{msg} — {self.detail}"
        return msg or self.code


# Stable error codes
E_TRUST_MANIFEST = "E_TRUST_MANIFEST"
E_UPDATE_BACKUP = "E_UPDATE_BACKUP"
E_UPDATE_APPLY = "E_UPDATE_APPLY"
E_UPDATE_ROLLBACK = "E_UPDATE_ROLLBACK"
E_LAUNCH_NO_PROCESS = "E_LAUNCH_NO_PROCESS"
E_SCRIPT_FAILED = "E_SCRIPT_FAILED"
