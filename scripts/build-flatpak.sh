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

echo "Installing Flatpak runtime/SDK + i386 compat (org.freedesktop.Platform//25.08)..."
flatpak install -y --user flathub \
    org.freedesktop.Platform//25.08 \
    org.freedesktop.Sdk//25.08 \
    org.freedesktop.Platform.Compat.i386//25.08 \
    org.flatpak.Builder 2>/dev/null || flatpak install -y flathub \
    org.freedesktop.Platform//25.08 \
    org.freedesktop.Sdk//25.08 \
    org.freedesktop.Platform.Compat.i386//25.08 \
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

# 32-bit wine needs Compat.i386 attached — only happens via real flatpak run,
# not flatpak-builder --run.
echo "Verifying 32-bit wine with Compat.i386 (install from local repo)..."
flatpak remote-add --user --if-not-exists --no-gpg-verify rezeptor-ci "file://${REPO_DIR}"
flatpak install -y --user --reinstall rezeptor-ci "$APP_ID" >/dev/null
if ! flatpak run --command=bash "$APP_ID" -c \
    '/app/runtime/proton-ge/GE-Proton10-28/files/bin/wine --version' >/dev/null; then
    echo "FAIL: 32-bit wine --version failed under flatpak run (Compat.i386/multiarch)" >&2
    exit 1
fi
echo "32-bit wine runs with Compat.i386 under flatpak run"

rm -f "$OUT"
flatpak build-bundle "$REPO_DIR" "$OUT" "$APP_ID"
chmod 644 "$OUT"
echo "Created: $OUT"
