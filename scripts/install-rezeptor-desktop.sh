#!/usr/bin/env bash
# Install Rezeptor menu entry + icon (KDE/GNOME/XDG).
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/scripts/rezeptor.desktop"
ICON_SRC="$ROOT/images/rezeptor-icon.svg"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
DESKTOP_DEST="$APPS_DIR/rezeptor.desktop"

[ -f "$TEMPLATE" ] || { echo "Fehlt: $TEMPLATE" >&2; exit 1; }
[ -x "$ROOT/setup.sh" ] || { echo "Fehlt oder nicht ausführbar: $ROOT/setup.sh" >&2; exit 1; }

mkdir -p "$APPS_DIR" "$ICON_DIR"
if [ -f "$ICON_SRC" ]; then
    cp -f "$ICON_SRC" "$ICON_DIR/rezeptor.svg"
fi

sed "s|REPO_ROOT|$ROOT|g" "$TEMPLATE" > "$DESKTOP_DEST"
chmod 644 "$DESKTOP_DEST"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
fi

echo "Rezeptor installiert:"
echo "  Menü:  Rezeptor (Anwendungen)"
echo "  Datei: $DESKTOP_DEST"
echo ""
echo "Start: KDE-Menü → „Rezeptor“ oder Doppelklick auf den Eintrag."
