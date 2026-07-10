# Rezept-Authoring (Rezeptor)

Jedes Programm ist ein Rezept — **gleiches Muster**, kein Sonderfall.

## Community: Rezept in 4 Schritten

```bash
./scripts/new-recipe.sh meine-app "Meine App"
./scripts/new-recipe.sh adobe-tool "Mein Tool" --type installer
./scripts/recipe-lint.sh
REZEPTOR_DEV=1 ./setup.sh
./scripts/recipe-manifest.sh
```

Vorlagen: `recipes/_template/`, `recipes/_template-installer/`.  
Referenz: `wiso-steuer` (deklarative `install_steps`), `photoshop` (`module:`).

---

## Architektur

```
recipes/<id>/
  recipe.yml          ← Metadaten + install_steps
  install.sh          ← recipe_hooks::load + recipe_install_steps::run
  launch.sh / validate.sh / repair.sh / kill.sh

core/
  recipe-hooks.sh           ← Einstieg
  recipe-install-steps.sh   ← führt install_steps aus
  recipe-<id>.sh            ← App-Logik (module:)
recipes/recipe.schema.json  ← Vertrag
```

### install.sh (immer dünn)

```bash
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_install_steps::run
```

### `install_steps` (Pflicht)

```yaml
install_steps:
  - prepare_source
  - require_portable   # portable
  - prefix
  - winetricks         # aus winetricks: in yml
  - winetricks: [corefonts, gdiplus]
  - module: recipe_wiso::apply_wined3d
  - copy_asset:
      src: assets/foo.sh
      dest: "{data_root}/bin/foo.sh"
  - run_installer      # installer_offline
  - win10
  - fonts_registry
```

| Schritt | Rolle |
|---------|--------|
| `prepare_source` | Quelle → `RECIPE_WORK_ROOT` |
| `require_portable` | erwartet `portable_folder` |
| `prefix` | Proton + Prefix |
| `winetricks` | Pakete (yml oder Liste); `vcrun*`/`dotnet*`/`win10` speziell |
| `deploy_graphics` | Proton-Grafik-DLLs |
| `run_installer` | Setup.exe |
| `module` | `recipe_*::funktion` aus Core |
| `copy_asset` | Datei deployen |
| `env_set` | Key in portable.env / Datei |
| `stabilize_prefix` / `win10` / `fonts_registry` | Hilfsschritte |

Parser: `scripts/recipe-yaml-read.py` · Schema: `scripts/recipe-schema-check.py` (embedded; optional `jsonschema`).

---

## `recipe.yml` Pflicht

`id`, `name`, `data_root`, `runtime`, `install_type`, `source_kind`, `fix_kind`, Hooks, **`install_steps`**.

Schema: [`recipes/recipe.schema.json`](../../recipes/recipe.schema.json).

**Portable:**

```yaml
install_type: portable_launch
deploy_mode: copy
source_kind: folder
source_formats: zip,tar.gz,tgz
target_default: "~/Dokumente/Meine App"
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

## Qualität / CI

```bash
./scripts/recipe-lint.sh      # Hooks ERROR, install_steps, Schema
./scripts/recipe-manifest.sh
make recipe-lint              # CI
REZEPTOR_DEV=1 ./setup.sh
```

Verboten (Lint ERROR): `winetricks dxvk`, System-Wine-Fallback, doppeltes win10.

---

## Grafik-Apps — GPU

Siehe [GPU-EXPERIMENTS.md](../maintainer/de/GPU-EXPERIMENTS.md), [HANDOFF-PHOTOSHOP-GPU.md](../maintainer/de/HANDOFF-PHOTOSHOP-GPU.md).  
DXVK nur über `wine_runtime::deploy_proton_graphics_dlls` — **kein** winetricks-dxvk.

---

## Kernmodule

| Datei | Zweck |
|-------|--------|
| `recipe-hooks.sh` | Hook-Einstieg |
| `recipe-install-steps.sh` | Deklarative Installation |
| `recipe-install.sh` | prepare_source / apply_fix |
| `recipe-<id>.sh` | App-Logik |
| `wine-runtime.sh` | Proton-GE |
