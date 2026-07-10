#!/usr/bin/env bash
# Rezeptor: Prefix + Desktop/Icons entfernen. Proton-GE (shared runtime) bleibt.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill
recipe_hooks::_source env-file.sh

export SCR_PATH="$DATA_ROOT"
export WINE_PREFIX="$DATA_ROOT/prefix"

output::section "Photoshop deinstallieren"
output::progress_begin 3 "Deinstallation"

output::progress_tick "Prozesse beenden"
recipe_kill::run "$WINEPREFIX" "Photoshop.exe" "Adobe Photoshop" || true
pkill -f "photoshop/launch.sh" 2>/dev/null || true

output::progress_tick "Desktop & Icons"
app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icon_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
for entry in \
    "$app_dir/photoshop.desktop" \
    "$app_dir/Adobe Photoshop 2021.desktop" \
    "$app_dir/Adobe Photoshop.desktop" \
    "$app_dir/photoshopCC.desktop"; do
    [ -f "$entry" ] && rm -f "$entry"
done
if [ -d "$app_dir/wine" ]; then
    find "$app_dir/wine" -type f \( -iname '*photoshop*' \) -delete 2>/dev/null || true
fi
for desk in "$(xdg-user-dir DESKTOP 2>/dev/null || true)" "$HOME/Schreibtisch" "$HOME/Desktop"; do
    [ -n "$desk" ] && [ -d "$desk" ] || continue
    find "$desk" -maxdepth 1 -type f \( -iname '*photoshop*' \) -delete 2>/dev/null || true
done
for size in 16 22 24 32 48 64 128 256 512; do
    rm -f "$icon_dir/${size}x${size}/apps/photoshop.png" 2>/dev/null || true
done
rm -f "$icon_dir/scalable/apps/photoshop.svg" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && [ -d "$icon_dir" ] && gtk-update-icon-cache -f -t "$icon_dir" 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$app_dir" 2>/dev/null || true

output::progress_tick "Datenordner"
if [ -d "$DATA_ROOT" ]; then
    rm -rf "$DATA_ROOT"
    output::success "Entfernt: $DATA_ROOT"
else
    output::success "Kein Rezept-Datenordner ($DATA_ROOT)"
fi

output::progress_done "Photoshop deinstalliert"
output::success "Photoshop Rezept deinstalliert (Proton-GE unter ~/.local/share/wine-software/runtime/ bleibt)"
