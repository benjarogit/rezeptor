#!/usr/bin/env bash
# Wine-Mono still installieren — vor jedem wine-Aufruf (blockiert sonst mit Dialog).
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
wine() { wine_runtime::wine "$@"; }
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-winetricks.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-dotnet.sh"

export WINEPREFIX="${WINEPREFIX:-$DATA_ROOT/prefix}"
export WINEARCH=win64

wine_runtime::init || exit 1
wine_runtime::export_env

_log_dir="$(wine_software_logs_dir 2>/dev/null || echo /tmp)"
mkdir -p "$_log_dir"
recipe_dotnet::ensure "$_log_dir/wine_mono_ensure.log"
