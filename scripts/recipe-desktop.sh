#!/usr/bin/env bash
# CLI: Menü-/Desktop-Verknüpfung für ein Rezept anlegen oder entfernen.
# Usage: recipe-desktop.sh <install|remove|refresh> [recipe_dir]
set -eu
(set -o pipefail 2>/dev/null) || true

ACTION="${1:?install|remove|refresh}"
RECIPE_DIR="${2:-}"
if [ -z "$RECIPE_DIR" ]; then
    echo "ERROR: recipe_dir fehlt" >&2
    exit 2
fi
RECIPE_DIR="$(cd "$RECIPE_DIR" && pwd)"

# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal
recipe_hooks::_source recipe-desktop.sh

case "$ACTION" in
    install)
        recipe_desktop::install
        ;;
    remove)
        recipe_desktop::remove
        ;;
    refresh)
        recipe_desktop::refresh_if_present
        ;;
    *)
        echo "ERROR: Aktion '$ACTION' (install|remove|refresh)" >&2
        exit 2
        ;;
esac
