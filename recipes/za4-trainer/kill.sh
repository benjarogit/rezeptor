#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill

output::section "ZA4 Trainer beenden"

# Nur Trainer — niemals wineserver -k am Spiel-Prefix
pkill -f 'ZA4-Trainer\.exe' 2>/dev/null || true
pkill -f 'za4-trainer-run\.sh' 2>/dev/null || true
pkill -f 'proton run .*/ZA4-Trainer' 2>/dev/null || true
sleep 0.4
pkill -9 -f 'ZA4-Trainer\.exe' 2>/dev/null || true

output::success "ZA4 Trainer beendet (Spiel-Prefix unangetastet)"
