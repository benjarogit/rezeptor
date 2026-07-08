#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
export PROJECT_ROOT RECIPE_DIR CORE_DIR

# shellcheck source=/dev/null
source "$CORE_DIR/paths.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe.sh"
recipe_export_env "$RECIPE_DIR/recipe.yml"
# shellcheck source=/dev/null
source "$CORE_DIR/env-file.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/wine-runtime.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-wiso.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-winetricks.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-dotnet.sh"

export WINEPREFIX="$DATA_ROOT/prefix"
export WINEARCH=win64

wine() { wine_runtime::wine "$@"; }

wine_runtime::init || exit 1
wine_runtime::export_env
recipe_dotnet::ensure "$(wine_software_logs_dir)/wiso_launch_mono.log" 2>/dev/null || true
recipe_wiso::restore_wined3d_prefix 2>/dev/null || true
recipe_wiso::ensure_graphics_x11 "$WINE"

WISO_PORTABLE_ROOT=""
if [ -f "$DATA_ROOT/portable.env" ]; then
    WISO_PORTABLE_ROOT="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT || true)"
fi
if [ -z "$WISO_PORTABLE_ROOT" ] || [ ! -d "$WISO_PORTABLE_ROOT" ]; then
    echo "WISO portable root not configured. Run install first." >&2
    exit 1
fi

export WISO_PORTABLE_ROOT WINE

if [ ! -x "$DATA_ROOT/bin/wiso-launch.sh" ]; then
    echo "Missing $DATA_ROOT/bin/wiso-launch.sh — re-run install." >&2
    exit 1
fi

exec bash "$DATA_ROOT/bin/wiso-launch.sh" "$@"
