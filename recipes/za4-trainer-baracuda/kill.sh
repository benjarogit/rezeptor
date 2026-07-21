#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load kill

output::section "ZA4 Baracuda Trainer beenden"

# Nur Trainer/CE — niemals wineserver -k am Spiel-Prefix (bricht ZA4 + nächsten Start)
pkill -f 'ZA4-Trainer-Baracuda\.exe' 2>/dev/null || true
pkill -f 'za4-trainer-baracuda-run\.sh' 2>/dev/null || true
pkill -f 'proton runinprefix .*/ZA4-Trainer-Baracuda' 2>/dev/null || true
pkill -f '[Cc]heat[Ee]ngine' 2>/dev/null || true
pkill -f 'CET_TRAINER' 2>/dev/null || true
sleep 0.4
pkill -9 -f 'ZA4-Trainer-Baracuda\.exe' 2>/dev/null || true
pkill -9 -f '[Cc]heat[Ee]ngine' 2>/dev/null || true

output::success "ZA4 Baracuda Trainer beendet (Spiel-Prefix unangetastet)"
