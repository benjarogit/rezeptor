#!/usr/bin/env bash
# Shared Adobe offline installer helpers (Photoshop, Premiere, …).
# Deploy Set-up.exe → C:\AdobeSetup, IE8/MSXML env, silent-install prep.

if ! type recipe_validate::dll_is_wine_builtin >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-validate.sh"
fi

adobe_setup::kill_all_wineservers() {
    # Nur Proton-wineserver dieses Prefix — kein globales pkill (andere Rezepte).
    if type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
    elif [ -n "${WINE:-}" ]; then
        "$WINE" wineserver -k 2>/dev/null || true
    fi
}

# iexplore.exe legt Wine in jedem Prefix an — nur natives mshtml belegt echtes IE8.
adobe_setup::ie8_present() {
    local prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    recipe_validate::native_pe "$prefix/drive_c/windows/syswow64/mshtml.dll" \
        || recipe_validate::native_pe "$prefix/drive_c/windows/system32/mshtml.dll"
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

# Ensure both case spellings exist (ISO often lowercases; Adobe may ask for either).
# Symlink preferred; cp fallback if ln fails (Permission denied on some mounts).
adobe_setup::_link_or_copy_case() {
    local dir="$1" existing="$2" missing="$3"
    local src="$dir/$existing" dest="$dir/$missing" err=""

    if [ -e "$dest" ]; then
        if [ "$src" -ef "$dest" ] 2>/dev/null; then
            return 0
        fi
        return 0
    fi

    if ln -sfn "$existing" "$dest" 2>/dev/null; then
        type output::info >/dev/null 2>&1 && output::info "Case-Alias: $missing → $existing"
        return 0
    fi
    err="$(ln -sfn "$existing" "$dest" 2>&1 || true)"
    if [ -n "${ERROR_LOG:-}" ]; then
        echo "[$(date '+%H:%M:%S')] WARN: Symlink $missing: ${err:-failed}" >>"$ERROR_LOG"
    fi
    if cp -f "$src" "$dest" 2>/dev/null; then
        type output::info >/dev/null 2>&1 \
            && output::info "Case-Alias: $missing (Kopie — Symlink nicht möglich)"
        [ -n "${ERROR_LOG:-}" ] \
            && echo "[$(date '+%H:%M:%S')] INFO: Case-Alias $missing via cp" >>"$ERROR_LOG"
        return 0
    fi
    type recipe_hooks::log_err >/dev/null 2>&1 \
        && recipe_hooks::log_err "Case-Alias $dir/$missing fehlgeschlagen (${err:-cp failed}) — weiter ohne Alias"
    return 0
}

adobe_setup::_ensure_case_pair() {
    local dir="$1" name_a="$2" name_b="$3"
    local fa="$dir/$name_a" fb="$dir/$name_b"

    [ -d "$dir" ] || return 0

    if [ -f "$fa" ] && [ ! -e "$fb" ]; then
        adobe_setup::_link_or_copy_case "$dir" "$name_a" "$name_b"
        return 0
    fi
    if [ -f "$fb" ] && [ ! -e "$fa" ]; then
        adobe_setup::_link_or_copy_case "$dir" "$name_b" "$name_a"
        return 0
    fi
    return 0
}

# Back-compat wrapper (canonical, alias) — now bidirectional via pair.
adobe_setup::_ensure_case_alias() {
    adobe_setup::_ensure_case_pair "$1" "$2" "$3"
}

adobe_setup::fix_installer_case_symlinks() {
    local base="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -d "$base" ] || return 0
    adobe_setup::_ensure_case_pair "$base/products" "Driver.xml" "driver.xml"
    adobe_setup::_ensure_case_pair "$base/resources" "Config.xml" "config.xml"
}

adobe_setup::diagnose_failed_install() {
    local rc="${1:-?}"
    local base="${WINEPREFIX:-}/drive_c/AdobeSetup"
    local log="${ERROR_LOG:-${LOG_FILE:-/dev/null}}"
    local drive_c="${WINEPREFIX:-}/drive_c"
    {
        echo "=== Adobe-Install Diagnose (exit=$rc) ==="
        echo "Zeit: $(date -Iseconds 2>/dev/null || date)"
        echo "RECIPE_ID=${RECIPE_ID:-}"
        echo "WINEPREFIX=${WINEPREFIX:-}"
        echo "DATA_ROOT=${DATA_ROOT:-}"
        echo "LOG_FILE=${LOG_FILE:-}"
        echo "ERROR_LOG=${ERROR_LOG:-}"
        if command -v findmnt >/dev/null 2>&1 && [ -n "${WINEPREFIX:-}" ]; then
            echo "FS: $(findmnt -no FSTYPE,OPTIONS,TARGET -T "$WINEPREFIX" 2>/dev/null || echo '?')"
        fi
        if command -v df >/dev/null 2>&1 && [ -n "${WINEPREFIX:-}" ]; then
            echo "Disk:"
            df -h "$WINEPREFIX" 2>/dev/null | tail -1 || true
        fi
        if [ -d "$base" ]; then
            echo "AdobeSetup:"
            ls -la "$base" 2>/dev/null | head -30 || true
            echo "resources/:"
            ls -la "$base/resources" 2>/dev/null | head -40 || true
            echo "products/ (head):"
            ls -la "$base/products" 2>/dev/null | head -20 || true
            for f in \
                "$base/resources/Config.xml" \
                "$base/resources/config.xml" \
                "$base/products/Driver.xml" \
                "$base/products/driver.xml" \
                "$base/Set-up.exe"; do
                if [ -e "$f" ]; then
                    echo "  present: $f ($(stat -c '%A %U:%G %s' "$f" 2>/dev/null || echo '?'))"
                    [ -L "$f" ] && echo "    symlink → $(readlink "$f" 2>/dev/null || true)"
                else
                    echo "  missing: $f"
                fi
            done
            # Case-pair sanity (ext4): one spelling without the other → Installer oft Exit 103
            if [ -e "$base/products/driver.xml" ] && [ ! -e "$base/products/Driver.xml" ]; then
                echo "WARN: Case-Mismatch products/: driver.xml vorhanden, Driver.xml fehlt — Case-Pair greift nicht oder Deploy zu früh"
            fi
            if [ -e "$base/products/Driver.xml" ] && [ ! -e "$base/products/driver.xml" ]; then
                echo "WARN: Case-Mismatch products/: Driver.xml vorhanden, driver.xml fehlt — Case-Pair greift nicht oder Deploy zu früh"
            fi
            if [ -e "$base/resources/Config.xml" ] && [ ! -e "$base/resources/config.xml" ]; then
                echo "WARN: Case-Mismatch resources/: Config.xml vorhanden, config.xml fehlt"
            fi
            if [ -e "$base/resources/config.xml" ] && [ ! -e "$base/resources/Config.xml" ]; then
                echo "WARN: Case-Mismatch resources/: config.xml vorhanden, Config.xml fehlt"
            fi
        else
            echo "AdobeSetup fehlt: $base"
        fi
        if [ -d "$drive_c" ]; then
            # Fehlende native Komponenten sind die häufigste 103-Ursache — zuerst zeigen.
            echo "Prefix-Komponenten:"
            for _dll in windows/syswow64/msxml3.dll windows/syswow64/msxml6.dll \
                windows/system32/msxml3.dll windows/syswow64/gdiplus.dll \
                windows/syswow64/atmlib.dll windows/syswow64/mshtml.dll \
                windows/syswow64/msvcp140.dll; do
                if [ ! -f "$drive_c/$_dll" ]; then
                    echo "  fehlt:   $_dll"
                elif recipe_validate::dll_is_wine_builtin "$drive_c/$_dll"; then
                    echo "  builtin: $_dll (Wine — nicht nativ)"
                else
                    echo "  nativ:   $_dll"
                fi
            done
            [ -f "${WINEPREFIX:-}/winetricks.log" ] \
                && echo "winetricks: $(tr '\n' ' ' <"${WINEPREFIX}/winetricks.log" 2>/dev/null)"
            command -v file >/dev/null 2>&1 \
                && echo "file: $(file --version 2>/dev/null | head -1)"

            echo "Adobe-Installer-Logs (priorisiert, max 8):"
            # Nur echte Logdateien — Paketdaten (.pima/.sig) sonst als Binärmüll im Report.
            {
                find "$drive_c" -type f \( -iname '*.log' -o -iname '*setup*.txt' \) \
                    \( -ipath '*/Adobe/*' -o -ipath '*/HDBox/*' -o -ipath '*/PDApp/*' \
                    -o -ipath '*/ACC/*' \) 2>/dev/null | head -40
                find "$drive_c" -type f \( -iname '*.log' -o -iname '*setup*.txt' \) 2>/dev/null \
                    | grep -viE 'vcredist|dd_vcredist|Package Cache' \
                    | head -20
            } | awk 'NF && !seen[$0]++' | head -8 | while IFS= read -r lf; do
                if ! grep -Iq . "$lf" 2>/dev/null; then
                    echo "  --- $lf (binär, übersprungen) ---"
                    continue
                fi
                echo "  --- $lf (tail) ---"
                tail -n 40 "$lf" 2>/dev/null || true
            done
        fi
        echo "=== Ende Diagnose ==="
    } | tee -a "${LOG_FILE:-/dev/null}" >>"$log" 2>/dev/null || true

    type output::error >/dev/null 2>&1 \
        && output::error "Adobe Set-up exit $rc — Diagnose in ERROR_LOG / Install-Log"
    type output::info >/dev/null 2>&1 \
        && output::info "Log: ${LOG_FILE:-?} · Fehlerlog: ${ERROR_LOG:-?}"
}

adobe_setup::deploy_installer_to_c_drive() {
    local src="$1"
    local dest="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -n "$src" ] && [ -f "$src/Set-up.exe" ] || return 1
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    chmod -R u+rwX "$dest" 2>/dev/null || true
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

# Der Adobe-Installer zeigt seine Oberfläche in einem IE-Steuerelement. Wines eigene
# Engine reicht dafür bei Proton-GE; echtes IE8 kostet 5–10 Min. und ist der brüchigste
# winetricks-Schritt — deshalb erst nach einem Fehlschlag (siehe run_silent_setup).
adobe_setup::configure_ie8() {
    output::step "IE-Engine (Adobe-Installer)"
    if adobe_setup::ie8_present; then
        output::success "Natives IE8 im Prefix"
    else
        output::info "Wine-eigene IE-Engine — IE8 nur bei Fehlschlag des Installers"
    fi
    adobe_setup::reregister_ie8_dlls
    return 0
}

adobe_setup::install_ie8() {
    output::step "IE8 nachinstallieren (5–10 Min.)"
    local wt_log="${LOG_DIR}/winetricks_ie8_${TIMESTAMP_ISO}.log"
    local attempt rc=1
    recipe_winetricks::sanitize_win7sp1_cache || true
    recipe_winetricks::prepare || return 1
    for attempt in 1 2; do
        set +e
        recipe_winetricks::_invoke_with_timeout "$wt_log" 900 -q ie8
        rc=$?
        set -e
        [ "$rc" -eq 0 ] && break
        [ "$attempt" -eq 1 ] || break
        output::warning "IE8-Setup fehlgeschlagen — win7sp1-Cache löschen und erneut versuchen"
        recipe_winetricks::purge_win7sp1_cache || true
        recipe_winetricks::sanitize_win7sp1_cache || true
    done
    [ "$rc" -eq 0 ] || return 1
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
        output::info "Vollständige Ausgabe landet im Install-Log; bei Fehler zusätzlich Diagnose im Fehlerlog"
    fi

    output::progress 70 "Adobe Set-up.exe"
    adobe_setup::_invoke_setup "$setup_dir" "${installer_args[@]}" || install_status=$?

    # Scheitert der Installer und steckt nur Wines IE-Engine im Prefix: echtes IE8
    # nachziehen und genau einmal wiederholen.
    if [ "$install_status" -ne 0 ] && ! adobe_setup::ie8_present; then
        output::warning "Set-up.exe exit ${install_status} — IE8 nachinstallieren und einmal wiederholen"
        if adobe_setup::install_ie8; then
            adobe_setup::prepare_adobe_installer_env || true
            install_status=0
            output::progress 70 "Adobe Set-up.exe (2. Versuch)"
            adobe_setup::_invoke_setup "$setup_dir" "${installer_args[@]}" || install_status=$?
        else
            output::warning "IE8-Nachinstallation fehlgeschlagen — Diagnose folgt"
        fi
    fi

    if [ "$install_status" -ne 0 ]; then
        adobe_setup::diagnose_failed_install "$install_status"
        recipe_hooks::emit_log_paths 2>/dev/null || true
    fi
    return "$install_status"
}

adobe_setup::_invoke_setup() {
    local setup_dir="$1" install_status=0
    shift
    (
        cd "$setup_dir" || exit 1
        # Alles nach LOG; Progress zusätzlich als GUI-Tag
        wine "./Set-up.exe" "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | while IFS= read -r _line; do
            case "$_line" in
                Progress:*)
                    _pct=$(echo "$_line" | grep -oE '[0-9]+' | tail -1)
                    if [ -n "$_pct" ] && [ "${LAUNCHER_GUI:-0}" = "1" ]; then
                        printf '@progress:%s\n' "$((70 + _pct * 25 / 100))"
                    else
                        echo "$_line"
                    fi
                    ;;
                *[Ee][Rr][Rr][Oo][Rr]*|*[Ff]atal*|*[Ff]ailed*|Exit\ [Cc]ode*)
                    echo "$_line"
                    [ -n "${ERROR_LOG:-}" ] && echo "[$(date '+%H:%M:%S')] $_line" >>"$ERROR_LOG"
                    ;;
            esac
        done
        exit "${PIPESTATUS[0]}"
    ) || install_status=$?

    adobe_setup::kill_all_wineservers
    return "$install_status"
}
