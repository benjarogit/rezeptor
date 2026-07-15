#!/usr/bin/env bash
# Prefix + Rezeptor-State entfernen. Portable-Ordner (Spiel/Steuer-Dateien) bleibt.

set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal

output::section "WISO deinstallieren"
output::progress_begin 3 "Deinstallation"
output::info "Portable-Ordner bleibt unberührt — nur Rezeptor-Prefix/State/Desktop."

output::progress_tick "Prozesse beenden"
pkill -f "wiso-launch.sh" 2>/dev/null || true
pkill -f "wiso-mit-wine.sh" 2>/dev/null || true
pkill -f "wisoakt.exe" 2>/dev/null || true
pkill -f "start.exe" 2>/dev/null || true

output::progress_tick "Desktop, Icons & Rezeptor-Daten"
recipe_hooks::purge_recipe_data

output::progress_tick "Fertig"
output::progress_done "WISO deinstalliert"
output::success "WISO Rezept entfernt (Portable-Ordner bleibt unberührt)"
