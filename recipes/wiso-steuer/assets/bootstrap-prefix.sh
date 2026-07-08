#!/usr/bin/env bash
# Prefix wie wiso-steuer-portable-linux/setup-wine-prefix.sh (System-Wine).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
export PROJECT_ROOT RECIPE_DIR CORE_DIR

# shellcheck source=/dev/null
source "$CORE_DIR/paths.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe.sh"
recipe_export_env "$RECIPE_DIR/recipe.yml"
# shellcheck source=/dev/null
source "$CORE_DIR/wine-runtime.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-wiso.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-win10.sh"

export WINEPREFIX="${WINEPREFIX:-$DATA_ROOT/prefix}"
export WINEARCH=win64

wine_runtime::init || exit 1
wine_runtime::export_env

if ! command -v winetricks >/dev/null 2>&1; then
    echo "winetricks fehlt (pacman -S winetricks)" >&2
    exit 1
fi

wine() { wine_runtime::wine "$@"; }
wineboot() { wine_runtime::wineboot "$@"; }

mkdir -p "$(dirname "$WINEPREFIX")"
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    wineboot -i
else
    wine wineboot -u
fi

recipe_wiso::restore_wined3d_prefix 2>/dev/null || true
WINE="$WINE" winetricks -q vcrun2022 corefonts d3dcompiler_47 gdiplus
WINE="$WINE" winetricks -q settings win10
recipe_wiso::ensure_graphics_x11 "$WINE"
recipe_wiso::restore_wined3d_prefix 2>/dev/null || true

echo "Prefix bereit: $WINEPREFIX"
