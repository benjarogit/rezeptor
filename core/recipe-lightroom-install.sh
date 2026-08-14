#!/usr/bin/env bash
# Adobe Lightroom Classic — Proton-GE, Adobe Set-up.exe (silent), Post-Install-Fixes.
#
# Fachliche Vorarbeit: 6im0n/lightroom-classic-on-linux (siehe recipe-lightroom-stubs.sh).
# Hier auf Rezeptor umgesetzt: Proton-GE statt System-Wine, DXVK/vkd3d aus dem
# Proton-Baum statt winetricks, Adobe-Installer über die geteilte adobe_setup-Kette.

if ! type adobe_setup::deploy_installer_to_c_drive >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-adobe-setup.sh"
fi

if ! type lr_stubs::fetch >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-lightroom-stubs.sh"
fi

recipe_lightroom::_env_bool_on() {
    case "${1:-}" in
        1 | true | yes | on | TRUE | YES | ON | True) return 0 ;;
        *) return 1 ;;
    esac
}

recipe_lightroom::ai_masking_enabled() {
    recipe_lightroom::_env_bool_on "${LIGHTROOM_AI_MASKING:-1}"
}

recipe_lightroom::histogram_fix_enabled() {
    recipe_lightroom::_env_bool_on "${LIGHTROOM_HISTOGRAM_FIX:-1}"
}

recipe_lightroom::_app_dir() {
    local exe
    exe="$(lightroom::find_exe "${WINEPREFIX:-${WINE_PREFIX:-}}" 2>/dev/null || true)"
    if [ -n "$exe" ] && [ -f "$exe" ]; then
        dirname "$exe"
        return 0
    fi
    return 1
}

recipe_lightroom::_prefix_runtime_ready() {
    recipe_validate::prefix_initialized "${WINEPREFIX:-}" || return 1
    adobe_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll" \
        && adobe_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll"
}

recipe_lightroom::_run_adobe_installer() {
    adobe_setup::run_silent_setup LIGHTROOM_INSTALLER_GUI || return $?

    local exe_path
    exe_path="$(lightroom::find_exe "$WINEPREFIX" 2>/dev/null || true)"
    [ -n "$exe_path" ] && [ -f "$exe_path" ] || {
        recipe_hooks::log_err "Adobe-Installer beendet, Lightroom.exe fehlt"
        return 1
    }
    output::success "Adobe Lightroom Classic installiert: $exe_path"
    return 0
}

# Dateien im Prefix (ohne wine): Stubs, gepatchtes d2d1, dxvk.conf, Case-Aliase,
# Proxy-version.dll neben Lightroom.exe. Idempotent — auch aus Reparieren/Starten.
recipe_lightroom::apply_stub_files() {
    local prefix app_dir
    prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    [ -n "$prefix" ] && [ -d "$prefix/drive_c/windows/system32" ] || return 1

    lr_stubs::ensure_patched_d2d1 "$prefix" \
        || recipe_hooks::log_warn "d2d1-Patch nicht verfügbar — Histogramm/Start ggf. eingeschränkt"
    lr_stubs::ensure_system_dlls "$prefix" || true
    lr_stubs::ensure_dxvk_conf "$prefix" || true
    lr_stubs::lock_dunamis_feedback "$prefix" || true
    lr_stubs::disable_dead_codecs "$prefix" || true
    if recipe_lightroom::ai_masking_enabled; then
        lr_stubs::ensure_fakeram >/dev/null 2>&1 \
            || recipe_hooks::log_warn "fakeram.so nicht verfügbar — KI-Masken ohne RAM-Deckel"
    fi

    if app_dir="$(recipe_lightroom::_app_dir)"; then
        # Wines PE-Loader ist auf der Platte case-sensitiv, Adobes Importtabellen
        # fragen teils klein geschrieben nach MixedCase-DLLs.
        adobe_setup::ensure_lowercase_pe_aliases "$app_dir" || true
        lr_stubs::disable_growth_sdk "$app_dir" || true
        lr_stubs::ensure_version_proxy "$app_dir" \
            || recipe_hooks::log_warn "version-Proxy fehlt — Exportieren/Einstellungen kopieren ggf. leer"
    fi
    return 0
}

# Registry (braucht wine): Win11, DLL-Overrides, ScreenDepth, WinRT-Klassen.
recipe_lightroom::apply_registry() {
    local wine_bin="${WINE:-wine}" exe d2d1_ov
    command -v "$wine_bin" >/dev/null 2>&1 || return 0

    # Der Adobe-Standalone-Installer prüft die OS-Version selbst und lehnt < Win10 ab.
    recipe_win10::ensure win11 >>"${LOG_FILE:-/dev/null}" 2>&1 || true

    adobe_setup::apply_graphics_registry >>"${LOG_FILE:-/dev/null}" 2>&1 || true

    # Echtes D3D12 aus vkd3d-proton — Wines Builtin meldet einen Platzhalter-Adapter,
    # dann bleibt der GPU-Schalter in Voreinstellungen → Leistung grau.
    for exe in d3d12 d3d12core; do
        "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$exe" /t REG_SZ /d native /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done

    d2d1_ov="$(lr_stubs::d2d1_override)"
    "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v d2d1 /t REG_SZ /d "$d2d1_ov" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v hnetcfg /t REG_SZ /d "native,builtin" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v mfplat /t REG_SZ /d native /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    # Lightroom zählt beim Öffnen des Export-Dialogs Brenner auf; Wines discburning
    # blockiert dabei den UI-Thread → die App friert ein.
    "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v discburning /t REG_SZ /d "" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true

    for exe in Lightroom.exe lightroom.exe; do
        # Xwayland-Tiefe 24 vs. ARGB-32: „Importieren“ bricht sonst mit BadMatch ab.
        "$wine_bin" reg add "HKCU\\Software\\Wine\\AppDefaults\\${exe}\\X11 Driver" \
            /v ScreenDepth /t REG_SZ /d 32 /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        # Proxy-version.dll nur für Lightroom selbst — global bricht sie andere Apps.
        "$wine_bin" reg add "HKCU\\Software\\Wine\\AppDefaults\\${exe}\\DllOverrides" \
            /v version /t REG_SZ /d "native,builtin" /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done

    # Adobe meldet sich sonst offline und fällt in einen kaputten Offline-Pfad.
    "$wine_bin" reg add "HKLM\\System\\CurrentControlSet\\Services\\NlaSvc\\Parameters\\Internet" \
        /v EnableActiveProbing /t REG_DWORD /d 1 /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true

    if recipe_lightroom::ai_masking_enabled; then
        # Wine zeigt seine eigenen Storage.Streams-Klassen nach jedem Prefix-Update
        # wieder an — deshalb bei jedem Lauf neu setzen.
        lr_stubs::register_winrt_classes
    fi
    return 0
}

recipe_lightroom::post_install() {
    output::progress 95 "Post-Install (Stubs, Registry, GPU)"
    adobe_setup::kill_all_wineservers
    sleep 1
    adobe_setup::disable_virtual_desktop
    recipe_lightroom::apply_stub_files || return 1
    recipe_lightroom::apply_registry || return 1
    return 0
}

recipe_lightroom::install() {
    local _err=0 installer_dir="" pkg exe_path
    if [ -z "${LOG_FILE:-}" ] || [ ! -f "${LOG_FILE}" ]; then
        recipe_hooks::log_setup "Lightroom_Install"
    fi
    recipe_hooks::_source sharedFuncs.sh
    recipe_hooks::_source recipe-fonts.sh
    recipe_hooks::_source recipe-validate.sh

    output::section "Adobe Lightroom Classic — Installation"
    output::progress 2 "Vorbereitung"

    if ! type recipe_source::extract_archive >/dev/null 2>&1; then
        recipe_hooks::_source recipe-source.sh 2>/dev/null || true
    fi

    if ! installer_dir="$(lightroom::resolve_installer_dir "$PROJECT_ROOT")"; then
        recipe_hooks::die "Set-up.exe fehlt — im Install-Dialog den Ordner mit Set-up.exe wählen (mit products/LTRM daneben)"
    fi
    output::info "Installer: $installer_dir/Set-up.exe"
    output::info "Datenordner: $DATA_ROOT"

    export SCR_PATH="$DATA_ROOT"
    export WINE_PREFIX="$DATA_ROOT/prefix"
    export CACHE_PATH="$(wine_software_cache_dir)"

    recipe_hooks::install_prefix || exit 1

    if ! recipe_lightroom::_prefix_runtime_ready; then
        output::progress 15 "Windows 11 (Adobe-OS-Prüfung)"
        recipe_win10::ensure win11 || _err=1

        for pkg in atmlib corefonts fontsmooth=rgb gdiplus; do
            output::progress 25 "winetricks: $pkg"
            recipe_winetricks::run "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$pkg" \
                || _err=1
        done

        adobe_setup::ensure_native_msxml || _err=1

        output::progress 58 "Visual C++ Runtime (Microsoft)"
        recipe_vcrun::ensure "${LOG_DIR}/vcrun_${TIMESTAMP_ISO}.log" || _err=1
    else
        output::success "Prefix-Komponenten bereits vorhanden (natives MSXML erkannt)"
    fi

    output::progress 62 "Proton-GE Grafik-DLLs (DXVK + vkd3d D3D12)"
    wine_runtime::deploy_proton_graphics_dlls || _err=1
    # Stubs vor dem Installer: hnetcfg/mfplat fehlen sonst schon der Installer-UI.
    recipe_lightroom::apply_stub_files || _err=1
    recipe_lightroom::apply_registry || _err=1

    output::progress 64 "Installer nach C: kopieren"
    adobe_setup::deploy_installer_to_c_drive "$installer_dir" || _err=1
    output::progress 66 "IE-Engine (Adobe-Installer)"
    adobe_setup::configure_ie8 || _err=1

    if [ "$_err" -ne 0 ]; then
        output::error "Voraussetzungen fehlgeschlagen — Log: $LOG_FILE"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    output::progress 69 "Adobe Set-up vorbereiten"
    if ! recipe_lightroom::_run_adobe_installer; then
        output::error "Adobe-Installation fehlgeschlagen — Log: $LOG_FILE"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    recipe_lightroom::post_install || _err=1

    output::progress 97 "Schriften & ClearType"
    adobe_setup::ensure_gdiplus || _err=1
    recipe_fonts::ensure "${LOG_DIR}/winetricks_fonts_${TIMESTAMP_ISO}.log" >>"${LOG_FILE:-/dev/null}" 2>&1 || _err=1
    recipe_fonts::registry >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    adobe_setup::kill_all_wineservers

    exe_path="$(lightroom::find_exe "$WINEPREFIX" 2>/dev/null || true)"
    if [ -n "$exe_path" ] && [ -f "$exe_path" ]; then
        recipe_hooks::state_set WORK_ROOT "$(cd "$(dirname "$exe_path")" && pwd)"
    fi
    if type recipe_app_link::ensure >/dev/null 2>&1; then
        recipe_app_link::ensure || true
    fi

    output::progress 99 "Validieren"
    if ! bash "${RECIPE_DIR}/validate.sh" >>"${LOG_FILE:-/dev/null}" 2>&1; then
        _err=1
    fi

    if [ "$_err" -ne 0 ]; then
        output::error "Installation unvollständig — Rezeptor → Reparieren"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    output::success "Lightroom-Classic-Rezept installiert"
    output::progress 100 "Installation abgeschlossen"
    recipe_hooks::emit_log_paths
    output::info "Start über Rezeptor → Starten"
}
