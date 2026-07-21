#!/usr/bin/env bash
################################################################################
# Wine / Proton-GE runtime resolver (runtime per recipe: proton-ge | system)
################################################################################

_WINE_RUNTIME_INITIALIZED=0
_WINE_RUNTIME_MODE=""
_WINE_RUNTIME_BIN=""
_WINE_RUNTIME_ROOT=""
_WINETRICKS_BIN=""

if [ -f "${BASH_SOURCE[0]%/*}/paths.sh" ]; then
    # shellcheck source=paths.sh
    source "${BASH_SOURCE[0]%/*}/paths.sh"
fi

wine_runtime::_project_root() {
    if [ -n "${PROJECT_ROOT:-}" ]; then
        echo "$PROJECT_ROOT"
    elif [ -n "${SCRIPT_DIR:-}" ]; then
        cd "$(dirname "$SCRIPT_DIR")" && pwd
    else
        echo "$HOME"
    fi
}

wine_runtime::_load_lock() {
    local root rt_dir
    root="$(wine_runtime::_project_root)"
    rt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$root/core/runtime.lock" ]; then
        # shellcheck source=/dev/null
        source "$root/core/runtime.lock"
    elif [ -f "$root/runtime.lock" ]; then
        # shellcheck source=/dev/null
        source "$root/runtime.lock"
    elif [ -f "$rt_dir/runtime.lock" ]; then
        # Deployed launcher copy (DATA_ROOT/launcher/runtime.lock)
        # shellcheck source=/dev/null
        source "$rt_dir/runtime.lock"
    fi
    export PROTON_GE_TAG="${PROTON_GE_TAG:-GE-Proton10-28}"
    export PROTON_GE_URL="${PROTON_GE_URL:-https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_GE_TAG}/${PROTON_GE_TAG}.tar.gz}"
    export PROTON_GE_SHA256="${PROTON_GE_SHA256:-}"
}

# Download with retries for transient network/CDN failures.
wine_runtime::_fail() {
    echo "ERROR: $*" >&2
    type log_err >/dev/null 2>&1 && log_err "$*"
    return 1
}

wine_runtime::_download() {
    local url="$1" dest="$2"
    if type security::validate_url >/dev/null 2>&1; then
        security::validate_url "$url" || return 1
    elif [[ ! "$url" =~ ^https:// ]]; then
        return 1
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --retry-connrefused "$url" -O "$dest"
    else
        return 1
    fi
}

wine_runtime::reset() {
    _WINE_RUNTIME_INITIALIZED=0
    _WINE_RUNTIME_MODE=""
    _WINE_RUNTIME_BIN=""
    _WINE_RUNTIME_ROOT=""
}

wine_runtime::_proton_bin_works() {
    local bin="${1:-}"
    [ -n "$bin" ] && [ -x "$bin" ] || return 1
    # Flatpak often lacks i386 ld-linux.so.2 — 32-bit wine exists but cannot exec.
    "$bin" --version >/dev/null 2>&1
}

wine_runtime::_apply_proton_env() {
    local bin32 bin64
    _WINE_RUNTIME_MODE="proton-ge"
    _WINE_RUNTIME_ROOT="$(wine_runtime::_find_proton_dir)"
    bin32="$_WINE_RUNTIME_ROOT/files/bin/wine"
    bin64="$_WINE_RUNTIME_ROOT/files/bin/wine64"
    # Prefer classic wine when it actually runs; else wine64 (Flatpak / no multiarch).
    if wine_runtime::_proton_bin_works "$bin32"; then
        _WINE_RUNTIME_BIN="$bin32"
    elif wine_runtime::_proton_bin_works "$bin64"; then
        _WINE_RUNTIME_BIN="$bin64"
    elif [ -x "$bin64" ]; then
        _WINE_RUNTIME_BIN="$bin64"
    else
        _WINE_RUNTIME_BIN="$bin32"
    fi
    export PROTON_PATH="$_WINE_RUNTIME_ROOT"
    export PATH="$_WINE_RUNTIME_ROOT/files/bin:$_WINE_RUNTIME_ROOT/files/bin/w64:$_WINE_RUNTIME_ROOT/files/bin/w32:${PATH}"
    export WINE_RUNTIME_MODE="proton-ge"
}

wine_runtime::_user_runtime_base() {
    if type wine_software_runtime_dir >/dev/null 2>&1; then
        wine_software_runtime_dir
    else
        echo "${WINE_SOFTWARE_BASE:-$HOME/.local/share/wine-software}/runtime/proton-ge"
    fi
}

wine_runtime::_find_proton_dir() {
    local candidate=""
    local -a glob_candidates=()
    local base appdir="${APPDIR:-}"
    base="$(wine_runtime::_user_runtime_base)"
    shopt -s nullglob 2>/dev/null || true
    if [ -n "$appdir" ] && [ -d "$appdir/runtime/proton-ge" ]; then
        glob_candidates+=(
            "$appdir/runtime/proton-ge/${PROTON_GE_TAG:-GE-Proton10-28}"
            "$appdir/runtime/proton-ge"/*
        )
    fi
    glob_candidates+=(
        "$base/${PROTON_GE_TAG:-GE-Proton10-28}"
        "$base"/*
    )
    shopt -u nullglob 2>/dev/null || true
    for candidate in "${glob_candidates[@]}"; do
        if [ -d "$candidate/files/bin" ] && {
            [ -x "$candidate/files/bin/wine" ] || [ -x "$candidate/files/bin/wine64" ]
        }; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

wine_runtime::ensure_proton_ge() {
    wine_runtime::_load_lock

    local existing
    if existing="$(wine_runtime::_find_proton_dir 2>/dev/null)"; then
        _WINE_RUNTIME_ROOT="$existing"
        return 0
    fi

    local base dest archive url tag
    tag="${PROTON_GE_TAG}"
    url="${PROTON_GE_URL}"
    base="$(wine_runtime::_user_runtime_base)"
    dest="$base/$tag"
    archive="$base/${tag}.tar.gz"

    mkdir -p "$base" || wine_runtime::_fail "Proton-GE runtime directory not writable: $base"

    if [ ! -f "$archive" ]; then
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            wine_runtime::_fail "Proton-GE download requires curl or wget"
        fi
        local lockfile="$base/.proton-download.lock"
        if command -v flock >/dev/null 2>&1; then
            (
                flock -w 300 9 || exit 1
                if [ ! -f "$archive" ]; then
                    wine_runtime::_download "$url" "$archive" || exit 1
                fi
            ) 9>"$lockfile" || wine_runtime::_fail "Proton-GE download lock failed: $lockfile"
        else
            wine_runtime::_download "$url" "$archive" || \
                wine_runtime::_fail "Proton-GE download failed: $url"
        fi
    fi

    # shellcheck source=/dev/null
    source "${BASH_SOURCE[0]%/*}/proton-ge-fetch.sh"
    if ! proton_ge_fetch::verify_tarball "$archive"; then
        wine_runtime::_fail "Proton-GE archive checksum verification failed: $archive"
        return 1
    fi

    mkdir -p "$dest" || {
        wine_runtime::_fail "Proton-GE extract directory not writable: $dest"
        return 1
    }
    if ! tar -xzf "$archive" -C "$base" --strip-components=0 2>/dev/null && \
        ! tar -xzf "$archive" -C "$base" 2>/dev/null; then
        wine_runtime::_fail "Proton-GE archive extract failed: $archive"
        return 1
    fi

    _WINE_RUNTIME_ROOT="$(wine_runtime::_find_proton_dir)" || {
        wine_runtime::_fail "Proton-GE install incomplete under $base"
        return 1
    }
    return 0
}

wine_runtime::_find_system_wine() {
    local candidate=""
    for candidate in /usr/bin/wine /opt/wine-cachyos/bin/wine; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

wine_runtime::_apply_system_env() {
    local bin
    bin="$(wine_runtime::_find_system_wine 2>/dev/null || true)"
    [ -n "$bin" ] || return 1
    _WINE_RUNTIME_MODE="system"
    _WINE_RUNTIME_BIN="$bin"
    _WINE_RUNTIME_ROOT=""
    export WINE_RUNTIME_MODE="system"
}

wine_runtime::init() {
    if [ "$_WINE_RUNTIME_INITIALIZED" = "1" ]; then
        return 0
    fi

    wine_runtime::_load_lock

    if [ "${WINE_METHOD:-}" = "system" ] || [ "${RECIPE_RUNTIME:-}" = "system" ]; then
        if wine_runtime::_apply_system_env; then
            _WINE_RUNTIME_INITIALIZED=1
            return 0
        fi
    fi

    if wine_runtime::ensure_proton_ge; then
        wine_runtime::_apply_proton_env
        _WINE_RUNTIME_INITIALIZED=1
        return 0
    fi
    wine_runtime::_fail "Proton-GE runtime unavailable (see messages above)"
}

wine_runtime::wine() {
    wine_runtime::init || return 1
    "$_WINE_RUNTIME_BIN" "$@"
}

wine_runtime::_tool() {
    local tool="$1"
    shift
    wine_runtime::init || return 1
    if [ "$_WINE_RUNTIME_MODE" = "proton-ge" ]; then
        if [ -x "$_WINE_RUNTIME_ROOT/files/bin/$tool" ]; then
            "$_WINE_RUNTIME_ROOT/files/bin/$tool" "$@"
        else
            "$_WINE_RUNTIME_BIN" "$tool" "$@"
        fi
    else
        wine_runtime::wine "$tool" "$@"
    fi
}

wine_runtime::wineboot() { wine_runtime::_tool wineboot "$@"; }
wine_runtime::winecfg() { wine_runtime::_tool winecfg "$@"; }
wine_runtime::wineserver() { wine_runtime::_tool wineserver "$@"; }

wine_runtime::winetricks() {
    wine_runtime::init || return 1
    local wt=""
    if [ -n "${APPDIR:-}" ] && [ -x "${APPDIR}/runtime/winetricks/winetricks" ]; then
        wt="${APPDIR}/runtime/winetricks/winetricks"
    elif command -v winetricks >/dev/null 2>&1; then
        wt="$(command -v winetricks)"
    else
        return 127
    fi
    WINE="$_WINE_RUNTIME_BIN" "$wt" "$@"
}

wine_runtime::winepath() { wine_runtime::_tool winepath "$@"; }

wine_runtime::describe() {
    wine_runtime::init || { echo "none"; return 1; }
    if [ "$_WINE_RUNTIME_MODE" = "system" ]; then
        echo "System-Wine ($_WINE_RUNTIME_BIN)"
        return 0
    fi
    echo "Proton-GE ${PROTON_GE_TAG:-} ($_WINE_RUNTIME_ROOT)"
}

# Pfad zum Proton-Launcher-Skript (…/proton) — nur Rezeptor Proton-GE.
wine_runtime::proton_script() {
    wine_runtime::_load_lock
    wine_runtime::ensure_proton_ge || return 1
    local root=""
    root="$(wine_runtime::_find_proton_dir)" || return 1
    [ -x "$root/proton" ] || return 1
    echo "$root/proton"
}

# Steam-/Spiel-Rezepte: Rezeptor Proton-GE zuerst, dann Steam-GE, zuletzt Valve-Proton.
wine_runtime::resolve_proton_script() {
    local steam_root="${1:-${STEAM_ROOT:-$HOME/.local/share/Steam}}"
    local p=""
    if p="$(wine_runtime::proton_script 2>/dev/null)" && [ -n "$p" ] && [ -f "$p" ]; then
        echo "$p"
        return 0
    fi
    [ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"
    if [ -d "$steam_root" ] && compgen -G "$steam_root/compatibilitytools.d/GE-Proton*/proton" >/dev/null 2>&1; then
        ls -1d "$steam_root/compatibilitytools.d"/GE-Proton*/proton 2>/dev/null | sort -V | tail -1
        return 0
    fi
    if [ -d "$steam_root" ] && compgen -G "$steam_root/steamapps/common/Proton"*/proton >/dev/null 2>&1; then
        ls -1d "$steam_root/steamapps/common"/Proton*/proton 2>/dev/null | sort -V | tail -1
        return 0
    fi
    return 1
}

wine_runtime::export_env() {
    wine_runtime::init || return 1
    export WINE="$_WINE_RUNTIME_BIN"
    export WINE_RUNTIME_BIN="$_WINE_RUNTIME_BIN"
    export WINE_RUNTIME_ROOT="${_WINE_RUNTIME_ROOT:-}"
    if [ "$_WINE_RUNTIME_MODE" = "proton-ge" ]; then
        export PROTON_PATH="$_WINE_RUNTIME_ROOT"
        # Proton-GE (Wine 10): neue WOW64-Architektur nur abschalten, wenn das Rezept es
        # braucht (z. B. Adobe IE-Installer/IE8) — recipe.yml: disable_wow64: true.
        # Global erzwungen hätte das andere Rezepte (z. B. WISO, 64-bit-lastig) kaputt machen können.
        if [ "${RECIPE_DISABLE_WOW64:-}" = "true" ] || [ "${RECIPE_DISABLE_WOW64:-}" = "1" ]; then
            export WINE_DISABLE_WOW64=1
        else
            unset WINE_DISABLE_WOW64 2>/dev/null || true
        fi
    else
        unset PROTON_PATH 2>/dev/null || true
        unset WINE_DISABLE_WOW64 2>/dev/null || true
    fi
}

# Proton ships vkd3d + DXVK DLLs; user prefixes from wineboot often lack libvkd3d → Photoshop won't start
wine_runtime::deploy_proton_graphics_dlls() {
    wine_runtime::init || return 1
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local root="$_WINE_RUNTIME_ROOT"
    local def_sys32="$root/files/share/default_pfx/drive_c/windows/system32"
    local def_wow64="$root/files/share/default_pfx/drive_c/windows/syswow64"
    local dxvk64="$root/files/lib/wine/dxvk/x86_64-windows"
    local dxvk32="$root/files/lib/wine/dxvk/i386-windows"
    local sys32="$prefix/drive_c/windows/system32"
    local wow64="$prefix/drive_c/windows/syswow64"
    local dll=""
    local err=0

    [ -n "$prefix" ] && [ -d "$sys32" ] || wine_runtime::_fail "Wine prefix system32 missing: ${prefix:-<unset>}"

    for dll in libvkd3d-1.dll libvkd3d-shader-1.dll; do
        if [ -f "$def_sys32/$dll" ]; then
            cp -f "$def_sys32/$dll" "$sys32/$dll" 2>/dev/null || err=1
        fi
        if [ -f "$def_wow64/$dll" ]; then
            cp -f "$def_wow64/$dll" "$wow64/$dll" 2>/dev/null || err=1
        fi
    done
    for dll in d3d11.dll dxgi.dll; do
        if [ -f "$dxvk64/$dll" ]; then
            cp -f "$dxvk64/$dll" "$sys32/$dll" 2>/dev/null || err=1
        fi
        if [ -f "$dxvk32/$dll" ]; then
            cp -f "$dxvk32/$dll" "$wow64/$dll" 2>/dev/null || err=1
        fi
    done
    if [ "$err" -ne 0 ]; then
        wine_runtime::_fail "Proton graphics DLL deploy failed for prefix $prefix"
    fi
    return 0
}

# DXVK (Vulkan) → wined3d (OpenGL). Community: Photoshop „Legacy OpenGL“ braucht DXVK=aus.
# libvkd3d bleibt (wined3d/Proton), d3d11/dxgi/d2d1/d3d10core aus default_pfx.
wine_runtime::restore_wined3d_dlls() {
    wine_runtime::init || return 1
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local root="$_WINE_RUNTIME_ROOT"
    local def_sys32="$root/files/share/default_pfx/drive_c/windows/system32"
    local def_wow64="$root/files/share/default_pfx/drive_c/windows/syswow64"
    local sys32="$prefix/drive_c/windows/system32"
    local wow64="$prefix/drive_c/windows/syswow64"
    local dll=""

    [ -n "$prefix" ] && [ -d "$sys32" ] || return 1

    for dll in libvkd3d-1.dll libvkd3d-shader-1.dll; do
        [ -f "$def_sys32/$dll" ] && cp -f "$def_sys32/$dll" "$sys32/$dll" 2>/dev/null || true
        [ -f "$def_wow64/$dll" ] && cp -f "$def_wow64/$dll" "$wow64/$dll" 2>/dev/null || true
    done
    for dll in d3d11.dll dxgi.dll d2d1.dll d3d10core.dll; do
        [ -f "$def_sys32/$dll" ] && cp -f "$def_sys32/$dll" "$sys32/$dll" 2>/dev/null || true
        [ -f "$def_wow64/$dll" ] && cp -f "$def_wow64/$dll" "$wow64/$dll" 2>/dev/null || true
    done
    return 0
}

wine_runtime::cache_dir() {
    local cache
    if type wine_software_cache_dir >/dev/null 2>&1; then
        cache="$(wine_software_cache_dir)"
    else
        cache="${WINE_CACHE_DIR:-${CACHE_PATH:-$HOME/.local/share/wine-software/cache/winetricks}}"
    fi
    mkdir -p "$cache" 2>/dev/null || true
    export WINETRICKS_CACHE="$cache"
    export WINE_CACHE_DIR="$cache"
    echo "$cache"
}
