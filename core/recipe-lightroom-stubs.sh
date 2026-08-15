#!/usr/bin/env bash
# Lightroom-on-Linux Stubs — geteilt von Lightroom Classic und Photoshop 2026.
#
# Vorarbeit: 6im0n/lightroom-classic-on-linux (MIT) auf Basis von
# sander110419/Lightroom-cc-on-linux (mfplat, d2d1, hnetcfg). Die gepatchten
# d2d1/mfplat sind Wine-DLLs (LGPL), hnetcfg/version-proxy/winrt_inmemstream
# eigene Stubs des Projekts. Danke an beide — hier nur an Rezeptor angepasst.
#
# Was die Bausteine lösen (Kurzform, Details im Upstream-GUIDE):
#   d2d1-patched          CLSID_D2D1ColorManagement + PushLayer-Stencil (Histogramm)
#   mfplat-patched        Forwarder MFCreateSampleCopierMFT → mf.dll
#   hnetcfg-stub          leerer Firewall-Enumerator (COM-Load sonst c0000135)
#   winrt_inmemstream     Windows.Storage.Streams mit IAsyncInfo → WinML/ONNX (KI-Masken)
#   fakeram.so            LD_PRELOAD-RAM-Deckel, damit onnxruntime nicht das ganze RAM nimmt
#   version-proxy         Dialog-Repaint-Fix (Exportieren / Einstellungen kopieren)

LR_STUB_BASE="${LR_STUB_BASE:-https://github.com/6im0n/lightroom-classic-on-linux/raw/main/resources/stubs/binaries}"
LR_STUB_D2D1_SHA256="${LR_STUB_D2D1_SHA256:-42ed63a8e9dd4c4ad2ec9116c1ca13f9db8c4a341fd69dad5a3fb53504551ba7}"
LR_STUB_HNETCFG_SHA256="${LR_STUB_HNETCFG_SHA256:-eb0f80ded1a13c503ddc846eeaae7c26b710def080cf30e05c84e9d45a510f5c}"
LR_STUB_MFPLAT_SHA256="${LR_STUB_MFPLAT_SHA256:-01d50be81963cc80045b0680d48a130bb396e40a6807fc5cb1ae43770152e27f}"
LR_STUB_VERSION_PROXY_SHA256="${LR_STUB_VERSION_PROXY_SHA256:-b745597562b3aae9fdce868884bd09abaa8219c5673e2f8eb54f283130f1c7ca}"
LR_STUB_WINRT_SHA256="${LR_STUB_WINRT_SHA256:-9dbc8f4be56b2309df8ba74af422eb4dcc07fd27fce3f37cb4e9cb1a29c65c7a}"
LR_STUB_FAKERAM_SHA256="${LR_STUB_FAKERAM_SHA256:-dd26e7a1456f5cc2ad69218e2b393f6a6fde39b13f9f8566435cca46894d72e3}"

lr_stubs::_cache_root() {
    if type wine_software_cache_dir >/dev/null 2>&1; then
        wine_software_cache_dir
    else
        echo "${HOME}/.local/share/wine-software/cache"
    fi
}

lr_stubs::cache_dir() {
    echo "$(lr_stubs::_cache_root)/lightroom-stubs"
}

# d2d1 hat historisch einen eigenen Cache (Photoshop 2026) — beibehalten, sonst
# lädt jedes bestehende Prefix die DLL erneut.
lr_stubs::_d2d1_cache_dir() {
    echo "$(lr_stubs::_cache_root)/d2d1-lightroom"
}

lr_stubs::_prefix() {
    echo "${WINEPREFIX:-${WINE_PREFIX:-}}"
}

lr_stubs::_download() {
    local url="$1" sha="$2" dest="$3"
    if [ -s "$dest" ] && echo "${sha}  $dest" | sha256sum -c --status 2>/dev/null; then
        return 0
    fi
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsSL --retry 3 -o "$dest.part" "$url" || return 1
    mv "$dest.part" "$dest"
    if ! echo "${sha}  $dest" | sha256sum -c --status 2>/dev/null; then
        rm -f "$dest"
        return 1
    fi
    return 0
}

# Stub in den Cache holen. Gibt den lokalen Pfad aus.
lr_stubs::fetch() {
    local name="$1" sha="$2" cache dest
    cache="$(lr_stubs::cache_dir)"
    mkdir -p "$cache" || return 1
    dest="$cache/$name"
    lr_stubs::_download "${LR_STUB_BASE}/${name}" "$sha" "$dest" || return 1
    printf '%s\n' "$dest"
}

lr_stubs::install_dll() {
    local src="$1" dest="$2"
    [ -n "$src" ] && [ -f "$src" ] && [ -n "$dest" ] || return 1
    mkdir -p "$(dirname "$dest")" || return 1
    if [ -f "$dest" ] && cmp -s "$src" "$dest" 2>/dev/null; then
        return 0
    fi
    cp -f "$src" "$dest"
}

# Wine-Builtin aus dem Proton-GE-Baum (für version_orig.dll & Co.).
lr_stubs::wine_builtin_dll() {
    local name="$1" root="${_WINE_RUNTIME_ROOT:-}" candidate
    if [ -z "$root" ] && [ -n "${WINE:-}" ]; then
        root="${WINE%/*}/.."
    fi
    [ -n "$root" ] || return 1
    for candidate in \
        "$root/files/lib/wine/x86_64-windows/$name" \
        "$root/lib/wine/x86_64-windows/$name"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

lr_stubs::ensure_patched_d2d1() {
    local prefix="${1:-$(lr_stubs::_prefix)}" cache src sys32
    sys32="$prefix/drive_c/windows/system32"
    [ -n "$prefix" ] && [ -d "$sys32" ] || return 1
    cache="$(lr_stubs::_d2d1_cache_dir)"
    mkdir -p "$cache" || return 1
    src="$cache/d2d1-patched.dll"
    lr_stubs::_download "${LR_STUB_BASE}/d2d1-patched.dll" "$LR_STUB_D2D1_SHA256" "$src" || return 1
    lr_stubs::install_dll "$src" "$sys32/d2d1.dll" || return 1
    return 0
}

# native nur wenn die gepatchte DLL wirklich im Prefix liegt — Wine-Builtin
# zusammen mit d2d1=native ergibt c0000135.
lr_stubs::d2d1_override() {
    local prefix="${1:-$(lr_stubs::_prefix)}" dll
    dll="$prefix/drive_c/windows/system32/d2d1.dll"
    if [ -f "$dll" ] && type recipe_validate::dll_is_wine_builtin >/dev/null 2>&1 \
        && ! recipe_validate::dll_is_wine_builtin "$dll"; then
        echo native
    else
        echo builtin
    fi
}

# hnetcfg / mfplat / winrt_inmemstream nach system32.
lr_stubs::ensure_system_dlls() {
    local prefix="${1:-$(lr_stubs::_prefix)}" sys32 src
    sys32="$prefix/drive_c/windows/system32"
    [ -n "$prefix" ] && [ -d "$sys32" ] || return 1
    if src="$(lr_stubs::fetch hnetcfg-stub.dll "$LR_STUB_HNETCFG_SHA256")"; then
        lr_stubs::install_dll "$src" "$sys32/hnetcfg.dll" || true
    fi
    if src="$(lr_stubs::fetch mfplat-patched.dll "$LR_STUB_MFPLAT_SHA256")"; then
        lr_stubs::install_dll "$src" "$sys32/mfplat.dll" || true
    fi
    if src="$(lr_stubs::fetch winrt_inmemstream.dll "$LR_STUB_WINRT_SHA256")"; then
        lr_stubs::install_dll "$src" "$sys32/winrt_inmemstream.dll" || true
    fi
    return 0
}

# Proxy version.dll neben die EXE + Wine-Builtin als version_orig.dll.
# Nach jedem Runtime-Wechsel neu — der Proxy forwardet an version_orig.
lr_stubs::ensure_version_proxy() {
    local app_dir="${1:-}" src builtin
    [ -n "$app_dir" ] && [ -d "$app_dir" ] || return 1
    src="$(lr_stubs::fetch version-proxy.dll "$LR_STUB_VERSION_PROXY_SHA256")" || return 1
    lr_stubs::install_dll "$src" "$app_dir/version.dll" || return 1
    if builtin="$(lr_stubs::wine_builtin_dll version.dll)"; then
        lr_stubs::install_dll "$builtin" "$app_dir/version_orig.dll" || true
    fi
    return 0
}

lr_stubs::register_winrt_classes() {
    local wine_bin="${WINE:-wine}" cls
    command -v "$wine_bin" >/dev/null 2>&1 || return 0
    for cls in InMemoryRandomAccessStream DataWriter RandomAccessStreamReference; do
        "$wine_bin" reg add \
            "HKLM\\Software\\Microsoft\\WindowsRuntime\\ActivatableClassId\\Windows.Storage.Streams.${cls}" \
            /v DllPath /t REG_SZ /d 'C:\windows\system32\winrt_inmemstream.dll' /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done
    return 0
}

# fakeram.so in den Cache holen. Gibt den Pfad aus (kein LD_PRELOAD).
lr_stubs::ensure_fakeram() {
    local so
    so="$(lr_stubs::fetch fakeram.so "$LR_STUB_FAKERAM_SHA256")" || return 1
    chmod +x "$so" 2>/dev/null || true
    printf '%s\n' "$so"
}

# fakeram.so als LD_PRELOAD exportieren (KI-Masken). Ohne Deckel dimensioniert
# onnxruntime seine Arena auf das gesamte System-RAM und OOMt.
lr_stubs::export_fakeram_preload() {
    local so gb totkb
    so="$(lr_stubs::ensure_fakeram)" || return 1
    gb="${FAKERAM_GB:-}"
    if [ -z "$gb" ]; then
        totkb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
        gb="$(awk -v k="${totkb:-0}" 'BEGIN{g=int(k/1024/1024*0.6); if(g<6)g=6; print g}')"
    fi
    export FAKERAM_GB="$gb"
    case ":${LD_PRELOAD:-}:" in
        *":$so:"*) ;;
        *) export LD_PRELOAD="${so}${LD_PRELOAD:+:$LD_PRELOAD}" ;;
    esac
    return 0
}

# Adobes dunamis-Tipps rendern unter Wine mit BadMatch/X_CopyArea → Abbruch.
# Feedback-Ordner leeren und schreibgeschützt lassen, dann rendert nichts.
lr_stubs::lock_dunamis_feedback() {
    local prefix="${1:-$(lr_stubs::_prefix)}" roaming fb
    [ -n "$prefix" ] || return 0
    for roaming in "$prefix"/drive_c/users/*/AppData/Roaming; do
        [ -d "$roaming" ] || continue
        fb="$roaming/com.adobe.dunamis/feedback"
        chmod -R u+w "$fb" 2>/dev/null || true
        rm -rf "$fb" 2>/dev/null || true
        mkdir -p "$fb/v1"
        chmod -R a-w "$fb" 2>/dev/null || true
    done
    return 0
}

# ir50_32/iyuv_32 sind tot und treiben Wine in TLS-Slot-Erschöpfung (Deadlock im Start).
lr_stubs::disable_dead_codecs() {
    local prefix="${1:-$(lr_stubs::_prefix)}" sys32 codec
    sys32="$prefix/drive_c/windows/system32"
    [ -d "$sys32" ] || return 0
    for codec in ir50_32.dll iyuv_32.dll; do
        if [ -f "$sys32/$codec" ] && [ ! -f "$sys32/${codec}.disabled" ]; then
            mv "$sys32/$codec" "$sys32/${codec}.disabled" 2>/dev/null || true
        fi
    done
    return 0
}

lr_stubs::_disable_file() {
    local p="$1"
    if [ -L "$p" ] && [ ! -e "$p" ]; then
        rm -f "$p"
        return 0
    fi
    [ -f "$p" ] || return 1
    if [ -e "${p}.disabled" ]; then
        rm -f "$p"
        return 0
    fi
    mv "$p" "${p}.disabled"
}

# AdobeGrowthSDK ruft kernel32.SetThreadpoolTimerEx (in Wine 11.x nicht
# implementiert) → Prozessabbruch. Adobe hat einen Fallback-Pfad ohne das SDK.
lr_stubs::disable_growth_sdk() {
    local app_dir="${1:-}" prefix f base moved=0
    if [ -n "$app_dir" ] && [ -d "$app_dir" ]; then
        lr_stubs::_disable_file "$app_dir/AdobeGrowthSDK.dll" && moved=1
        lr_stubs::_disable_file "$app_dir/adobegrowthsdk.dll" && moved=1
    fi
    prefix="$(lr_stubs::_prefix)"
    if [ -n "$prefix" ]; then
        for base in "$prefix/drive_c/Program Files" "$prefix/drive_c/Program Files (x86)"; do
            [ -d "$base" ] || continue
            while IFS= read -r -d '' f; do
                lr_stubs::_disable_file "$f" && moved=1
            done < <(find "$base" \( -iname 'AdobeGrowthSDK.dll' -o -iname 'growthsdk.node' \) -print0 2>/dev/null)
        done
    fi
    if [ "$moved" = 1 ] && type output::info >/dev/null 2>&1; then
        output::info "AdobeGrowthSDK.dll deaktiviert (SetThreadpoolTimerEx)"
    fi
    return 0
}

# Die Electron/WebView2-UI der Adobe-Installer-Engine ruft
# CreateSwapChainForComposition — DXVK stubbt das ohne diesen Schalter.
lr_stubs::ensure_dxvk_conf() {
    local prefix="${1:-$(lr_stubs::_prefix)}" conf
    [ -n "$prefix" ] || return 0
    conf="$prefix/dxvk.conf"
    mkdir -p "$(dirname "$conf")" 2>/dev/null || true
    if [ ! -f "$conf" ]; then
        cat >"$conf" <<'EOF'
dxgi.hideNvidiaGpu = False
dxgi.hideNvkGpu = False
dxgi.enableDummyCompositionSwapchain = True
EOF
        return 0
    fi
    grep -q 'enableDummyCompositionSwapchain' "$conf" 2>/dev/null \
        || printf '%s\n' 'dxgi.enableDummyCompositionSwapchain = True' >>"$conf"
    return 0
}
