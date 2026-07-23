"""Per-recipe options (Medizin menu): declare in recipe.yml, persist in options.env."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from version_detect import load_recipe_mapping

_ENV_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


@dataclass
class RecipeOption:
    id: str
    env: str
    type: str  # bool
    default: bool
    label: dict[str, str]
    tip: dict[str, str]
    when: str = ""  # "", "nvidia"

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
        if otype != "bool":
            continue
        out.append(
            RecipeOption(
                id=oid,
                env=env,
                type=otype,
                default=_as_bool(item.get("default"), True),
                label=_lang_map(item.get("label")),
                tip=_lang_map(item.get("tip") or item.get("tooltip")),
                when=str(item.get("when") or "").strip().lower(),
            )
        )
    return out


def option_visible(opt: RecipeOption) -> bool:
    if opt.when == "nvidia":
        return host_has_nvidia()
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
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
            val = val[1:-1]
        data[key] = val
    return data


def read_option_values(data_root: Path, options: list[RecipeOption]) -> dict[str, bool]:
    """Effective bool values: options.env overrides default."""
    stored = _parse_env_file(options_env_path(data_root))
    result: dict[str, bool] = {}
    for opt in options:
        if opt.env in stored:
            result[opt.id] = _as_bool(stored[opt.env], opt.default)
        else:
            result[opt.id] = opt.default
    return result


def write_option_value(data_root: Path, opt: RecipeOption, enabled: bool) -> None:
    """Persist one bool option as 1/0 via env_file_set (bash) or plain write."""
    data_root.mkdir(parents=True, exist_ok=True)
    path = options_env_path(data_root)
    value = "1" if enabled else "0"
    # Prefer project env_file_set for %q safety when bash+core available
    root = Path(__file__).resolve().parent.parent
    env_sh = root / "core" / "env-file.sh"
    if env_sh.is_file() and shutil.which("bash"):
        script = (
            f'source "{env_sh}" && env_file_set "{path}" "{opt.env}" "{value}"'
        )
        try:
            subprocess.run(
                ["bash", "-c", script],
                check=True,
                capture_output=True,
                timeout=10,
            )
            return
        except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError):
            pass
    # Fallback: rewrite file
    cur = _parse_env_file(path)
    cur[opt.env] = value
    tmp = path.with_suffix(".env.tmp")
    lines = [f"{k}={v}\n" for k, v in sorted(cur.items())]
    tmp.write_text("".join(lines), encoding="utf-8")
    tmp.replace(path)


def env_overrides_for_options(
    data_root: Path, options: list[RecipeOption]
) -> dict[str, str]:
    """Env map to inject into recipe subprocesses (visible options only)."""
    values = read_option_values(data_root, options)
    out: dict[str, str] = {}
    for opt in options:
        if not option_visible(opt):
            continue
        out[opt.env] = "1" if values.get(opt.id, opt.default) else "0"
    return out


def load_options_from_recipe_dir(recipe_dir: Path) -> list[RecipeOption]:
    return parse_recipe_options(recipe_dir / "recipe.yml")
