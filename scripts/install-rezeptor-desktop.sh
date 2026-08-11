#!/usr/bin/env bash
# Install Rezeptor menu entry + icon (KDE/GNOME/XDG).
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/scripts/rezeptor.desktop"
ICON_SVG="$ROOT/images/rezeptor-icon.svg"
ICON_PNG="$ROOT/images/rezeptor-icon.png"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
DESKTOP_DEST="$APPS_DIR/rezeptor.desktop"

[ -f "$TEMPLATE" ] || { echo "Fehlt: $TEMPLATE" >&2; exit 1; }
[ -x "$ROOT/setup.sh" ] || { echo "Fehlt oder nicht ausführbar: $ROOT/setup.sh" >&2; exit 1; }
[ -f "$ICON_SVG" ] || { echo "Fehlt: $ICON_SVG" >&2; exit 1; }

mkdir -p "$APPS_DIR" "$ICON_BASE/scalable/apps"
cp -f "$ICON_SVG" "$ICON_BASE/scalable/apps/rezeptor.svg"
if [ -f "$ICON_PNG" ]; then
    for sz in 48 64 128 256 512; do
        mkdir -p "$ICON_BASE/${sz}x${sz}/apps"
        if command -v magick >/dev/null 2>&1; then
            magick "$ICON_SVG" -resize "${sz}x${sz}" "$ICON_BASE/${sz}x${sz}/apps/rezeptor.png"
        elif command -v convert >/dev/null 2>&1; then
            convert "$ICON_SVG" -resize "${sz}x${sz}" "$ICON_BASE/${sz}x${sz}/apps/rezeptor.png"
        else
            cp -f "$ICON_PNG" "$ICON_BASE/${sz}x${sz}/apps/rezeptor.png"
        fi
    done
fi

sed "s|REPO_ROOT|$ROOT|g" "$TEMPLATE" > "$DESKTOP_DEST"
chmod 644 "$DESKTOP_DEST"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f "$ICON_BASE" 2>/dev/null || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 >/dev/null 2>&1 || true
fi

echo "Rezeptor installiert:"
echo "  Menü:  Rezeptor (Anwendungen)"
echo "  Datei: $DESKTOP_DEST"
echo "  Icon:  $ICON_BASE/scalable/apps/rezeptor.svg"
echo ""
echo "Start: KDE-Menü → „Rezeptor“ oder ./setup.sh im Repo."
