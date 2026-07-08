#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
CORE_DIR="$PROJECT_ROOT/core"
export PROJECT_ROOT RECIPE_DIR CORE_DIR

source "$CORE_DIR/paths.sh"
source "$CORE_DIR/recipe.sh"
recipe_export_env "$RECIPE_DIR/recipe.yml"
source "$CORE_DIR/env-file.sh" 2>/dev/null || true

export SCR_PATH="$DATA_ROOT"
echo "Deinstalliere WISO Rezept …"
pkill -f "wiso.*${DATA_ROOT}" 2>/dev/null || true
[ -d "$DATA_ROOT/prefix" ] && rm -rf "$DATA_ROOT/prefix"
rm -f "$DATA_ROOT/portable.env" "$DATA_ROOT/bin/wiso-launch.sh"
echo "✓ WISO Rezept entfernt (Portable-Ordner bleibt unberührt)"
