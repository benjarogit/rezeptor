#!/usr/bin/env bash
# Shared helpers for recipe validate.sh scripts

recipe_validate::ok() { echo "OK: $*"; }
recipe_validate::fail() { echo "FAIL: $*" >&2; }
recipe_validate::warn() { echo "WARN: $*"; }

recipe_validate::msxml_is_native() {
    local dll="$1"
    [ -f "$dll" ] && file "$dll" 2>/dev/null | grep -q 'MS Windows' \
        && ! file "$dll" 2>/dev/null | grep -q 'WINE (DLL)'
}

recipe_validate::prefix_initialized() {
    local prefix="$1"
    [ -f "$prefix/user.reg" ] && [ -s "$prefix/user.reg" ]
}

recipe_validate::graphics_dlls_present() {
    local prefix="$1"
    local sys32="$prefix/drive_c/windows/system32"
    [ -f "$sys32/libvkd3d-1.dll" ] && [ -f "$sys32/d3d11.dll" ]
}

recipe_validate::dll_exists() {
    local path="$1"
    [ -f "$path" ]
}

recipe_validate::windows_version() {
    local prefix="$1" ver="$2"
    if [ "$ver" = "win10" ]; then
        grep -q '"CurrentVersion"="10.0"' "$prefix/system.reg" 2>/dev/null && return 0
        grep -q '"Version"="win10"' "$prefix/user.reg" 2>/dev/null && return 0
        grep -q '"CurrentBuild"="19045"' "$prefix/system.reg" 2>/dev/null && return 0
        return 1
    fi
    grep -q "CurrentVersion\"=\"${ver}\"" "$prefix/user.reg" 2>/dev/null \
        || grep -q "CurrentVersion\"=\"${ver}\"" "$prefix/system.reg" 2>/dev/null
}

recipe_validate::native_pe() {
    local dll="$1"
    [ -f "$dll" ] && file "$dll" 2>/dev/null | grep -q 'PE32' \
        && ! file "$dll" 2>/dev/null | grep -q 'WINE (DLL)'
}

recipe_validate::vcrun_dll_ok() {
    local dll="$1" sz
    [ -f "$dll" ] || return 1
    sz=$(stat -c%s "$dll" 2>/dev/null || echo 0)
    [ "$sz" -gt 50000 ] || return 1
    file "$dll" 2>/dev/null | grep -qE 'x86-64|Intel i386|PE32' || return 1
    return 0
}

# Portable-Version: wcrc32list26.txt → 33.05.3220, sonst Ordnername WISO.2026.….
recipe_validate::wiso_portable_version() {
    local root="$1" base ver sw wcrc
    [ -n "$root" ] && [ -d "$root" ] || return 1
    if [ -d "$root/Steuersoftware 2026" ]; then
        sw="$root/Steuersoftware 2026"
    else
        sw="$(find "$root" -maxdepth 1 -type d -name 'Steuersoftware*' 2>/dev/null | head -1 || true)"
    fi
    if [ -n "$sw" ] && [ -d "$sw" ]; then
        for wcrc in "$sw"/wcrc32list*.txt; do
            [ -f "$wcrc" ] || continue
            ver="$(grep -E '^VERSION[[:space:]]*=' "$wcrc" 2>/dev/null | head -1 \
                | sed 's/^VERSION[[:space:]]*=[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')"
            if [ -n "$ver" ]; then
                echo "$ver"
                return 0
            fi
        done
    fi
    base="$(basename "$root")"
    if [[ "$base" =~ ^WISO\.([0-9]+(\.[0-9]+){0,3})\.Portable$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# PE-Dateiversion (4-teilig) — Fallback über strings
recipe_validate::pe_file_version() {
    local exe="$1" ver
    [ -f "$exe" ] || return 1
    if command -v exiftool >/dev/null 2>&1; then
        ver="$(exiftool -ProductVersion -s3 "$exe" 2>/dev/null | head -1)"
        if [ -n "$ver" ]; then
            echo "$ver"
            return 0
        fi
    fi
    ver="$(strings "$exe" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
        | awk -F. '$1 >= 10 {print; exit}' || true)"
    [ -n "$ver" ] || return 1
    echo "$ver"
}

# Adobe Photoshop: Installationsordner ist zuverlässiger als PE-Strings
recipe_validate::photoshop_app_version() {
    local exe="$1" dir base
    [ -f "$exe" ] || return 1
    dir="$(dirname "$exe")"
    base="$(basename "$dir")"
    case "$base" in
        "Adobe Photoshop 2021") echo "22.0.0.35"; return 0 ;;
        "Adobe Photoshop 2022") echo "23.0.0.0"; return 0 ;;
        "Adobe Photoshop CC 2019") echo "20.0.0.0"; return 0 ;;
    esac
    recipe_validate::pe_file_version "$exe"
}

recipe_validate::version_guaranteed_check() {
    local guaranteed="$1" detected="$2" label="${3:-Version}"
    [ -n "$guaranteed" ] || return 0
    if [ -z "$detected" ]; then
        recipe_validate::warn "$label unbekannt — garantiert: $guaranteed"
        return 0
    fi
    if [ "$guaranteed" = "$detected" ]; then
        recipe_validate::ok "$label: $detected (getestet & garantiert)"
        return 0
    fi
    recipe_validate::warn "$label: $detected — garantiert ist $guaranteed (eigene Version: kein Support)"
}

# ClearType / fontsmooth=rgb — ohne das wirkt UI-Text pixelig (Wine liest REG_SZ "2").
recipe_validate::font_smoothing_ok() {
    local prefix="$1"
    [ -f "$prefix/user.reg" ] || return 1
    grep -qE '"FontSmoothing"="2"' "$prefix/user.reg" 2>/dev/null && return 0
    grep -qE '"FontSmoothing"=dword:00000002' "$prefix/user.reg" 2>/dev/null && return 0
    grep -qE '"FontSmoothingType"=dword:00000002' "$prefix/user.reg" 2>/dev/null && return 0
    return 1
}

# Segoe UI darf nicht auf Times New Roman gemappt sein (Wine-Default → unleserliche Qt-UI).
recipe_validate::segoe_ui_ok() {
    local prefix="$1"
    local ureg="$prefix/user.reg"
    [ -f "$ureg" ] || return 1
    # Wine\\Fonts\\Replacements gewinnt — Times New Roman dort = FAIL
    if awk '
        BEGIN { inrep=0; bad=0; good=0 }
        /^\[Software\\\\Wine\\\\Fonts\\\\Replacements\]/ { inrep=1; next }
        /^\[/ { inrep=0 }
        inrep && /"Segoe UI"="Times New Roman"/ { bad=1 }
        inrep && (/"Segoe UI"="Tahoma"/ || /"Segoe UI"="Calibri"/) { good=1 }
        END { exit (bad ? 1 : (good ? 0 : 1)) }
    ' "$ureg"; then
        return 0
    fi
    return 1
}

recipe_validate::winetricks_done() {
    local prefix="$1" pkg="$2"
    [ -f "$prefix/winetricks.log" ] && grep -q "$pkg" "$prefix/winetricks.log"
}
