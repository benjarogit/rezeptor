#!/usr/bin/env bash
# Shared Proton-GE tarball download + SHA256 verify (uses core/runtime.lock vars).

proton_ge_fetch::_load_lock() {
    if [ -n "${PROTON_GE_TAG:-}" ] && [ -n "${PROTON_GE_URL:-}" ]; then
        return 0
    fi
    local root="${PROJECT_ROOT:-}"
    if [ -z "$root" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
        root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    fi
    if [ -f "${root}/core/runtime.lock" ]; then
        # shellcheck source=/dev/null
        source "${root}/core/runtime.lock"
    elif [ -f "${root}/runtime.lock" ]; then
        # shellcheck source=/dev/null
        source "${root}/runtime.lock"
    fi
}

proton_ge_fetch::verify_tarball() {
    local archive="$1"
    proton_ge_fetch::_load_lock
    if [ -n "${PROTON_GE_SHA256:-}" ]; then
        echo "${PROTON_GE_SHA256}  $archive" | sha256sum -c - >/dev/null 2>&1 || return 1
    fi
    return 0
}

proton_ge_fetch::download_tarball() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --retry-connrefused "$url" -O "$dest"
    else
        return 1
    fi
}

proton_ge_fetch::ensure_tarball() {
    local dest="$1" url="${2:-}"
    proton_ge_fetch::_load_lock
    url="${url:-${PROTON_GE_URL:-}}"
    [ -n "$url" ] || return 1
    if [ ! -f "$dest" ]; then
        proton_ge_fetch::download_tarball "$url" "$dest" || return 1
    fi
    proton_ge_fetch::verify_tarball "$dest"
}
