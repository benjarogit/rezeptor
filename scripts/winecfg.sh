#!/usr/bin/env bash
# Wine configuration for Photoshop prefix — uses core/ only.
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/core"
export PROJECT_ROOT="$ROOT" CORE_DIR="$CORE"

# shellcheck source=/dev/null
source "$CORE/paths.sh"
# shellcheck source=/dev/null
source "$CORE/security.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$CORE/sharedFuncs.sh"
# shellcheck source=/dev/null
source "$CORE/wine-runtime.sh"

export WINE_METHOD="${WINE_METHOD:-proton-ge}"
wine() { wine_runtime::wine "$@"; }

main() {
    if load_paths "true" 2>/dev/null && [ -n "$SCR_PATH" ] && [ -d "$SCR_PATH/prefix" ]; then
        RESOURCES_PATH="$SCR_PATH/resources"
        WINE_PREFIX="$SCR_PATH/prefix"
        if command -v security::validate_path >/dev/null 2>&1; then
            security::validate_path "$WINE_PREFIX" || exit 1
        fi
        export WINEPREFIX="$WINE_PREFIX"
    else
        SCR_PATH="$(recipe_data_root photoshop 2>/dev/null || echo "$HOME/.local/share/wine-software/photoshop")"
        WINE_PREFIX="$SCR_PATH/prefix"
        export WINEPREFIX="$WINE_PREFIX"
        if [ ! -d "$WINEPREFIX" ]; then
            echo "Photoshop prefix not found: $WINEPREFIX" >&2
            echo "Install first: ./setup.sh → Photoshop → Installieren" >&2
            exit 1
        fi
    fi

    wine_runtime::init || exit 1
    wine_runtime::export_env
    exec wine winecfg
}

main "$@"
