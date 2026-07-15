#!/usr/bin/env bash
# Wine-Mono / .NET — zuerst still per msiexec; bei Dialog: User klickt Installieren.

recipe_dotnet::_load_mono_lock() {
    local root="${PROJECT_ROOT:-}"
    [ -n "$root" ] && [ -f "$root/core/runtime.lock" ] && source "$root/core/runtime.lock"
    export WINE_MONO_VERSION="${WINE_MONO_VERSION:-11.1.0}"
    export WINE_MONO_URL="${WINE_MONO_URL:-https://dl.winehq.org/wine/wine-mono/${WINE_MONO_VERSION}/wine-mono-${WINE_MONO_VERSION}-x86.msi}"
}

recipe_dotnet::installed() {
    local prefix="${WINEPREFIX:-}"
    [ -n "$prefix" ] || return 1
    if [ -f "$prefix/drive_c/windows/mono/mono-2.0/bin/libmono-2.0-x86.dll" ] \
        || [ -f "$prefix/drive_c/windows/mono/mono-2.0/bin/libmono-2.0-x86_64.dll" ]; then
        return 0
    fi
    if [ -d "$prefix/drive_c/windows/mono/mono-2.0/lib/mono" ]; then
        return 0
    fi
    if [ -f "$prefix/drive_c/windows/system32/mscoree.dll" ] \
        && ! file "$prefix/drive_c/windows/system32/mscoree.dll" 2>/dev/null | grep -q 'WINE (DLL)'; then
        return 0
    fi
    return 1
}

recipe_dotnet::_mono_msi_cache() {
    local d msi
    for d in "$HOME/.cache/wine" /usr/share/wine/mono /opt/wine/mono; do
        [ -d "$d" ] || continue
        for msi in "$d"/wine-mono*.msi; do
            [ -f "$msi" ] || continue
            echo "$msi"
            return 0
        done
    done
    return 1
}

recipe_dotnet::_download_mono_msi() {
    local cache="$HOME/.cache/wine" dest url ver
    recipe_dotnet::_load_mono_lock
    ver="$WINE_MONO_VERSION"
    url="$WINE_MONO_URL"
    dest="$cache/wine-mono-${ver}-x86.msi"
    mkdir -p "$cache"
    [ -f "$dest" ] && return 0
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        return 1
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest" || return 1
    else
        wget -q "$url" -O "$dest" || return 1
    fi
    [ -f "$dest" ] && [ -s "$dest" ]
}

recipe_dotnet::_stage_mono_msi() {
    local cache="$HOME/.cache/wine" ver dest

    mkdir -p "$cache"
    recipe_dotnet::_load_mono_lock
    ver="$WINE_MONO_VERSION"
    dest="$cache/wine-mono-${ver}-x86.msi"

    recipe_dotnet::_download_mono_msi || true

    if [ -f "$dest" ]; then
        return 0
    fi

    if command -v pacman >/dev/null 2>&1; then
        local src
        src="$(pacman -Ql wine-mono 2>/dev/null | awk '/\.msi$/ {print $2; exit}')"
        if [ -n "$src" ] && [ -f "$src" ]; then
            cp -f "$src" "$dest" 2>/dev/null || true
        fi
    fi

    [ -f "$dest" ] && [ -s "$dest" ]
}

recipe_dotnet::_with_mscoree_disabled() {
    local old="${WINEDLLOVERRIDES:-}"
    export WINEDLLOVERRIDES="${old:+${old};}mscoree=d;mshtml=d"
    "$@"
    local rc=$?
    export WINEDLLOVERRIDES="$old"
    return "$rc"
}

recipe_dotnet::_install_support_msi() {
    local log_file="${1:-${LOG_FILE:-/dev/null}}"
    local support_msi="${WINEPREFIX}/drive_c/windows/mono/mono-2.0/support/winemono-support.msi"
    [ -f "$support_msi" ] || return 0
    local wine_bin="${WINE:-$(command -v wine 2>/dev/null)}"
    recipe_wine_silent::run env WINEDLLOVERRIDES="" "$wine_bin" msiexec /i "$support_msi" /qn \
        >> "$log_file" 2>&1 || true
}

recipe_dotnet::install_wine_mono() {
    local log_file="${1:-${LOG_DIR:-/tmp}/wine_mono.log}"
    local msi

    recipe_winetricks::prepare || return 1

    if ! recipe_dotnet::_stage_mono_msi; then
        type output::user_action >/dev/null 2>&1 && output::user_action \
            "Wine-Mono MSI fehlt — Internet nötig; Rezeptor → Reparieren"
        type output::info >/dev/null 2>&1 && output::info \
            "Wine-Mono MSI fehlt — Rezeptor → Reparieren (lädt von dl.winehq.org)"
        return 1
    fi

    msi="$(recipe_dotnet::_mono_msi_cache)" || return 1

    wine_runtime::init || return 1
    wine_runtime::export_env
    local wine_bin="${WINE:-}"
    [ -n "$wine_bin" ] || wine_bin="$(command -v wine 2>/dev/null || true)"
    [ -n "$wine_bin" ] || return 1

    {
        echo "=== wine-mono msiexec ($(date -Iseconds)) ==="
        echo "MSI=$msi WINEPREFIX=$WINEPREFIX"
        recipe_wine_silent::run env WINEDLLOVERRIDES="" "$wine_bin" msiexec /i "$msi" /qn /norestart
    } >> "$log_file" 2>&1

    recipe_dotnet::_install_support_msi "$log_file"

    if recipe_dotnet::installed; then
        recipe_winetricks::stabilize_prefix
        return 0
    fi

    {
        echo "=== wine-mono msiexec retry ($(date -Iseconds)) ==="
        recipe_wine_silent::run env WINEDLLOVERRIDES="" "$wine_bin" msiexec /i "$msi" /passive /norestart
    } >> "$log_file" 2>&1 || true

    recipe_dotnet::_install_support_msi "$log_file"
    recipe_dotnet::installed
}

recipe_dotnet::ensure() {
    local log_file="${1:-${LOG_DIR:-/tmp}/wine_dotnet.log}"
    recipe_dotnet::installed && return 0
    recipe_winetricks::prepare || return 1

    type recipe_hooks::hint_wine_popup >/dev/null 2>&1 && recipe_hooks::hint_wine_popup
    if type output::progress >/dev/null 2>&1; then
        output::progress 45 "Wine-Mono (.NET)"
    elif type output::step >/dev/null 2>&1; then
        output::step "Wine-Mono (.NET)"
    fi

    if recipe_dotnet::install_wine_mono "$log_file"; then
        type output::success >/dev/null 2>&1 && output::success "Wine-Mono installiert"
        return 0
    fi

    if type output::step >/dev/null 2>&1; then
        output::step ".NET 4.8 (dotnet48, Fallback)"
    fi
    type recipe_hooks::hint_wine_popup >/dev/null 2>&1 && recipe_hooks::hint_wine_popup
    if recipe_winetricks::run "$log_file" dotnet48 && recipe_dotnet::installed; then
        type output::success >/dev/null 2>&1 && output::success "dotnet48 installiert"
        return 0
    fi
    return 1
}

# Vor wineboot: MSI bereitstellen und still installieren; Dialog → User klickt Installieren.
recipe_dotnet::prefix_bootstrap() {
    local log_file="${1:-${LOG_DIR:-/tmp}/wine_mono_prefix.log}"
    recipe_dotnet::_stage_mono_msi || return 0
    recipe_dotnet::installed && return 0
    recipe_dotnet::install_wine_mono "$log_file" || return 1
}
