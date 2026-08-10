"""Per-recipe options (Medizin menu): declare in recipe.yml, persist in options.env."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from version_detect import load_recipe_mapping

_ENV_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


@dataclass
class RecipeOptionPick:
    """Optional path picker attached to a bool option (e.g. trainer BYOS)."""

    kind: str  # file_or_folder
    dest_rel: str  # relative to data_root
    source_env: str = ""  # optional path stored in options.env


@dataclass
class RecipeOptionChoice:
    """One value for ``type: choice`` (stored as string in options.env)."""

    id: str
    label: dict[str, str]

    def label_for(self, locale: str) -> str:
        code = (locale or "de").split("-", 1)[0].lower()
        return (
            self.label.get(code)
            or self.label.get("en")
            or self.label.get("de")
            or self.id
        )


@dataclass
class RecipeOption:
    id: str
    env: str
    type: str  # bool | choice
    default: bool | str
    label: dict[str, str]
    tip: dict[str, str]
    when: str = ""  # "", "nvidia", "steam"
    group: str = ""  # "", "runtime", "graphics", "mods" — Medizin tabs
    pick: RecipeOptionPick | None = None
    choices: list[RecipeOptionChoice] = field(default_factory=list)

    def label_for(self, locale: str) -> str:
        code = (locale or "de").split("-", 1)[0].lower()
        return (
            self.label.get(code)
            or self.label.get("en")
            or self.label.get("de")
            or self.id
        )

    def tip_for(self, locale: str) -> str:
        code = (locale or "de").split("-", 1)[0].lower()
        return self.tip.get(code) or self.tip.get("en") or self.tip.get("de") or ""


def options_env_path(data_root: Path) -> Path:
    return data_root / "options.env"


_PS_UI_ENVS = (
    "PHOTOSHOP_UI_HOME_SCREEN",
    "PHOTOSHOP_UI_RICH_TOOLTIPS",
    "PHOTOSHOP_UI_MODERN_NEW",
)


def migrate_photoshop_windows_like_ui(data_root: Path) -> bool:
    """Expand legacy PHOTOSHOP_WINDOWS_LIKE_UI=1 into the three UI toggles once."""
    path = options_env_path(data_root)
    if not path.is_file():
        return False
    stored = _parse_env_file(path)
    legacy = _as_bool(stored.get("PHOTOSHOP_WINDOWS_LIKE_UI"), False)
    if not legacy:
        return False
    if any(k in stored for k in _PS_UI_ENVS):
        return False
    for env in _PS_UI_ENVS:
        write_option_value(
            data_root,
            RecipeOption(
                id=env.lower(),
                env=env,
                type="bool",
                default=False,
                label={},
                tip={},
            ),
            True,
        )
    return True


def host_has_nvidia() -> bool:
    if shutil.which("nvidia-smi"):
        try:
            r = subprocess.run(
                ["nvidia-smi", "-L"],
                capture_output=True,
                timeout=5,
                check=False,
            )
            if r.returncode == 0:
                return True
        except (OSError, subprocess.TimeoutExpired):
            pass
    if Path("/dev/nvidia0").exists() or Path("/dev/nvidiactl").exists():
        return True
    return False


def _as_bool(val: Any, default: bool = True) -> bool:
    if val is None:
        return default
    if isinstance(val, bool):
        return val
    s = str(val).strip().lower()
    if s in ("1", "true", "yes", "on"):
        return True
    if s in ("0", "false", "no", "off"):
        return False
    return default


def _lang_map(raw: Any) -> dict[str, str]:
    if isinstance(raw, dict):
        out: dict[str, str] = {}
        for k, v in raw.items():
            s = str(v).strip()
            if s:
                out[str(k).strip().lower()] = s
        return out
    if isinstance(raw, str) and raw.strip():
        return {"de": raw.strip(), "en": raw.strip()}
    return {}


def parse_recipe_options(recipe_yml: Path | dict[str, Any]) -> list[RecipeOption]:
    """Load ``options:`` list from recipe.yml path or already-loaded mapping."""
    if isinstance(recipe_yml, dict):
        raw = recipe_yml
    else:
        if not recipe_yml.is_file():
            return []
        raw = load_recipe_mapping(recipe_yml)
    items = raw.get("options")
    if not isinstance(items, list):
        return []
    out: list[RecipeOption] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        oid = str(item.get("id") or "").strip()
        env = str(item.get("env") or "").strip()
        if not oid or not _ENV_KEY_RE.match(env):
            continue
        otype = str(item.get("type") or "bool").strip().lower()
        if otype not in ("bool", "choice"):
            continue
        grp = str(item.get("group") or "").strip().lower()
        if grp not in ("", "runtime", "graphics", "mods"):
            grp = ""
        pick = _parse_pick(item.get("pick"))
        choices = _parse_choices(item.get("choices"))
        if otype == "choice":
            if not choices:
                continue
            default_raw = item.get("default")
            default: bool | str = (
                str(default_raw).strip()
                if default_raw is not None and str(default_raw).strip()
                else choices[0].id
            )
            # Ensure default is one of the declared ids (or keep for dynamic catalogs).
            ids = {c.id for c in choices}
            if default not in ids:
                default = choices[0].id
        else:
            default = _as_bool(item.get("default"), True)
        out.append(
            RecipeOption(
                id=oid,
                env=env,
                type=otype,
                default=default,
                label=_lang_map(item.get("label")),
                tip=_lang_map(item.get("tip") or item.get("tooltip")),
                when=str(item.get("when") or "").strip().lower(),
                group=grp,
                pick=pick if otype == "bool" else None,
                choices=choices if otype == "choice" else [],
            )
        )
    return out


def _parse_choices(raw: Any) -> list[RecipeOptionChoice]:
    if not isinstance(raw, list):
        return []
    out: list[RecipeOptionChoice] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        cid = str(item.get("id") or "").strip()
        if not cid:
            continue
        out.append(
            RecipeOptionChoice(id=cid, label=_lang_map(item.get("label")))
        )
    return out


def _parse_pick(raw: Any) -> RecipeOptionPick | None:
    if not isinstance(raw, dict):
        return None
    kind = str(raw.get("kind") or "").strip().lower()
    dest = str(raw.get("dest_rel") or "").strip().lstrip("/")
    if kind != "file_or_folder" or not dest or ".." in dest.split("/"):
        return None
    source_env = str(raw.get("source_env") or "").strip()
    if source_env and not _ENV_KEY_RE.match(source_env):
        source_env = ""
    return RecipeOptionPick(kind=kind, dest_rel=dest, source_env=source_env)


def option_visible(opt: RecipeOption) -> bool:
    if opt.when == "nvidia":
        return host_has_nvidia()
    if opt.when == "steam":
        try:
            from steam_paths import steam_roots

            return bool(steam_roots())
        except Exception:
            return False
    return True


def _parse_env_file(path: Path) -> dict[str, str]:
    """Read key=value (printf %q or bare) — same tolerance as launcher recipe.env."""
    data: dict[str, str] = {}
    if not path.is_file():
        return data
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return data
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        key = key.strip()
        if not _ENV_KEY_RE.match(key):
            continue
        val = raw.strip()
        # printf %q: quoted or backslash-escaped (same as launcher recipe.env)
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
            val = val[1:-1]
        else:
            val = (
                val.replace("\\ ", " ")
                .replace("\\'", "'")
                .replace('\\"', '"')
                .replace("\\\\", "\\")
            )
        data[key] = val
    return data


def read_option_values(
    data_root: Path, options: list[RecipeOption]
) -> dict[str, bool | str]:
    """Effective values: options.env overrides default (bool or choice string)."""
    stored = _parse_env_file(options_env_path(data_root))
    result: dict[str, bool | str] = {}
    for opt in options:
        if opt.type == "choice":
            if opt.env in stored and str(stored[opt.env]).strip():
                result[opt.id] = str(stored[opt.env]).strip()
            else:
                result[opt.id] = str(opt.default)
            continue
        if opt.env in stored:
            result[opt.id] = _as_bool(stored[opt.env], bool(opt.default))
        else:
            result[opt.id] = bool(opt.default)
    return result


def _env_file_write(data_root: Path, key: str, value: str) -> None:
    """Persist one key=value in options.env via env_file_set or plain rewrite."""
    if not _ENV_KEY_RE.match(key):
        raise ValueError(f"invalid env key: {key}")
    data_root.mkdir(parents=True, exist_ok=True)
    path = options_env_path(data_root)
    root = Path(__file__).resolve().parent.parent
    env_sh = root / "core" / "env-file.sh"
    if env_sh.is_file() and shutil.which("bash"):
        # Pass path/key/value as argv — safe for spaces in trainer paths.
        script = 'source "$1" && env_file_set "$2" "$3" "$4"'
        try:
            subprocess.run(
                [
                    "bash",
                    "-c",
                    script,
                    "_",
                    str(env_sh),
                    str(path),
                    key,
                    value,
                ],
                check=True,
                capture_output=True,
                timeout=10,
            )
            return
        except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError):
            pass
    cur = _parse_env_file(path)
    cur[key] = value
    tmp = path.with_suffix(".env.tmp")
    lines = [f"{k}={v}\n" for k, v in sorted(cur.items())]
    tmp.write_text("".join(lines), encoding="utf-8")
    tmp.replace(path)


def write_option_value(
    data_root: Path, opt: RecipeOption, enabled: bool | str
) -> None:
    """Persist one option (bool as 1/0, choice as string)."""
    if opt.type == "choice":
        _env_file_write(data_root, opt.env, str(enabled).strip())
        return
    _env_file_write(data_root, opt.env, "1" if enabled else "0")


def write_option_env(data_root: Path, key: str, value: str) -> None:
    """Persist an arbitrary options.env string (e.g. trainer source path)."""
    _env_file_write(data_root, key, value)


def env_overrides_for_options(
    data_root: Path, options: list[RecipeOption]
) -> dict[str, str]:
    """Env map to inject into recipe subprocesses (visible options only)."""
    values = read_option_values(data_root, options)
    out: dict[str, str] = {}
    for opt in options:
        if not option_visible(opt):
            continue
        if opt.type == "choice":
            out[opt.env] = str(values.get(opt.id, opt.default))
            continue
        out[opt.env] = "1" if values.get(opt.id, opt.default) else "0"
    return out


def load_options_from_recipe_dir(recipe_dir: Path) -> list[RecipeOption]:
    return parse_recipe_options(recipe_dir / "recipe.yml")
