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

# wined3d.dll (Proton) braucht libvkd3d-*.dll, die ein normaler wineboot-Prefix NICHT enthält —
# erst per deploy_proton_graphics_dlls reinkopieren, dann d3d11/dxgi/d2d1/d3d10core von DXVK
# (Vulkan, bricht Qt-WebEngine) zurück auf wined3d (OpenGL, aus default_pfx) drehen.
recipe_wiso::restore_wined3d_prefix() {
    [ "${WINE_METHOD:-}" = "system" ] || [ "${RECIPE_RUNTIME:-}" = "system" ] && return 0
    wine_runtime::restore_wined3d_dlls
}

# Portable-Root: start.exe / Patch.exe / VC_redist (Buhl ReadMe)
recipe_wiso::find_root_exe() {
    local root="$1" want="$2"
    local f base lc
    [ -n "$root" ] && [ -d "$root" ] || return 1
    lc="${want,,}"
    for f in "$root"/*.exe "$root"/*/*.exe; do
        [ -f "$f" ] || continue
        base="${f##*/}"
        if [ "${base,,}" = "$lc" ]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

recipe_wiso::portable_start_exe() {
    recipe_wiso::find_root_exe "$1" "start.exe"
}

recipe_wiso::portable_patch_exe() {
    recipe_wiso::find_root_exe "$1" "Patch.exe"
}

recipe_wiso::portable_vc_redist() {
    local root="$1" f
    recipe_wiso::find_root_exe "$root" "VC_redist.x64.exe" && return 0
    for f in "$root"/VC_redist*.exe "$root"/vc_redist*.exe; do
        [ -f "$f" ] || continue
        echo "$f"
        return 0
    done
    return 1
}

recipe_wiso::run_vc_redist() {
    local exe="$1" log="${2:-/dev/null}"
    [ -f "$exe" ] || return 0
    wine "$exe" /install /quiet /norestart >>"$log" 2>&1 \
        || wine "$exe" /quiet /norestart >>"$log" 2>&1 \
        || wine "$exe" >>"$log" 2>&1 || return 1
    return 0
}

recipe_wiso::run_patch() {
    local exe="$1" log="${2:-/dev/null}"
    [ -f "$exe" ] || return 0
    ( cd "$(dirname "$exe")" && wine "./$(basename "$exe")" >>"$log" 2>&1 ) \
        || wine "$exe" >>"$log" 2>&1 || return 1
    return 0
}

recipe_wiso::notify_icon() {
    local portable_root="${1:-${WISO_PORTABLE_ROOT:-}}"
    local data_root="${2:-${DATA_ROOT:-}}"
    local icon=""
    if [ -n "$portable_root" ]; then
        icon="$(find "$portable_root" -maxdepth 3 -name 'wisoakt.ico' -type f 2>/dev/null | head -1 || true)"
    fi
    if [ -z "$icon" ] && [ -n "$data_root" ]; then
        icon="$(find "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" \
            -path '*/apps/wiso-steuer-wine.png' 2>/dev/null | head -1 || true)"
    fi
    [ -n "$icon" ] && echo "$icon" || echo "wine"
}

# --- Declarative install_steps helpers (called via module: recipe_wiso::…) ---

recipe_wiso::portable_root() {
    echo "${WISO_PORTABLE_ROOT:-${RECIPE_WORK_ROOT:-}}"
}

recipe_wiso::after_prepare() {
    local portable_root="${RECIPE_WORK_ROOT:?}"
    local _sw="" _exe=""
    export WISO_PORTABLE_ROOT="$portable_root"
    export RECIPE_SOURCE_ROOT="$portable_root"
    recipe_hooks::require_portable_source || return 1

    if [ -d "$portable_root/Steuersoftware 2026" ]; then
        _sw="Steuersoftware 2026"
    else
        _sw="$(find "$portable_root" -maxdepth 1 -type d -name 'Steuersoftware*' 2>/dev/null | head -1)"
        _sw="${_sw##*/}"
    fi
    _exe="$(find "$portable_root" -maxdepth 3 -name 'wiso*.exe' -type f 2>/dev/null | head -1 || true)"
    if [ -z "$_sw" ] && [ -z "$_exe" ]; then
        recipe_hooks::log_err "Kein Steuersoftware* Ordner und keine wiso*.exe unter $portable_root"
        return 1
    fi
    output::info "Quelltyp: ${RECIPE_SOURCE_TYPE}"
    output::info "Portable: $portable_root"
    [ -n "$_sw" ] && output::info "Software-Ordner: $_sw"
    [ -n "$_exe" ] && output::info "EXE: $_exe"
    return 0
}

recipe_wiso::deploy_portable_launcher() {
    local portable_root
    portable_root="$(recipe_wiso::portable_root)"
    [ -n "$portable_root" ] && [ -d "$portable_root" ] || return 1
    mkdir -p "$DATA_ROOT/bin"
    cp -f "$RECIPE_DIR/assets/wiso-mit-wine.sh" "$DATA_ROOT/bin/wiso-launch.sh"
    chmod +x "$DATA_ROOT/bin/wiso-launch.sh"
    env_file_set "$DATA_ROOT/portable.env" WISO_PORTABLE_ROOT "$portable_root"
    local _wiso_ver=""
    recipe_hooks::_source recipe-validate.sh
    _wiso_ver="$(recipe_validate::wiso_portable_version "$portable_root" || true)"
    [ -n "$_wiso_ver" ] && env_file_set "$DATA_ROOT/portable.env" WISO_PORTABLE_VERSION "$_wiso_ver"
    cp -f "$DATA_ROOT/bin/wiso-launch.sh" "$portable_root/wiso-mit-wine.sh" 2>/dev/null || true
    chmod +x "$portable_root/wiso-mit-wine.sh" 2>/dev/null || true
    output::success "Launcher-Skript bereit"
    return 0
}

recipe_wiso::apply_qt_network_fix() {
    local portable_root sw_dir
    portable_root="$(recipe_wiso::portable_root)"
    sw_dir="$(recipe_wiso::software_dir "$portable_root" || true)"
    [ -n "$sw_dir" ] || return 0
    if recipe_wiso::qnetwork_disabled "$sw_dir"; then
        output::success "Qt-Startfix bereits aktiv (Linux-Internet unverändert)"
        return 0
    fi
    output::progress 28 "Qt-Startfix (qnetworklistmanager.dll)"
    if recipe_wiso::disable_qnetworklistmanager "$sw_dir"; then
        output::success "Qt-Plugin deaktiviert — WLAN/LAN bleibt aktiv"
        return 0
    fi
    recipe_hooks::log_err "Konnte qnetworklistmanager.dll nicht umbenennen — $sw_dir/networkinformation/"
    return 1
}

recipe_wiso::apply_wined3d() {
    output::step "Wine-Grafik (wined3d statt DXVK für Qt/WebEngine)"
    if recipe_wiso::restore_wined3d_prefix; then
        output::success "Grafik-DLLs bereit (wined3d aktiv)"
    else
        recipe_hooks::log_err "Grafik-DLLs (wined3d/libvkd3d) fehlgeschlagen"
        return 1
    fi
    recipe_wiso::ensure_graphics_x11 "${WINE:-wine}"
    return 0
}

recipe_wiso::optional_vc_redist() {
    local portable_root vc_exe
    portable_root="$(recipe_wiso::portable_root)"
    vc_exe="$(recipe_wiso::portable_vc_redist "$portable_root" 2>/dev/null || true)"
    [ -n "$vc_exe" ] || return 0
    output::progress 90 "VC_redist.x64.exe (Portable-Bundle)"
    if recipe_wiso::run_vc_redist "$vc_exe" "${LOG_FILE:-/dev/null}"; then
        output::success "VC_redist.x64.exe installiert"
    else
        output::warning "VC_redist optional fehlgeschlagen (vcrun2019 bereits im Prefix)"
        recipe_hooks::log_err "VC_redist fehlgeschlagen — $vc_exe"
    fi
    return 0
}

recipe_wiso::optional_patch_exe() {
    local portable_root patch_exe
    portable_root="$(recipe_wiso::portable_root)"
    patch_exe="$(recipe_wiso::portable_patch_exe "$portable_root" 2>/dev/null || true)"
    [ -n "$patch_exe" ] || return 0
    output::progress 92 "Optionaler Patch.exe (Windows-Host-Block — unter Linux oft ohne Wirkung)"
    if recipe_wiso::run_patch "$patch_exe" "${LOG_FILE:-/dev/null}"; then
        output::success "Patch.exe ausgeführt"
    else
        # Kein ERROR-Log: erwartet unter Proton/Wine, Installation läuft weiter
        output::info "Patch.exe übersprungen — unter Linux meist nicht nötig (optionaler Windows-Patch)"
    fi
    return 0
}

recipe_wiso::optional_fix_root() {
    local fix="${WISO_FIX_ROOT:-${RECIPE_FIX_ROOT:-}}"
    [ -n "$fix" ] || return 0
    env_file_set "$DATA_ROOT/portable.env" WISO_FIX_ROOT "$fix"
    recipe_install::apply_fix "$fix" "${LOG_FILE:-/dev/null}" wine || return 1
    return 0
}

recipe_wiso::ensure_x11_driver() {
    wine reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /t REG_SZ /d x11 /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    return 0
}

# Qt-Custom-Titlebar unter Wine: Header/Sidebar-Überlappung.
# Fix: DPI fest 96 + Qt High-DPI-Skalierung aus (Host-Skalierung bricht Client-Insets).
recipe_wiso::apply_ui_layout_fix() {
    local log="${LOG_FILE:-${DATA_ROOT:-}/wiso-runtime.log}"
    export WISO_FORCE_DPI="${WISO_FORCE_DPI:-96}"
    export WINE_LOGPIXELS="${WINE_LOGPIXELS:-$WISO_FORCE_DPI}"
    if type recipe_dpi::logpixels >/dev/null 2>&1; then
        recipe_dpi::logpixels
    else
        wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "${WINE_LOGPIXELS}" /f \
            >>"$log" 2>&1 || true
    fi
    # Qt 5/6: keine automatische Screen-Skalierung (Wine DWM-Stubs sonst kaputt).
    export QT_AUTO_SCREEN_SCALE_FACTOR=0
    export QT_ENABLE_HIGHDPI_SCALING=0
    export QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-1}"
    export QT_FONT_DPI="${QT_FONT_DPI:-$WINE_LOGPIXELS}"
    echo "[recipe_wiso] UI-Layout: LogPixels=$WINE_LOGPIXELS QT_SCALE_FACTOR=$QT_SCALE_FACTOR" \
        >>"$log" 2>/dev/null || true
    return 0
}

recipe_wiso::install_desktop() {
    recipe_hooks::_source recipe-desktop.sh
    recipe_desktop::install
}

# Kompatibilität für repair.sh (Argumente werden ignoriert — DATA_ROOT/RECIPE_* zählen)
recipe_wiso::install_desktop_entry() {
    recipe_hooks::_source recipe-desktop.sh
    recipe_desktop::refresh_if_present
}
