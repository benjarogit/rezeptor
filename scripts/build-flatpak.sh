#!/usr/bin/env bash
# Build Rezeptor Flatpak bundle (core + recipes + Proton-GE + PyQt6/Fluent + winetricks).
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo dev)"
MANIFEST="$ROOT/flatpak/io.github.benjarogit.Rezeptor.yml"
BUILD_DIR="$ROOT/flatpak/build-flatpak"
REPO_DIR="$ROOT/flatpak/repo"
OUT="$ROOT/rezeptor-${VERSION}-x86_64.flatpak"
APP_ID="io.github.benjarogit.Rezeptor"

if ! command -v flatpak-builder >/dev/null 2>&1; then
    echo "flatpak-builder not found. Install: flatpak install flathub org.flatpak.Builder" >&2
    exit 1
fi

chmod +x "$ROOT/flatpak/rezeptor-launch" "$ROOT/flatpak/build-app.sh"

echo "Installing Flatpak runtime/SDK (org.freedesktop.Platform//25.08)..."
flatpak install -y --user flathub \
    org.freedesktop.Platform//25.08 \
    org.freedesktop.Sdk//25.08 \
    org.flatpak.Builder 2>/dev/null || flatpak install -y flathub \
    org.freedesktop.Platform//25.08 \
    org.freedesktop.Sdk//25.08 \
    org.flatpak.Builder

echo "Building Flatpak (Rezeptor ${VERSION})..."
rm -rf "$BUILD_DIR"
mkdir -p "$REPO_DIR"
flatpak-builder \
    --force-clean \
    --repo="$REPO_DIR" \
    --user \
    "$BUILD_DIR" \
    "$MANIFEST"

chmod +x "$ROOT/scripts/verify-flatpak-bundle.sh"
"$ROOT/scripts/verify-flatpak-bundle.sh" "$BUILD_DIR"

rm -f "$OUT"
flatpak build-bundle "$REPO_DIR" "$OUT" "$APP_ID"
chmod 644 "$OUT"
echo "Created: $OUT"
