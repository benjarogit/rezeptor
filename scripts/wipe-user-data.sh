#!/usr/bin/env bash
# wipe-user-data.sh — safe wipe of Rezeptor INSTALLATION data for fresh user testing.
#
# Removes per-recipe data under ~/.local/share/wine-software/<recipe-id>/ only.
# NEVER deletes shipping recipes/ (or anything else) from the git checkout.
#
# Usage:
#   ./scripts/wipe-user-data.sh                         # dry-run: list targets
#   ./scripts/wipe-user-data.sh --yes                   # wipe all known recipe installs
#   ./scripts/wipe-user-data.sh photoshop wiso-steuer   # dry-run for those ids
#   ./scripts/wipe-user-data.sh photoshop --yes         # wipe one recipe
#   ./scripts/wipe-user-data.sh --settings --yes        # also clear launcher settings.json
#   ./scripts/wipe-user-data.sh --runtime --yes         # also wipe Proton-GE runtime/
#
# Defaults:
#   - Keeps ~/.local/share/wine-software/runtime/ (Proton-GE)
#   - Keeps launcher settings unless --settings
#   - Prints planned deletes; requires --yes to actually remove
#
# Env:
#   WINE_SOFTWARE_BASE  override data root (default: ~/.local/share/wine-software)
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${WINE_SOFTWARE_BASE:-$HOME/.local/share/wine-software}"
YES=0
WIPE_SETTINGS=0
WIPE_RUNTIME=0
IDS=()

usage() {
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage 0 ;;
        --yes|-y) YES=1; shift ;;
        --settings) WIPE_SETTINGS=1; shift ;;
        --runtime) WIPE_RUNTIME=1; shift ;;
        --)
            shift
            while [ $# -gt 0 ]; do IDS+=("$1"); shift; done
            break
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            usage 1
            ;;
        *)
            IDS+=("$1"); shift ;;
    esac
done

# Collect recipe ids from shipping tree (official + community). Never touch recipes/ on disk for wipe.
discover_known_ids() {
    local dir base
    for dir in "$ROOT/recipes"/*/ "$ROOT/recipes/community"/*/; do
        [ -d "$dir" ] || continue
        base="$(basename "$dir")"
        case "$base" in
            _*|community) continue ;;
        esac
        [ -f "$dir/recipe.yml" ] || continue
        echo "$base"
    done | sort -u
}

if [ "${#IDS[@]}" -eq 0 ]; then
    mapfile -t IDS < <(discover_known_ids)
fi

if [ "${#IDS[@]}" -eq 0 ]; then
    echo "No recipe ids to wipe (pass ids as args, or add recipes under recipes/)." >&2
    exit 1
fi

TARGETS=()
for id in "${IDS[@]}"; do
    [ -n "$id" ] || continue
    case "$id" in
        runtime|rezeptor|logs|cache|community)
            echo "ERROR: refusing reserved id: $id (use --runtime / --settings for those)" >&2
            exit 1
            ;;
        */*|.*|*..*)
            echo "ERROR: invalid recipe id: $id" >&2
            exit 1
            ;;
    esac
    TARGETS+=("$BASE/$id")
done

SETTINGS_FILE="$BASE/rezeptor/settings.json"
RUNTIME_DIR="$BASE/runtime"

echo "Base: $BASE"
echo "Will remove recipe data:"
for t in "${TARGETS[@]}"; do
    if [ -e "$t" ]; then
        echo "  $t"
    else
        echo "  $t  (absent)"
    fi
done
if [ "$WIPE_SETTINGS" -eq 1 ]; then
    if [ -e "$SETTINGS_FILE" ]; then
        echo "  $SETTINGS_FILE  (--settings)"
    else
        echo "  $SETTINGS_FILE  (absent, --settings)"
    fi
fi
if [ "$WIPE_RUNTIME" -eq 1 ]; then
    if [ -e "$RUNTIME_DIR" ]; then
        echo "  $RUNTIME_DIR  (--runtime)"
    else
        echo "  $RUNTIME_DIR  (absent, --runtime)"
    fi
else
    echo "Keeping runtime (Proton-GE). Pass --runtime to wipe $RUNTIME_DIR"
fi
echo "Shipping recipes/ under $ROOT are NOT touched."

if [ "$YES" -ne 1 ]; then
    echo ""
    echo "Dry-run only. Re-run with --yes to delete."
    exit 0
fi

for t in "${TARGETS[@]}"; do
    if [ -e "$t" ]; then
        rm -rf -- "$t"
        echo "Removed $t"
    fi
done
if [ "$WIPE_SETTINGS" -eq 1 ] && [ -e "$SETTINGS_FILE" ]; then
    rm -f -- "$SETTINGS_FILE"
    echo "Removed $SETTINGS_FILE"
fi
if [ "$WIPE_RUNTIME" -eq 1 ] && [ -e "$RUNTIME_DIR" ]; then
    rm -rf -- "$RUNTIME_DIR"
    echo "Removed $RUNTIME_DIR"
fi
echo "Done."
