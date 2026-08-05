#!/usr/bin/env bash
# Halo CE — Ghidra-Analyse vorbereiten (Vanilla-EXE + optionales Headless-Import).
#
# Nutzung:
#   bash recipes/halo-campaign-evolved/assets/prepare-ghidra.sh          # nur EXE kopieren
#   bash recipes/halo-campaign-evolved/assets/prepare-ghidra.sh --import # + Ghidra Headless (lange!)
set -eu
(set -o pipefail 2>/dev/null) || true

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load validate

# shellcheck source=/dev/null
source "$CORE_DIR/recipe-halo-campaign-evolved.sh"

IMPORT=0
for arg in "$@"; do
    case "$arg" in
        --import) IMPORT=1 ;;
        -h | --help)
            echo "Usage: prepare-ghidra.sh [--import]"
            echo "  Kopiert ungepatchte HaloCampaignEvolved.exe nach ~/.local/share/.../analysis/"
            echo "  --import  Ghidra analyzeHeadless (Projekt HaloRE, kann 10–30 Min dauern)"
            exit 0
            ;;
    esac
done

EXE="$(recipe_halo_campaign_evolved::find_game_exe 2>/dev/null || true)"
[ -n "$EXE" ] && [ -f "$EXE" ] || {
    echo "Halo-EXE fehlt — zuerst installieren." >&2
    exit 1
}

VANILLA_SRC="$(recipe_halo_campaign_evolved::vanilla_exe_path "$EXE")"
[ -n "$VANILLA_SRC" ] && [ -f "$VANILLA_SRC" ] || VANILLA_SRC="$EXE"

ANALYSIS_ROOT="${HALO_GHIDRA_HOME:-$HOME/Dokumente/halo-ce-ghidra}"
PROJECT_DIR="$ANALYSIS_ROOT"
PROJECT_NAME="HaloRE"
VANILLA_DST="$ANALYSIS_ROOT/HaloCampaignEvolved_vanilla.exe"
GHIDRA_HOME="${GHIDRA_HOME:-/opt/ghidra}"
HEADLESS="$GHIDRA_HOME/support/analyzeHeadless"

mkdir -p "$ANALYSIS_ROOT"
cp -f "$VANILLA_SRC" "$VANILLA_DST"
chmod a-w "$VANILLA_DST" 2>/dev/null || true

echo "OK: Vanilla-EXE für Ghidra"
echo "    Quelle: $VANILLA_SRC"
echo "    Ziel:   $VANILLA_DST"
echo "    Größe:  $(stat -c%s "$VANILLA_DST" 2>/dev/null || echo ?) Bytes"
echo ""
echo "Ghidra GUI — Projekt anlegen:"
echo "  1. ghidra  (oder: $GHIDRA_HOME/ghidraRun)"
echo "  2. File → New Project → Non-Shared Project → Next"
echo "  3. Project Directory: $ANALYSIS_ROOT"
echo "     (Ordner im Dialog wählen — NICHT ~/.local, dort sind versteckte Pfade!)"
echo "  4. Project Name: $PROJECT_NAME → Finish"
echo "  5. File → Import File → $VANILLA_DST"
echo "  6. Format PE, Language x86:LE:64:default, Analyze = Yes"
echo "  7. Memory Map: ImageBase 0x140000000"
echo ""
echo "Leitfaden: recipes/halo-campaign-evolved/assets/halo-analyse-leitfaden.md"

if [ "$IMPORT" -eq 0 ]; then
    exit 0
fi

[ -x "$HEADLESS" ] || {
    echo "analyzeHeadless fehlt: $HEADLESS" >&2
    exit 1
}

LOG="$ANALYSIS_ROOT/ghidra-headless-import.log"
echo "Headless-Import startet (Log: $LOG) …"

"$HEADLESS" \
    "$PROJECT_DIR" "$PROJECT_NAME" \
    -import "$VANILLA_DST" \
    -overwrite \
    -processor "x86:LE:64:default" \
    -cspec "windows" \
    -analysisTimeoutPerFile 7200 \
    2>&1 | tee "$LOG"

echo "Headless fertig. Ghidra-Projekt: $PROJECT_DIR/$PROJECT_NAME"
