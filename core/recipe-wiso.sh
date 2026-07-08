#!/usr/bin/env bash
# WISO Steuer portable — Wine-Workarounds (Qt/Netzwerk, Proton ohne DXVK).

recipe_wiso::software_dir() {
    local portable_root="$1"
    [ -n "$portable_root" ] || return 1
    [ -d "$portable_root" ] || return 1
    if [ -d "$portable_root/Steuersoftware 2026" ]; then
        echo "$portable_root/Steuersoftware 2026"
        return 0
    fi
    local alt
    alt="$(find "$portable_root" -maxdepth 1 -type d -name 'Steuersoftware*' 2>/dev/null | head -1 || true)"
    [ -n "$alt" ] && [ -d "$alt" ] || return 1
    echo "$alt"
}

# WineHQ / Buhl-Forum: Qt-Plugin lässt wmain26.dll abstürzen (nicht Linux-WLAN).
recipe_wiso::disable_qnetworklistmanager() {
    local sw_dir="$1"
    [ -n "$sw_dir" ] || return 0
    local dll="$sw_dir/networkinformation/qnetworklistmanager.dll"
    local bak="$sw_dir/networkinformation/qnetworklistmanager.dll.bak"
    [ -f "$dll" ] || return 0
    if mv -f "$dll" "$bak" 2>/dev/null; then
        echo "qnetworklistmanager.dll → .bak (WISO-Qt-Startfix)"
        return 0
    fi
    return 1
}

recipe_wiso::qnetwork_disabled() {
    local sw_dir="$1"
    [ -n "$sw_dir" ] || return 1
    local dll="$sw_dir/networkinformation/qnetworklistmanager.dll"
    local bak="$sw_dir/networkinformation/qnetworklistmanager.dll.bak"
    [ ! -f "$dll" ] && [ -f "$bak" ]
}

# wiso-steuer-portable-linux: X11-Treiber im Prefix (Wayland/KDE).
recipe_wiso::ensure_graphics_x11() {
    local wine_cmd="${1:-wine}"
    "$wine_cmd" reg add "HKCU\\Software\\Wine\\Drivers" \
        /v Graphics /t REG_SZ /d x11 /f >/dev/null 2>&1 || true
}

# Proton kopiert DXVK — für WISO wined3d aus default_pfx wiederherstellen.
recipe_wiso::restore_wined3d_prefix() {
    [ "${WINE_METHOD:-}" = "system" ] || [ "${RECIPE_RUNTIME:-}" = "system" ] && return 0
    wine_runtime::init || return 1
    local prefix="${WINEPREFIX:-}"
    local root="${WINE_RUNTIME_ROOT:-${PROTON_PATH:-}}"
    local dll="" dir="" src="" dst=""
    [ -n "$prefix" ] && [ -n "$root" ] || return 1
    for dir in system32 syswow64; do
        for dll in d3d11.dll dxgi.dll d2d1.dll d3d10core.dll; do
            src="$root/files/share/default_pfx/drive_c/windows/$dir/$dll"
            dst="$prefix/drive_c/windows/$dir/$dll"
            [ -f "$src" ] || continue
            cp -f "$src" "$dst" 2>/dev/null || true
        done
    done
    return 0
}

recipe_wiso::export_proton_env() {
    export PROTON_USE_WINED3D=1
    export DXVK_ENABLE=0
    unset WINE_DISABLE_WOW64 2>/dev/null || true
}
