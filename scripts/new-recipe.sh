#!/usr/bin/env bash
# Neues Rezept aus Vorlage erzeugen.
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES="$ROOT/recipes"

usage() {
    echo "Usage: $0 [--type portable|installer] <recipe-id> [Anzeigename]" >&2
    echo "" >&2
    echo "  --type portable   Portable → Zielordner (Standard)" >&2
    echo "  --type installer  Offline-Installer (fixed_path)" >&2
    exit 1
}

TYPE="portable"
while [ $# -gt 0 ]; do
    case "$1" in
        --type)
            TYPE="${2:-}"; shift 2 ;;
        --type=*)
            TYPE="${1#*=}"; shift ;;
        -h|--help)
            usage ;;
        --)
            shift; break ;;
        -*)
            echo "ERROR: Unbekannte Option: $1" >&2; usage ;;
        *)
            break ;;
    esac
done

[ "${1:-}" ] || usage
ID="$1"
NAME="${2:-My App}"

if ! [[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "ERROR: Ungültige ID: $ID (z. B. meine-app)" >&2
    exit 1
fi

case "$TYPE" in
    portable) TEMPLATE="$RECIPES/_template" ;;
    installer) TEMPLATE="$RECIPES/_template-installer" ;;
    *)
        echo "ERROR: --type muss portable oder installer sein (ist: $TYPE)" >&2
        exit 1
        ;;
esac

DEST="$RECIPES/$ID"
[ -d "$TEMPLATE" ] || { echo "ERROR: Vorlage fehlt: $TEMPLATE" >&2; exit 1; }
[ ! -e "$DEST" ] || { echo "ERROR: Existiert bereits: $DEST" >&2; exit 1; }

cp -a "$TEMPLATE" "$DEST"

sed -i "s/^id: example-app/id: $ID/" "$DEST/recipe.yml"
sed -i "s|^data_root:.*|data_root: \"~/.local/share/wine-software/$ID\"|" "$DEST/recipe.yml"
sed -i "s/^name:.*$/name: \"$NAME\"/" "$DEST/recipe.yml"

if [ "$TYPE" = "portable" ]; then
    sed -i "s|^target_default:.*|target_default: \"~/Dokumente/$NAME\"|" "$DEST/recipe.yml"
else
    mkdir -p "$ROOT/installer"
    sed -i "s|^installer_dir:.*|installer_dir: \"{repo}/installer\"|" "$DEST/recipe.yml"
    echo "Lege Setup-Dateien ab unter: $ROOT/installer/"
fi

chmod +x "$DEST"/*.sh

echo "Rezept angelegt ($TYPE): $DEST"
echo ""
echo "Nächste Schritte:"
echo "  1. recipe.yml prüfen"
if [ "$TYPE" = "installer" ]; then
    echo "  2. Installer nach $ROOT/installer/ (setup.exe + Daten)"
else
    echo "  2. Optional: core/recipe-${ID}.sh für App-spezifische Schritte"
fi
echo "  3. ./scripts/recipe-lint.sh"
echo "  4. REZEPTOR_DEV=1 ./setup.sh"
echo ""
echo "Doku: docs/RECIPE-AUTHORING.md"

