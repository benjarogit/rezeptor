#!/usr/bin/env bash
# Photoshop-Installation — Proton-GE, Adobe Set-up.exe (silent), Post-Install-Konfiguration.

photoshop_setup::kill_all_wineservers() {
    # Nur Proton-wineserver dieses Prefix — kein globales pkill (andere Rezepte).
    if type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
    elif [ -n "${WINE:-}" ]; then
        "$WINE" wineserver -k 2>/dev/null || true
    fi
}

photoshop_setup::ie8_present() {
    local prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    [ -f "$prefix/drive_c/Program Files/Internet Explorer/iexplore.exe" ] \
        || [ -f "$prefix/drive_c/Program Files (x86)/Internet Explorer/iexplore.exe" ]
}

photoshop_setup::msxml_is_native() {
    recipe_validate::msxml_is_native "$1"
}

photoshop_setup::export_adobe_installer_dll_overrides() {
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;msxml3=native,builtin;msxml6=native,builtin;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin"
}

photoshop_setup::apply_adobe_network_registry() {
    wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings" \
        /v AutoDetect /t REG_DWORD /d 0 /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings" \
        /v ProxyEnable /t REG_DWORD /d 0 /f >>"${LOG_FILE:-/dev/null}" 2>&1 || true
}

photoshop_setup::fix_installer_case_symlinks() {
    local base="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -d "$base/products" ] || return 0
    [ -f "$base/products/Driver.xml" ] && [ ! -e "$base/products/driver.xml" ] \
        && ln -sf Driver.xml "$base/products/driver.xml"
    [ -f "$base/resources/Config.xml" ] && [ ! -e "$base/resources/config.xml" ] \
        && ln -sf Config.xml "$base/resources/config.xml"
}

photoshop_setup::deploy_installer_to_c_drive() {
    local src="$1"
    local dest="${WINEPREFIX}/drive_c/AdobeSetup"
    [ -n "$src" ] && [ -f "$src/Set-up.exe" ] || return 1
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    photoshop_setup::fix_installer_case_symlinks
    export ADOBE_INSTALLER_DIR="$dest"
}

photoshop_setup::resolve_setup_exe() {
    if [ -n "${ADOBE_INSTALLER_DIR:-}" ] && [ -f "${ADOBE_INSTALLER_DIR}/Set-up.exe" ]; then
        echo "${ADOBE_INSTALLER_DIR}/Set-up.exe"
        return 0
    fi
    [ -f "${WINEPREFIX}/drive_c/AdobeSetup/Set-up.exe" ] \
        && echo "${WINEPREFIX}/drive_c/AdobeSetup/Set-up.exe" && return 0
    return 1
}

photoshop_setup::reregister_ie8_dlls() {
    local dll dir="C:\\windows\\syswow64"
    for dll in mshtml.dll jscript.dll vbscript.dll urlmon.dll wininet.dll ieframe.dll shdocvw.dll; do
        wine regsvr32 /S "${dir}\\${dll}" >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done
}

photoshop_setup::disable_virtual_desktop() {
    local wine_bin="${WINE:-wine}"
    # Kein Wine-„blauer Desktop“ — Photoshop als normales Fenster.
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

photoshop_setup::prepare_adobe_installer_env() {
    photoshop_setup::disable_virtual_desktop
    photoshop_setup::kill_all_wineservers
    sleep 1
    recipe_photoshop::_ensure_native_msxml || return 1
    photoshop_setup::apply_adobe_network_registry
    photoshop_setup::export_adobe_installer_dll_overrides
    recipe_win10::ensure >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    photoshop_setup::reregister_ie8_dlls
}

recipe_photoshop::_prefs_path() {
    local version="${1:-2021}"
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local user
    if [ -d "$prefix/drive_c/users/steamuser" ]; then
        user="steamuser"
    else
        user="${USER:-$(id -un)}"
    fi
    case "$version" in
        2022) echo "$prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop 2022" ;;
        2021) echo "$prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop 2021" ;;
        *) echo "$prefix/drive_c/users/$user/AppData/Roaming/Adobe/Adobe Photoshop CC 2019" ;;
    esac
}

recipe_photoshop::_install_path() {
    local version="${1:-2021}"
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    case "$version" in
        2022) echo "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop 2022" ;;
        2021) echo "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop 2021" ;;
        *) echo "$prefix/drive_c/Program Files/Adobe/Adobe Photoshop CC 2019" ;;
    esac
}

recipe_photoshop::_prefix_runtime_ready() {
    recipe_validate::prefix_initialized "${WINEPREFIX:-}" || return 1
    photoshop_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll" \
        && photoshop_setup::msxml_is_native "${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll"
}

recipe_photoshop::_ensure_native_msxml() {
    local msxml3="${WINEPREFIX}/drive_c/windows/syswow64/msxml3.dll"
    local msxml6="${WINEPREFIX}/drive_c/windows/syswow64/msxml6.dll"
    photoshop_setup::msxml_is_native "$msxml3" \
        && photoshop_setup::msxml_is_native "$msxml6" && return 0

    output::step "Native MSXML3/MSXML6 (Adobe-Installer)"
    local wt_log="${LOG_DIR}/winetricks_msxml_${TIMESTAMP_ISO}.log"
    if ! recipe_winetricks::run "$wt_log" -f msxml3 msxml6; then
        recipe_hooks::log_err "MSXML winetricks fehlgeschlagen — $wt_log"
        return 1
    fi
    wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v msxml3 /t REG_SZ /d "native,builtin" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v msxml6 /t REG_SZ /d "native,builtin" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine regsvr32 /S C:\\windows\\syswow64\\msxml3.dll >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    wine regsvr32 /S C:\\windows\\syswow64\\msxml6.dll >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    photoshop_setup::msxml_is_native "$msxml3" && photoshop_setup::msxml_is_native "$msxml6"
}

recipe_photoshop::_apply_graphics_registry() {
    output::step "Grafik-Registry (DXVK + d2d1 builtin)"
    local wine_bin="${WINE:-wine}" dll
    # albakhtari/isatsam: dxvk für Start/UI. d2d1=builtin (native ohne DLL → CEP-Bruch).
    for dll in d3d11 dxgi d3dcompiler_47 d3dcompiler_43 opcservices; do
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

recipe_photoshop::_configure_ie8() {
    output::step "IE8 (Adobe-Installer, 5–10 Min.)"
    output::info "Silent-Install nutzt IE-Engine — IE8 muss im Prefix sein"
    if photoshop_setup::ie8_present; then
        output::success "IE8 bereits im Prefix"
        photoshop_setup::reregister_ie8_dlls
        return 0
    fi
    local wt_log="${LOG_DIR}/winetricks_ie8_${TIMESTAMP_ISO}.log"
    recipe_winetricks::prepare || return 1
    recipe_winetricks::_invoke_with_timeout "$wt_log" 900 -q ie8 || return 1
    if ! photoshop_setup::ie8_present; then
        recipe_hooks::log_err "IE8 fehlgeschlagen — $wt_log"
        return 1
    fi
    output::success "IE8 installiert"
    recipe_win10::ensure >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    photoshop_setup::reregister_ie8_dlls
    return 0
}

recipe_photoshop::_run_adobe_installer() {
    photoshop_setup::prepare_adobe_installer_env
    local setup_exe setup_dir installer_args=() install_status=0
    setup_exe="$(photoshop_setup::resolve_setup_exe)" || {
        recipe_hooks::die "Set-up.exe nicht gefunden (C:\\AdobeSetup)"
    }
    setup_dir="$(dirname "$setup_exe")"

    if [ "${PHOTOSHOP_INSTALLER_GUI:-0}" = "1" ]; then
        output::info "GUI-Installer (PHOTOSHOP_INSTALLER_GUI=1)"
        installer_args=()
    else
        installer_args=(--silent=1)
        output::info "Silent-Installation (Adobe ESD) — ca. 2–4 Minuten"
    fi

    output::step "Adobe Set-up.exe"
    output::progress 70 "Adobe-Installer"
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

    photoshop_setup::kill_all_wineservers
    [ "$install_status" -eq 0 ] || return "$install_status"

    local exe_path
    exe_path="$(photoshop::find_exe "$WINEPREFIX" 2>/dev/null || true)"
    [ -n "$exe_path" ] && [ -f "$exe_path" ] || {
        recipe_hooks::log_err "Adobe-Installer beendet, Photoshop.exe fehlt"
        return 1
    }
    output::success "Adobe Photoshop installiert: $exe_path"
    return 0
}

# Adobe-Prefs sind binär (key + "bool" + u32 LE). ASCII-Dateien dort ignoriert Photoshop.
recipe_photoshop::_prefs_set_bool() {
    local file="$1" key="$2" value="$3"
    [ -f "$file" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path
path, key, value = Path(sys.argv[1]), sys.argv[2].encode(), int(sys.argv[3])
data = bytearray(path.read_bytes())
needle = key + b"bool"
i = data.find(needle)
if i < 0:
    sys.exit(1)
val_at = i + len(needle)
data[val_at : val_at + 4] = bytes([value & 1, 0, 0, 0])
path.write_bytes(data)
PY
}

recipe_photoshop::_prefs_get_bool() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$file" "$key" <<'PY'
import sys
from pathlib import Path
path, key = Path(sys.argv[1]), sys.argv[2].encode()
data = path.read_bytes()
needle = key + b"bool"
i = data.find(needle)
if i < 0:
    sys.exit(2)
sys.exit(0 if data[i + len(needle)] == 1 else 1)
PY
}

recipe_photoshop::configure_post_install() {
    local ps_path="" version="2021" prefs_path settings_dir ui_prefs machine_prefs
    local _err=0
    output::progress 96 "Photoshop konfigurieren"
    output::step "Post-Install (GPU aus, Tooltips aus, Legacy-Neu, CEP)"

    ps_path="$(recipe_photoshop::_install_path "$version")"
    [ -d "$ps_path" ] || ps_path="$(photoshop::find_exe "$WINEPREFIX" | xargs -r dirname 2>/dev/null || true)"
    [ -n "$ps_path" ] && [ -d "$ps_path" ] || return 1

    photoshop_setup::disable_virtual_desktop
    if ! wine_runtime::deploy_proton_graphics_dlls; then
        recipe_hooks::log_err "deploy_proton_graphics_dlls fehlgeschlagen"
        _err=1
    fi
    recipe_photoshop::_apply_graphics_registry || _err=1
    recipe_photoshop::ensure_scripting_support "$ps_path" || true

    # Nur Design-Library entfernen (Ballast). Spaces / Home / ccx.start / ccx.fnft
    # bleiben — sonst leerer Workspace und Datei→Neu ohne Dialog (live belegt 2026-07-10).
    # UXP Common Files (com.adobe.ccx.start-*) NIEMALS löschen — sonst Startbildschirm-Fehler.
    # Programmfehler bei Neu: GPU-Profil stable + Legacy-Prefs, nicht Extension-Löschung.
    local problematic_plugins=(
        "$ps_path/Required/CEP/extensions/com.adobe.DesignLibraryPanel.html"
    )
    local plugin
    for plugin in "${problematic_plugins[@]}"; do
        [ -f "$plugin" ] && rm -f "$plugin" 2>/dev/null || true
        [ -d "$plugin" ] && rm -rf "$plugin" 2>/dev/null || true
    done

    # Falls UXP-Start fehlt (früher fälschlich gelöscht): aus lokalem Backup zurück.
    recipe_photoshop::_ensure_uxp_start || true

    prefs_path="$(recipe_photoshop::_prefs_path "$version")"
    settings_dir="$prefs_path/Adobe Photoshop $version Settings"
    mkdir -p "$settings_dir"

    # Falsche ASCII-Prefs (früherer Bug) entfernen — Photoshop nutzt nur die binäre Prefs.psp.
    if [ -f "$prefs_path/Adobe Photoshop $version Prefs.psp" ] \
        && file "$prefs_path/Adobe Photoshop $version Prefs.psp" 2>/dev/null | grep -qi 'ASCII\|text'; then
        rm -f "$prefs_path/Adobe Photoshop $version Prefs.psp"
    fi

    # GPU: Default stable. Experiment nur wenn Flag gesetzt (REZEPTOR_PS_GPU_PROFILE / gpu-profile.active).
    # Self-Heal überschreibt Experiment-Profile nicht still.
    if ! recipe_photoshop::apply_gpu_profile "$(recipe_photoshop::active_gpu_profile)"; then
        recipe_hooks::log_err "GPU-Profil anwenden fehlgeschlagen"
        _err=1
    fi

    # Legacy-Neu (CEP unter Wine kaputt). ToolTips aus = Text-Tool/Plugins nutzbar.
    ui_prefs="$settings_dir/UIPrefs.psp"
    if [ -f "$ui_prefs" ]; then
        recipe_photoshop::_prefs_set_bool "$ui_prefs" useClassicFileNewDialog 1 || true
        recipe_photoshop::_prefs_set_bool "$ui_prefs" honorUseOldFileNewDialogPref 1 || true
        recipe_photoshop::_prefs_set_bool "$ui_prefs" autoShowHomeScreen 0 || true
        recipe_photoshop::_prefs_set_bool "$ui_prefs" ToolTips 0 || true
        recipe_photoshop::_prefs_set_bool "$ui_prefs" useRichToolTips 0 || true
    fi

    if ! recipe_photoshop::deploy_text_smooth_script; then
        recipe_hooks::log_err "deploy_text_smooth_script fehlgeschlagen"
        _err=1
    fi
    return "$_err"
}

# UXP-Startbildschirm (Common Files) — fehlt → Dialog „UXP-Startbildschirm-Erweiterung…“.
# Quelle: Adobe Set-up oder DATA_ROOT/backups/uxp-ccx-start-*.
recipe_photoshop::_ensure_uxp_start() {
    local uxp_ext prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local dest bak
    uxp_ext="$prefix/drive_c/Program Files/Common Files/Adobe/UXP/extensions"
    mkdir -p "$uxp_ext"
    if [ -f "$uxp_ext/com.adobe.ccx.start-3.7.0/manifest.json" ] \
        || [ -f "$uxp_ext/com.adobe.ccx.start-3.6.0/manifest.json" ]; then
        return 0
    fi
    bak="$(ls -d "${DATA_ROOT}/backups"/uxp-ccx-start-* 2>/dev/null | tail -1 || true)"
    [ -n "$bak" ] || return 1
    for dest in com.adobe.ccx.start-3.7.0 com.adobe.ccx.start-3.6.0; do
        if [ -d "$bak/$dest" ] && [ ! -d "$uxp_ext/$dest" ]; then
            cp -a "$bak/$dest" "$uxp_ext/"
        fi
    done
    [ -f "$uxp_ext/com.adobe.ccx.start-3.7.0/manifest.json" ] \
        || [ -f "$uxp_ext/com.adobe.ccx.start-3.6.0/manifest.json" ]
}

# Aktives GPU-Profil: Env > Flag-Datei > stable.
recipe_photoshop::active_gpu_profile() {
    local p="${REZEPTOR_PS_GPU_PROFILE:-}"
    if [ -z "$p" ] && [ -n "${DATA_ROOT:-}" ] && [ -f "$DATA_ROOT/gpu-profile.active" ]; then
        p="$(tr -d '[:space:]' <"$DATA_ROOT/gpu-profile.active" 2>/dev/null || true)"
    fi
    case "$p" in
        stable|dxvk_ui_only|ps_gpu_no_opencl|ps_gpu_full) echo "$p" ;;
        *) echo "stable" ;;
    esac
}

recipe_photoshop::_gpu_profile_dir() {
    local name="$1" base=""
    if [ -n "${RECIPE_DIR:-}" ] && [ -d "$RECIPE_DIR/assets/gpu-profiles/$name" ]; then
        base="$RECIPE_DIR/assets/gpu-profiles/$name"
    elif [ -n "${PROJECT_ROOT:-}" ] && [ -d "$PROJECT_ROOT/recipes/photoshop/assets/gpu-profiles/$name" ]; then
        base="$PROJECT_ROOT/recipes/photoshop/assets/gpu-profiles/$name"
    else
        return 1
    fi
    echo "$base"
}

# PSUserConfig + MachinePrefs + Registry für ein GPU-Profil. Kill-Switch: name=stable.
recipe_photoshop::apply_gpu_profile() {
    local name="${1:-stable}" version="2021" prefs_path settings_dir machine_prefs
    local profile_dir psuc wine_bin key val gpu_on=0
    profile_dir="$(recipe_photoshop::_gpu_profile_dir "$name")" || {
        echo "ERROR: GPU-Profil unbekannt: $name" >&2
        return 1
    }
    [ -f "$profile_dir/PSUserConfig.txt" ] || return 1

    prefs_path="$(recipe_photoshop::_prefs_path "$version")"
    settings_dir="$prefs_path/Adobe Photoshop $version Settings"
    mkdir -p "$settings_dir"
    cp -f "$profile_dir/PSUserConfig.txt" "$settings_dir/PSUserConfig.txt" || return 1

    machine_prefs="$settings_dir/MachinePrefs.psp"
    if [ -f "$machine_prefs" ] && [ -f "$profile_dir/machine.prefs" ]; then
        while IFS='=' read -r key val || [ -n "$key" ]; do
            key="${key%%#*}"
            key="$(echo "$key" | tr -d '[:space:]')"
            val="$(echo "${val%%#*}" | tr -d '[:space:]')"
            [ -n "$key" ] || continue
            case "$val" in
                0|1) recipe_photoshop::_prefs_set_bool "$machine_prefs" "$key" "$val" || true ;;
            esac
        done <"$profile_dir/machine.prefs"
    fi

    grep -qE '^GPUForce[[:space:]]+1' "$settings_dir/PSUserConfig.txt" 2>/dev/null && gpu_on=1
    wine_bin="${WINE:-wine}"
    "$wine_bin" reg add "HKCU\\Software\\Adobe\\Photoshop\\Settings" /v GPUAcceleration /t REG_DWORD /d "$gpu_on" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    if grep -qE '^UseOpenCL[[:space:]]+1' "$settings_dir/PSUserConfig.txt" 2>/dev/null; then
        "$wine_bin" reg add "HKCU\\Software\\Adobe\\Photoshop\\Settings" /v useOpenCL /t REG_DWORD /d 1 /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    else
        "$wine_bin" reg add "HKCU\\Software\\Adobe\\Photoshop\\Settings" /v useOpenCL /t REG_DWORD /d 0 /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    fi
    "$wine_bin" reg add "HKCU\\Software\\Adobe\\Photoshop\\Settings" /v useGraphicsProcessor /t REG_DWORD /d "$gpu_on" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true

    if [ -n "${DATA_ROOT:-}" ]; then
        mkdir -p "$DATA_ROOT"
        echo "$name" >"$DATA_ROOT/gpu-profile.active"
    fi
    if type output::info >/dev/null 2>&1; then
        output::info "GPU-Profil: $name"
    else
        echo "GPU-Profil: $name"
    fi
    return 0
}

# ScriptingSupport.8li aus Offline-Installer wiederherstellen (früher fälschlich gelöscht).
recipe_photoshop::ensure_scripting_support() {
    local ps_path="${1:-}"
    local dest installer_zip
    [ -n "$ps_path" ] || ps_path="$(recipe_photoshop::_install_path 2021)"
    dest="$ps_path/Required/Plug-ins/Extensions/ScriptingSupport.8li"
    [ -f "$dest" ] && return 0
    installer_zip=""
    if [ -n "${PROJECT_ROOT:-}" ] && [ -f "$PROJECT_ROOT/photoshop/products/PHSP/AdobePhotoshop22-Core_x64.zip" ]; then
        installer_zip="$PROJECT_ROOT/photoshop/products/PHSP/AdobePhotoshop22-Core_x64.zip"
    fi
    [ -n "$installer_zip" ] || return 1
    command -v unzip >/dev/null 2>&1 || return 1
    mkdir -p "$(dirname "$dest")"
    unzip -p "$installer_zip" \
        "1/Application/Required/Plug-ins/Extensions/ScriptingSupport.8li" \
        >"$dest" 2>/dev/null || return 1
    [ -s "$dest" ] || { rm -f "$dest"; return 1; }
    return 0
}

# Datei → Skripte → Rezeptor-Text-Glatt (+ Silent + Register-Startup).
recipe_photoshop::deploy_text_smooth_script() {
    local src_dir="" dest_dir="" f
    if [ -n "${RECIPE_DIR:-}" ] && [ -d "$RECIPE_DIR/assets" ]; then
        src_dir="$RECIPE_DIR/assets"
    elif [ -n "${PROJECT_ROOT:-}" ] && [ -d "$PROJECT_ROOT/recipes/photoshop/assets" ]; then
        src_dir="$PROJECT_ROOT/recipes/photoshop/assets"
    else
        return 1
    fi
    [ -f "$src_dir/Rezeptor-Text-Glatt.jsx" ] || return 1
    dest_dir="$(recipe_photoshop::_install_path "${1:-2021}")/Presets/Scripts"
    [ -d "$dest_dir" ] || return 1
    for f in Rezeptor-Text-Glatt.jsx Rezeptor-Text-Glatt-Silent.jsx Rezeptor-Register-Startup.jsx; do
        [ -f "$src_dir/$f" ] || continue
        cp -f "$src_dir/$f" "$dest_dir/$f" || return 1
    done
    if [ -d "$dest_dir/Event Scripts Only" ]; then
        cp -f "$src_dir/Rezeptor-Text-Glatt-Silent.jsx" \
            "$dest_dir/Event Scripts Only/Rezeptor-Text-Glatt-Silent.jsx" || return 1
    fi
    return 0
}

# Marker: Event „Start Application“ wurde einmal erfolgreich registriert.
recipe_photoshop::startup_event_registered() {
    local prefs_path settings_dir marker
    prefs_path="$(recipe_photoshop::_prefs_path "${1:-2021}")"
    settings_dir="$prefs_path/Adobe Photoshop ${1:-2021} Settings"
    marker="$settings_dir/.rezeptor-startup-event"
    [ -f "$marker" ]
}

# CLI-Fallback: Register-Startup.jsx einmal ausführen (setzt Notifier + Text-AA).
recipe_photoshop::run_text_glatt_cli() {
    local exe="$1" script_path wine_script
    [ -n "$exe" ] && [ -f "$exe" ] || return 1
    script_path="$(dirname "$exe")/Presets/Scripts/Rezeptor-Register-Startup.jsx"
    [ -f "$script_path" ] || return 1
    if type wine_runtime::winepath >/dev/null 2>&1; then
        wine_script="$(wine_runtime::winepath -w "$script_path" 2>/dev/null || true)"
    else
        wine_script=""
    fi
    [ -n "$wine_script" ] || wine_script="$(echo "$script_path" | sed 's|^/|Z:/|' | sed 's|/|\\|g')"
    wine "$exe" -script "$wine_script" >>"${DATA_ROOT:-/tmp}/photoshop-runtime.log" 2>&1 || return 1
    return 0
}

# Native MS-GDI+ (winetricks gdiplus / Win7) — gdiplus_winxp-Download ist tot (MS 404 / archive.org 429).
# Separat vom Launch-Pfad: winetricks kann Minuten brauchen.
recipe_photoshop::ensure_gdiplus() {
    local wow64="${WINEPREFIX:?}/drive_c/windows/syswow64/gdiplus.dll"
    if recipe_validate::native_pe "$wow64"; then
        return 0
    fi
    local log="${LOG_DIR:-${DATA_ROOT}/logs}/winetricks_gdiplus_${TIMESTAMP_ISO:-$(date +%Y-%m-%d_%H-%M-%S)}.log"
    mkdir -p "$(dirname "$log")"
    output::step "gdiplus (native MS-GDI+ — Neu-Dokument / Export)"
    recipe_winetricks::run "$log" gdiplus || {
        recipe_hooks::log_err "gdiplus fehlgeschlagen — $log"
        return 1
    }
    wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v gdiplus /t REG_SZ /d "native" /f \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    recipe_validate::native_pe "$wow64"
}

recipe_photoshop::ensure_post_install_config() {
    export WINE_PREFIX="${WINE_PREFIX:-${WINEPREFIX:?}}"
    export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"
    local exe_path
    exe_path="$(photoshop::find_exe "$WINE_PREFIX" 2>/dev/null || true)"
    [ -n "$exe_path" ] || return 1
    recipe_photoshop::configure_post_install
}

recipe_photoshop::install_desktop() {
    local launch="${RECIPE_DIR}/launch.sh"
    local app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local icon_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
    local icon_src="${PROJECT_ROOT}/images/AdobePhotoshop-icon.png"
    local launch_esc icon_line="Icon=photoshop" theme_name="photoshop"

    [ -x "$launch" ] || recipe_hooks::die "launch.sh fehlt: $launch"
    mkdir -p "$app_dir"

    if [ -f "$icon_src" ] && command -v magick >/dev/null 2>&1; then
        local s=""
        for s in 48 64 128 256; do
            mkdir -p "$icon_dir/${s}x${s}/apps"
            magick "$icon_src" -resize "${s}x${s}" "$icon_dir/${s}x${s}/apps/${theme_name}.png" 2>/dev/null || true
        done
        [ -f "$icon_dir/48x48/apps/${theme_name}.png" ] && icon_line="Icon=${theme_name}"
        command -v gtk-update-icon-cache >/dev/null 2>&1 \
            && gtk-update-icon-cache -f -t "$icon_dir" 2>/dev/null || true
    fi

    launch_esc="$(printf '%s' "$launch" | sed 's/[\\"]/\\&/g')"
    cat >"$app_dir/photoshop.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Adobe Photoshop CC 2021
Comment=Adobe Photoshop via Rezeptor (Proton-GE)
Exec=env WINEPREFIX="${DATA_ROOT}/prefix" DATA_ROOT="${DATA_ROOT}" SCR_PATH="${DATA_ROOT}" bash "${launch_esc}" %F
Path=${DATA_ROOT}
StartupNotify=true
StartupWMClass=Photoshop.exe
MimeType=image/vnd.adobe.photoshop;image/x-photoshop;application/x-photoshop;image/psd;application/psd;
Categories=Graphics;2DGraphics;RasterGraphics;
Terminal=false
${icon_line}
EOF
    chmod 644 "$app_dir/photoshop.desktop"
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$app_dir" 2>/dev/null || true
    return 0
}

recipe_photoshop::install() {
    local _err=0 installer_dir=""
    recipe_hooks::log_setup "Photoshop_Install"
    recipe_hooks::_source sharedFuncs.sh
    recipe_hooks::_source recipe-fonts.sh
    recipe_hooks::_source recipe-validate.sh

    output::section "Adobe Photoshop CC 2021 — Installation"
    output::progress 2 "Vorbereitung"

    if ! installer_dir="$(photoshop::resolve_installer_dir "$PROJECT_ROOT")"; then
        recipe_hooks::die "Set-up.exe fehlt — nach ${PROJECT_ROOT}/photoshop/ kopieren oder PHOTOSHOP_INSTALLER_DIR setzen"
    fi
    output::info "Installer: $installer_dir/Set-up.exe"

    export SCR_PATH="$DATA_ROOT"
    export WINE_PREFIX="$DATA_ROOT/prefix"
    export CACHE_PATH="$(wine_software_cache_dir)"

    recipe_hooks::install_prefix || exit 1

    if ! recipe_photoshop::_prefix_runtime_ready; then
        output::step "Wine-Komponenten"
        output::progress 15 "Windows 10"
        recipe_win10::ensure || _err=1

        for pkg in atmlib corefonts fontsmooth=rgb gdiplus; do
            output::step "winetricks: $pkg"
            recipe_winetricks::run "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$pkg" \
                || _err=1
        done

        recipe_photoshop::_ensure_native_msxml || _err=1

        output::step "Visual C++ Runtime (Microsoft)"
        recipe_vcrun::ensure "${LOG_DIR}/vcrun_${TIMESTAMP_ISO}.log" || _err=1
    else
        output::success "Prefix-Komponenten bereits vorhanden"
    fi

    output::step "Proton-GE Grafik-DLLs (DXVK)"
    wine_runtime::deploy_proton_graphics_dlls || _err=1
    recipe_photoshop::_apply_graphics_registry

    photoshop_setup::deploy_installer_to_c_drive "$installer_dir" || _err=1
    recipe_photoshop::_configure_ie8 || _err=1

    if [ "$_err" -ne 0 ]; then
        output::error "Voraussetzungen fehlgeschlagen — Log: $LOG_FILE"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    if ! recipe_photoshop::_run_adobe_installer; then
        output::error "Adobe-Installation fehlgeschlagen — Log: $LOG_FILE"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    recipe_photoshop::configure_post_install || _err=1
    recipe_photoshop::ensure_gdiplus || _err=1
    recipe_fonts::ensure "${LOG_DIR}/winetricks_fonts_${TIMESTAMP_ISO}.log" >>"${LOG_FILE:-/dev/null}" 2>&1 || _err=1
    recipe_fonts::registry >>"${LOG_FILE:-/dev/null}" 2>&1 || _err=1

    output::step "Desktop-Eintrag"
    recipe_photoshop::install_desktop || _err=1

    if ! bash "${RECIPE_DIR}/validate.sh" >>"${LOG_FILE:-/dev/null}" 2>&1; then
        _err=1
    fi

    if [ "$_err" -ne 0 ]; then
        output::error "Installation unvollständig — Rezeptor → Reparieren"
        recipe_hooks::emit_log_paths
        exit 11
    fi

    output::success "Photoshop Rezept installiert"
    output::progress 100 "Installation abgeschlossen"
    recipe_hooks::emit_log_paths
    output::info "Start über Rezeptor → Starten"
}
