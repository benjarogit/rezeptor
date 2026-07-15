#!/usr/bin/env bash
# Validate → bei Fehlern Wrapper/Pfade erneut aus GAME_DIR schreiben (kein Reinstall des Spiels).
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

output::progress_begin 3 "Reparatur"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    exit 0
fi

output::progress_tick "Spielordner / Wrapper"
game_dir="$(recipe_hooks::state_get GAME_DIR 2>/dev/null || true)"
[ -n "$game_dir" ] || game_dir="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -z "$game_dir" ] || [ ! -d "$game_dir" ]; then
    output::progress_done "Spielordner unbekannt — Installieren erneut (Ordner wählen)"
    exit 1
fi

export RECIPE_SOURCE_ROOT="$game_dir"
if ! bash "$RECIPE_DIR/install.sh"; then
    output::progress_done "Reparatur fehlgeschlagen"
    exit 1
fi

if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig — Fix-Dateien prüfen"
exit 1
