#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate

failures=0
output::progress_begin 3 "Prüfen"

script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -z "$trainer" ] && [ -n "$work" ] && [ -f "$work/ZA4-Trainer-Baracuda.exe" ]; then
    trainer="$work/ZA4-Trainer-Baracuda.exe"
fi

output::progress_tick "Trainer-EXE"
if [ -n "$trainer" ] && [ -f "$trainer" ]; then
    recipe_validate::ok "Trainer: $trainer"
else
    recipe_validate::fail "Baracuda-Trainer (ZA4-Trainer-Baracuda.exe) fehlt — bitte installieren"
    failures=$((failures + 1))
fi

output::progress_tick "Launch-Wrapper"
if [ -n "$script" ] && [ -x "$script" ]; then
    recipe_validate::ok "Wrapper: $script"
else
    recipe_validate::fail "Launch-Wrapper fehlt"
    failures=$((failures + 1))
fi

output::progress_tick "Steam compatdata"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 694280)"
if [ -n "$compat" ] && [ -d "$compat" ]; then
    recipe_validate::ok "compatdata: $compat"
elif [ -d "$HOME/.local/share/Steam/steamapps/compatdata/$appid" ]; then
    recipe_validate::warn "compatdata unter Standard-Steam — Wrapper ggf. neu installieren"
else
    recipe_validate::warn "compatdata AppID $appid nicht gefunden — Spiel einmal unter Proton starten"
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
