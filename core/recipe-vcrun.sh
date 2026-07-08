#!/usr/bin/env bash
# Visual C++ 2015–2022 via offizielle Microsoft-Installer (zuverlässiger als winetricks vcrun2019).

recipe_vcrun::cache_dir() {
    if type wine_software_cache_dir >/dev/null 2>&1; then
        echo "$(wine_software_cache_dir)/vcredist"
    else
        echo "${HOME}/.local/share/wine-software/cache/vcredist"
    fi
}

recipe_vcrun::download() {
    local url="$1" dest="$2"
    [ -f "$dest" ] && return 0
    mkdir -p "$(dirname "$dest")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        return 1
    fi
}

recipe_vcrun::install_exe() {
    local exe="$1" log="${2:-${LOG_FILE:-/dev/null}}"
    wine "$exe" /install /quiet /norestart >>"$log" 2>&1 \
        || wine "$exe" /quiet /norestart >>"$log" 2>&1 \
        || return 1
    return 0
}

recipe_vcrun::dll_ok() {
    local dll="$1"
    local sz
    [ -f "$dll" ] || return 1
    sz=$(stat -c%s "$dll" 2>/dev/null || echo 0)
    [ "$sz" -gt 50000 ] || return 1
    file "$dll" 2>/dev/null | grep -qE 'x86-64|Intel i386|PE32' || return 1
    return 0
}

recipe_vcrun::ensure() {
    local log="${1:-${LOG_FILE:-/dev/null}}"
    local cache x64 x86 prefix sys32 wow64

    recipe_winetricks::prepare || return 1
    prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    sys32="$prefix/drive_c/windows/system32/msvcp140.dll"
    wow64="$prefix/drive_c/windows/syswow64/msvcp140.dll"

    if recipe_vcrun::dll_ok "$sys32" && recipe_vcrun::dll_ok "$wow64"; then
        return 0
    fi

    cache="$(recipe_vcrun::cache_dir)"
    mkdir -p "$cache"
    x64="$cache/vc_redist.x64.exe"
    x86="$cache/vc_redist.x86.exe"

    recipe_vcrun::download "https://aka.ms/vc14/vc_redist.x64.exe" "$x64" || return 1
    recipe_vcrun::download "https://aka.ms/vc14/vc_redist.x86.exe" "$x86" || return 1

    if ! recipe_vcrun::dll_ok "$sys32"; then
        if type output::step >/dev/null 2>&1; then
            output::step "Visual C++ 2015–2022 (x64, Microsoft)"
        fi
        recipe_vcrun::install_exe "$x64" "$log" || return 1
    fi

    if ! recipe_vcrun::dll_ok "$wow64"; then
        if type output::step >/dev/null 2>&1; then
            output::step "Visual C++ 2015–2022 (x86, Microsoft)"
        fi
        recipe_vcrun::install_exe "$x86" "$log" || true
    fi

    recipe_vcrun::dll_ok "$wow64" || recipe_vcrun::dll_ok "$sys32"
}
