#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/core/recipe.sh"
recipe_export_env "$RECIPE_DIR/recipe.yml"
echo "Template install — ersetzen Sie dieses Skript." >&2
exit 1
