#!/usr/bin/env bash
# Premiere Pro 2024 starten — Proton-GE, DLL-Overrides (DXVK/Vulkan).

if ! type adobe_setup::disable_virtual_desktop >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/recipe-adobe-setup.sh"
fi

recipe_premiere::_locale() {
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

recipe_premiere::_runtime_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${DATA_ROOT}/premiere-runtime.log" 2>/dev/null || true
}

recipe_premiere::_notify() {
    local title="${1:-Adobe Premiere Pro 2024}" message="${2:-}" icon="${3:-}"
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

recipe_premiere::_clear_stuck_session() {
    if ! recipe_guard::process_matches 'Adobe Premiere Pro.exe'; then
        return 0
    fi
    if pgrep -f 'explorer\.exe /desktop' >/dev/null 2>&1 \
        || pgrep -f 'explorer\.exe.*\/desktop' >/dev/null 2>&1; then
        echo "⚠ Hängende unsichtbare Premiere-Session (Virtual Desktop) — beende…"
        recipe_premiere::_runtime_log "Stuck session: Premiere + explorer /desktop — kill"
        pkill -f 'Adobe Premiere Pro\.exe' 2>/dev/null || true
        pkill -f 'explorer\.exe /desktop' 2>/dev/null || true
        sleep 1
        pkill -9 -f 'Adobe Premiere Pro\.exe' 2>/dev/null || true
        pkill -9 -f 'explorer\.exe /desktop' 2>/dev/null || true
        if [ -n "${WINEPREFIX:-}" ] && type wine_runtime::wineserver >/dev/null 2>&1; then
            wine_runtime::wineserver -k 2>/dev/null || true
        fi
        sleep 1
    fi
    return 0
}

recipe_premiere::_export_launch_env() {
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

    # Kein MESA_GL_VERSION_OVERRIDE — Premiere nutzt DXVK/Vulkan; GL-Override stört CEF/UXP.
    unset MESA_GL_VERSION_OVERRIDE || true
    export __GL_SHADER_DISK_CACHE=0
    # d3d10core=native (DXVK) — ohne: DXGID3D10CreateDevice abort → schwarze Panels.
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;desktop=n;d3d11=native,builtin;d3d10core=native,builtin;dxgi=native,builtin;d2d1=builtin;gdiplus=native;msxml3=native,builtin}"
    # "4:2" ist unter Proton-GE 10 ungültig (Invalid WINE_CPU_TOPOLOGY) — weglassen.
    unset WINE_CPU_TOPOLOGY || true
    export __GL_THREADED_OPTIMIZATIONS=1
    export __GL_YIELD="USLEEP"
    export CSMT=enabled
    export DXVK_ASYNC=0
    export DXVK_HUD=0
    # Echte NVIDIA-GPU melden (Proton/DXVK default: als AMD getarnt → Premiere/GPUSniffer verwirrt).
    export DXVK_CONFIG="${DXVK_CONFIG:-dxgi.hideNvidiaGpu = False}"
    export PROTON_HIDE_NVIDIA_GPU="${PROTON_HIDE_NVIDIA_GPU:-0}"
    export WINE_HIDE_NVIDIA_GPU="${WINE_HIDE_NVIDIA_GPU:-0}"
    # NVAPI/CUDA: an, wenn nvidia-libs im Prefix (sonst aus).
    export PROTON_ENABLE_NVAPI="${PROTON_ENABLE_NVAPI:-0}"
    export DXVK_ENABLE_NVAPI="${DXVK_ENABLE_NVAPI:-0}"
    if ! type recipe_nvidia_libs::export_launch_env >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "$(dirname "${BASH_SOURCE[0]}")/recipe-nvidia-libs.sh" 2>/dev/null || true
    fi
    if type recipe_nvidia_libs::export_launch_env >/dev/null 2>&1; then
        recipe_nvidia_libs::export_launch_env
    fi
    # CEF/UXP: bei kaputtem GPU-Pfad SwiftShader bevorzugen (weniger schwarze Home-Panels).
    export ANGLE_DEFAULT_PLATFORM="${ANGLE_DEFAULT_PLATFORM:-swiftshader}"
    # Vom Host-GUI (Qt/Electron) geerbtes D-Bus killt Wine oft mit Assertion-Abort.
    unset DBUS_SESSION_BUS_ADDRESS || true
    export NO_AT_BRIDGE=1
    export DBUS_FATAL_WARNINGS=0
}

recipe_premiere::_validate_prefix() {
    if ! type security::validate_path >/dev/null 2>&1; then
        recipe_hooks::_source security.sh
    fi
    security::validate_path "$WINE_PREFIX" || return 1
    [ -d "$WINE_PREFIX" ] || {
        echo "FEHLER: Wine-Prefix nicht gefunden: $WINE_PREFIX" >&2
        recipe_premiere::_notify "Adobe Premiere Pro 2024" \
            "Wine-Prefix nicht gefunden — bitte installieren/reparieren." "dialog-error"
        return 1
    }
    return 0
}

recipe_premiere::_prepare_prefix() {
    recipe_hooks::_source recipe-premiere-install.sh
    recipe_guard::kill_stale_winetricks 2>/dev/null || true
    # Live: Premiere unter Proton balloniert auf ~15–20 GB RSS und triggert OOM.
    # Unter 16 GB frei → Start verweigern (sonst killt der Kernel Rezeptor mit).
    if ! recipe_guard::require_mem 16384; then
        recipe_premiere::_notify "Adobe Premiere Pro 2024" \
            "Zu wenig freier RAM — Browser/Apps schließen, dann erneut Starten (mind. ~16 GB frei)." \
            "dialog-error"
        return 1
    fi
    recipe_premiere::_clear_stuck_session
    # Halbstarts ohne Fenster fressen RAM bis OOM — vor jedem Start aufräumen.
    if recipe_guard::process_matches "Adobe Premiere Pro.exe"; then
        echo "⚠ Beende hängende Premiere-Instanz (RAM-Schutz)…"
        recipe_premiere::_runtime_log "Kill leftover Premiere before launch"
        pkill -f 'Adobe Premiere Pro\.exe' 2>/dev/null || true
        sleep 1
        pkill -9 -f 'Adobe Premiere Pro\.exe' 2>/dev/null || true
        if type wine_runtime::wineserver >/dev/null 2>&1; then
            wine_runtime::wineserver -k 2>/dev/null || true
        fi
        sleep 1
    fi
    if recipe_guard::process_matches "Adobe Premiere Pro.exe"; then
        recipe_premiere::_notify "Adobe Premiere Pro 2024" \
            "Läuft noch — zuerst Beenden, dann erneut Starten." \
            "$(recipe_guard::notify_icon 2>/dev/null || true)"
        return 1
    fi
    adobe_setup::disable_virtual_desktop
    recipe_premiere::disable_crash_reporters
    recipe_premiere::fix_icu_dlls
    recipe_premiere::apply_ui_workarounds
    adobe_setup::ensure_msxml3r_system32 2>/dev/null || true
    if ! type recipe_nvidia_libs::ensure >/dev/null 2>&1; then
        recipe_hooks::_source recipe-nvidia-libs.sh 2>/dev/null || true
    fi
    if type recipe_nvidia_libs::ensure >/dev/null 2>&1 && recipe_nvidia_libs::wanted; then
        if ! recipe_nvidia_libs::installed "$WINEPREFIX"; then
            recipe_premiere::_runtime_log "nvidia-libs fehlen — installiere (CUDA)"
            recipe_nvidia_libs::ensure || recipe_premiere::_runtime_log "nvidia-libs optional fehlgeschlagen"
        fi
    fi
    recipe_win10::ensure 2>/dev/null \
        || recipe_premiere::_runtime_log "Warnung: win10 Registry fehlgeschlagen"

    if ! recipe_fonts::ensure "${DATA_ROOT}/premiere-fonts.log"; then
        recipe_premiere::_runtime_log "Schriften fehlgeschlagen — siehe ${DATA_ROOT}/premiere-fonts.log"
        return 1
    fi
    recipe_fonts::registry
    recipe_dpi::logpixels 2>/dev/null || true

    if ! recipe_validate::vcrun_dll_ok "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll"; then
        local arch
        arch="$(file "$WINEPREFIX/drive_c/windows/system32/msvcp140.dll" 2>/dev/null \
            | grep -o 'ARM64\|x86-64' || true)"
        if [ "$arch" = "ARM64" ] && type recipe_vcrun::ensure >/dev/null 2>&1; then
            recipe_premiere::_runtime_log "MSVCP140 ARM64 — installiere VC++ x64"
            recipe_vcrun::ensure "${DATA_ROOT}/premiere-vcrun-fix.log" || return 1
        fi
    fi

    wine_runtime::deploy_proton_graphics_dlls \
        || recipe_premiere::_runtime_log "FEHLER: Proton-Grafik-DLLs nicht deploybar — Reparieren"

    if ! recipe_validate::native_pe "$WINEPREFIX/drive_c/windows/syswow64/gdiplus.dll"; then
        echo "FEHLER: Native gdiplus fehlt — Rezeptor → Reparieren." >&2
        recipe_premiere::_notify "Adobe Premiere Pro 2024" "gdiplus fehlt — bitte Reparieren." "dialog-error"
        return 1
    fi
    return 0
}

recipe_premiere::_find_exe() {
    local exe=""
    exe="$(premiere::find_exe "$WINE_PREFIX" 2>/dev/null || true)"
    if [ -n "$exe" ]; then
        echo "$exe"
        return 0
    fi
    local path
    while IFS= read -r path; do
        [ -f "$path" ] || continue
        echo "$path"
        return 0
    done < <(premiere::possible_exe_paths "$WINE_PREFIX" 2>/dev/null || true)
    return 1
}

recipe_premiere::_wine_args() {
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
        recipe_premiere::_runtime_log "Öffne Datei: $file -> $wine_path"
    done
}

recipe_premiere::launch() {
    recipe_premiere::_locale
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

    recipe_premiere::_export_launch_env
    recipe_premiere::_validate_prefix || exit 1
    recipe_premiere::_prepare_prefix || exit 1

    local premiere_exe runtime_desc wine_args=() exit_code notify_icon
    premiere_exe="$(recipe_premiere::_find_exe)" || {
        recipe_premiere::_notify "Adobe Premiere Pro 2024" \
            "Adobe Premiere Pro.exe nicht gefunden — Installation prüfen." "dialog-error"
        recipe_hooks::die "Adobe Premiere Pro.exe nicht gefunden — installieren oder reparieren"
    }

    runtime_desc="$(wine_runtime::describe 2>/dev/null || echo "Proton-GE")"
    echo "✓ Premiere gefunden: $premiere_exe"
    echo "═══════════════════════════════════════════════════════════════"
    echo "           Adobe Premiere Pro - Linux Launcher"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Premiere-Pfad: $premiere_exe"
    echo "Wine-Prefix: $WINE_PREFIX"
    echo "Wine-Version: $runtime_desc"
    echo ""
    echo "Tipps: Erster Start kann 1–2 Minuten dauern; bei Problemen Reparieren."
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "🔄 Premiere wird gestartet..."

    if type recipe_notify::starting >/dev/null 2>&1; then
        recipe_notify::starting
    else
        notify_icon="$(recipe_guard::notify_icon 2>/dev/null || true)"
        recipe_premiere::_notify "Adobe Premiere Pro 2024" "Wird gestartet…" "$notify_icon"
    fi

    recipe_premiere::_wine_args wine_args "$@"
    echo "⏳ Initialisiere Wine-Umgebung..."
    recipe_premiere::_runtime_log "Starte Premiere: $premiere_exe"
    recipe_premiere::_runtime_log "WINEDLLOVERRIDES=$WINEDLLOVERRIDES WINE_CPU_TOPOLOGY=${WINE_CPU_TOPOLOGY:-<unset>}"

    # wine64 bevorzugen (Premiere ist x64); Fallback: wine.
    local wine_bin="${WINE:-wine}"
    if [ -n "${WINE64:-}" ] && [ -x "${WINE64}" ]; then
        wine_bin="$WINE64"
    elif [ -x "$(dirname "${WINE:-}")/wine64" ]; then
        wine_bin="$(dirname "$WINE")/wine64"
    fi

    if [ ${#wine_args[@]} -gt 0 ]; then
        "$wine_bin" "$premiere_exe" "${wine_args[@]}" >> "${DATA_ROOT}/premiere-runtime.log" 2>&1
    else
        "$wine_bin" "$premiere_exe" >> "${DATA_ROOT}/premiere-runtime.log" 2>&1
    fi
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "⚠ Premiere wurde mit Exit-Code $exit_code beendet"
        echo "Log: ${DATA_ROOT}/premiere-runtime.log"
        recipe_premiere::_notify "Adobe Premiere Pro 2024" \
            "Start fehlgeschlagen (Exit $exit_code) — Log prüfen." "dialog-error"
    fi
    return "$exit_code"
}
