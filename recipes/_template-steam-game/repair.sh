#!/usr/bin/env bash
# Steam-Template: Wrapper neu schreiben = Install erneut (BYOS, kein Kopieren).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$RECIPE_DIR/install.sh" "$@"
