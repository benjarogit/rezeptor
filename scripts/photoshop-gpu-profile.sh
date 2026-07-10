#!/usr/bin/env bash
# Photoshop GPU-Profil setzen (Kill-Switch: stable).
# Usage:
#   bash scripts/photoshop-gpu-profile.sh              # list
#   bash scripts/photoshop-gpu-profile.sh stable       # Kill-Switch
#   bash scripts/photoshop-gpu-profile.sh ps_gpu_no_opencl
#   REZEPTOR_PS_GPU_PROFILE=ps_gpu_full bash recipes/photoshop/launch.sh
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPE_DIR="$ROOT/recipes/photoshop"
export PROJECT_ROOT="$ROOT" RECIPE_DIR
export DATA_ROOT="${DATA_ROOT:-$HOME/.local/share/wine-software/photoshop}"
export WINE_PREFIX="${WINE_PREFIX:-$DATA_ROOT/prefix}"
export WINEPREFIX="$WINE_PREFIX"

# shellcheck source=/dev/null
source "$ROOT/core/recipe-hooks.sh"
recipe_hooks::load minimal
recipe_hooks::_source wine-runtime.sh
recipe_hooks::_source recipe-photoshop-install.sh
wine_runtime::init 2>/dev/null || true
wine_runtime::export_env 2>/dev/null || true

PROFILES=(stable dxvk_ui_only ps_gpu_no_opencl ps_gpu_full)
name="${1:-}"

if [ -z "$name" ] || [ "$name" = "list" ] || [ "$name" = "-h" ] || [ "$name" = "--help" ]; then
    echo "Photoshop GPU-Profile (Rezeptor)"
    echo "Aktiv: $(recipe_photoshop::active_gpu_profile)  (Flag: ${DATA_ROOT}/gpu-profile.active)"
    echo ""
    echo "Profile:"
    echo "  stable            Kill-Switch — GPU/OpenGL aus (Default, Neu/Text OK)"
    echo "  dxvk_ui_only      wie stable (DXVK UI, PS-GPU aus) — dokumentiert"
    echo "  ps_gpu_no_opencl  EXPERIMENT: PS-GPU an, OpenCL aus"
    echo "  ps_gpu_full       EXPERIMENT: PS-GPU + OpenCL an (Fail-Kandidat)"
    echo ""
    echo "Usage: $0 <profil>"
    echo "Bei Fail: $0 stable && Rezeptor → Beenden → Starten"
    echo "Doku: docs/GPU-EXPERIMENTS.md"
    exit 0
fi

ok=0
for p in "${PROFILES[@]}"; do
    [ "$p" = "$name" ] && ok=1 && break
done
[ "$ok" -eq 1 ] || {
    echo "ERROR: unbekanntes Profil: $name" >&2
    echo "Bekannt: ${PROFILES[*]}" >&2
    exit 1
}

if pgrep -f 'Photoshop\.exe' >/dev/null 2>&1; then
    echo "⚠ Photoshop läuft — bitte zuerst Beenden, sonst greifen Prefs erst nach Neustart." >&2
fi

recipe_photoshop::apply_gpu_profile "$name"
echo "OK: Profil „$name“ geschrieben → $DATA_ROOT/gpu-profile.active"
echo "Nächster Schritt: Rezeptor → Starten → Test (Neu, Text, Zoom 100%)."
[ "$name" != "stable" ] && echo "Bei Programmfehler: $0 stable"
exit 0
