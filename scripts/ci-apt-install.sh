#!/usr/bin/env bash
# Install CI packages on ubuntu-latest without failing when third-party
# runner sources (e.g. packages.microsoft.com) return 403 / unsigned.
set -eu
(set -o pipefail 2>/dev/null) || true

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <apt-package>..." >&2
    exit 2
fi

# Hosted images sometimes ship broken Microsoft/Azure apt entries.
sudo rm -f \
    /etc/apt/sources.list.d/microsoft*.list \
    /etc/apt/sources.list.d/azure-cli*.list \
    /etc/apt/sources.list.d/*microsoft* \
    2>/dev/null || true

# Prefer a clean update; if other third-party lists still fail, retry with
# AllowReleaseInfoChange and ignore remaining list errors for Ubuntu main.
if ! sudo apt-get update -qq; then
    echo "WARN: apt-get update had errors — retry allowing release info change" >&2
    sudo apt-get update -qq -o Acquire::AllowReleaseInfoChange=true || true
fi

sudo apt-get install -y "$@"
