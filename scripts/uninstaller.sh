#!/usr/bin/env bash
# Legacy: nur Photoshop-Rezept. Für alle Rezepte die GUI (Deinstallieren) nutzen.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Hinweis: uninstaller.sh ist Photoshop-Legacy — GUI → Deinstallieren bevorzugen." >&2
exec bash "$ROOT/recipes/photoshop/uninstall.sh" "$@"
