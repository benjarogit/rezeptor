#!/usr/bin/env bash
# Pack official recipes + catalog + manifest for release asset:
#   rezeptor-recipes-<VERSION>.tar.gz
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ver="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
  echo "VERSION invalid: '$ver'" >&2
  exit 1
fi

out="${1:-rezeptor-recipes-${ver}.tar.gz}"
stage="$(mktemp -d "${TMPDIR:-/tmp}/rezeptor-recipes.XXXXXX")"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

cp -a recipes/catalog.json "$stage/catalog.json"
cp -a recipes/manifest.json "$stage/manifest.json"

shopt -s nullglob
for dir in recipes/*/; do
  name="$(basename "$dir")"
  case "$name" in
    _*|community) continue ;;
  esac
  if [[ ! -f "${dir}recipe.yml" ]]; then
    continue
  fi
  cp -a "$dir" "$stage/$name"
done

# Drop accidental Adobe installer leftovers if present
find "$stage" \( \
  -name 'Set-up.exe' -o -name '*.iso' -o -name '*.pima' -o -name '*.pimx' \
\) -delete 2>/dev/null || true
rm -rf "$stage"/*/packages "$stage"/*/products "$stage"/*/resources 2>/dev/null || true

tar -C "$stage" -czf "$out" .
echo "Wrote $out"
ls -lh "$out"
