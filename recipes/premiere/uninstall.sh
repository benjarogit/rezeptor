#!/usr/bin/env bash
# Rezeptor: Prefix + Desktop/Icons + Datenordner entfernen. Proton-GE (shared) bleibt.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal

output::section "Premiere deinstallieren"
output::progress_begin 3 "Deinstallation"

output::progress_tick "Prozesse beenden"
pkill -f "Adobe Premiere Pro.exe" 2>/dev/null || true
pkill -f "premiere/launch.sh" 2>/dev/null || true
pkill -9 -f "Adobe Premiere Pro.exe" 2>/dev/null || true

output::progress_tick "Desktop, Icons & Daten"
recipe_hooks::purge_recipe_data

output::progress_tick "Fertig"
output::progress_done "Premiere deinstalliert"
output::success "Premiere-Rezept entfernt (Proton-GE unter ~/.local/share/wine-software/runtime/ bleibt)"
