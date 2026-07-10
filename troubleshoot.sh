#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/core/troubleshoot.sh" "$@"
