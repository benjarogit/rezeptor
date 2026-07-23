#!/usr/bin/env bash
# Premiere Pro 2024 — Proton-GE, Adobe Set-up.exe (silent), schlanker Post-Install.
# KC-Guide: DXVK (via Proton), corefonts, native msxml3 (x64), gdiplus, ICU-Duplikate.

if ! type adobe_setup::deploy_installer_to_c_drive >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-adobe-setup.sh"
fi

recipe_premiere::_prefix_runtime_ready() {
    recipe_validate::prefix_initialized "${WINEPREFIX:-}" || return 1
    adobe_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll" \
        && adobe_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll" \
        && adobe_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/system32/msxml3.dll"
}

recipe_premiere::_run_adobe_installer() {
    adobe_setup::run_silent_setup PREMIERE_INSTALLER_GUI || return $?

    local exe_path
    exe_path="$(premiere::find_exe "$WINEPREFIX" 2>/dev/null || true)"
    [ -n "$exe_path" ] && [ -f "$exe_path" ] || {
        recipe_hooks::log_err "Adobe-Installer beendet, Adobe Premiere Pro.exe fehlt"
        return 1
    }
    output::success "Adobe Premiere Pro installiert: $exe_path"
    return 0
}

# Premiere 2024 importiert dvacrashreporter.dll hart (Frontend/DisplaySurface).
# Umbenennen → sofortiger Exit (status c0000135). Frühere .rezeptor-disabled wiederherstellen.
# Crashpad-EXE (kein Import) darf optional deaktiviert bleiben — aktuell lassen wir sie.
recipe_premiere::disable_crash_reporters() {
    local exe_dir="" f base
    exe_dir="$(dirname "$(premiere::find_exe "${WINEPREFIX:-${WINE_PREFIX:-}}" 2>/dev/null || true)" 2>/dev/null || true)"
    [ -n "$exe_dir" ] && [ -d "$exe_dir" ] || return 0
    shopt -s nullglob 2>/dev/null || true
    for f in "$exe_dir"/*.rezeptor-disabled; do
        [ -f "$f" ] || continue
        base="${f%.rezeptor-disabled}"
        case "$(basename "$base")" in
            dvacrashreporter.dll|dvacrashhandler.dll|sentry_crashpad.dll)
                mv -f "$f" "$base" || true
                echo "Crash-DLL wiederhergestellt (Import nötig): $(basename "$base")"
                ;;
        esac
    done
    shopt -u nullglob 2>/dev/null || true
    return 0
}

# Drover/UXP: Debug-Database — D2D unter Wine oft schwarze Panels.
recipe_premiere::apply_ui_workarounds() {
    local pref_root="" db="" tmp=""
    pref_root="${WINEPREFIX:-${WINE_PREFIX:-}}/drive_c/users/steamuser/AppData/Roaming/Adobe/Premiere Pro/24.0"
    [ -d "$pref_root" ] || pref_root="$(find "${WINEPREFIX:-${WINE_PREFIX:-}}/drive_c/users" \
        -path '*/AppData/Roaming/Adobe/Premiere Pro/2*/' -type d 2>/dev/null | sort | tail -1)"
    [ -n "$pref_root" ] && [ -d "$pref_root" ] || return 0
    db="$pref_root/Debug Database.txt"
    mkdir -p "$pref_root"
    if [ ! -f "$db" ]; then
        printf '%s\t%s\t%s\n' \
            "Suppress D2D in Drover V7" "true" "true" \
            "Use D2D Supplier" "false" "false" \
            >"$db"
        echo "Premiere UI: Debug Database angelegt (D2D off)"
        return 0
    fi
    tmp="$(mktemp)" || return 0
    # Bestehende Keys überschreiben / fehlende ergänzen
    awk -F'\t' '
        BEGIN { OFS="\t" }
        $1=="Suppress D2D in Drover V7" { print $1,"true","true"; seen_s=1; next }
        $1=="Use D2D Supplier" { print $1,"false","false"; seen_d=1; next }
        { print }
        END {
            if (!seen_s) print "Suppress D2D in Drover V7","true","true"
            if (!seen_d) print "Use D2D Supplier","false","false"
        }
    ' "$db" >"$tmp" && mv -f "$tmp" "$db"
    rm -f "$tmp" 2>/dev/null || true
    return 0
}

# KC-Guide: icuin69.dll → icuin.dll (Kopie, nicht Rename) — gleiches für icuuc*.
recipe_premiere::fix_icu_dlls() {
    local exe_dir="" src=""
    exe_dir="$(dirname "$(premiere::find_exe "${WINEPREFIX:-${WINE_PREFIX:-}}" 2>/dev/null || true)" 2>/dev/null || true)"
    [ -n "$exe_dir" ] && [ -d "$exe_dir" ] || return 0
    shopt -s nullglob 2>/dev/null || true
    if [ ! -f "$exe_dir/icuin.dll" ]; then
        for src in "$exe_dir"/icuin[0-9]*.dll; do
            [ -f "$src" ] || continue
            cp -f "$src" "$exe_dir/icuin.dll" || true
            echo "ICU: $(basename "$src") → icuin.dll"
            break
        done
    fi
    if [ ! -f "$exe_dir/icuuc.dll" ]; then
        for src in "$exe_dir"/icuuc[0-9]*.dll; do
            [ -f "$src" ] || continue
            cp -f "$src" "$exe_dir/icuuc.dll" || true
            echo "ICU: $(basename "$src") → icuuc.dll"
            break
        done
    fi
    shopt -u nullglob 2>/dev/null || true
    return 0
}

recipe_premiere::install() {
    local _err=0 installer_dir=""
    recipe_hooks::log_setup "Premiere_Install"
    recipe_hooks::_source sharedFuncs.sh
    recipe_hooks::_source recipe-fonts.sh
    recipe_hooks::_source recipe-validate.sh

    output::section "Adobe Premiere Pro 2024 — Installation"
    output::progress 2 "Vorbereitung"

    if ! type recipe_source::extract_archive >/dev/null 2>&1; then
        recipe_hooks::_source recipe-source.sh 2>/dev/null || true
    fi

    if ! installer_dir="$(premiere::resolve_installer_dir "$PROJECT_ROOT")"; then
        recipe_hooks::die "Set-up.exe fehlt — Ordner mit Set-up.exe (oder Adobe-*.iso) wählen bzw. nach ${PROJECT_ROOT}/premiere/ legen"
    fi
    output::info "Installer: $installer_dir/Set-up.exe"
    output::info "Datenordner: $DATA_ROOT"

    export SCR_PATH="$DATA_ROOT"
    export WINE_PREFIX="$DATA_ROOT/prefix"
    export CACHE_PATH="$(wine_software_cache_dir)"

    recipe_hooks::install_prefix || exit 1

    if ! recipe_premiere::_prefix_runtime_ready; then
        output::progress 15 "Windows 10 (Registry)"
        recipe_win10::ensure || _err=1

        local _pkgs=(atmlib corefonts fontsmooth=rgb gdiplus)
        local _n="${#_pkgs[@]}"
        local _i=0
        for pkg in "${_pkgs[@]}"; do
            _i=$((_i + 1))
            output::progress $((15 + _i * 40 / _n)) "winetricks: $pkg"
            recipe_winetricks::run "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$pkg" \
                || _err=1
        done

        adobe_setup::ensure_native_msxml || _err=1

        output::progress 58 "Visual C++ Runtime (Microsoft)"
        recipe_vcrun::ensure "${LOG_DIR}/vcrun_${TIMESTAMP_ISO}.log" || _err=1
    else
        output::success "Prefix-Komponenten bereits vorhanden"
    fi

    output::progress 62 "Proton-GE Grafik-DLLs (DXVK)"
    wine_runtime::deploy_proton_graphics_dlls || _err=1
    adobe_setup::apply_graphics_registry

    if ! type recipe_nvidia_libs::ensure >/dev/null 2>&1; then
        recipe_hooks::_source recipe-nvidia-libs.sh 2>/dev/null || true
    fi
    if type recipe_nvidia_libs::ensure >/dev/null 2>&1; then
        output::progress 63 "nvidia-libs (CUDA, NVIDIA)"
        recipe_nvidia_libs::ensure || true
    fi

    output::progress 64 "Installer nach C: kopieren"
    adobe_setup::deploy_installer_to_c_drive "$installer_dir" || _err=1
    output::progress 66 "IE8 (Adobe-Installer)"
    adobe_setup::configure_ie8 || _err=1

    if [ "$_err" -ne 0 ]; then
        output::error "Voraussetzungen fehlgeschlagen — Log: $LOG_FILE"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    output::progress 69 "Adobe Set-up vorbereiten"
    if ! recipe_premiere::_run_adobe_installer; then
        output::error "Adobe-Installation fehlgeschlagen — Log: $LOG_FILE"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    output::progress 95 "Post-Install"
    # Adobe Set-up lässt oft explorer/winedevice zurück → wineserver -w hängt sonst ewig.
    adobe_setup::kill_all_wineservers
    sleep 1
    adobe_setup::ensure_gdiplus || _err=1
    recipe_fonts::ensure "${LOG_DIR}/winetricks_fonts_${TIMESTAMP_ISO}.log" >>"${LOG_FILE:-/dev/null}" 2>&1 || _err=1
    recipe_fonts::registry >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    adobe_setup::disable_virtual_desktop
    recipe_premiere::disable_crash_reporters
    recipe_premiere::fix_icu_dlls
    recipe_premiere::apply_ui_workarounds
    if type recipe_nvidia_libs::ensure >/dev/null 2>&1; then
        recipe_nvidia_libs::ensure || true
    fi
    adobe_setup::kill_all_wineservers

    output::progress 99 "Validieren"
    if ! bash "${RECIPE_DIR}/validate.sh" >>"${LOG_FILE:-/dev/null}" 2>&1; then
        _err=1
    fi

    if [ "$_err" -ne 0 ]; then
        output::error "Installation unvollständig — Rezeptor → Reparieren"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    output::success "Premiere-Rezept installiert"
    output::progress 100 "Installation abgeschlossen"
    recipe_hooks::emit_log_paths
    output::info "Start über Rezeptor → Starten"
}
