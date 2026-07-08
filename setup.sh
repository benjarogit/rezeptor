#!/usr/bin/env bash
# Entry point: pre-check then PyQt6 launcher (required)
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$ROOT"

bash "$ROOT/pre-check.sh" --rezeptor "$@" || exit 1
exec python3 "$ROOT/launcher/launcher.py" "$@"
