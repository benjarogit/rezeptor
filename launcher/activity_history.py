"""Cross-recipe activity history for the home page (no secrets)."""

from __future__ import annotations

import json
import os
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

from settings import SETTINGS_DIR, _ensure_settings_dir

HISTORY_FILE = SETTINGS_DIR / "activity-history.json"
HISTORY_CAP = 20
DISPLAY_CAP = 8

# Completed recipe ops only — not launch/kill/genp step noise.
TRACKED_OPS = frozenset(
    {
        "install",
        "reinstall",
        "repair",
        "validate",
        "update",
        "relocate",
        "uninstall",
    }
)


@dataclass(frozen=True)
class ActivityEntry:
    ts: float
    rid: str
    name: str
    op: str
    ok: bool


def is_tracked_op(op: str) -> bool:
    return (op or "").strip() in TRACKED_OPS


def _atomic_write_history(path: Path, text: str) -> None:
    """Atomic write with 0o600; temp file in ``path.parent`` (cross-device safe)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def _parse_entry(raw: object) -> ActivityEntry | None:
    if not isinstance(raw, dict):
        return None
    try:
        ts = float(raw.get("ts", 0))
    except (TypeError, ValueError):
        return None
    rid = str(raw.get("rid", "")).strip()
    name = str(raw.get("name", "")).strip() or rid
    op = str(raw.get("op", "")).strip()
    if not rid or not op or not is_tracked_op(op) or ts <= 0:
        return None
    ok_raw = raw.get("ok", True)
    if isinstance(ok_raw, bool):
        ok = ok_raw
    else:
        ok = str(ok_raw).strip().lower() in ("1", "true", "yes", "on")
    return ActivityEntry(ts=ts, rid=rid, name=name, op=op, ok=ok)


def load_activity_history(path: Path | None = None) -> list[ActivityEntry]:
    """Load newest-first history. Corrupt/missing file → empty list (never raises)."""
    p = path or HISTORY_FILE
    if not p.is_file():
        return []
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError, TypeError, ValueError):
        return []
    if not isinstance(raw, list):
        return []
    out: list[ActivityEntry] = []
    for item in raw:
        entry = _parse_entry(item)
        if entry is not None:
            out.append(entry)
    out.sort(key=lambda e: e.ts, reverse=True)
    return out[:HISTORY_CAP]


def append_activity(
    *,
    rid: str,
    name: str,
    op: str,
    ok: bool,
    path: Path | None = None,
    ts: float | None = None,
) -> None:
    """Prepend a completed op and prune to HISTORY_CAP. No-op for untracked ops."""
    rid = (rid or "").strip()
    op = (op or "").strip()
    if not rid or not is_tracked_op(op):
        return
    entry = ActivityEntry(
        ts=float(ts if ts is not None else time.time()),
        rid=rid,
        name=(name or "").strip() or rid,
        op=op,
        ok=bool(ok),
    )
    p = path or HISTORY_FILE
    items = load_activity_history(p)
    payload = [
        {
            "ts": entry.ts,
            "rid": entry.rid,
            "name": entry.name,
            "op": entry.op,
            "ok": entry.ok,
        }
    ]
    for old in items:
        if len(payload) >= HISTORY_CAP:
            break
        payload.append(
            {
                "ts": old.ts,
                "rid": old.rid,
                "name": old.name,
                "op": old.op,
                "ok": old.ok,
            }
        )
    if p == HISTORY_FILE:
        _ensure_settings_dir()
    _atomic_write_history(
        p,
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    )


def format_activity_ago(ts: float, *, now: float | None = None) -> str:
    """Locale-aware relative time for home list rows."""
    from i18n import t

    age = max(0, int((now if now is not None else time.time()) - ts))
    if age < 60:
        return t("home.activity_ago_just_now")
    minutes = age // 60
    if minutes < 60:
        return t("home.activity_ago_minutes", n=minutes)
    hours = minutes // 60
    if hours < 48:
        return t("home.activity_ago_hours", n=hours)
    days = hours // 24
    return t("home.activity_ago_days", n=days)


def format_activity_line(entry: ActivityEntry, *, now: float | None = None) -> str:
    from i18n import t

    ago = format_activity_ago(entry.ts, now=now)
    action_key = f"action.{entry.op}"
    action = t(action_key)
    if action == action_key:
        action = entry.op
    if entry.ok:
        return t(
            "home.activity_line",
            ago=ago,
            name=entry.name,
            action=action,
        )
    return t(
        "home.activity_line_failed",
        ago=ago,
        name=entry.name,
        action=action,
    )
