#!/usr/bin/env bash
# Photoshop starten — Proton-GE, DLL-Overrides, Datei-Argumente (PSD/PSB).

recipe_photoshop::_locale() {
    if command -v locale >/dev/null 2>&1; then
        if locale -a 2>/dev/null | grep -qE 'de_DE\.(utf8|UTF-8)|de_DE'; then
            export LANG="${LANG:-de_DE.UTF-8}"
        elif locale -a 2>/dev/null | grep -qE 'C\.(utf8|UTF-8)'; then
            export LANG="${LANG:-C.UTF-8}"
        else
            export LANG="${LANG:-C}"
        fi
    else
        export LANG="${LANG:-C.UTF-8}"
    fi
    export LC_ALL="${LC_ALL:-$LANG}"
}

recipe_photoshop::_runtime_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${DATA_ROOT}/photoshop-runtime.log" 2>/dev/null || true
}

recipe_photoshop::_notify() {
    local title="${1:-Adobe Photoshop CC 2021}" message="${2:-}" icon="${3:-}"
    if type recipe_notify::send >/dev/null 2>&1; then
        recipe_notify::send "$title" "$title" "$message" "$icon"
        return 0
    fi
    command -v notify-send >/dev/null 2>&1 || return 0
    if [ -n "$icon" ]; then
        notify-send -a "$title" -i "$icon" "$title" "$message" 2>/dev/null || true
    else
        notify-send -a "$title" "$title" "$message" 2>/dev/null || true
    fi
}

# Hängende unsichtbare Session (explorer /desktop) beenden — sonst „läuft bereits“ ohne Fenster.
recipe_photoshop::_clear_stuck_session() {
    if ! recipe_guard::process_matches 'Photoshop.exe'; then
        return 0
    fi
    if pgrep -f 'explorer\.exe /desktop' >/dev/null 2>&1 \
        || pgrep -f 'explorer\.exe.*\/desktop' >/dev/null 2>&1; then
        echo "⚠ Hängende unsichtbare Photoshop-Session (Virtual Desktop) — beende…"
        recipe_photoshop::_runtime_log "Stuck session: Photoshop + explorer /desktop — kill"
        pkill -f 'Photoshop\.exe' 2>/dev/null || true
        pkill -f 'explorer\.exe /desktop' 2>/dev/null || true
        sleep 1
        pkill -9 -f 'Photoshop\.exe' 2>/dev/null || true
        pkill -9 -f 'explorer\.exe /desktop' 2>/dev/null || true
        if [ -n "${WINEPREFIX:-}" ] && type wine_runtime::wineserver >/dev/null 2>&1; then
            wine_runtime::wineserver -k 2>/dev/null || true
        fi
        sleep 1
    fi
    return 0
}

recipe_photoshop::_export_launch_env() {
    export WINE_PREFIX="${WINE_PREFIX:-${DATA_ROOT}/prefix}"
    export SCR_PATH="${SCR_PATH:-$DATA_ROOT}"
    export WINEPREFIX="$WINE_PREFIX"
    export FREETYPE_PROPERTIES="${FREETYPE_PROPERTIES:-truetype:interpreter-version=35,lcdfilter:default}"
    export WINEDEBUG="${WINEDEBUG:--all,+err}"

    if [ -d /proc/sys/fs/epoll ] || [ -c /dev/shm ]; then
        export WINEESYNC=1
        if [ -f /proc/sys/fs/aio-max-nr ] && [ "$(uname -r | cut -d. -f1)" -ge 5 ] 2>/dev/null; then
            export WINEFSYNC=1
        fi
    fi

    export MESA_GL_VERSION_OVERRIDE=3.3
    export __GL_SHADER_DISK_CACHE=0
    # DXVK für Start/UI (albakhtari). GPU in Prefs bleibt aus — sonst Neu/Text-Tool kaputt.
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;desktop=n;d3d11=native,builtin;d2d1=builtin;gdiplus=native;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin}"
    export WINE_CPU_TOPOLOGY="4:2"
    export __GL_THREADED_OPTIMIZATIONS=1
    export __GL_YIELD="USLEEP"
    export CSMT=enabled
    export DXVK_ASYNC=0
    export DXVK_HUD=0
}

recipe_photoshop::_validate_prefix() {
    if type security::validate_path >/dev/null 2>&1; then
        security::validate_path "$WINE_PREFIX" || return 1
    elif [[ "$WINE_PREFIX" =~ ^/etc|^/usr/bin|^/usr/sbin|^/bin|^/sbin|^/lib|^/var/log|^/root ]]; then
        echo "ERROR: WINEPREFIX zeigt auf System-Verzeichnis: $WINE_PREFIX" >&2
        return 1
    fi
    [ -d "$WINE_PREFIX" ] || {
        echo "FEHLER: Wine-Prefix nicht gefunden: $WINE_PREFIX" >&2
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" \
            "Wine-Prefix nicht gefunden — bitte installieren/reparieren." "dialog-error"
        return 1
    }
    return 0
}

recipe_photoshop::_prepare_prefix() {
    recipe_hooks::_source recipe-photoshop-install.sh
    recipe_guard::kill_stale_winetricks 2>/dev/null || true
    recipe_guard::require_mem 4096 || return 1
    recipe_photoshop::_clear_stuck_session
    if ! recipe_guard::abort_if_running "Photoshop.exe"; then
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" \
            "Läuft bereits — zuerst Beenden, dann erneut Starten." \
            "$(recipe_guard::notify_icon 2>/dev/null || true)"
        return 1
    fi
    # VD-Registry vor jedem Start (sonst explorer /desktop unsichtbar).
    photoshop_setup::disable_virtual_desktop
    recipe_win10::ensure 2>/dev/null \
        || recipe_photoshop::_runtime_log "Warnung: win10 Registry fehlgeschlagen"

    if ! recipe_fonts::ensure "${DATA_ROOT}/photoshop-fonts.log"; then
        recipe_photoshop::_runtime_log "Schriften fehlgeschlagen — siehe ${DATA_ROOT}/photoshop-fonts.log"
        return 1
    fi
    recipe_fonts::registry
    recipe_dpi::logpixels

    if ! recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
        local arch
        arch="$(file "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll" 2>/dev/null \
            | grep -o 'ARM64\|x86-64' || true)"
        if [ "$arch" = "ARM64" ] && type recipe_vcrun::ensure >/dev/null 2>&1; then
            recipe_photoshop::_runtime_log "MSVCP140 ARM64 — installiere VC++ x64"
            recipe_vcrun::ensure "${DATA_ROOT}/photoshop-vcrun-fix.log" || return 1
        fi
    fi

    wine_runtime::deploy_proton_graphics_dlls \
        || recipe_photoshop::_runtime_log "FEHLER: Proton-Grafik-DLLs nicht deploybar — Reparieren"

    # Nur leichte Prefs/Plugins — kein winetricks (gdiplus gehört in Reparieren).
    if ! recipe_photoshop::ensure_post_install_config; then
        recipe_photoshop::_runtime_log "Post-Install-Konfiguration fehlgeschlagen"
        return 1
    fi
    # Vor jedem -script-Start: Skript-Abfrage hart aus (sonst „Möchtest du das wirklich tun?“).
    recipe_photoshop::_ensure_warn_running_scripts_off || true
    if ! recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/syswow64/gdiplus.dll"; then
        echo "FEHLER: Native gdiplus fehlt — Rezeptor → Reparieren (sonst bricht „Neu erstellen“)." >&2
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" "gdiplus fehlt — bitte Reparieren." "dialog-error"
        return 1
    fi
    return 0
}

# PSUserConfig: WarnRunningScripts 0 — sonst fragt Photoshop bei jedem -script nach.
recipe_photoshop::_ensure_warn_running_scripts_off() {
    local version="2021" prefs_path settings_dir cfg
    prefs_path="$(recipe_photoshop::_prefs_path "$version" 2>/dev/null || true)"
    [ -n "$prefs_path" ] || return 0
    settings_dir="$prefs_path/Adobe Photoshop $version Settings"
    mkdir -p "$settings_dir"
    cfg="$settings_dir/PSUserConfig.txt"
    if [ -f "$cfg" ] && grep -qE '^WarnRunningScripts[[:space:]]+0' "$cfg" 2>/dev/null; then
        return 0
    fi
    if [ -f "$cfg" ]; then
        grep -vE '^WarnRunningScripts[[:space:]]+' "$cfg" >"${cfg}.tmp" 2>/dev/null || cp -f "$cfg" "${cfg}.tmp"
        { echo "WarnRunningScripts 0"; cat "${cfg}.tmp"; } >"$cfg"
        rm -f "${cfg}.tmp"
    else
        printf '%s\n' "WarnRunningScripts 0" "[GPU]" "GPUForce 0" "UseOpenCL 0" "AllowGPU 0" "DisableNativeCanvas 1" >"$cfg"
    fi
}

recipe_photoshop::_find_exe() {
    local exe=""
    exe="$(photoshop::find_exe "$WINE_PREFIX" 2>/dev/null || true)"
    if [ -n "$exe" ]; then
        echo "$exe"
        return 0
    fi
    local path
    while IFS= read -r path; do
        [ -f "$path" ] || continue
        echo "$path"
        return 0
    done < <(photoshop::possible_exe_paths "$WINE_PREFIX" 2>/dev/null || true)
    return 1
}

recipe_photoshop::_wine_args() {
    local -n _out=$1
    local file abs wine_path
    _out=()
    for file in "${@:2}"; do
        [ -f "$file" ] || [ -d "$file" ] || continue
        abs="$(readlink -f "$file" 2>/dev/null || echo "$file")"
        if type wine_runtime::winepath >/dev/null 2>&1; then
            wine_path="$(wine_runtime::winepath -w "$abs" 2>/dev/null || true)"
        else
            wine_path=""
        fi
        [ -n "$wine_path" ] || wine_path="$(echo "$abs" | sed 's|^/|Z:/|' | sed 's|/|\\|g')"
        _out+=("$wine_path")
        echo "📂 Öffne Datei: $(basename "$file")"
        recipe_photoshop::_runtime_log "Öffne Datei: $file -> $wine_path"
    done
}

recipe_photoshop::launch() {
    recipe_photoshop::_locale
    recipe_hooks::_source security.sh
    recipe_hooks::_source sharedFuncs.sh
    recipe_hooks::_source recipe-fonts.sh
    recipe_hooks::_source recipe-guard.sh
    recipe_hooks::_source recipe-win10.sh
    recipe_hooks::_source recipe-winetricks.sh
    recipe_hooks::_source recipe-vcrun.sh
    recipe_hooks::_source recipe-validate.sh

    export WINE_METHOD="${WINE_METHOD:-proton-ge}"
    recipe_hooks::runtime_init || {
        recipe_hooks::die "Proton-GE nicht verfügbar — Rezeptor → Reparieren"
    }

    recipe_photoshop::_export_launch_env
    recipe_photoshop::_validate_prefix || exit 1
    recipe_photoshop::_prepare_prefix || exit 1

    local photoshop_exe runtime_desc wine_args=() exit_code icon notify_icon
    photoshop_exe="$(recipe_photoshop::_find_exe)" || {
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" "Photoshop.exe nicht gefunden — Installation prüfen." "dialog-error"
        recipe_hooks::die "Photoshop.exe nicht gefunden — installieren oder reparieren"
    }

    runtime_desc="$(wine_runtime::describe 2>/dev/null || echo "Proton-GE")"
    echo "✓ Photoshop gefunden: $photoshop_exe"
    echo "═══════════════════════════════════════════════════════════════"
    echo "           Adobe Photoshop - Linux Launcher"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Photoshop-Pfad: $photoshop_exe"
    echo "Wine-Prefix: $WINE_PREFIX"
    echo "Wine-Version: $runtime_desc"
    echo ""
    echo "Tipps: Erster Start kann 1–2 Minuten dauern; bei Problemen Reparieren."
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "🔄 Photoshop wird gestartet..."

    notify_icon="$(recipe_guard::notify_icon 2>/dev/null || true)"
    recipe_photoshop::_notify "Adobe Photoshop CC 2021" "Wird gestartet…" "$notify_icon"

    recipe_photoshop::_wine_args wine_args "$@"
    echo "⏳ Initialisiere Wine-Umgebung..."
    recipe_photoshop::_runtime_log "Starte Photoshop: $photoshop_exe"

    # Jeder Start: Text-AA setzen. Ohne Marker zusätzlich Notifier registrieren.
    local script_args=() jsx wine_script
    if ! recipe_photoshop::startup_event_registered; then
        jsx="$(dirname "$photoshop_exe")/Presets/Scripts/Rezeptor-Register-Startup.jsx"
        echo "📝 Text-Glatt Autostart registrieren…"
        recipe_photoshop::_runtime_log "Launch mit -script Register-Startup"
    else
        jsx="$(dirname "$photoshop_exe")/Presets/Scripts/Rezeptor-Text-Glatt-Silent.jsx"
        echo "📝 Text-Anti-Alias (Scharf) setzen…"
        recipe_photoshop::_runtime_log "Launch mit -script Text-Glatt-Silent"
    fi
    if [ -f "$jsx" ]; then
        if type wine_runtime::winepath >/dev/null 2>&1; then
            wine_script="$(wine_runtime::winepath -w "$jsx" 2>/dev/null || true)"
        else
            wine_script=""
        fi
        [ -n "$wine_script" ] || wine_script="$(echo "$jsx" | sed 's|^/|Z:/|' | sed 's|/|\\|g')"
        script_args=(-script "$wine_script")
    fi

    if [ ${#wine_args[@]} -gt 0 ]; then
        wine "$photoshop_exe" "${script_args[@]}" "${wine_args[@]}" >> "${DATA_ROOT}/photoshop-runtime.log" 2>&1
    else
        wine "$photoshop_exe" "${script_args[@]}" >> "${DATA_ROOT}/photoshop-runtime.log" 2>&1
    fi
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "⚠ Photoshop wurde mit Exit-Code $exit_code beendet"
        echo "Log: ${DATA_ROOT}/photoshop-runtime.log"
    fi
    return "$exit_code"
}
