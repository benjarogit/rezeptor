#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load launch
recipe_hooks::_source recipe-winetricks.sh
recipe_hooks::_source recipe-dotnet.sh

recipe_hooks::runtime_init || exit 1
if ! recipe_dotnet::ensure "$(wine_software_logs_dir)/wiso_launch_mono.log"; then
    recipe_hooks::die "Wine-Mono fehlt — Rezeptor → Reparieren (bei Dialog „Installieren“ klicken)"
fi
recipe_hooks::_source recipe-fonts.sh
recipe_hooks::_source recipe-guard.sh
export WINEPREFIX="$DATA_ROOT/prefix"
export FREETYPE_PROPERTIES="${FREETYPE_PROPERTIES:-truetype:interpreter-version=35,lcdfilter:default}"
# Beim Start nur ClearType/DPI — kein winetricks (gehört in Reparieren).
recipe_fonts::registry
# Header/Sidebar-Überlappung: DPI 96 + Qt High-DPI aus
recipe_wiso::apply_ui_layout_fix
if recipe_wiso::restore_wined3d_prefix; then
    :
else
    echo "⚠ wined3d-Wiederherstellung fehlgeschlagen — Rezeptor → Reparieren" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: restore_wined3d_prefix fehlgeschlagen — Reparieren" \
        >> "${DATA_ROOT}/wiso-runtime.log" 2>/dev/null || true
fi
recipe_wiso::ensure_graphics_x11 "$WINE"

WISO_PORTABLE_ROOT=""
if [ -f "$DATA_ROOT/portable.env" ]; then
    WISO_PORTABLE_ROOT="$(env_file_get "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT || true)"
fi
if [ -z "$WISO_PORTABLE_ROOT" ] || [ ! -d "$WISO_PORTABLE_ROOT" ]; then
    recipe_hooks::die "Portable nicht konfiguriert — zuerst installieren"
fi

export WISO_PORTABLE_ROOT WINE

cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$DATA_ROOT/bin/wiso-launch.sh"
chmod +x "$DATA_ROOT/bin/wiso-launch.sh"

if [ ! -x "$DATA_ROOT/bin/wiso-launch.sh" ]; then
    recipe_hooks::die "Fehlt $DATA_ROOT/bin/wiso-launch.sh — Installation wiederholen"
fi

exec bash "$DATA_ROOT/bin/wiso-launch.sh" "$@"
