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
_guaranteed="$(recipe_get "$RECIPE_DIR/recipe.yml" version_guaranteed || true)"
# shellcheck source=/dev/null
source "$CORE_DIR/env-file.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-validate.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-dotnet.sh"
# shellcheck source=/dev/null
source "$CORE_DIR/recipe-wiso.sh"

WISO_PORTABLE_ROOT=""
if [ -f "$DATA_ROOT/portable.env" ]; then
    WISO_PORTABLE_ROOT="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT || true)"
fi

export WINEPREFIX="$DATA_ROOT/prefix"
failures=0

if [ -n "$WISO_PORTABLE_ROOT" ] && [ -d "$WISO_PORTABLE_ROOT" ]; then
    recipe_validate::ok "Portable: $WISO_PORTABLE_ROOT"
    _wiso_ver="$(recipe_validate::wiso_portable_version "$WISO_PORTABLE_ROOT" || true)"
    if [ -z "$_wiso_ver" ] && [ -f "$DATA_ROOT/portable.env" ]; then
        _wiso_ver="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_VERSION || true)"
    fi
    recipe_validate::version_guaranteed_check "$_guaranteed" "$_wiso_ver" "WISO-Version"
else
    recipe_validate::fail "Portable fehlt (portable.env / WISO_PORTABLE_ROOT)"
    failures=$((failures + 1))
fi

if recipe_validate::prefix_initialized "$WINEPREFIX"; then
    recipe_validate::ok "Wine-Prefix ($WINEPREFIX)"
else
    recipe_validate::fail "Wine-Prefix fehlt"
    failures=$((failures + 1))
fi

wow64="$WINEPREFIX/drive_c/windows/syswow64"
if recipe_validate::vcrun_dll_ok "$wow64/msvcp140.dll" \
    || recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
    recipe_validate::ok "vcrun2019 (msvcp140.dll)"
else
    recipe_validate::fail "vcrun2019 fehlt — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::dll_exists "$wow64/gdiplus.dll"; then
    recipe_validate::ok "gdiplus"
else
    recipe_validate::fail "gdiplus fehlt — Reparieren"
    failures=$((failures + 1))
fi

if recipe_validate::windows_version "$WINEPREFIX" "win10"; then
    recipe_validate::ok "Windows-Version win10"
else
    recipe_validate::fail "win10 nicht gesetzt — Reparieren"
    failures=$((failures + 1))
fi

if recipe_dotnet::installed; then
    recipe_validate::ok "Wine-Mono / .NET"
else
    recipe_validate::fail "Wine-Mono fehlt — Reparieren"
    failures=$((failures + 1))
fi

if [ -x "$DATA_ROOT/bin/wiso-launch.sh" ]; then
    recipe_validate::ok "Launcher-Skript"
else
    recipe_validate::fail "wiso-launch.sh fehlt"
    failures=$((failures + 1))
fi

if [ -n "$WISO_PORTABLE_ROOT" ] && [ -d "$WISO_PORTABLE_ROOT" ]; then
    _sw_dir="$(recipe_wiso::software_dir "$WISO_PORTABLE_ROOT" || true)"
    if [ -n "$_sw_dir" ] && recipe_wiso::qnetwork_disabled "$_sw_dir"; then
        recipe_validate::ok "Wine-Startfix (qnetworklistmanager)"
    elif [ -n "$_sw_dir" ] && [ -f "$_sw_dir/networkinformation/qnetworklistmanager.dll" ]; then
        recipe_validate::fail "Wine-Startfix fehlt — Reparieren (qnetworklistmanager.dll)"
        failures=$((failures + 1))
    fi
fi

_font_n=$(find "$WINEPREFIX/drive_c/windows/Fonts" -maxdepth 1 -type f 2>/dev/null | wc -l)
if [ "$_font_n" -ge 5 ]; then
    recipe_validate::ok "Windows-Schriften ($_font_n)"
else
    recipe_validate::fail "Schriften fehlen (corefonts) — Reparieren"
    failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] && exit 0
exit 1
