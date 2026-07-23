#!/usr/bin/env bash
# Shared Adobe offline installer helpers (Photoshop, Premiere, …).
# Deploy Set-up.exe → C:\AdobeSetup, IE8/MSXML env, silent-install prep.

adobe_setup::kill_all_wineservers() {
    # Nur Proton-wineserver dieses Prefix — kein globales pkill (andere Rezepte).
    if type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
    elif [ -n "${WINE:-}" ]; then
        "$WINE" wineserver -k 2>/dev/null || true
    fi
}

adobe_setup::ie8_present() {
    local prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    [ -f "$prefix/drive_c/Program Files/Internet Explorer/iexplore.exe" ] \
        || [ -f "$prefix/drive_c/Program Files (x86)/Internet Explorer/iexplore.exe" ]
}

adobe_setup::msxml_is_native() {
    recipe_validate::msxml_is_native "$1"
}

adobe_setup::export_adobe_installer_dll_overrides() {
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;msxml3=native,builtin;msxml6=native,builtin;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin"
}

adobe_setup::apply_adobe_network_registry() {
    wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings" \
        /v AutoDetect /t REG_DWORD /d 0 /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings" \
        /v ProxyEnable /t REG_DWORD /d 0 /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true
}

adobe_setup::fix_installer_case_symlinks() {
    local base="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -d "$base/products" ] || return 0
    [ -f "$base/products/Driver.xml" ] && [ ! -e "$base/products/driver.xml" ] \
        && ln -sf Driver.xml "$base/products/driver.xml"
    [ -f "$base/resources/Config.xml" ] && [ ! -e "$base/resources/config.xml" ] \
        && ln -sf Config.xml "$base/resources/config.xml"
}

adobe_setup::deploy_installer_to_c_drive() {
    local src="$1"
    local dest="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -n "$src" ] && [ -f "$src/Set-up.exe" ] || return 1
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    adobe_setup::fix_installer_case_symlinks
    export ADOBE_INSTALLER_DIR="$dest"
}

adobe_setup::resolve_setup_exe() {
    if [ -n "${ADOBE_INSTALLER_DIR:-}" ] && [ -f "${ADOBE_INSTALLER_DIR}/Set-up.exe" ]; then
        echo "${ADOBE_INSTALLER_DIR}/Set-up.exe"
        return 0
    fi
    [ -f "${WINEPREFIX}/drive_c/AdobeSetup/Set-up.exe" ] \
        && echo "${WINEPREFIX}/drive_c/AdobeSetup/Set-up.exe" && return 0
    return 1
}

adobe_setup::reregister_ie8_dlls() {
    local dll dir="C:\\windows\\syswow64"
    for dll in mshtml.dll jscript.dll vbscript.dll urlmon.dll wininet.dll ieframe.dll shdocvw.dll; do
        wine regsvr32 /S "${dir}\\${dll}" >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done
}

adobe_setup::disable_virtual_desktop() {
    local wine_bin="${WINE:-wine}"
    # Kein Wine-„blauer Desktop“ — App als normales Fenster.
    "$wine_bin" reg delete "HKCU\\Software\\Wine\\X11 Driver" /v Desktop /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg delete "HKCU\\Software\\Wine\\Explorer" /v Desktop /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg delete "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg delete "HKCU\\Software\\Wine\\Explorer\\Desktop" /v Enable /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg add "HKCU\\Software\\Wine\\Explorer\\Desktop" /v Enable /t REG_SZ /d N /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
}

# KC-Guide: msxml3r.dll auch in system32 (Ressourcen für x64-msxml3).
adobe_setup::ensure_msxml3r_system32() {
    local sys32="${WINEPREFIX}/drive_c/windows/system32/msxml3r.dll"
    local wow64="${WINEPREFIX}/drive_c/windows/syswow64/msxml3r.dll"
    [ -f "$sys32" ] && return 0
    [ -f "$wow64" ] || return 0
    cp -f "$wow64" "$sys32" || return 0
    return 0
}

adobe_setup::ensure_native_msxml() {
    local msxml3="${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll"
    local msxml6="${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll"
    local msxml3_64="${WINEPREFIX}/drive_c/windows/system32/msxml3.dll"
    local wine64_bin="${WINE64:-}"
    # Premiere 2024 braucht natives MSXML auch in system32 (x64); wow64 allein reicht nicht.
    if adobe_setup::msxml_is_native "$msxml3" \
        && adobe_setup::msxml_is_native "$msxml6" \
        && adobe_setup::msxml_is_native "$msxml3_64"; then
        adobe_setup::ensure_msxml3r_system32
        return 0
    fi

    output::step "Native MSXML3/MSXML6 (Adobe-Installer)"
    local wt_log="${LOG_DIR}/winetricks_msxml_${TIMESTAMP_ISO}.log"
    if ! recipe_winetricks::run "$wt_log" -f msxml3 msxml6; then
        recipe_hooks::log_err "MSXML winetricks fehlgeschlagen — $wt_log"
        return 1
    fi
    adobe_setup::ensure_msxml3r_system32
    wine_runtime::wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v msxml3 /t REG_SZ /d "native,builtin" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine_runtime::wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v msxml6 /t REG_SZ /d "native,builtin" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine_runtime::wine regsvr32 /S C:\\windows\\syswow64\\msxml3.dll >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine_runtime::wine regsvr32 /S C:\\windows\\syswow64\\msxml6.dll >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    # x64-Registrierung (Premiere ist 64-bit)
    if [ -n "$wine64_bin" ] && [ -x "$wine64_bin" ]; then
        "$wine64_bin" regsvr32 /S C:\\windows\\system32\\msxml3.dll >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    else
        wine_runtime::wine regsvr32 /S C:\\windows\\system32\\msxml3.dll >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    fi
    adobe_setup::msxml_is_native "$msxml3" \
        && adobe_setup::msxml_is_native "$msxml6" \
        && adobe_setup::msxml_is_native "$msxml3_64"
}

adobe_setup::apply_graphics_registry() {
    output::step "Grafik-Registry (DXVK + d2d1 builtin)"
    local wine_bin="${WINE:-wine}" dll
    for dll in d3d11 d3d10core dxgi d3dcompiler_47 d3dcompiler_43 opcservices; do
        "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /t REG_SZ /d "native,builtin" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done
    "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v d2d1 /t REG_SZ /d "builtin" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg add "HKCU\\Software\\Wine\\Direct3D" /v csmt /t REG_DWORD /d 1 /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg add "HKCU\\Software\\Wine\\Direct3D" /v shader_backend /t REG_SZ /d glsl /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg add "HKCU\\Software\\Wine\\Direct3D" /v DirectDrawRenderer /t REG_SZ /d opengl /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
}

adobe_setup::configure_ie8() {
    output::step "IE8 (Adobe-Installer, 5–10 Min.)"
    output::info "Silent-Install nutzt IE-Engine — IE8 muss im Prefix sein"
    if adobe_setup::ie8_present; then
        output::success "IE8 bereits im Prefix"
        adobe_setup::reregister_ie8_dlls
        return 0
    fi
    local wt_log="${LOG_DIR}/winetricks_ie8_${TIMESTAMP_ISO}.log"
    recipe_winetricks::prepare || return 1
    recipe_winetricks::_invoke_with_timeout "$wt_log" 900 -q ie8 || return 1
    if ! adobe_setup::ie8_present; then
        recipe_hooks::log_err "IE8 fehlgeschlagen — $wt_log"
        return 1
    fi
    output::success "IE8 installiert"
    recipe_win10::ensure >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    adobe_setup::reregister_ie8_dlls
    return 0
}

adobe_setup::prepare_adobe_installer_env() {
    adobe_setup::disable_virtual_desktop
    adobe_setup::kill_all_wineservers
    sleep 1
    adobe_setup::ensure_native_msxml || return 1
    adobe_setup::apply_adobe_network_registry
    adobe_setup::export_adobe_installer_dll_overrides
    recipe_win10::ensure >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    adobe_setup::reregister_ie8_dlls
}

adobe_setup::ensure_gdiplus() {
    local wow64="${WINEPREFIX:?}/drive_c/windows/syswow64/gdiplus.dll"
    if recipe_validate::native_pe "$wow64"; then
        return 0
    fi
    local log="${LOG_DIR:-${DATA_ROOT}/logs}/winetricks_gdiplus_${TIMESTAMP_ISO:-$(date +%Y-%m-%d_%H-%M-%S)}.log"
    mkdir -p "$(dirname "$log")"
    output::step "gdiplus (native MS-GDI+)"
    recipe_winetricks::run "$log" gdiplus || {
        recipe_hooks::log_err "gdiplus fehlgeschlagen — $log"
        return 1
    }
    wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v gdiplus /t REG_SZ /d "native" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    recipe_validate::native_pe "$wow64"
}

adobe_setup::run_silent_setup() {
    # Args: optional env flag name for GUI mode (default PHOTOSHOP_INSTALLER_GUI for BC)
    local gui_flag="${1:-PHOTOSHOP_INSTALLER_GUI}"
    adobe_setup::prepare_adobe_installer_env || return 1
    local setup_exe setup_dir installer_args=() install_status=0
    setup_exe="$(adobe_setup::resolve_setup_exe)" || {
        recipe_hooks::die "Set-up.exe nicht gefunden (C:\\AdobeSetup)"
    }
    setup_dir="$(dirname "$setup_exe")"

    if [ "${!gui_flag:-0}" = "1" ]; then
        output::info "GUI-Installer (${gui_flag}=1)"
        installer_args=()
    else
        installer_args=(--silent=1)
        output::info "Silent-Installation (Adobe ESD) — kann mehrere Minuten dauern"
    fi

    output::progress 70 "Adobe Set-up.exe"
    (
        cd "$setup_dir" || exit 1
        wine "./Set-up.exe" "${installer_args[@]}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | while IFS= read -r _line; do
            case "$_line" in
                Progress:*)
                    _pct=$(echo "$_line" | grep -oE '[0-9]+' | tail -1)
                    if [ -n "$_pct" ] && [ "${LAUNCHER_GUI:-0}" = "1" ]; then
                        printf '@progress:%s\n' "$((70 + _pct * 25 / 100))"
                    else
                        echo "$_line"
                    fi
                    ;;
            esac
        done
        exit "${PIPESTATUS[0]}"
    ) || install_status=$?

    adobe_setup::kill_all_wineservers
    return "$install_status"
}
