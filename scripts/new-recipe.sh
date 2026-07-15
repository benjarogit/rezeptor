#!/usr/bin/env bash
# Neues Rezept aus Vorlage erzeugen.
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES="$ROOT/recipes"

usage() {
    echo "Usage: $0 [--type portable|installer|steam-game] [--community] <recipe-id> [Anzeigename]" >&2
    echo "" >&2
    echo "  --type portable     Portable → Zielordner (Standard)" >&2
    echo "  --type installer    Offline-Installer" >&2
    echo "  --type steam-game   Steam/Proton BYOS + Online-Fix-Wrapper" >&2
    echo "  --community         Nach recipes/community/<id>/ (Community-Badge)" >&2
    exit 1
}

TYPE="portable"
COMMUNITY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --type)
            TYPE="${2:-}"; shift 2 ;;
        --type=*)
            TYPE="${1#*=}"; shift ;;
        --community)
            COMMUNITY=1; shift ;;
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
    steam-game) TEMPLATE="$RECIPES/_template-steam-game" ;;
    *)
        echo "ERROR: --type muss portable, installer oder steam-game sein (ist: $TYPE)" >&2
        exit 1
        ;;
esac

if [ "$COMMUNITY" -eq 1 ]; then
    mkdir -p "$RECIPES/community"
    DEST="$RECIPES/community/$ID"
else
    DEST="$RECIPES/$ID"
fi
[ -d "$TEMPLATE" ] || { echo "ERROR: Vorlage fehlt: $TEMPLATE" >&2; exit 1; }
[ ! -e "$DEST" ] || { echo "ERROR: Existiert bereits: $DEST" >&2; exit 1; }

cp -a "$TEMPLATE" "$DEST"

# Community-Rezepte: core-Pfad ../../ → ../../../
if [ "$COMMUNITY" -eq 1 ]; then
    for sh in "$DEST"/*.sh; do
        [ -f "$sh" ] || continue
        sed -i 's|\$RECIPE_DIR/../../core/|\$RECIPE_DIR/../../../core/|g' "$sh"
    done
    if grep -q '^origin:' "$DEST/recipe.yml" 2>/dev/null; then
        sed -i 's/^origin:.*/origin: community/' "$DEST/recipe.yml"
    else
        sed -i '/^author:/a origin: community' "$DEST/recipe.yml" || true
    fi
fi

sed -i "s/^id: example-app/id: $ID/" "$DEST/recipe.yml"
sed -i "s/^id: example-steam-game/id: $ID/" "$DEST/recipe.yml"
sed -i "s|^data_root:.*|data_root: \"~/.local/share/wine-software/$ID\"|" "$DEST/recipe.yml"
sed -i "s/^name:.*$/name: \"$NAME\"/" "$DEST/recipe.yml"

if [ "$TYPE" = "portable" ]; then
    sed -i "s|^target_default:.*|target_default: \"~/Dokumente/$NAME\"|" "$DEST/recipe.yml"
elif [ "$TYPE" = "installer" ]; then
    sed -i "s|^target_default:.*|target_default: \"~/.local/share/wine-software/$ID\"|" "$DEST/recipe.yml"
    echo "Installer-Ordner bei Installation in der GUI wählen (Set-up.exe / setup.exe)."
elif [ "$TYPE" = "steam-game" ]; then
    echo "Steam-Spiel: steam_appid, exe_glob und Fix-Pfade in recipe.yml anpassen."
fi

chmod +x "$DEST"/*.sh

echo "Rezept angelegt ($TYPE$([ "$COMMUNITY" -eq 1 ] && echo ', community')): $DEST"
echo ""
echo "Nächste Schritte:"
echo "  1. recipe.yml prüfen (Proton-GE Pflicht)"
echo "  2. Icon unter images/${ID}-icon.png"
echo "  3. ./scripts/recipe-lint.sh"
echo "  4. REZEPTOR_DEV=1 ./setup.sh"
echo "  5. ./scripts/recipe-manifest.sh"
echo ""
echo "Doku: docs/de/RECIPE-AUTHORING.md (Wiki nach MkDocs-Deploy)"
