#!/usr/bin/env bash
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load repair

output::progress_begin 2 "Reparatur"
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Validate OK — nichts zu reparieren"
    exit 0
fi

output::step "Launcher erneut prüfen"
script="$(recipe_hooks::state_get SCRIPT_PATH 2>/dev/null || true)"
compat="$(recipe_hooks::state_get COMPATDATA 2>/dev/null || true)"
trainer="$(recipe_hooks::state_get TRAINER_EXE 2>/dev/null || true)"
appid="$(recipe_hooks::state_get STEAM_APPID 2>/dev/null || true)"
[ -n "$appid" ] || appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 694280)"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

if [ -n "$script" ] && [ -f "$script" ] && [ -n "$trainer" ] && [ -f "$trainer" ]; then
    proton=""
    if type wine_runtime::resolve_compatdata_proton_script >/dev/null 2>&1; then
        proton="$(wine_runtime::resolve_compatdata_proton_script "$steam_root" "$compat" 2>/dev/null || true)"
    fi
    if [ -n "$proton" ] && [ -f "$proton" ]; then
        q_steam="$(printf '%q' "$steam_root")"
        q_compat="$(printf '%q' "$compat")"
        q_proton="$(printf '%q' "$proton")"
        q_trainer="$(printf '%q' "$trainer")"
        cat >"$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
APPID=$appid
STEAM_ROOT=$q_steam
COMPATDATA=$q_compat
PROTON=$q_proton
TRAINER=$q_trainer
if [[ ! -f "\$PROTON" ]]; then
  echo "Proton nicht gefunden: \$PROTON" >&2
  exit 1
fi
if [[ ! -f "\$TRAINER" ]]; then
  echo "Trainer nicht gefunden: \$TRAINER" >&2
  exit 1
fi
if [[ -z "\$COMPATDATA" || ! -d "\$COMPATDATA" ]]; then
  echo "Steam compatdata für AppID \$APPID fehlt." >&2
  exit 1
fi
if ! pgrep -f 'za4_(vulkan|dx12)\\.exe' >/dev/null 2>&1; then
  echo "Hinweis: ZA4 scheint nicht zu laufen. Trainer erst NACH dem Spielstart ausführen."
fi
export STEAM_COMPAT_CLIENT_INSTALL_PATH="\$STEAM_ROOT"
export STEAM_COMPAT_DATA_PATH="\$COMPATDATA"
unset PROTON_ENABLE_WAYLAND || true
exec "\$PROTON" run "\$TRAINER"
EOF
        chmod +x "$script" || true
        recipe_hooks::state_set PROTON "$proton"
        output::info "Launch-Wrapper: $proton"
    else
        chmod +x "$script" || true
    fi
elif [ -n "$script" ] && [ -f "$script" ]; then
    chmod +x "$script" || true
fi
if bash "$RECIPE_DIR/validate.sh"; then
    output::progress_done "Reparatur OK"
    exit 0
fi
output::progress_done "Reparatur unvollständig — Installieren erneut ausführen"
exit 1
