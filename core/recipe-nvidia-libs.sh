#!/usr/bin/env bash
# SveSop/nvidia-libs — CUDA/NVAPI/NVENC in einem Wine-Prefix (NVIDIA-Host).
# Kein Proton-Tree-Patch; nur Prefix-DLLs + DllOverrides.
# Opt-in: PREMIERE_NVIDIA_LIBS=1 | Auto wenn Host-NVIDIA und nicht =0.

recipe_nvidia_libs::_lock_vars() {
    local lock="${PROJECT_ROOT:-}/core/runtime.lock"
    [ -f "$lock" ] || return 1
    # shellcheck disable=SC1090
    set -a
    # shellcheck source=/dev/null
    source "$lock"
    set +a
    [ -n "${NVIDIA_LIBS_URL:-}" ] && [ -n "${NVIDIA_LIBS_SHA256:-}" ]
}

recipe_nvidia_libs::host_has_nvidia() {
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        return 0
    fi
    if [ -e /dev/nvidia0 ] || [ -e /dev/nvidiactl ]; then
        return 0
    fi
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | grep -qi 'NVIDIA' && return 0
    fi
    return 1
}

recipe_nvidia_libs::cache_dir() {
    local base=""
    if type wine_software_cache_dir >/dev/null 2>&1; then
        base="$(wine_software_cache_dir)"
    else
        base="${CACHE_PATH:-$HOME/.local/share/wine-software/cache}"
    fi
    echo "${base%/}/nvidia-libs"
}

recipe_nvidia_libs::installed() {
    local prefix="${1:-${WINEPREFIX:-${WINE_PREFIX:-}}}"
    local nvcuda="${prefix}/drive_c/windows/system32/nvcuda.dll"
    local sz=0
    [ -n "$prefix" ] && [ -f "$nvcuda" ] || return 1
    # Marker = unsere Installation
    [ -f "${prefix}/.rezeptor-nvidia-libs" ] && return 0
    # Wine/Proton-Stub ist winzig (~35 KB); echte nvidia-libs nvcuda ist >1 MB
    sz="$(wc -c <"$nvcuda" 2>/dev/null || echo 0)"
    [ "$sz" -gt 500000 ] || return 1
    return 0
}

# Premiere: default an auf NVIDIA-Host; PREMIERE_NVIDIA_LIBS=0 aus; =1 erzwingen.
recipe_nvidia_libs::wanted() {
    case "${PREMIERE_NVIDIA_LIBS:-auto}" in
        0|false|no|off|OFF) return 1 ;;
        1|true|yes|on|ON) return 0 ;;
        *)
            recipe_nvidia_libs::host_has_nvidia
            ;;
    esac
}

recipe_nvidia_libs::_download() {
    recipe_nvidia_libs::_lock_vars || return 1
    local cache archive dest_dir="" tag_plain=""
    cache="$(recipe_nvidia_libs::cache_dir)"
    /bin/mkdir -p "$cache" || mkdir -p "$cache"
    archive="$cache/$(basename "$NVIDIA_LIBS_URL")"
    tag_plain="${NVIDIA_LIBS_TAG#v}"
    # Tarball-Root: nvidia-libs-v1.0.2/ oder nvidia-libs-1.0.2/
    dest_dir="$cache/extract/nvidia-libs-${NVIDIA_LIBS_TAG}"
    [ -f "$dest_dir/x64/nvcuda.dll" ] || dest_dir="$cache/extract/nvidia-libs-${tag_plain}"

    if [ -f "$archive" ]; then
        echo "$NVIDIA_LIBS_SHA256  $archive" | /usr/bin/sha256sum -c --status 2>/dev/null \
            || echo "$NVIDIA_LIBS_SHA256  $archive" | sha256sum -c --status 2>/dev/null \
            || rm -f "$archive"
    fi
    if [ ! -f "$archive" ]; then
        if type security::validate_url >/dev/null 2>&1; then
            security::validate_url "$NVIDIA_LIBS_URL" || return 1
        fi
        type output::step >/dev/null 2>&1 && output::step "nvidia-libs ${NVIDIA_LIBS_TAG} laden"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --retry 3 --retry-delay 2 "$NVIDIA_LIBS_URL" -o "$archive" || return 1
        elif command -v wget >/dev/null 2>&1; then
            wget -q --tries=3 "$NVIDIA_LIBS_URL" -O "$archive" || return 1
        else
            return 1
        fi
    fi
    if ! echo "$NVIDIA_LIBS_SHA256  $archive" | /usr/bin/sha256sum -c --status 2>/dev/null \
        && ! echo "$NVIDIA_LIBS_SHA256  $archive" | sha256sum -c --status 2>/dev/null; then
        rm -f "$archive"
        return 1
    fi
    if [ ! -f "$dest_dir/x64/nvcuda.dll" ]; then
        /bin/rm -rf "$cache/extract" 2>/dev/null || rm -rf "$cache/extract"
        /bin/mkdir -p "$cache/extract" || mkdir -p "$cache/extract"
        if command -v tar >/dev/null 2>&1; then
            tar -xJf "$archive" -C "$cache/extract" || return 1
        else
            return 1
        fi
        dest_dir="$cache/extract/nvidia-libs-${NVIDIA_LIBS_TAG}"
        [ -f "$dest_dir/x64/nvcuda.dll" ] || dest_dir="$cache/extract/nvidia-libs-${tag_plain}"
    fi
    [ -f "$dest_dir/x64/nvcuda.dll" ] || return 1
    echo "$dest_dir"
}

recipe_nvidia_libs::_reg_native() {
    local dll="$1"
    local wine_bin="${WINE64:-${WINE:-wine}}"
    unset DBUS_SESSION_BUS_ADDRESS || true
    export NO_AT_BRIDGE=1 DBUS_FATAL_WARNINGS=0
    if type wine_runtime::wine >/dev/null 2>&1; then
        wine_runtime::wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /t REG_SZ /d "native" /f \
            >/dev/null 2>&1 || true
    else
        "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /t REG_SZ /d "native" /f \
            >/dev/null 2>&1 || true
    fi
}

recipe_nvidia_libs::install_prefix() {
    local prefix="${1:-${WINEPREFIX:-${WINE_PREFIX:-}}}"
    local src="" sys32="" wow64="" f
    [ -n "$prefix" ] && [ -d "$prefix/drive_c/windows/system32" ] || return 1

    if recipe_nvidia_libs::installed "$prefix"; then
        type output::success >/dev/null 2>&1 && output::success "nvidia-libs bereits im Prefix"
        return 0
    fi

    src="$(recipe_nvidia_libs::_download)" || {
        type output::warning >/dev/null 2>&1 && output::warning "nvidia-libs Download fehlgeschlagen — CUDA optional"
        return 1
    }

    type output::step >/dev/null 2>&1 && output::step "nvidia-libs → Prefix (CUDA/NVAPI)"
    sys32="$prefix/drive_c/windows/system32"
    wow64="$prefix/drive_c/windows/syswow64"
    for f in nvcuda nvoptix nvcuvid nvencodeapi64 nvapi64 nvofapi64; do
        [ -f "$src/x64/${f}.dll" ] || continue
        cp -f "$src/x64/${f}.dll" "$sys32/${f}.dll" || return 1
        recipe_nvidia_libs::_reg_native "$f"
    done
    if [ -f "$src/x32/nvapi.dll" ] && [ -d "$wow64" ]; then
        cp -f "$src/x32/nvapi.dll" "$wow64/nvapi.dll" || true
        recipe_nvidia_libs::_reg_native "nvapi"
    fi

    printf 'NVIDIA_LIBS_TAG=%s\nINSTALLED_AT=%s\n' \
        "${NVIDIA_LIBS_TAG:-}" "$(date -Iseconds 2>/dev/null || date)" \
        >"$prefix/.rezeptor-nvidia-libs"
    if [ -n "${DATA_ROOT:-}" ]; then
        printf 'PREMIERE_NVIDIA_LIBS=1\nNVIDIA_LIBS_TAG=%s\n' "${NVIDIA_LIBS_TAG:-}" \
            >"${DATA_ROOT}/nvidia-libs.env" 2>/dev/null || true
    fi
    type output::success >/dev/null 2>&1 && output::success "nvidia-libs installiert (CUDA/NVENC)"
    return 0
}

recipe_nvidia_libs::ensure() {
    recipe_nvidia_libs::wanted || {
        if type output::info >/dev/null 2>&1; then
            if [ "${PREMIERE_NVIDIA_LIBS:-auto}" = "0" ]; then
                output::info "nvidia-libs übersprungen (PREMIERE_NVIDIA_LIBS=0)"
            elif recipe_nvidia_libs::host_has_nvidia; then
                output::info "nvidia-libs übersprungen"
            else
                output::info "nvidia-libs übersprungen — Host ohne NVIDIA (AMD/Intel: kein CUDA-Pfad)"
            fi
        fi
        return 0
    }
    recipe_nvidia_libs::install_prefix "$@"
}

# Launch-Env: NVAPI an, wenn Prefix die Libs hat.
recipe_nvidia_libs::export_launch_env() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    if recipe_nvidia_libs::installed "$prefix"; then
        export PROTON_ENABLE_NVAPI=1
        export DXVK_ENABLE_NVAPI=1
        export DXVK_CONFIG="${DXVK_CONFIG:-dxgi.hideNvidiaGpu = False}"
        export PROTON_HIDE_NVIDIA_GPU=0
        export WINE_HIDE_NVIDIA_GPU=0
        # Overrides ergänzen (nicht ersetzen)
        local extra="nvcuda=native;nvapi64=native;nvapi=native;nvcuvid=native;nvencodeapi64=native;nvoptix=native;nvofapi64=native"
        if [ -n "${WINEDLLOVERRIDES:-}" ]; then
            export WINEDLLOVERRIDES="${WINEDLLOVERRIDES};${extra}"
        else
            export WINEDLLOVERRIDES="$extra"
        fi
        return 0
    fi
    return 0
}
