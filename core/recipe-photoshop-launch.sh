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

# Kill matching PIDs only when WINEPREFIX matches this recipe (no global pkill).
recipe_photoshop::_kill_pat_in_prefix() {
    local pat="${1:?}"
    local sig="${2:-TERM}"
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local pid environ
    [ -n "$prefix" ] || return 0
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [ -r "/proc/$pid/environ" ] || continue
        environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
        case "$environ" in
            *"WINEPREFIX=${prefix}"*) ;;
            *) continue ;;
        esac
        kill "-${sig}" "$pid" 2>/dev/null || true
    done < <(pgrep -f "$pat" 2>/dev/null || true)
}

# Orphan AdobeIPCBroker (cmdline embeds Photoshop.exe path) — not a real session.
recipe_photoshop::_clear_orphan_ipc_broker() {
    if recipe_guard::process_matches 'Photoshop.exe'; then
        return 0
    fi
    if ! pgrep -f '[Aa]dobe[Ii][Pp][Cc][Bb]roker' >/dev/null 2>&1; then
        return 0
    fi
    echo "⚠ Verwaisten Adobe IPC Broker beenden…"
    recipe_photoshop::_runtime_log "Orphan AdobeIPCBroker — kill"
    recipe_photoshop::_kill_pat_in_prefix '[Aa]dobe[Ii][Pp][Cc][Bb]roker' TERM
    sleep 0.5
    recipe_photoshop::_kill_pat_in_prefix '[Aa]dobe[Ii][Pp][Cc][Bb]roker' 9
}

# Weißer Vollbild-Desktop ohne Photoshop: explorer.exe /desktop (Wine-VD).
# Muss auch greifen, wenn Photoshop.exe bereits abgestürzt ist.
recipe_photoshop::_clear_orphan_virtual_desktop() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local pid environ found=0
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if [ -n "$prefix" ] && [ -r "/proc/$pid/environ" ]; then
            environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
            case "$environ" in
                *"WINEPREFIX=${prefix}"*) ;;
                *) continue ;;
            esac
        fi
        found=1
        break
    done < <(pgrep -f 'explorer\.exe.*/desktop' 2>/dev/null || true)

    if [ "$found" -ne 1 ]; then
        return 0
    fi

    # Echte PS-Session mit VD: _clear_stuck_session räumt mit Photoshop auf.
    if recipe_guard::process_matches 'Photoshop.exe'; then
        return 0
    fi

    echo "⚠ Orphan Wine-Virtual-Desktop (weißes Fenster) — beende…"
    recipe_photoshop::_runtime_log "Orphan explorer /desktop — kill"
    recipe_photoshop::_drop_virtual_desktop_shell
    if [ -n "$prefix" ] && type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
    fi
    sleep 0.5
    return 0
}

# Nur explorer /desktop dieses Prefixes — Photoshop.exe bleibt.
recipe_photoshop::_drop_virtual_desktop_shell() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local pid environ
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if [ -n "$prefix" ] && [ -r "/proc/$pid/environ" ]; then
            environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
            case "$environ" in
                *"WINEPREFIX=${prefix}"*) ;;
                *) continue ;;
            esac
        fi
        kill "$pid" 2>/dev/null || true
    done < <(pgrep -f 'explorer\.exe.*/desktop' 2>/dev/null || true)
    sleep 0.3
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        if [ -n "$prefix" ] && [ -r "/proc/$pid/environ" ]; then
            environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
            case "$environ" in
                *"WINEPREFIX=${prefix}"*) ;;
                *) continue ;;
            esac
        fi
        kill -9 "$pid" 2>/dev/null || true
    done < <(pgrep -f 'explorer\.exe.*/desktop' 2>/dev/null || true)
}

# Hängende unsichtbare Session (explorer /desktop) beenden — sonst „läuft bereits“ ohne Fenster.
# Prefix-scoped only — never global pkill (would hit other Wine apps / wrong hosts).
recipe_photoshop::_clear_stuck_session() {
    if ! recipe_guard::process_matches 'Photoshop.exe'; then
        return 0
    fi
    if pgrep -f 'explorer\.exe /desktop' >/dev/null 2>&1 \
        || pgrep -f 'explorer\.exe.*\/desktop' >/dev/null 2>&1; then
        echo "⚠ Hängende unsichtbare Photoshop-Session (Virtual Desktop) — beende…"
        recipe_photoshop::_runtime_log "Stuck session: Photoshop + explorer /desktop — kill"
        recipe_photoshop::_kill_pat_in_prefix '[\\/]Photoshop\.exe|[\\/]photoshop\.exe' TERM
        recipe_photoshop::_drop_virtual_desktop_shell
        sleep 1
        recipe_photoshop::_kill_pat_in_prefix '[\\/]Photoshop\.exe|[\\/]photoshop\.exe' 9
        recipe_photoshop::_drop_virtual_desktop_shell
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
    # Kein „desktop=n“ in WINEDLLOVERRIDES — unter Proton-GE kann das explorer /desktop
    # (weißes Vollbild) triggern; VD wird nur über Registry abgeschaltet.
    # GE-11 Medizin: DXVK 2.7 overlay + X11 + d2d1=n (Wine 11 d2d1 → white chrome, issue #8).
    if type recipe_photoshop::apply_ge11_x11_env >/dev/null 2>&1; then
        recipe_photoshop::apply_ge11_x11_env
    fi
    if recipe_photoshop::_env_bool_on "${PHOTOSHOP_PROTON_GE_11:-${PHOTOSHOP_GE11_FORCE_X11:-0}}"; then
        # Force (not :-): stale WINEDLLOVERRIDES must not keep d2d1=builtin.
        export WINEDLLOVERRIDES="winewayland.drv=d;winemenubuilder.exe=d;d3d11=native,builtin;d3d10core=native,builtin;dxgi=native,builtin;d2d1=n;gdiplus=native;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin"
    else
        export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;d3d11=native,builtin;d2d1=builtin;gdiplus=native;mshtml=native,builtin;jscript=native,builtin;vbscript=native,builtin;urlmon=native,builtin;wininet=native,builtin;shdocvw=native,builtin;ieframe=native,builtin;actxprxy=native,builtin;browseui=native,builtin;dxtrans=native,builtin;msimtf=native,builtin;shlwapi=native,builtin;shell32=native,builtin;iertutil=native,builtin;jsproxy=native,builtin}"
    fi
    # Experimental Hand-tool stub (#9). Default off — caused minimize/window regressions.
    case "${PHOTOSHOP_OPENGL_STUB:-0}" in
        1|true|yes|on|TRUE|YES|ON)
            case ";${WINEDLLOVERRIDES};" in
                *\;opengl32=*) ;;
                *) export WINEDLLOVERRIDES="${WINEDLLOVERRIDES};opengl32=n" ;;
            esac
            ;;
    esac
    # Match Premiere: do not spoof Nvidia as AMD (Hand-tool / canvas quirks, issue #9).
    export DXVK_CONFIG="${DXVK_CONFIG:-dxgi.hideNvidiaGpu = False}"
    if [ -z "${DXVK_CONFIG_FILE:-}" ] && [ -f "${WINEPREFIX:-}/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="${WINEPREFIX}/dxvk.conf"
    fi
    # Optional debug overrides (recipe.yml env otherwise forces WINEDEBUG=-all,+err).
    if [ -n "${REZEPTOR_WINEDEBUG:-}" ]; then
        export WINEDEBUG="$REZEPTOR_WINEDEBUG"
    fi
    if [ -n "${REZEPTOR_WINE_CPU_TOPOLOGY:-}" ]; then
        export WINE_CPU_TOPOLOGY="$REZEPTOR_WINE_CPU_TOPOLOGY"
    else
        export WINE_CPU_TOPOLOGY="4:2"
    fi
    export __GL_THREADED_OPTIMIZATIONS=1
    export __GL_YIELD="USLEEP"
    export CSMT="${REZEPTOR_CSMT:-enabled}"
    export DXVK_ASYNC=0
    export DXVK_HUD=0
}

recipe_photoshop::_validate_prefix() {
    if ! type security::validate_path >/dev/null 2>&1; then
        recipe_hooks::_source security.sh
    fi
    security::validate_path "$WINE_PREFIX" || return 1
    [ -d "$WINE_PREFIX" ] || {
        echo "FEHLER: Wine-Prefix nicht gefunden: $WINE_PREFIX" >&2
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" \
            "Wine-Prefix nicht gefunden — bitte installieren/reparieren." "dialog-error"
        return 1
    }
    return 0
}

recipe_photoshop::_ensure_dxvk_conf() {
    # Stop DXVK from spoofing Nvidia as AMD (same idea as Premiere). Helps GPU
    # identity; Hand-tool (#9): opengl32 stub → NumGLGPUs=0 (see assets/opengl32-stub/).
    local conf="${WINEPREFIX:-${WINE_PREFIX:-}}/dxvk.conf"
    [ -n "${WINEPREFIX:-${WINE_PREFIX:-}}" ] || return 0
    mkdir -p "$(dirname "$conf")" 2>/dev/null || true
    if [ ! -f "$conf" ] || ! grep -q 'hideNvidiaGpu' "$conf" 2>/dev/null; then
        cat >"$conf" <<'EOF'
dxgi.hideNvidiaGpu = False
dxgi.hideNvkGpu = False
EOF
    fi
    export DXVK_CONFIG_FILE="${DXVK_CONFIG_FILE:-$conf}"
}

recipe_photoshop::_prepare_prefix() {
    recipe_hooks::_source recipe-photoshop-install.sh
    recipe_guard::kill_stale_winetricks 2>/dev/null || true
    recipe_guard::require_mem 4096 || return 1
    recipe_photoshop::_ensure_dxvk_conf
    recipe_photoshop::_clear_orphan_ipc_broker
    recipe_photoshop::_clear_orphan_virtual_desktop
    recipe_photoshop::_clear_stuck_session
    if ! recipe_guard::abort_if_running "Photoshop.exe"; then
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" \
            "Läuft bereits — zuerst Beenden, dann erneut Starten." \
            "$(recipe_guard::notify_icon 2>/dev/null || true)"
        return 1
    fi
    # VD-Registry vor jedem Start (sonst explorer /desktop = weißes Vollbild).
    photoshop_setup::disable_virtual_desktop
    # Registry-Änderung greift erst mit frischem wineserver — sonst bleibt weißer Desktop.
    if type wine_runtime::wineserver >/dev/null 2>&1; then
        wine_runtime::wineserver -k 2>/dev/null || true
        sleep 0.3
    fi
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
    if recipe_photoshop::_env_bool_on "${PHOTOSHOP_PROTON_GE_11:-0}"; then
        recipe_photoshop::_runtime_log "GE-11 Medizin: DXVK from ${PROTON_GE_DXVK_TAG:-?} + X11 + d2d1=n"
    fi
    # Drop leftover opengl32 stub (or deploy if PHOTOSHOP_OPENGL_STUB=1).
    if type recipe_photoshop::deploy_opengl_stub >/dev/null 2>&1; then
        recipe_photoshop::deploy_opengl_stub || \
            recipe_photoshop::_runtime_log "WARN: opengl32 stub deploy/cleanup failed"
    fi

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
    # Shared pin helper lives in install module.
    if ! type recipe_photoshop::apply_proton_pin >/dev/null 2>&1; then
        recipe_hooks::_source recipe-photoshop-install.sh
    fi
    recipe_photoshop::apply_proton_pin
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

    if type recipe_notify::starting >/dev/null 2>&1; then
        recipe_notify::starting
    else
        notify_icon="$(recipe_guard::notify_icon 2>/dev/null || true)"
        recipe_photoshop::_notify "Adobe Photoshop CC 2021" "Wird gestartet…" "$notify_icon"
    fi

    recipe_photoshop::_wine_args wine_args "$@"
    echo "⏳ Initialisiere Wine-Umgebung..."
    recipe_photoshop::_runtime_log "Starte Photoshop: $photoshop_exe"

    # Nur einmal Notifier registrieren. Kein -script bei jedem Start —
    # Text-Glatt auf der Startseite → „Programmfehler“ unter Wine.
    # PHOTOSHOP_FORCE_JSX: one-shot debug/repair script (absolute host path).
    local script_args=() jsx wine_script
    if [ -n "${PHOTOSHOP_FORCE_JSX:-}" ] && [ -f "${PHOTOSHOP_FORCE_JSX}" ]; then
        jsx="$PHOTOSHOP_FORCE_JSX"
        recipe_photoshop::_runtime_log "FORCE JSX: $jsx"
        if type wine_runtime::winepath >/dev/null 2>&1; then
            wine_script="$(wine_runtime::winepath -w "$jsx" 2>/dev/null || true)"
        else
            wine_script=""
        fi
        [ -n "$wine_script" ] || wine_script="$(echo "$jsx" | sed 's|^/|Z:/|' | sed 's|/|\\|g')"
        script_args=(-script "$wine_script")
    elif ! recipe_photoshop::startup_event_registered; then
        jsx="$(dirname "$photoshop_exe")/Presets/Scripts/Rezeptor-Register-Startup.jsx"
        echo "📝 Text-Glatt Autostart registrieren…"
        recipe_photoshop::_runtime_log "Launch mit -script Register-Startup"
        if [ -f "$jsx" ]; then
            if type wine_runtime::winepath >/dev/null 2>&1; then
                wine_script="$(wine_runtime::winepath -w "$jsx" 2>/dev/null || true)"
            else
                wine_script=""
            fi
            [ -n "$wine_script" ] || wine_script="$(echo "$jsx" | sed 's|^/|Z:/|' | sed 's|/|\\|g')"
            script_args=(-script "$wine_script")
        fi
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
