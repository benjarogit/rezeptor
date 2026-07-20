"""Rezeptor user settings (~/.local/share/wine-software/rezeptor/settings.json)."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path

SETTINGS_DIR = Path.home() / ".local/share/wine-software/rezeptor"
SETTINGS_FILE = SETTINGS_DIR / "settings.json"
ARCHIVE_PASSWORDS_FILE = SETTINGS_DIR / "archive-passwords.json"
ARCHIVE_PASSWORDS_KEY_FILE = SETTINGS_DIR / "archive-passwords.key"
SETTINGS_SCHEMA_VERSION = 1


def _default_locale() -> str:
    try:
        from i18n import detect_system_locale

        return detect_system_locale()
    except Exception:
        return "en"


@dataclass
class RezeptorSettings:
    schema_version: int = SETTINGS_SCHEMA_VERSION
    log_retention_days: int = 14
    log_max_files: int = 50
    prune_logs_on_startup: bool = True
    # Beim Start validate.sh für alle Rezepte (mit Hinweisdialog)
    validate_on_startup: bool = True
    locale: str = ""
    theme: str = "dark"  # nur dark — Light war unbrauchbar, kein Parallel-Theme
    last_recipe_id: str = ""
    developer_mode: bool = False
    hidden_recipe_ids: list[str] = field(default_factory=list)
    recipe_order: list[str] = field(default_factory=list)  # drag order of recipe ids
    custom_category_order: list[str] = field(default_factory=list)  # DnD order for non-standard categories
    # User sidebar category override (rid → category). Default remains recipe.yml.
    recipe_category_overrides: dict[str, str] = field(default_factory=dict)
    recipe_sources: list[dict] = field(default_factory=list)  # [{id, url, label, trusted: bool}]
    # Archive passwords (secrets file; never persisted in settings.json)
    archive_passwords: list[str] = field(default_factory=list)
    # Pending install env per recipe id (source/target from dialog — not yet installed)
    recipe_install_env: dict[str, dict[str, str]] = field(default_factory=dict)
    # First-start host tool prompt (System prüfen) already shown
    host_deps_prompt_done: bool = False
    # UI-Persistenz (Base64 von QWidget.saveGeometry / QSplitter.saveState)
    window_geometry: str = ""
    window_maximized: bool = False
    splitter_state: str = ""
    content_tab: str = "overview"
    recipe_view_geometry: str = ""
    docs_geometry: str = ""
    settings_geometry: str = ""


def _parse_str_list(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for item in raw:
        s = str(item).strip()
        if s:
            out.append(s)
    return out


def _parse_str_dict(raw: object) -> dict[str, str]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, str] = {}
    for key, val in raw.items():
        k = str(key).strip()
        v = str(val).strip()
        if k and v:
            out[k] = v
    return out


_SOURCE_ENV_KEYS = (
    "RECIPE_SOURCE_ROOT",
    "RECIPE_ARCHIVE_PATH",
    "RECIPE_INSTALLER_PATH",
)
_EPHEMERAL_ENV_KEYS = (
    "RECIPE_ARCHIVE_PASSWORD_FILE",
    "RECIPE_ARCHIVE_PASSWORD_USED_FILE",
)
# User cleared Quelle/Ziel in the dialog — do not re-apply heuristics on reopen.
_CLEARED_KEY = "__cleared__"


def _parse_recipe_install_env(raw: object) -> dict[str, dict[str, str]]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, dict[str, str]] = {}
    for rid, env in raw.items():
        key = str(rid).strip()
        if not key or not isinstance(env, dict):
            continue
        cleaned = _sanitize_install_env({str(k): str(v) for k, v in env.items()})
        if cleaned and (
            has_recipe_install_source(cleaned) or is_recipe_install_cleared(cleaned)
        ):
            out[key] = cleaned
    return out


def _sanitize_install_env(env: dict[str, str]) -> dict[str, str]:
    """Drop empty values and ephemeral password temp-file paths."""
    out: dict[str, str] = {}
    for k, v in env.items():
        key = str(k).strip()
        val = str(v).strip()
        if not key or not val or key in _EPHEMERAL_ENV_KEYS:
            continue
        out[key] = val
    return out


def has_recipe_install_source(env: dict[str, str] | None) -> bool:
    if not env or is_recipe_install_cleared(env):
        return False
    return any((env.get(k) or "").strip() for k in _SOURCE_ENV_KEYS)


def is_recipe_install_cleared(env: dict[str, str] | None) -> bool:
    return bool(env and (env.get(_CLEARED_KEY) or "").strip() == "1")


def load_recipe_install_env(
    settings: RezeptorSettings, rid: str
) -> dict[str, str] | None:
    env = settings.recipe_install_env.get(rid)
    if not env:
        return None
    if is_recipe_install_cleared(env):
        return {_CLEARED_KEY: "1"}
    if not has_recipe_install_source(env):
        return None
    return dict(env)


def save_recipe_install_env(
    settings: RezeptorSettings, rid: str, env: dict[str, str]
) -> None:
    cleaned = _sanitize_install_env(env)
    if not has_recipe_install_source(cleaned):
        clear_recipe_install_env(settings, rid)
        return
    settings.recipe_install_env[rid] = cleaned
    save_settings(settings)


def clear_recipe_install_env(settings: RezeptorSettings, rid: str) -> None:
    """Remember that the user cleared paths — heuristics must not refill them."""
    settings.recipe_install_env[rid] = {_CLEARED_KEY: "1"}
    save_settings(settings)


def _parse_recipe_sources(raw: object) -> list[dict]:
    if not isinstance(raw, list):
        return []
    out: list[dict] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        rid = str(item.get("id", "")).strip()
        url = str(item.get("url", "")).strip()
        label = str(item.get("label", "")).strip()
        if not rid or not url:
            continue
        out.append(
            {
                "id": rid,
                "url": url,
                "label": label or rid,
                "trusted": bool(item.get("trusted", False)),
            }
        )
    return out


def prepend_archive_password(settings: RezeptorSettings, password: str) -> bool:
    """Prepend a working password to the global list (JDownloader-style). Returns True if changed."""
    pw = (password or "").strip()
    if not pw:
        return False
    existing = [p for p in settings.archive_passwords if p != pw]
    new_list = [pw, *existing]
    if new_list == settings.archive_passwords:
        return False
    settings.archive_passwords = new_list
    return True


def recipe_edit_allowed(settings: RezeptorSettings | None = None) -> bool:
    """True when REZEPTOR_DEV=1 or settings.developer_mode (recipe view save)."""
    if os.environ.get("REZEPTOR_DEV", "").lower() in ("1", "true", "yes"):
        return True
    return bool(settings and settings.developer_mode)


def _ensure_settings_dir() -> None:
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(SETTINGS_DIR, 0o700)
    except OSError:
        pass


def _atomic_write_bytes(path: Path, data: bytes, mode: int = 0o600) -> None:
    _ensure_settings_dir()
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(SETTINGS_DIR))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
        try:
            os.chmod(path, mode)
        except OSError:
            pass
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def _atomic_write_text(path: Path, text: str, mode: int = 0o600) -> None:
    _atomic_write_bytes(path, text.encode("utf-8"), mode=mode)


def _try_fernet():
    try:
        from cryptography.fernet import Fernet

        return Fernet
    except ImportError:
        return None


def _fernet_key() -> bytes | None:
    Fernet = _try_fernet()
    if Fernet is None:
        return None
    if ARCHIVE_PASSWORDS_KEY_FILE.is_file():
        try:
            key = ARCHIVE_PASSWORDS_KEY_FILE.read_bytes().strip()
            if key:
                return key
        except OSError:
            return None
    key = Fernet.generate_key()
    try:
        _atomic_write_bytes(ARCHIVE_PASSWORDS_KEY_FILE, key + b"\n", mode=0o600)
    except OSError:
        return None
    return key


def _encrypt_passwords_blob(passwords: list[str]) -> dict:
    """Return JSON-serializable secrets payload (Fernet when available)."""
    plain = json.dumps({"passwords": passwords}, ensure_ascii=False).encode("utf-8")
    Fernet = _try_fernet()
    key = _fernet_key() if Fernet is not None else None
    if Fernet is not None and key is not None:
        token = Fernet(key).encrypt(plain).decode("ascii")
        return {"version": 1, "enc": "fernet", "payload": token}
    return {"version": 1, "enc": "plain", "passwords": passwords}


def _decrypt_passwords_blob(data: dict) -> list[str]:
    enc = str(data.get("enc", "plain")).strip().lower()
    if enc == "fernet":
        Fernet = _try_fernet()
        key = _fernet_key() if Fernet is not None else None
        payload = str(data.get("payload", "") or "").strip()
        if Fernet is None or key is None or not payload:
            return []
        try:
            raw = Fernet(key).decrypt(payload.encode("ascii"))
            inner = json.loads(raw.decode("utf-8"))
            return _parse_str_list(inner.get("passwords") if isinstance(inner, dict) else None)
        except Exception:
            return []
    return _parse_str_list(data.get("passwords"))


def _load_archive_passwords_file() -> list[str]:
    if not ARCHIVE_PASSWORDS_FILE.is_file():
        return []
    try:
        data = json.loads(ARCHIVE_PASSWORDS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    if isinstance(data, list):
        return _parse_str_list(data)
    if isinstance(data, dict):
        return _decrypt_passwords_blob(data)
    return []


def _save_archive_passwords(passwords: list[str]) -> None:
    cleaned = _parse_str_list(passwords)
    blob = _encrypt_passwords_blob(cleaned)
    _atomic_write_text(
        ARCHIVE_PASSWORDS_FILE,
        json.dumps(blob, indent=2, ensure_ascii=False) + "\n",
        mode=0o600,
    )


def load_settings() -> RezeptorSettings:
    if not SETTINGS_FILE.is_file():
        s = RezeptorSettings(locale=_default_locale())
        s.archive_passwords = _load_archive_passwords_file()
        return s
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return RezeptorSettings(locale=_default_locale())
    if not isinstance(data, dict):
        return RezeptorSettings(locale=_default_locale())

    locale = str(data.get("locale", "")).strip() or _default_locale()
    # Früher system/light → immer Standard (dark)
    theme = str(data.get("theme", "dark")).strip().lower()
    if theme != "dark":
        theme = "dark"
    tab = str(data.get("content_tab", "overview") or "overview").strip()
    if tab not in ("overview", "progress", "logs"):
        tab = "overview"

    # Secrets: dedicated file preferred; migrate plaintext out of settings.json.
    passwords = _load_archive_passwords_file()
    legacy = _parse_str_list(data.get("archive_passwords"))
    migrated = False
    if legacy:
        if not passwords:
            passwords = legacy
        migrated = True

    settings = RezeptorSettings(
        schema_version=max(
            1, int(data.get("schema_version", SETTINGS_SCHEMA_VERSION))
        ),
        log_retention_days=max(1, min(365, int(data.get("log_retention_days", 14)))),
        log_max_files=max(5, min(500, int(data.get("log_max_files", 50)))),
        prune_logs_on_startup=bool(data.get("prune_logs_on_startup", True)),
        validate_on_startup=bool(data.get("validate_on_startup", True)),
        locale=locale,
        theme=theme,
        last_recipe_id=str(data.get("last_recipe_id", "") or "").strip(),
        developer_mode=bool(data.get("developer_mode", False)),
        hidden_recipe_ids=_parse_str_list(data.get("hidden_recipe_ids")),
        recipe_order=_parse_str_list(data.get("recipe_order")),
        custom_category_order=_parse_str_list(data.get("custom_category_order")),
        recipe_category_overrides=_parse_str_dict(data.get("recipe_category_overrides")),
        recipe_sources=_parse_recipe_sources(data.get("recipe_sources")),
        archive_passwords=passwords,
        recipe_install_env=_parse_recipe_install_env(data.get("recipe_install_env")),
        host_deps_prompt_done=bool(data.get("host_deps_prompt_done", False)),
        window_geometry=str(data.get("window_geometry", "") or ""),
        window_maximized=bool(data.get("window_maximized", False)),
        splitter_state=str(data.get("splitter_state", "") or ""),
        content_tab=tab,
        recipe_view_geometry=str(data.get("recipe_view_geometry", "") or ""),
        docs_geometry=str(data.get("docs_geometry", "") or ""),
        settings_geometry=str(data.get("settings_geometry", "") or ""),
    )
    if migrated:
        # Persist secrets file and strip plaintext from settings.json.
        save_settings(settings)
    return settings


def save_settings(settings: RezeptorSettings) -> None:
    _ensure_settings_dir()
    if not settings.locale:
        settings.locale = _default_locale()
    data = asdict(settings)
    passwords = _parse_str_list(data.pop("archive_passwords", []))
    settings.archive_passwords = passwords
    _atomic_write_text(
        SETTINGS_FILE,
        json.dumps(data, indent=2, sort_keys=True) + "\n",
        mode=0o600,
    )
    _save_archive_passwords(passwords)
