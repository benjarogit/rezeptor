#!/usr/bin/env bash
# Legacy entry — delegates to recipe install
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT/recipes/photoshop/install.sh" "$@"
