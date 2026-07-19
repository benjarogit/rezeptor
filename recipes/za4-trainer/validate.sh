#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/wine-runtime.sh"

failures=0
output::progress_begin 4 "Prüfen"

script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
work="$(recipe_hooks::state_get WORK_ROOT 2>/dev/null || true)"
if [ -z "$trainer" ] && [ -n "$work" ] && [ -f "$work/ZA4-Trainer.exe" ]; then
    trainer="$work/ZA4-Trainer.exe"
fi

output::progress_tick "Trainer-EXE"
if [ -n "$trainer" ] && [ -f "$trainer" ]; then
    recipe_validate::ok "Trainer: $trainer"
else
    recipe_validate::fail "ZA4-Trainer.exe fehlt — bitte installieren"
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

output::progress_tick "Proton (compatdata)"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
expected_proton=""
if [ -n "$compat" ] && [ -d "$compat" ] && type wine_runtime::resolve_compatdata_proton_script >/dev/null 2>&1; then
    expected_proton="$(wine_runtime::resolve_compatdata_proton_script "$steam_root" "$compat" 2>/dev/null || true)"
fi
if [ -n "$script" ] && [ -x "$script" ] && [ -n "$expected_proton" ] && [ -f "$expected_proton" ]; then
    wrapper_proton="$(grep -m1 '^PROTON=' "$script" 2>/dev/null | sed 's/^PROTON=//' || true)"
    if [ -n "$wrapper_proton" ] && [ "$wrapper_proton" = "$expected_proton" ]; then
        recipe_validate::ok "Proton: $(basename "$(dirname "$expected_proton")")"
    elif [ -n "$wrapper_proton" ]; then
        recipe_validate::fail "Launch-Wrapper Proton veraltet ($(basename "$(dirname "$wrapper_proton")") → $(basename "$(dirname "$expected_proton")")) — Reparieren"
        failures=$((failures + 1))
    else
        recipe_validate::warn "Launch-Wrapper ohne PROTON-Zeile — Reparieren"
    fi
elif [ -n "$expected_proton" ] && [ -f "$expected_proton" ]; then
    recipe_validate::warn "Launch-Wrapper fehlt — Proton wäre $(basename "$(dirname "$expected_proton")")"
fi

if [ "$failures" -eq 0 ]; then
    output::progress_done "Prüfung OK"
    exit 0
fi
output::progress_done "Prüfung mit Fehlern"
exit 1
