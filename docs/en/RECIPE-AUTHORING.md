# Recipe authoring (Rezeptor)

Every app is a recipe — **one pattern**, no special cases.

## Community: recipe in 4 steps

```bash
./scripts/new-recipe.sh my-app "My App"
./scripts/new-recipe.sh adobe-tool "My Tool" --type installer
./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh
./scripts/recipe-manifest.sh
```

Templates: `recipes/_template/`, `recipes/_template-installer/`.  
Reference: `wiso-steuer` (full declarative `install_steps`), `photoshop` (`module:`).

---

## Architecture

```
recipes/<id>/
  recipe.yml          ← metadata + install_steps
  install.sh          ← recipe_hooks::load + recipe_install_steps::run
  launch.sh / validate.sh / repair.sh / kill.sh

core/
  recipe-hooks.sh           ← entry
  recipe-install-steps.sh   ← runs install_steps
  recipe-<id>.sh            ← app logic (module:)
recipes/recipe.schema.json  ← contract
```

### Thin install.sh

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_install_steps::run
```

### `install_steps` (required)

```yaml
install_steps:
  - prepare_source
  - require_portable   # portable
  - prefix
  - winetricks         # from winetricks: in yml
  - winetricks: [corefonts, gdiplus]
  - module: recipe_wiso::apply_wined3d
  - copy_asset:
      src: assets/foo.sh
      dest: "{data_root}/bin/foo.sh"
  - run_installer      # installer_offline
  - win10
  - fonts_registry
```

| Step | Role |
|------|------|
| `prepare_source` | Source → `RECIPE_WORK_ROOT` |
| `require_portable` | expects `portable_folder` |
| `prefix` | Proton + prefix |
| `winetricks` | packages (yml or list); `vcrun*`/`dotnet*`/`win10` special-cased |
| `deploy_graphics` | Proton graphics DLLs |
| `run_installer` | Setup.exe |
| `module` | `recipe_*::function` from core |
| `copy_asset` | deploy a file |
| `env_set` | key in portable.env / file |
| `stabilize_prefix` / `win10` / `fonts_registry` | helpers |

Parser: `scripts/recipe-yaml-read.py` · Schema: `scripts/recipe-schema-check.py` (embedded; optional `jsonschema`).

---

## Required `recipe.yml` fields

`id`, `name`, `data_root`, `runtime`, `install_type`, `source_kind`, `fix_kind`, hooks, **`install_steps`**.

Schema: [`recipes/recipe.schema.json`](../../recipes/recipe.schema.json).

**Portable:**

```yaml
install_type: portable_launch
deploy_mode: copy
source_kind: folder
source_formats: zip,tar.gz,tgz
target_default: "~/Documents/My App"
winetricks: [win10, vcrun2019]
install_steps:
  - prepare_source
  - require_portable
  - prefix
  - winetricks
```

**Installer:**

```yaml
install_type: installer_offline
source_kind: fixed_path
installer_dir: "{repo}/installer"
install_steps:
  - prepare_source
  - prefix
  - winetricks
  - run_installer
```

Tokens: `{repo}`, `{data_root}`, `{recipe}`, `~`.

---

## Quality / CI

```bash
./scripts/recipe-lint.sh      # hooks ERROR, install_steps, schema
./scripts/recipe-manifest.sh
make recipe-lint              # CI
REZEPTOR_DEV=1 ./setup.sh
```

Forbidden (lint ERROR): `winetricks dxvk`, system-Wine fallback, duplicate win10.

---

## GPU graphics apps

See [GPU-EXPERIMENTS.md](../maintainer/en/GPU-EXPERIMENTS.md), [HANDOFF-PHOTOSHOP-GPU.md](../maintainer/en/HANDOFF-PHOTOSHOP-GPU.md).  
DXVK only via `wine_runtime::deploy_proton_graphics_dlls` — **no** winetricks-dxvk.

---

## Core modules

| File | Role |
|------|------|
| `recipe-hooks.sh` | Hook entry |
| `recipe-install-steps.sh` | Declarative install |
| `recipe-install.sh` | prepare_source / apply_fix |
| `recipe-<id>.sh` | App logic |
| `wine-runtime.sh` | Proton-GE |
