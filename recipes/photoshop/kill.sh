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
source "$CORE_DIR/wine-runtime.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-kill.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-guard.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/output.sh"

export WINEPREFIX="$DATA_ROOT/prefix"
wine_runtime::init 2>/dev/null || true

output::section "Photoshop beenden"
recipe_kill::run "$WINEPREFIX" "Photoshop.exe" "Adobe Photoshop"
recipe_kill::run "$WINEPREFIX" "wmain26.dll" "Photoshop (Wine)"
pkill -f "photoshop/launcher/launcher.sh" 2>/dev/null || true
recipe_guard::kill_stale_winetricks 2>/dev/null || pkill -f 'winetricks -q win10' 2>/dev/null || true
