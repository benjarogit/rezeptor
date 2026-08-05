#!/usr/bin/env bash
# Halo Campaign Evolved — nach Setup EXE im Prefix finden und WORK_ROOT setzen.
#
# The game binary is never modified. Everything the Xbox sign-in needs happens in
# the prefix: RUNE crack (offline Steam), the release's own MSVC runtime 14.40+ and
# its original libHttpClient. See recipes/halo-campaign-evolved/assets/ for the
# analysis that led there.
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_halo_campaign_evolved::find_game_exe() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local f preferred
    [ -d "$prefix/drive_c" ] || return 1
    # Bevorzugter /DIR=-Pfad aus Silent-Install
    preferred="$prefix/drive_c/Games/HaloCampaignEvolved/HaloCampaignEvolved.exe"
    if [ -f "$preferred" ]; then
        echo "$preferred"
        return 0
    fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            setup.exe|Setup.exe|unins*.exe|vcredist*.exe|dxwebsetup.exe) continue ;;
        esac
        echo "$f"
        return 0
    done < <(
        find "$prefix/drive_c" -type f \( \
            -iname 'HaloCampaignEvolved.exe' -o \
            -iname '*Halo*Campaign*Evolved*.exe' -o \
            -iname 'MCC-Win64-Shipping.exe' \
        \) 2>/dev/null | head -5
    )
    return 1
}

# Unreal-Layout: <Spielordner>/<Projekt>/Binaries/Win64/<Spiel>.exe.
# Configs und Release-Beigaben liegen im Spielordner, nicht neben der EXE.
recipe_halo_campaign_evolved::game_root_from_exe_dir() {
    local dir="${1:?dir}" up
    case "${dir,,}" in
        */binaries/win64 | */binaries/win32)
            up="$(cd "$dir/../../.." 2>/dev/null && pwd)" || up=""
            [ -n "$up" ] && [ -d "$up" ] && dir="$up"
            ;;
    esac
    printf '%s' "$dir"
}

recipe_halo_campaign_evolved::steamworks_dir() {
    local root="${1:-}"
    [ -n "$root" ] && [ -d "$root" ] || return 1
    if [ -f "$root/Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll" ]; then
        echo "$root/Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64"
        return 0
    fi
    local d
    d="$(find "$root/Engine/Binaries/ThirdParty/Steamworks" -type d -name 'Win64' 2>/dev/null | head -1 || true)"
    [ -n "$d" ] && [ -d "$d" ] || return 1
    echo "$d"
}

# ElAmigos/RUNE: steam_emu.ini + RUNE64 neben jedem steam_api64 (Hauptspiel + DigitalExtras).
# LoadDll=RUNE64.dll — ohne DLL greift der Crack nicht.
# Offline=1 = ElAmigos-Default (wie unter Windows); Offline=0 nicht erzwingen.
# Overlay, lobby and self-protect off is the combination the campaign was verified
# with under Proton; the overlay hooks have no counterpart here.
recipe_halo_campaign_evolved::_patch_steam_emu_ini() {
    local emu="${1:-}"
    [ -f "$emu" ] || return 0
    if ! grep -qE '^Offline=' "$emu"; then
        printf '\nOffline=1\n' >>"$emu"
    fi
    sed -i 's/^Overlays=.*/Overlays=0/' "$emu" 2>/dev/null || true
    sed -i 's/^LobbyEnabled=.*/LobbyEnabled=0/' "$emu" 2>/dev/null || true
    if grep -qE '^SelfProtect=' "$emu"; then
        sed -i 's/^SelfProtect=.*/SelfProtect=0/' "$emu"
    else
        printf 'SelfProtect=0\n' >>"$emu"
    fi
    if grep -qE '^LoadDll=' "$emu"; then
        sed -i 's/^LoadDll=.*/LoadDll=RUNE64.dll/' "$emu"
    else
        printf 'LoadDll=RUNE64.dll\n' >>"$emu"
    fi
}

recipe_halo_campaign_evolved::ensure_rune_crack() {
    local root="${1:-}" exe_dir="${2:-}" steam_dir="" rune="" d
    [ -n "$root" ] && [ -d "$root" ] || return 0
    steam_dir="$(recipe_halo_campaign_evolved::steamworks_dir "$root" || true)"

    if [ -f "$exe_dir/RUNE64.dll" ]; then
        rune="$exe_dir/RUNE64.dll"
    elif [ -n "$steam_dir" ] && [ -f "$steam_dir/RUNE64.dll" ]; then
        rune="$steam_dir/RUNE64.dll"
    else
        rune="$(find "$root" -type f -iname 'RUNE64.dll' 2>/dev/null | head -1 || true)"
    fi
    if [ -z "$rune" ] || [ ! -f "$rune" ]; then
        output::info "RUNE64.dll fehlt — ElAmigos-Crack unvollständig?"
        return 0
    fi

    # RUNE neben EXE (cwd beim Start) und in jedem Steamworks-Win64
    if [ -n "$exe_dir" ] && [ -d "$exe_dir" ] \
        && [ "$(readlink -f "$rune")" != "$(readlink -f "$exe_dir/RUNE64.dll")" ]; then
        cp -f "$rune" "$exe_dir/RUNE64.dll"
    fi
    # steam_api64 + emu auch neben EXE (Validate: RUNE-OK braucht alle drei dort)
    if [ -n "$exe_dir" ] && [ -d "$exe_dir" ] && [ -n "$steam_dir" ]; then
        if [ -f "$steam_dir/steam_api64.dll" ] && [ ! -f "$exe_dir/steam_api64.dll" ]; then
            cp -f "$steam_dir/steam_api64.dll" "$exe_dir/steam_api64.dll"
        fi
        if [ -f "$steam_dir/steam_emu.ini" ]; then
            cp -f "$steam_dir/steam_emu.ini" "$exe_dir/steam_emu.ini"
            recipe_halo_campaign_evolved::_patch_steam_emu_ini "$exe_dir/steam_emu.ini"
        fi
    fi
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        if [ "$(readlink -f "$rune")" != "$(readlink -f "$d/RUNE64.dll")" ]; then
            cp -f "$rune" "$d/RUNE64.dll"
        fi
        if [ -f "$d/steam_emu.ini" ]; then
            recipe_halo_campaign_evolved::_patch_steam_emu_ini "$d/steam_emu.ini"
        fi
    done < <(
        find "$root" -type f -iname 'steam_api64.dll' -printf '%h\n' 2>/dev/null | sort -u
    )

    if [ -n "$steam_dir" ] && [ -f "$steam_dir/steam_emu.ini" ]; then
        if type recipe_hooks::state_set >/dev/null 2>&1; then
            recipe_hooks::state_set STEAM_EMU_INI "$steam_dir/steam_emu.ini"
        fi
    fi
    output::success "RUNE: Offline=1 + LoadDll (alle steam_api64)"
    return 0
}

recipe_halo_campaign_evolved::_env_bool_on() {
    case "${1:-}" in
        1|true|yes|on|TRUE|YES|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# Kein Xbox-Hosts-Block: Connection-refused → OnlineXsapi.LoginFailed-Dialog.
# Firewall-Hinweis von RUNE gilt unter Wine anders; Auth muss der Crack kurzschließen.
recipe_halo_campaign_evolved::ensure_hosts_clean() {
    local hosts="${WINEPREFIX:-${DATA_ROOT}/prefix}/drive_c/windows/system32/drivers/etc/hosts"
    local tmp
    [ -f "$hosts" ] || return 0
    if grep -qiE 'xboxlive|login\.live|microsoftonline|playfabapi' "$hosts" 2>/dev/null; then
        tmp="$(mktemp)"
        grep -viE 'xboxlive|login\.live|microsoftonline|playfabapi|# Rezeptor: Xbox' "$hosts" >"$tmp" || true
        if ! grep -qE '^127\.0\.0\.1[[:space:]]+localhost' "$tmp"; then
            printf '127.0.0.1 localhost\n::1 localhost\n' | cat - "$tmp" >"${tmp}.2"
            mv -f "${tmp}.2" "$tmp"
        fi
        mv -f "$tmp" "$hosts"
        output::info "hosts: Xbox/MS-Blöcke entfernt (LoginFailed-Falle)"
    fi
    return 0
}

# Engine.ini: match the known-good "Original-Modus" session (2026-08-05 morning).
# Never force Lumen HardwareRayTracing CVars — under vkd3d/Proton that caused
# black screen + AV@0x10 after intro (same PCallStackHash as the gfx crashes).
# Never set DefaultPlatformService=Null (silent exit). Optional HALO_GFX_* only.
# Do not set r.Tonemapper.GrainQuantization=0 — banding.
recipe_halo_campaign_evolved::ensure_offline_ini() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local cfg="$prefix/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    local ini="$cfg/Engine.ini"
    local have_gfx=0
    mkdir -p "$cfg"
    chmod u+w "$ini" 2>/dev/null || true
    {
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_CLEAR_IMAGE:-0}" \
            || recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRAM_6GB:-0}" \
            || recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRR:-0}" \
            || recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}"; then
            have_gfx=1
            printf '%s\n' '[SystemSettings]'
        fi
        # Default off in shell; Medizin default true writes options.env=1
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_CLEAR_IMAGE:-0}"; then
            printf '%s\n' \
                '; Preset: clear image (opt-in; menu toggles exist)' \
                'r.FilmGrain=0' \
                'r.SceneColorFringeQuality=0' \
                'r.SceneColorFringe.Max=0' \
                'r.NT.Lens.ChromaticAberration.Intensity=0' \
                'r.DefaultFeature.MotionBlur=0' \
                'r.MotionBlurQuality=0' \
                'r.DepthOfFieldQuality=0'
        fi
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRAM_6GB:-0}"; then
            printf '%s\n' \
                '; Preset: 6 GB VRAM — soft caps only (opt-in; can crash after intro)' \
                'r.Streaming.PoolSize=2048' \
                'r.LumenScene.SurfaceCache.AtlasSize=2048' \
                'r.Lumen.ScreenProbeGather.DownsampleFactor=32' \
                'r.Nanite.MaxPixelsPerEdge=2.0' \
                'r.Shadow.Virtual.ResolutionLodBiasDirectional=0.5'
        fi
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRR:-0}"; then
            printf '%s\n' \
                '; VRR / adaptive sync (opt-in)' \
                'r.VSync=0' \
                'r.D3D12.UseAllowTearing=1'
        fi
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}"; then
            printf '%s\n' \
                '; Low mouse/input latency (opt-in)' \
                'r.OneFrameThreadLag=0' \
                '; Sync game thread closer to present (UE low-latency frame sync)' \
                'r.GTSyncType=1' \
                'r.VSync=0' \
                'r.D3D12.UseAllowTearing=1'
        fi
        [ "$have_gfx" -eq 1 ] && printf '\n'
        # Community-known UE input block — game rewrites/deletes Engine.ini unless
        # we lock it after write (chmod below).
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}"; then
            printf '%s\n' \
                '[/Script/Engine.InputSettings]' \
                'bEnableMouseSmoothing=False' \
                'bViewAccelerationEnabled=False' \
                'bDisableMouseAcceleration=True' \
                ''
        fi
        printf '%s\n%s\n%s\n' \
            '[CrashReportClient]' \
            'bAgreeToCrashUpload=0' \
            'bImplicitSend=0'
    } >"$ini"
    # Halo CE wipes a writable Engine.ini on exit — keep our CVars across sessions.
    chmod a-w "$ini" 2>/dev/null || true
    if type output::info >/dev/null 2>&1; then
        if [ "$have_gfx" -eq 1 ]; then
            output::info "Engine.ini: Original-Modus + Medizin-Grafikoptionen (schreibgeschützt)"
        else
            output::info "Engine.ini: ohne OnlineSubsystem-Override (schreibgeschützt)"
        fi
    fi
    if [ -f "$cfg/GameUserSettings.ini" ]; then
        # ResolutionQuality=0 → blank/broken scaling + heavy hitching under Wine.
        # Game may rewrite it; re-apply every launch (regex covers 0 / 0.0 / CRLF).
        if command -v python3 >/dev/null 2>&1; then
            if python3 - "$cfg/GameUserSettings.ini" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8", errors="replace")
n = re.sub(
    r"(?m)^(sg\.ResolutionQuality=)\d+(?:\.\d+)?\s*$",
    r"\g<1>100",
    t,
)
n = n.replace("bIsFirstTimeUserDevice=True", "bIsFirstTimeUserDevice=False")
changed = n != t
if changed:
    p.write_text(n, encoding="utf-8")
# Exit 0 only when ResolutionQuality was repaired (for the info log).
sys.exit(0 if re.search(r"(?m)^sg\.ResolutionQuality=0", t) and changed else 1)
PY
            then
                type output::info >/dev/null 2>&1 \
                    && output::info "GameUserSettings: sg.ResolutionQuality → 100" \
                    || true
            fi
        else
            sed -i -E 's/^sg\.ResolutionQuality=[0-9.]+/sg.ResolutionQuality=100/' \
                "$cfg/GameUserSettings.ini" 2>/dev/null || true
            sed -i 's/bIsFirstTimeUserDevice=True/bIsFirstTimeUserDevice=False/' \
                "$cfg/GameUserSettings.ini" 2>/dev/null || true
        fi
    fi
    return 0
}

# Drop a 0-byte DXVK state cache (blocks real cache growth → shader hitching).
recipe_halo_campaign_evolved::ensure_dxvk_cache_sane() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local d="$prefix/drive_c/users/steamuser/AppData/Local/dxvk"
    local f
    [ -d "$d" ] || return 0
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [ ! -s "$f" ]; then
            rm -f "$f" "${f%.bin}.lut" 2>/dev/null || true
            type output::info >/dev/null 2>&1 \
                && output::info "DXVK-State-Cache war leer (0 B) — neu aufbauen" \
                || true
        fi
    done < <(find "$d" -maxdepth 1 -type f -name '*.dxvk.bin' 2>/dev/null)
    return 0
}

# Meteorite stores real video/gameplay toggles under Config/*/Halo*GameUserSettings.ini
# (often Config/invalid_id/ when offline). Patch keys for Medizin / stutter profile.
recipe_halo_campaign_evolved::ensure_halo_video_settings() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local root="$prefix/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config"
    local clear=0 exclusive=0 lowlat=0
    local max_fps="${HALO_GFX_MAX_FPS:-}"
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_CLEAR_IMAGE:-0}" && clear=1
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_EXCLUSIVE_FS:-0}" && exclusive=1
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}" && lowlat=1
    # Soft FPS cap near refresh reduces render-queue mouse lag (unlimited = worse).
    if [ -z "$max_fps" ] && [ "$lowlat" -eq 1 ]; then
        max_fps="$(
            xrandr 2>/dev/null | awk '/[[:space:]][0-9.]+[[:space:]]*\*/{print $2; exit}' \
                | cut -d. -f1
        )"
        # Prefer refresh-1 when we got a plausible Hz (e.g. 144 → 143).
        if [[ "${max_fps:-}" =~ ^[0-9]+$ ]] && [ "$max_fps" -ge 30 ] && [ "$max_fps" -le 360 ]; then
            max_fps=$((max_fps > 60 ? max_fps - 1 : max_fps))
        else
            max_fps=141
        fi
    fi
    [ -d "$root" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    local py_rc=0
    python3 - "$root" "$clear" "$exclusive" "$lowlat" "${max_fps:-0}" <<'PY' || py_rc=$?
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
clear = sys.argv[2] == "1"
exclusive = sys.argv[3] == "1"
lowlat = sys.argv[4] == "1"
max_fps = sys.argv[5]


def set_key(text: str, key: str, value: str) -> str:
    pat = rf"(?m)^({re.escape(key)}=).*$"
    if re.search(pat, text):
        return re.sub(pat, rf"\g<1>{value}", text)
    if "[HaloUserSettings]" in text:
        return text.replace(
            "[HaloUserSettings]",
            f"[HaloUserSettings]\n{key}={value}",
            1,
        )
    return text + f"\n{key}={value}\n"


def get_key(text: str, key: str) -> str:
    m = re.search(rf"(?m)^{re.escape(key)}=(.*)$", text)
    return (m.group(1).strip() if m else "")


# Never force VeryLow. If clear-image is on and the user (or first-run) is still
# on Low/VeryLow, bump to Medium — looks fine on a 2060-class GPU, stays fluid.
_QUALITY_KEYS = (
    "QualityPreset",
    "TextureQuality",
    "GeometryQuality",
    "ReflectionsQuality",
    "GlobalIlluminationQuality",
    "LightingQuality",
    "EffectsQuality",
    "AtmosphericsQuality",
    "PostprocessingQuality",
)

changed_any = False
for path in root.rglob("HaloGlobalGameUserSettings.ini"):
    t = path.read_text(encoding="utf-8", errors="replace")
    n = t
    # Always: accel/smoothing add look lag under Proton even when "scale=0".
    n = set_key(n, "bMouseSmoothingEnabled", "False")
    n = set_key(n, "bMouseAccelerationEnabled", "False")
    if clear:
        for k in (
            "bMotionBlur",
            "bScreenShake",
            "bChromaticAberration",
            "bHUDParallax",
        ):
            n = set_key(n, k, "False")
    if n != t:
        path.write_text(n, encoding="utf-8")
        changed_any = True

for path in root.rglob("HaloLocalGameUserSettings.ini"):
    t = path.read_text(encoding="utf-8", errors="replace")
    n = t
    n = set_key(n, "bVSync", "False")
    # Proton: exclusive FS often falls back to a small windowed mode.
    # Default path keeps borderless at desktop resolution.
    if exclusive:
        n = set_key(n, "bBorderlessFullscreen", "False")
    else:
        n = set_key(n, "bBorderlessFullscreen", "True")
        n = set_key(n, "ResolutionSizeX", "1920")
        n = set_key(n, "ResolutionSizeY", "1080")
    if clear:
        preset = get_key(n, "QualityPreset")
        if preset in ("", "VeryLow", "Low"):
            for k in _QUALITY_KEYS:
                n = set_key(n, k, "Medium")
        # In this title Upscaler "Medium" ≈ Performance mode (softer image).
        # Prefer High with clear-image — does not lower Ultra/Native if set.
        uq = get_key(n, "UpscalingQuality")
        if uq in ("", "Low", "VeryLow", "Performance", "Medium"):
            n = set_key(n, "UpscalingQuality", "High")
    if lowlat:
        # VendorSpecific → NVIDIA Reflex / AMD Anti-Lag path (needs NVAPI under Proton).
        n = set_key(n, "LowLatencyMode", "VendorSpecific")
        n = set_key(n, "bFrameGeneration", "False")  # FG adds aim latency
        if max_fps.isdigit() and int(max_fps) > 0:
            n = set_key(n, "MaximumFrameRate", max_fps)
    if n != t:
        path.write_text(n, encoding="utf-8")
        changed_any = True

# UE FullscreenMode: 0=exclusive, 1=borderless, 2=windowed
gus = root / "Windows" / "GameUserSettings.ini"
if gus.is_file():
    t = gus.read_text(encoding="utf-8", errors="replace")
    n = t
    mode = "0" if exclusive else "1"
    for k in (
        "FullscreenMode",
        "LastConfirmedFullscreenMode",
        "PreferredFullscreenMode",
    ):
        n = re.sub(rf"(?m)^({re.escape(k)}=).*$", rf"\g<1>{mode}", n)
    if not exclusive:
        n = re.sub(r"(?m)^(ResolutionSizeX=).*$", r"\g<1>1920", n)
        n = re.sub(r"(?m)^(ResolutionSizeY=).*$", r"\g<1>1080", n)
        n = re.sub(
            r"(?m)^(LastUserConfirmedResolutionSizeX=).*$", r"\g<1>1920", n
        )
        n = re.sub(
            r"(?m)^(LastUserConfirmedResolutionSizeY=).*$", r"\g<1>1080", n
        )
    if n != t:
        gus.write_text(n, encoding="utf-8")
        changed_any = True

sys.exit(0 if changed_any else 1)
PY
    if [ "$py_rc" -eq 0 ] && type output::info >/dev/null 2>&1; then
        output::info "Halo-Videoeinstellungen an Medizin angepasst"
    fi
    return 0
}

# Copy Proton-GE nvapi into the prefix. Rezeptor launches `wine` directly, so
# PROTON_FORCE_NVAPI (proton script only) never runs — Reflex needs the DLLs.
recipe_halo_campaign_evolved::ensure_nvapi_dlls() {
    local prefix="${WINEPREFIX:-${DATA_ROOT:-}/prefix}"
    local root="${PROTON_PATH:-${WINE_RUNTIME_ROOT:-}}"
    local src64 src32 dst64 dst32
    [ -n "$prefix" ] && [ "$prefix" != "/prefix" ] || return 0
    [ -d "$prefix/drive_c/windows/system32" ] || return 0
    [ -n "$root" ] || return 0
    src64="$root/files/lib/wine/nvapi/x86_64-windows/nvapi64.dll"
    src32="$root/files/lib/wine/nvapi/i386-windows/nvapi.dll"
    [ -f "$src64" ] || return 0
    dst64="$prefix/drive_c/windows/system32/nvapi64.dll"
    dst32="$prefix/drive_c/windows/syswow64/nvapi.dll"
    if [ ! -f "$dst64" ] || ! cmp -s "$src64" "$dst64" 2>/dev/null; then
        cp -f "$src64" "$dst64" || return 0
        type output::info >/dev/null 2>&1 && output::info "NVAPI: nvapi64 aus Proton-GE kopiert" || true
    fi
    if [ -f "$src32" ] && [ -d "$prefix/drive_c/windows/syswow64" ]; then
        cp -f "$src32" "$dst32" 2>/dev/null || true
    fi
    return 0
}

# Mirror GE-Proton's winewayland setup. PROTON_ENABLE_WAYLAND alone is a no-op
# when we exec Proton's wine binary (not the python `proton` launcher).
recipe_halo_campaign_evolved::apply_winewayland() {
    local root="${PROTON_PATH:-${WINE_RUNTIME_ROOT:-}}"
    local ov
    [ -n "${WAYLAND_DISPLAY:-}" ] || return 1
    ov="winex11.drv=d;winewayland.drv=b"
    if [ -n "${WINEDLLOVERRIDES:-}" ]; then
        # Avoid duplicating if launch/repair called twice.
        case ";${WINEDLLOVERRIDES};" in
            *";winewayland.drv="*|*winewayland.drv=*) ;;
            *) export WINEDLLOVERRIDES="${WINEDLLOVERRIDES};${ov}" ;;
        esac
    else
        export WINEDLLOVERRIDES="$ov"
    fi
    export WINE_USE_EGL="${WINE_USE_EGL:-1}"
    export WINE_DISABLE_FULLSCREEN_HACK="${WINE_DISABLE_FULLSCREEN_HACK:-1}"
    export WINE_MOVE_HACK="${WINE_MOVE_HACK:-1}"
    export PROTON_USE_XALIA=0
    if [ -n "$root" ] && [ -d "$root/files/share/X11/locale" ]; then
        export XLOCALEDIR="${XLOCALEDIR:-$root/files/share/X11/locale}"
    fi
    # Same as GE-Proton: winewayland misbehaves if DISPLAY stays set (XWayland).
    unset DISPLAY
    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: winewayland.drv aktiv (nicht XWayland) — Maus-Lag-Fix" \
        || true
    return 0
}

# Host-side: overlays off + NVIDIA shader cache + best-effort PowerMizer.
# Always applied for this recipe (not a Medizin toggle) — stutter/perf baseline.
# Optional HALO_GFX_LOW_LATENCY: real winewayland + NVAPI (Rezeptor skips proton script).
recipe_halo_campaign_evolved::apply_host_perf() {
    # Discord / MangoHud / Steam overlay / common VK layers
    export MANGOHUD=0
    export DISABLE_MANGOHUD=1
    unset MANGOHUD_CONFIG 2>/dev/null || true
    export DISCORD_DISABLE_OVERLAY=1
    export DISABLE_VK_LAYER_VALVE_steam_overlay_1=1
    export ENABLE_VK_LAYER_VALVE_steam_overlay_1=0
    # Vulkan loader 1.3.236+: disable named layers (harmless if unsupported)
    export VK_LOADER_LAYERS_DISABLE="${VK_LOADER_LAYERS_DISABLE:-VK_LAYER_VALVE_steam_overlay:VK_LAYER_VALVE_steam_fossilize:VK_LAYER_MANGOHUD_overlay:*OBS*}"

    export __GL_SHADER_DISK_CACHE="${__GL_SHADER_DISK_CACHE:-1}"
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP="${__GL_SHADER_DISK_CACHE_SKIP_CLEANUP:-1}"
    export __GL_SHADER_DISK_CACHE_SIZE="${__GL_SHADER_DISK_CACHE_SIZE:-2147483648}"
    export DXVK_STATE_CACHE="${DXVK_STATE_CACHE:-1}"

    if command -v nvidia-settings >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
        # Prefer Maximum Performance while playing (0=adaptive). Best-effort:
        # some drivers report 0 even after a successful assign. Needs X11 DISPLAY
        # — run before winewayland unsets it.
        nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=1' >/dev/null 2>&1 \
            && type output::info >/dev/null 2>&1 \
            && output::info "nvidia-settings: PowerMizer → Maximum Performance" \
            || true
    fi

    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}"; then
        recipe_halo_campaign_evolved::ensure_nvapi_dlls || true
        # Native NVAPI for Reflex (VendorSpecific). Direct wine — not proton script.
        case ";${WINEDLLOVERRIDES:-};" in
            *";nvapi64="*|*"nvapi64="*) ;;
            *)
                if [ -n "${WINEDLLOVERRIDES:-}" ]; then
                    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES};nvapi64,nvapi=n"
                else
                    export WINEDLLOVERRIDES="nvapi64,nvapi=n"
                fi
                ;;
        esac
        export DXVK_ENABLE_NVAPI="${DXVK_ENABLE_NVAPI:-1}"
        export PROTON_HIDE_NVIDIA_GPU=0
        export WINE_HIDE_NVIDIA_GPU=0
        export KWIN_DRM_ALLOW_TEARING="${KWIN_DRM_ALLOW_TEARING:-1}"
        # Stock vkd3d defaults to 3 in-flight frames ("Ensure maximum latency of 3
        # frames") — that alone is multiple refresh periods of mouse lag.
        export VKD3D_SWAPCHAIN_LATENCY_FRAMES="${VKD3D_SWAPCHAIN_LATENCY_FRAMES:-1}"
        type output::info >/dev/null 2>&1 \
            && output::info "Host-Perf: NVAPI native + VKD3D_SWAPCHAIN_LATENCY_FRAMES=${VKD3D_SWAPCHAIN_LATENCY_FRAMES}" \
            || true

        if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            recipe_halo_campaign_evolved::apply_winewayland || true
        fi
    fi

    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: Overlays aus, NVIDIA-Shader-Cache an" \
        || true
    return 0
}

# Drop folder for BYOS community mods (Rezeptor does not ship game/mod binaries).
recipe_halo_campaign_evolved::mods_dir() {
    printf '%s/mods' "${DATA_ROOT:-}"
}

# BYOS trainer EXE (FLiNG etc.) — never shipped; co-launched in the same prefix.
recipe_halo_campaign_evolved::trainer_dir() {
    printf '%s/trainer' "${DATA_ROOT:-}"
}

recipe_halo_campaign_evolved::trainer_launch_enabled() {
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_LAUNCH_TRAINER:-0}"
}

# Prefer *Trainer*.exe / *Plus*.exe, else the only .exe in trainer/.
recipe_halo_campaign_evolved::find_trainer_exe() {
    local dir f prefer="" any=""
    dir="$(recipe_halo_campaign_evolved::trainer_dir)"
    [ -n "${DATA_ROOT:-}" ] && [ -d "$dir" ] || return 1
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            *.[Ee][Xx][Ee]) ;;
            *) continue ;;
        esac
        case "$(basename "$f")" in
            *[Tt]rainer*|*[Pp]lus*)
                prefer="$f"
                break
                ;;
        esac
        [ -z "$any" ] && any="$f"
    done < <(find "$dir" -maxdepth 2 -type f -iname '*.exe' 2>/dev/null | sort)
    if [ -n "$prefer" ]; then
        printf '%s\n' "$prefer"
        return 0
    fi
    [ -n "$any" ] || return 1
    printf '%s\n' "$any"
}

recipe_halo_campaign_evolved::ensure_trainer_readme() {
    local d readme
    d="$(recipe_halo_campaign_evolved::trainer_dir)"
    [ -n "${DATA_ROOT:-}" ] || return 0
    mkdir -p "$d"
    readme="$d/README.txt"
    [ -f "$readme" ] && return 0
    cat >"$readme" <<'EOF'
Halo Campaign Evolved — Trainer drop folder (BYOS)

Look for this pack title (search hint, no download from Rezeptor):
  Halo.Campaign.Evolved.v1.0-v20260729.Plus.16.Trainer-FLiNG

Prefer: Medizin → folder icon → pick the .exe or a trainer folder
(Rezeptor copies here). Or place files in this folder manually.
Rezeptor does not ship trainers. Other trainers: no guarantee.

Then enable "Trainer mitstarten" (auto-on after pick) and Launch.
The trainer starts in the same Wine prefix a few seconds after the game.

Tips:
- Antivirus often flags trainers — that is expected.
- If the trainer window is empty, wait until the game has reached the menu.
EOF
    return 0
}

# Start trainer in the background after a short delay (same WINEPREFIX as the game).
# Caller must already have wine on PATH and WINEPREFIX set. Does not wait.
recipe_halo_campaign_evolved::spawn_trainer_after_delay() {
    local trainer delay wine_bin
    recipe_halo_campaign_evolved::trainer_launch_enabled || return 0
    trainer="$(recipe_halo_campaign_evolved::find_trainer_exe 2>/dev/null || true)"
    if [ -z "$trainer" ] || [ ! -f "$trainer" ]; then
        output::warning "Trainer-Mitstart an, aber keine .exe unter $(recipe_halo_campaign_evolved::trainer_dir)/"
        return 0
    fi
    delay="${HALO_TRAINER_DELAY_SEC:-12}"
    wine_bin="$(command -v wine 2>/dev/null || true)"
    [ -n "$wine_bin" ] || wine_bin="wine"
    output::info "Trainer startet in ${delay}s: $(basename "$trainer")"
    (
        sleep "$delay"
        # Same prefix/session as the game — required for memory trainers.
        cd "$(dirname "$trainer")" || exit 0
        "$wine_bin" "./$(basename "$trainer")" >/dev/null 2>&1 || true
    ) &
    return 0
}

recipe_halo_campaign_evolved::ensure_mods_readme() {
    local d readme
    d="$(recipe_halo_campaign_evolved::mods_dir)"
    [ -n "${DATA_ROOT:-}" ] || return 0
    mkdir -p "$d"
    readme="$d/README.txt"
    [ -f "$readme" ] && return 0
    cat >"$readme" <<'EOF'
Halo Campaign Evolved — Mod drop folder (BYOS)

Place unpacked mod contents here, then enable the matching option in Medizin
and run Repair / Start.

  ue4ss/           Contents of "UE4SS for Halo Campaign Evolved" (dwmapi.dll + ue4ss/)
  viewmodels/      Halo CE Viewmodels .pak/.ucas/.utoc
  hidden_skins/    Hidden Skins Unlocked packs
  clean_hud/       Clean HUD → ue4ss/Mods/CleanHUD/ (needs ue4ss/)
  skulls/          SkullUnlocker → ue4ss/Mods/SkullUnlocker/ (needs ue4ss/; save backup)
  weapon_slots/    MoreWeaponSlots → ue4ss/Mods/MoreWeaponSlots/ (needs ue4ss/)
  third_person/    Instant 1st→3rd Person Steam: version.dll (+ ini if any)

Trainer (separate): <data root>/trainer/*.exe — Medizin folder icon or drop manually.

Online co-op (OnlineFix / GDK) is not supported under Proton — see recipe info.
Local splitscreen may work with a second controller (no extra files).
EOF
    return 0
}

recipe_halo_campaign_evolved::_copy_tree_contents() {
    local src="${1:-}" dest="${2:-}"
    [ -n "$src" ] && [ -d "$src" ] && [ -n "$dest" ] || return 1
    mkdir -p "$dest"
    # shellcheck disable=SC2086
    cp -a "$src"/. "$dest"/ 2>/dev/null || return 1
    return 0
}

# Backup SaveGames before mods that write into the save (SkullUnlocker).
recipe_halo_campaign_evolved::backup_savegames() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    local saved stamp dest
    saved="$prefix/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/SaveGames"
    [ -d "$saved" ] || return 0
    stamp="$(date +%Y%m%d_%H%M%S)"
    dest="${DATA_ROOT}/backups/SaveGames_${stamp}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$saved" "$dest"
    output::info "Spielstand gesichert → $dest"
    return 0
}

recipe_halo_campaign_evolved::_ue4ss_needed() {
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_CLEAN_HUD:-0}" \
        || recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_SKULLS_UNLOCKED:-0}" \
        || recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_WEAPON_SLOTS_4:-0}" \
        || recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_SPLITSCREEN:-0}"
}

recipe_halo_campaign_evolved::ensure_ue4ss() {
    local exe_dir="${1:-}" drop
    [ -n "$exe_dir" ] && [ -d "$exe_dir" ] || return 0
    drop="$(recipe_halo_campaign_evolved::mods_dir)/ue4ss"
    if ! recipe_halo_campaign_evolved::_ue4ss_needed; then
        # Leave files if already present — user may have installed manually.
        return 0
    fi
    if [ ! -f "$drop/dwmapi.dll" ] || [ ! -d "$drop/ue4ss" ]; then
        output::warning "UE4SS-Option an, aber $drop fehlt (dwmapi.dll + ue4ss/) — Drop-Ordner füllen"
        return 0
    fi
    cp -f "$drop/dwmapi.dll" "$exe_dir/dwmapi.dll"
    mkdir -p "$exe_dir/ue4ss"
    cp -a "$drop/ue4ss"/. "$exe_dir/ue4ss"/
    # Wine-safe defaults (already correct in the Halo UE4SS pack; enforce anyway)
    if [ -f "$exe_dir/ue4ss/UE4SS-settings.ini" ]; then
        sed -i \
            -e 's/^ConsoleEnabled=.*/ConsoleEnabled = 0/' \
            -e 's/^GuiConsoleEnabled=.*/GuiConsoleEnabled = 0/' \
            -e 's/^GuiConsoleVisible=.*/GuiConsoleVisible = 0/' \
            -e 's/^GraphicsAPI=.*/GraphicsAPI = opengl/' \
            "$exe_dir/ue4ss/UE4SS-settings.ini" 2>/dev/null || true
    fi
    output::success "UE4SS neben EXE (dwmapi native)"
    return 0
}

recipe_halo_campaign_evolved::_deploy_paks_from() {
    local src="${1:-}" paks="${2:-}" f
    [ -d "$src" ] && [ -n "$paks" ] || return 1
    mkdir -p "$paks"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "${f,,}" in
            *.baboon|*.txt|*.md|*.jpg|*.png|*.jpeg) continue ;;
        esac
        case "${f,,}" in
            *.pak|*.ucas|*.utoc)
                cp -f "$f" "$paks/$(basename "$f")"
                ;;
        esac
    done < <(find "$src" -type f 2>/dev/null)
    return 0
}

recipe_halo_campaign_evolved::_deploy_ue4ss_mod_from() {
    local src="${1:-}" exe_dir="${2:-}" name="${3:-}" dest
    [ -d "$src" ] && [ -d "$exe_dir" ] && [ -n "$name" ] || return 1
    dest="$exe_dir/ue4ss/Mods/$name"
    mkdir -p "$dest"
    # Prefer nested Mods/<name> if the drop already mirrors UE4SS layout
    if [ -d "$src/$name" ]; then
        cp -a "$src/$name"/. "$dest"/
    elif [ -d "$src/Scripts" ] || [ -f "$src/dlls" ] || [ -f "$src/main.dll" ]; then
        cp -a "$src"/. "$dest"/
    else
        # Search one level for the mod folder
        local d
        d="$(find "$src" -maxdepth 2 -type d -iname "$name" 2>/dev/null | head -1 || true)"
        if [ -n "$d" ]; then
            cp -a "$d"/. "$dest"/
        else
            cp -a "$src"/. "$dest"/
        fi
    fi
    # Ensure enabled in mods.txt when present
    local mt="$exe_dir/ue4ss/Mods/mods.txt"
    if [ -f "$mt" ]; then
        if ! grep -qiE "^${name}[[:space:]]*:[[:space:]]*1" "$mt"; then
            if grep -qiE "^${name}[[:space:]]*:" "$mt"; then
                sed -i -E "s/^${name}[[:space:]]*:.*/${name} : 1/I" "$mt"
            else
                printf '%s : 1\n' "$name" >>"$mt"
            fi
        fi
    fi
    return 0
}

recipe_halo_campaign_evolved::ensure_skip_intro() {
    local root="${1:-}" movies splash logo splash_bmp
    [ -n "$root" ] && [ -d "$root" ] || return 0
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_SKIP_INTRO:-0}" || return 0
    movies="$root/Meteorite/Content/Movies"
    splash="$root/Meteorite/Content/Splash"
    [ -d "$movies" ] || return 0
    logo="$movies/LogoParade.mp4"
    if [ -f "$logo" ] && [ ! -f "${logo}.rezeptor_bak" ]; then
        # Keep original; replace with tiny stub (same idea as community packs)
        cp -f "$logo" "${logo}.rezeptor_bak"
        printf '\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom' >"$logo" 2>/dev/null \
            || : >"$logo"
    fi
    splash_bmp="$splash/Splash.bmp"
    if [ -f "$splash_bmp" ] && [ ! -f "${splash_bmp}.rezeptor_bak" ]; then
        cp -f "$splash_bmp" "${splash_bmp}.rezeptor_bak"
        printf 'BM\x00\x00\x00\x00' >"$splash_bmp" 2>/dev/null || true
    fi
    output::success "Intro/Splash übersprungen (Originale als .rezeptor_bak)"
    return 0
}

recipe_halo_campaign_evolved::ensure_mods() {
    local exe_dir="${1:-}" root="${2:-}" drop paks
    [ -n "$exe_dir" ] && [ -d "$exe_dir" ] || return 0
    recipe_halo_campaign_evolved::ensure_mods_readme || true
    recipe_halo_campaign_evolved::ensure_trainer_readme || true
    drop="$(recipe_halo_campaign_evolved::mods_dir)"
    [ -n "$root" ] || root="$(recipe_halo_campaign_evolved::game_root_from_exe_dir "$exe_dir")"
    paks="$root/Meteorite/Content/Paks/~mods"

    recipe_halo_campaign_evolved::ensure_ue4ss "$exe_dir" || true
    recipe_halo_campaign_evolved::ensure_skip_intro "$root" || true

    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_VIEWMODELS:-0}"; then
        if [ -d "$drop/viewmodels" ]; then
            recipe_halo_campaign_evolved::_deploy_paks_from "$drop/viewmodels" "$paks" \
                && output::success "Mod: Halo-CE-Viewmodels" \
                || output::warning "Viewmodels: Deploy fehlgeschlagen"
        else
            output::warning "HALO_MOD_VIEWMODELS an, aber $drop/viewmodels fehlt"
        fi
    fi
    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_HIDDEN_SKINS:-0}"; then
        if [ -d "$drop/hidden_skins" ]; then
            recipe_halo_campaign_evolved::_deploy_paks_from "$drop/hidden_skins" "$paks" \
                && output::success "Mod: Hidden Skins" \
                || output::warning "Hidden Skins: Deploy fehlgeschlagen"
        else
            output::warning "HALO_MOD_HIDDEN_SKINS an, aber $drop/hidden_skins fehlt"
        fi
    fi
    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_CLEAN_HUD:-0}"; then
        if [ -d "$drop/clean_hud" ]; then
            recipe_halo_campaign_evolved::_deploy_ue4ss_mod_from "$drop/clean_hud" "$exe_dir" "CleanHUD" \
                && output::success "Mod: Clean HUD" \
                || output::warning "Clean HUD: Deploy fehlgeschlagen"
        else
            output::warning "HALO_MOD_CLEAN_HUD an, aber $drop/clean_hud fehlt"
        fi
    fi
    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_SKULLS_UNLOCKED:-0}"; then
        if [ -d "$drop/skulls" ]; then
            recipe_halo_campaign_evolved::backup_savegames || true
            recipe_halo_campaign_evolved::_deploy_ue4ss_mod_from "$drop/skulls" "$exe_dir" "SkullUnlocker" \
                && output::success "Mod: SkullUnlocker (Spielstand vorher gesichert)" \
                || output::warning "SkullUnlocker: Deploy fehlgeschlagen"
        else
            output::warning "HALO_MOD_SKULLS_UNLOCKED an, aber $drop/skulls fehlt"
        fi
    fi
    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_WEAPON_SLOTS_4:-0}"; then
        if [ -d "$drop/weapon_slots" ]; then
            recipe_halo_campaign_evolved::_deploy_ue4ss_mod_from "$drop/weapon_slots" "$exe_dir" "MoreWeaponSlots" \
                && output::success "Mod: MoreWeaponSlots" \
                || output::warning "MoreWeaponSlots: Deploy fehlgeschlagen"
        else
            output::warning "HALO_MOD_WEAPON_SLOTS_4 an, aber $drop/weapon_slots fehlt"
        fi
    fi
    if recipe_halo_campaign_evolved::_env_bool_on "${HALO_MOD_THIRD_PERSON:-0}"; then
        if [ -f "$drop/third_person/version.dll" ]; then
            cp -f "$drop/third_person/version.dll" "$exe_dir/version.dll"
            # companion ini if present
            if [ -f "$drop/third_person/shoulder_swap.ini" ]; then
                cp -f "$drop/third_person/shoulder_swap.ini" "$exe_dir/shoulder_swap.ini"
            fi
            output::success "Mod: Third Person (version.dll)"
        else
            output::warning "HALO_MOD_THIRD_PERSON an, aber $drop/third_person/version.dll fehlt"
        fi
    fi
    return 0
}

# Community: Steam im Hintergrund stört RUNE/ElAmigos.
recipe_halo_campaign_evolved::steam_process_names() {
    printf '%s\n' steam steamwebhelper steam-runtime-launcher-service
}

recipe_halo_campaign_evolved::steam_running_p() {
    local p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        pgrep -x "$p" >/dev/null 2>&1 && return 0
    done < <(recipe_halo_campaign_evolved::steam_process_names)
    return 1
}

recipe_halo_campaign_evolved::require_steam_stopped() {
    local p names=""
    [ "${HALO_ALLOW_STEAM:-}" = "1" ] && return 0
    if ! recipe_halo_campaign_evolved::steam_running_p; then
        return 0
    fi
    while IFS= read -r p; do
        pgrep -x "$p" >/dev/null 2>&1 && names="${names:+$names, }$p"
    done < <(recipe_halo_campaign_evolved::steam_process_names)
    recipe_hooks::die "Steam läuft noch ($names) — beenden und erneut starten (RUNE/ElAmigos)"
}

recipe_halo_campaign_evolved::warn_if_steam_running() {
    if recipe_halo_campaign_evolved::steam_running_p; then
        output::info "Steam läuft — vor Halo beenden (RUNE/ElAmigos); Start wird blockiert"
    fi
    return 0
}

# EXE for Ghidra/GDB. The recipe no longer patches the binary, so the live EXE is
# already vanilla; .pre_xsapi_patch is the untouched copy kept from the analysis.
recipe_halo_campaign_evolved::vanilla_exe_path() {
    local exe="${1:-}" bak
    [ -n "$exe" ] || return 1
    bak="${exe}.pre_xsapi_patch"
    if [ -f "$bak" ]; then
        printf '%s\n' "$bak"
        return 0
    fi
    [ -f "$exe" ] && printf '%s\n' "$exe"
}

# MSVC runtime gate for libHttpClient.
#
# libHttpClient.Win32.dll is built with MSVC toolset >= 14.40, where std::mutex and
# std::condition_variable became constexpr-constructible: the DLL zero-initialises the
# mutex storage and no longer imports _Mtx_init_in_situ / _Cnd_init_in_situ (its older
# neighbours PartyWin.dll and PlayFabMultiplayerWin.dll still do). Only msvcp140 >= 14.40
# supports that layout — it locks a raw SRWLOCK at mtx+0x10. msvcp140 14.29 instead loads
# the stl_critical_section vtable pointer from mtx+8, which was never created, and calls
# through it: EXCEPTION_ACCESS_VIOLATION reading 0x0 in MSVCP140!_Mtx_lock right after
# XTaskQueueCreate (crash dumps 2026-08-05). Windows never sees this because the release
# installs its bundled _CommonRedist VC_redist.x64.exe (14.50); winetricks vcrun2019 does not.
HALO_CRT_MIN_VERSION=1440
HALO_CRT_DLLS="msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids vcruntime140 vcruntime140_1 concrt140"

# Prints "major.minor.build.rev" from a PE version resource, or nothing.
recipe_halo_campaign_evolved::pe_file_version() {
    local f="${1:-}"
    [ -n "$f" ] && [ -f "$f" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$f" <<'PY'
import struct, sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
# VS_FIXEDFILEINFO.dwSignature, followed by dwStrucVersion / FileVersion MS+LS.
i = data.find(b"\xbd\x04\xef\xfe")
if i < 0 or i + 16 > len(data):
    sys.exit(1)
ms, ls = struct.unpack_from("<II", data, i + 8)
print("%d.%d.%d.%d" % (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF))
PY
}

# true when "major.minor…" is at least HALO_CRT_MIN_VERSION (14.40 -> 1440).
recipe_halo_campaign_evolved::crt_version_ok() {
    local v="${1:-}" major minor
    major="${v%%.*}"
    v="${v#*.}"
    minor="${v%%.*}"
    case "${major:-}${minor:-}" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$((major * 100 + minor))" -ge "$HALO_CRT_MIN_VERSION" ]
}

recipe_halo_campaign_evolved::bundled_vcredist() {
    local root="${1:-}" f
    [ -n "$root" ] && [ -d "$root/_CommonRedist" ] || return 1
    f="$(find "$root/_CommonRedist" -maxdepth 4 -type f -iname 'VC_redist.x64.exe' 2>/dev/null | head -1 || true)"
    [ -n "$f" ] || return 1
    echo "$f"
}

# Installs the CRT from the release's own VC_redist.x64.exe. The bundle is a WiX
# archive: cabextract first yields a0..aN, one of which holds the amd64 payload.
# Running the installer under Wine is unreliable (winehq bug 57518), so unpack it.
recipe_halo_campaign_evolved::_install_crt_from_redist() {
    local redist="${1:?redist}" sys32="${2:?sys32}"
    local tmp cab n rc=1
    command -v cabextract >/dev/null 2>&1 || {
        output::warning "cabextract fehlt — MSVC-Runtime kann nicht entpackt werden"
        return 1
    }
    tmp="$(mktemp -d)" || return 1
    if cabextract -q -d "$tmp" "$redist" >/dev/null 2>&1; then
        for cab in "$tmp"/a*; do
            [ -f "$cab" ] || continue
            if cabextract -l "$cab" 2>/dev/null | grep -q 'msvcp140\.dll_amd64'; then
                for n in $HALO_CRT_DLLS; do
                    cabextract -q -d "$tmp/out" -F "${n}.dll_amd64" "$cab" >/dev/null 2>&1 || true
                done
                rc=0
                break
            fi
        done
    fi
    if [ "$rc" -eq 0 ] && [ -f "$tmp/out/msvcp140.dll_amd64" ]; then
        for n in $HALO_CRT_DLLS; do
            [ -f "$tmp/out/${n}.dll_amd64" ] || continue
            cp -f "$tmp/out/${n}.dll_amd64" "$sys32/${n}.dll" 2>/dev/null || rc=1
        done
    else
        rc=1
    fi
    rm -rf "$tmp" 2>/dev/null || true
    return "$rc"
}

recipe_halo_campaign_evolved::ensure_modern_crt() {
    local root="${1:-}"
    local sys32="${WINEPREFIX:-${DATA_ROOT:-}/prefix}/drive_c/windows/system32"
    local cur redist
    [ -d "$sys32" ] || return 0
    cur="$(recipe_halo_campaign_evolved::pe_file_version "$sys32/msvcp140.dll" 2>/dev/null || true)"
    if recipe_halo_campaign_evolved::crt_version_ok "$cur"; then
        output::success "MSVC-Runtime ${cur} (libHttpClient braucht 14.40+)"
        return 0
    fi
    redist="$(recipe_halo_campaign_evolved::bundled_vcredist "$root" 2>/dev/null || true)"
    if [ -z "$redist" ]; then
        output::warning "VC_redist.x64.exe fehlt unter _CommonRedist — Xbox-Login stürzt ab"
        return 0
    fi
    if recipe_halo_campaign_evolved::_install_crt_from_redist "$redist" "$sys32"; then
        cur="$(recipe_halo_campaign_evolved::pe_file_version "$sys32/msvcp140.dll" 2>/dev/null || true)"
        output::success "MSVC-Runtime ${cur:-14.40+} aus dem Release nachinstalliert"
    else
        output::warning "MSVC-Runtime aus dem Release nicht entpackbar (alt: ${cur:-unbekannt})"
    fi
    return 0
}

# Undo the earlier 25 KB stub: with msvcp140 >= 14.40 the release's own
# libHttpClient works, and only it can complete XAsync callbacks (a stub that never
# signals completion leaves the sign-in UI spinning forever).
recipe_halo_campaign_evolved::ensure_real_http_client() {
    local exe_dir="${1:-}"
    local dest orig sz
    [ -n "$exe_dir" ] && [ -d "$exe_dir" ] || return 0
    dest="$exe_dir/libHttpClient.Win32.dll"
    orig="$exe_dir/libHttpClient.Win32.dll.orig"
    sz="$(stat -c%s "$dest" 2>/dev/null || echo 0)"
    if [ "$sz" -gt 200000 ]; then
        output::success "libHttpClient: Original aktiv"
        return 0
    fi
    if [ -f "$orig" ]; then
        cp -f "$orig" "$dest"
        output::success "libHttpClient: Original wiederhergestellt (Stub entfernt)"
    else
        output::warning "libHttpClient.Win32.dll.orig fehlt — Release neu entpacken"
    fi
    return 0
}

# DirectML zieht DXCore CreateAdapterList — unter Proton noch semi-stub → Crash.
recipe_halo_campaign_evolved::ensure_directml_off() {
    local exe_dir="${1:-}" dml
    [ -n "$exe_dir" ] && [ -d "$exe_dir/DML" ] || return 0
    dml="$exe_dir/DML/DirectML.dll"
    if [ -f "$dml" ]; then
        mv -f "$dml" "$dml.bak"
        output::info "DirectML deaktiviert (DXCore unter Wine unvollständig)"
    fi
    return 0
}

# Nickname: RUNE → steam_emu.ini UserName=
recipe_halo_campaign_evolved::find_player_configs() {
    local dir="$1" f steam_dir
    [ -d "$dir" ] || return 1
    steam_dir="$(recipe_halo_campaign_evolved::steamworks_dir "$dir" || true)"
    if [ -n "$steam_dir" ] && [ -f "$steam_dir/steam_emu.ini" ]; then
        echo "$steam_dir/steam_emu.ini"
    fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        echo "$f"
    done < <(
        find "$dir" -maxdepth 3 -type f \( \
            -iname '*player*.ini' -o -iname '*player*.cfg' -o \
            -iname '*user*.ini' -o -iname '*user*.cfg' -o \
            -iname '*nick*.ini' -o -iname '*nick*.cfg' -o \
            -iname '*lang*.ini' -o -iname '*lang*.cfg' -o \
            -iname '*language*' -o -iname 'settings.ini' -o \
            -iname 'config.ini' -o -iname 'options.ini' \
        \) 2>/dev/null | head -20
    )
}

recipe_halo_campaign_evolved::offer_player_config() {
    local dir="$1"
    local configs="" f count=0 post_dir="$dir"
    [ -d "$dir" ] || return 0

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        configs="${configs}${configs:+|}${f}"
        count=$((count + 1))
        output::info "Config: $(basename "$f") — $(dirname "$f")"
        if [ "$(basename "$f")" = "steam_emu.ini" ]; then
            post_dir="$(dirname "$f")"
        fi
    done < <(recipe_halo_campaign_evolved::find_player_configs "$dir" || true)

    if [ "$count" -gt 0 ]; then
        recipe_hooks::state_set PLAYER_CONFIG_PATHS "$configs"
        output::info "Nickname: UserName= in steam_emu.ini (ElAmigos/RUNE)"
    else
        recipe_hooks::state_set PLAYER_CONFIG_PATHS ""
        output::info "Nickname/Spielsprache: nach dem ersten Start ggf. im Spielordner einstellen"
    fi

    type output::_gui_emit >/dev/null 2>&1 \
        && output::_gui_emit info "POST_CONFIG:$post_dir" \
        || true
    return 0
}

recipe_halo_campaign_evolved::prepare_runtime() {
    local exe="${1:-}" dir root
    [ -n "$exe" ] && [ -f "$exe" ] || return 1
    dir="$(cd "$(dirname "$exe")" && pwd)"
    root="$(recipe_halo_campaign_evolved::game_root_from_exe_dir "$dir")"
    recipe_halo_campaign_evolved::ensure_hosts_clean || true
    recipe_halo_campaign_evolved::ensure_rune_crack "$root" "$dir" || true
    if [ ! -f "$dir/RUNE64.dll" ]; then
        # RUNE64 next to EXE (AV often deletes this copy)
        output::info "RUNE64.dll fehlt neben EXE — Crack erneut kopieren / AV-Ausschluss"
    fi
    # Order matters: the CRT must be >= 14.40 before the release's own libHttpClient
    # is put back, otherwise MSVCP140!_Mtx_lock derefs a null vtable pointer.
    recipe_halo_campaign_evolved::ensure_modern_crt "$root" || true
    recipe_halo_campaign_evolved::ensure_real_http_client "$dir" || true
    recipe_halo_campaign_evolved::ensure_directml_off "$dir" || true
    recipe_halo_campaign_evolved::ensure_offline_ini || true
    recipe_halo_campaign_evolved::ensure_halo_video_settings || true
    recipe_halo_campaign_evolved::ensure_dxvk_cache_sane || true
    recipe_halo_campaign_evolved::ensure_mods "$dir" "$root" || true
    recipe_halo_campaign_evolved::ensure_game_visible_at_data_root "$root" || true
    recipe_halo_campaign_evolved::warn_if_steam_running || true
    return 0
}

# Wine installers write under prefix/drive_c/… — users expect the game at the
# chosen target root. Symlink so DATA_ROOT/HaloCampaignEvolved opens the real tree.
recipe_halo_campaign_evolved::ensure_game_visible_at_data_root() {
    local root="${1:-}" data link real
    data="${DATA_ROOT:-}"
    [ -n "$data" ] && [ -d "$data" ] || return 0
    [ -n "$root" ] && [ -d "$root" ] || return 0
    real="$(cd "$root" && pwd)" || return 0
    link="$data/HaloCampaignEvolved"
    # Already a correct symlink
    if [ -L "$link" ]; then
        if [ "$(readlink -f "$link" 2>/dev/null || true)" = "$(readlink -f "$real" 2>/dev/null || true)" ]; then
            return 0
        fi
        rm -f "$link"
    elif [ -e "$link" ]; then
        # Do not clobber a real directory the user created
        if [ "$(readlink -f "$link" 2>/dev/null || true)" = "$(readlink -f "$real" 2>/dev/null || true)" ]; then
            return 0
        fi
        output::info "Ziel enthält bereits HaloCampaignEvolved/ — kein Symlink"
        return 0
    fi
    # Prefer relative link so relocate stays readable
    if ln -sfn "prefix/drive_c/Games/HaloCampaignEvolved" "$link" 2>/dev/null \
        || ln -sfn "$real" "$link" 2>/dev/null; then
        output::success "Spiel sichtbar unter $link"
    else
        output::warning "Konnte Spiel-Link unter $data nicht anlegen"
    fi
    return 0
}

recipe_halo_campaign_evolved::finalize() {
    local exe dir root
    output::progress 92 "Spielordner ermitteln"
    exe="$(recipe_halo_campaign_evolved::find_game_exe || true)"
    if [ -z "$exe" ]; then
        output::info "Spiel-EXE noch nicht gefunden — nach manuellem Setup → Reparieren"
        return 0
    fi
    dir="$(cd "$(dirname "$exe")" && pwd)"
    root="$(recipe_halo_campaign_evolved::game_root_from_exe_dir "$dir")"
    recipe_hooks::state_set WORK_ROOT "$dir"
    recipe_hooks::state_set GAME_EXE "$exe"
    recipe_hooks::state_set GAME_DIR "$dir"
    recipe_hooks::state_set GAME_ROOT "$root"
    output::success "Spiel: $(basename "$exe")"
    output::info "Pfad: $dir"
    recipe_halo_campaign_evolved::ensure_game_visible_at_data_root "$root" || true
    output::progress 94 "ElAmigos/RUNE absichern"
    recipe_halo_campaign_evolved::prepare_runtime "$exe" || true
    output::progress 96 "Spieler-Einstellungen"
    recipe_halo_campaign_evolved::offer_player_config "$root" || true
    return 0
}
