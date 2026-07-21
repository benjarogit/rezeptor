#!/usr/bin/env bash
# Trainer-EXE nach Zielordner kopieren + Launch-Wrapper schreiben.
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load install
recipe_hooks::log_setup "ZA4_Trainer_Baracuda_Install"

src="${RECIPE_INSTALLER_PATH:-}"
[ -n "$src" ] && [ -f "$src" ] || recipe_hooks::die \
    "Bitte die Trainer-EXE im Install-Dialog wählen (*.exe)"

case "${src,,}" in
    *.exe) ;;
    *) recipe_hooks::die "Erwartet eine .exe — erhalten: $src" ;;
esac

target="${RECIPE_TARGET_DIR:-$DATA_ROOT/ZA4-Trainer-Baracuda}"
target="${target/#\~/$HOME}"
mkdir -p "$target"
base="$(basename "$src")"
# Kanonischer Name für Launch/Validate
dest="$target/ZA4-Trainer-Baracuda.exe"

output::section "ZA4 Baracuda +13 Trainer — Installation"
output::progress 10 "Trainer kopieren"
output::info "Quelle: $src"
output::info "Ziel: $dest"
cp -a "$src" "$dest"
chmod +x "$dest" 2>/dev/null || true
printf "%s\n" "$base" >"$target/.source-basename.txt" 2>/dev/null || true
output::info "Baracuda/Cheat-Engine: Spiel zuerst starten, dann Trainer."

# Steam / Proton-Pfade für Launch speichern
appid="$(recipe_get "$RECIPE_YML" steam_appid 2>/dev/null || echo 694280)"
steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
compat=""
for lib in "$steam_root" /mnt/*/SteamLibrary "$HOME"/.local/share/Steam; do
    [ -d "$lib/steamapps/compatdata/$appid" ] || continue
    compat="$lib/steamapps/compatdata/$appid"
    break
done
# libraryfolders: zusätzliche Libraries
if [ -z "$compat" ] && [ -f "$steam_root/steamapps/libraryfolders.vdf" ]; then
    while IFS= read -r p; do
        [ -d "$p/steamapps/compatdata/$appid" ] || continue
        compat="$p/steamapps/compatdata/$appid"
        break
    done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$steam_root/steamapps/libraryfolders.vdf" \
        | sed -E 's/.*"([^"]+)"/\1/' || true)
fi

# Nur Steam GE — Rezeptor-GE (wine-software/runtime) teilt nicht den Spiel-Prefix.
proton=""
if compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
    proton="$(ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1)"
fi
[ -n "$proton" ] && [ -f "$proton" ] || recipe_hooks::die \
    "Steam GE-Proton fehlt — in Steam unter Kompatibilität GE-Proton installieren"

output::progress 60 "Launch-Wrapper"
wrapper="$DATA_ROOT/za4-trainer-baracuda-run.sh"
q_steam="$(printf '%q' "$steam_root")"
q_compat="$(printf '%q' "$compat")"
q_proton="$(printf '%q' "$proton")"
q_trainer="$(printf '%q' "$dest")"
cat >"$wrapper" <<EOF
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
  echo "Hinweis: ZA4 scheint nicht zu laufen — Trainer erst nach Spielstart nutzen." >&2
fi
export STEAM_COMPAT_CLIENT_INSTALL_PATH="\$STEAM_ROOT"
export STEAM_COMPAT_DATA_PATH="\$COMPATDATA"
unset PROTON_ENABLE_WAYLAND || true
# Gleicher Steam-Proton + Prefix wie das laufende Spiel
exec "\$PROTON" runinprefix "\$TRAINER"
EOF
chmod +x "$wrapper"

recipe_hooks::state_set SCRIPT_PATH "$wrapper"
recipe_hooks::state_set TRAINER_EXE "$dest"
recipe_hooks::state_set WORK_ROOT "$target"
recipe_hooks::state_set STEAM_APPID "$appid"
[ -n "$compat" ] && recipe_hooks::state_set COMPATDATA "$compat"
[ -n "$proton" ] && recipe_hooks::state_set PROTON "$proton"

recipe_hooks::_source recipe-guard.sh 2>/dev/null || true
notify_title="$(recipe_get "$RECIPE_YML" notify_title 2>/dev/null || true)"
[ -n "$notify_title" ] || notify_title="$(recipe_get "$RECIPE_YML" name)"
if type recipe_notify::send >/dev/null 2>&1; then
    recipe_notify::send "$notify_title" "Trainer installiert" "$dest"
fi

output::progress 100 "Fertig"
output::success "Installiert: $dest"
recipe_hooks::emit_log_paths
