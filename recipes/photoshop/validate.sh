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
source "$CORE_DIR/recipe-validate.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/sharedFuncs.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/wine-runtime.sh"

export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"
export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"

failures=0

if recipe_validate::prefix_initialized "$WINE_PREFIX"; then
    recipe_validate::ok "Wine-Prefix initialisiert ($WINE_PREFIX)"
else
    recipe_validate::fail "Wine-Prefix fehlt oder leer ($WINE_PREFIX)"
    failures=$((failures + 1))
fi

msxml3="$WINE_PREFIX/drive_c/windows/syswow64/msxml3.dll"
msxml6="$WINE_PREFIX/drive_c/windows/syswow64/msxml6.dll"
if recipe_validate::msxml_is_native "$msxml3" && recipe_validate::msxml_is_native "$msxml6"; then
    recipe_validate::ok "Native MSXML3/MSXML6 (Adobe-Installer)"
else
    recipe_validate::fail "MSXML nicht nativ — Adobe-Installer bricht ab (winetricks msxml3 msxml6)"
    failures=$((failures + 1))
fi

if recipe_validate::graphics_dlls_present "$WINE_PREFIX"; then
    recipe_validate::ok "Grafik-DLLs (vkd3d/DXVK) im Prefix"
else
    recipe_validate::warn "Grafik-DLLs fehlen — Launcher → Reparieren"
fi

if photoshop_exe="$(photoshop::find_exe "$WINE_PREFIX" 2>/dev/null)"; then
    recipe_validate::ok "Photoshop: $photoshop_exe"
    _guaranteed="$(recipe_get "$RECIPE_DIR/recipe.yml" version_guaranteed || true)"
    _ps_ver="$(recipe_validate::photoshop_app_version "$photoshop_exe" || true)"
    recipe_validate::version_guaranteed_check "$_guaranteed" "$_ps_ver" "Photoshop-Version"
else
    recipe_validate::fail "Photoshop.exe nicht gefunden"
    failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
    exit 0
fi
exit 1
