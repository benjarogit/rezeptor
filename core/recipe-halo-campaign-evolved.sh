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

# Normalize HALO_GFX_PRESET → ultra_low|low|balanced|high|ultra (default balanced).
recipe_halo_campaign_evolved::gfx_preset() {
    local p="${HALO_GFX_PRESET:-balanced}"
    p="${p,,}"
    p="${p//$'\r'/}"
    p="${p## }"
    p="${p%% }"
    case "$p" in
        ultra_low|ultralow|very_low|verylow) printf '%s\n' "ultra_low" ;;
        low) printf '%s\n' "low" ;;
        high) printf '%s\n' "high" ;;
        ultra|epic|max) printf '%s\n' "ultra" ;;
        *) printf '%s\n' "balanced" ;;
    esac
}

# Soft VRAM/Lumen caps for 6 GB GPUs. Preset may enable; HALO_GFX_VRAM_6GB forces on.
recipe_halo_campaign_evolved::gfx_vram_caps_wanted() {
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRAM_6GB:-0}" && return 0
    case "$(recipe_halo_campaign_evolved::gfx_preset)" in
        ultra_low|low|balanced|high) return 0 ;;
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
    local preset screen_pct
    preset="$(recipe_halo_campaign_evolved::gfx_preset)"
    screen_pct=100
    [ "$preset" = "ultra_low" ] && screen_pct=85
    mkdir -p "$cfg"
    chmod u+w "$ini" 2>/dev/null || true
    {
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_CLEAR_IMAGE:-0}" \
            || recipe_halo_campaign_evolved::gfx_vram_caps_wanted \
            || recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRR:-0}" \
            || recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}" \
            || [ -n "${HALO_GFX_PRESET:-}" ]; then
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
        if recipe_halo_campaign_evolved::gfx_vram_caps_wanted; then
            case "$preset" in
                ultra_low)
                    printf '%s\n' \
                        '; VRAM caps: aggressive (ultra_low / 6 GB)' \
                        'r.Streaming.PoolSize=1536' \
                        'r.LumenScene.SurfaceCache.AtlasSize=1024' \
                        'r.Lumen.ScreenProbeGather.DownsampleFactor=48' \
                        'r.Nanite.MaxPixelsPerEdge=4.0' \
                        'r.Shadow.Virtual.ResolutionLodBiasDirectional=1.0'
                    ;;
                low)
                    printf '%s\n' \
                        '; VRAM caps: mild (low / 6 GB)' \
                        'r.Streaming.PoolSize=1792' \
                        'r.LumenScene.SurfaceCache.AtlasSize=1536' \
                        'r.Lumen.ScreenProbeGather.DownsampleFactor=40' \
                        'r.Nanite.MaxPixelsPerEdge=3.0' \
                        'r.Shadow.Virtual.ResolutionLodBiasDirectional=0.75'
                    ;;
                high)
                    printf '%s\n' \
                        '; VRAM caps: soft (high on 6 GB)' \
                        'r.Streaming.PoolSize=2304' \
                        'r.LumenScene.SurfaceCache.AtlasSize=2048' \
                        'r.Lumen.ScreenProbeGather.DownsampleFactor=28' \
                        'r.Nanite.MaxPixelsPerEdge=1.5' \
                        'r.Shadow.Virtual.ResolutionLodBiasDirectional=0.25'
                    ;;
                *)
                    # balanced + forced HALO_GFX_VRAM_6GB on ultra
                    printf '%s\n' \
                        '; VRAM caps: soft (balanced / Empfohlen RTX 2060)' \
                        'r.Streaming.PoolSize=2048' \
                        'r.LumenScene.SurfaceCache.AtlasSize=2048' \
                        'r.Lumen.ScreenProbeGather.DownsampleFactor=32' \
                        'r.Nanite.MaxPixelsPerEdge=2.0' \
                        'r.Shadow.Virtual.ResolutionLodBiasDirectional=0.5'
                    ;;
            esac
        fi
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_VRR:-0}"; then
            printf '%s\n' \
                '; VRR / adaptive sync (opt-in)' \
                'r.VSync=0' \
                'r.D3D12.UseAllowTearing=1'
        fi
        if recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_LOW_LATENCY:-0}"; then
            # Under Steam Non-Steam, FinishCurrentFrame + AllowTearing often yield a
            # black window (Steam compositor). Soft low-latency only there.
            if recipe_halo_campaign_evolved::steam_proton_wanted; then
                printf '%s\n' \
                    '; Low input latency soft (Steam Non-Steam — no Tear/FinishCurrentFrame)' \
                    'r.OneFrameThreadLag=0' \
                    'r.GTSyncType=1' \
                    'r.VSync=0'
            else
                printf '%s\n' \
                    '; Low input latency (opt-in) — look + move share the same frame queue' \
                    'r.OneFrameThreadLag=0' \
                    '; Sync game thread closer to present (UE low-latency frame sync)' \
                    'r.GTSyncType=1' \
                    '; Finish GPU work before next game tick (costs some FPS, cuts feel-lag)' \
                    'r.FinishCurrentFrame=1' \
                    'r.VSync=0' \
                    'r.D3D12.UseAllowTearing=1'
            fi
        fi
        # Always: sg.ResolutionQuality=0 → black / missing image under Proton.
        # Lock via Engine.ini CVar — GameUserSettings is rewritten by the game.
        if [ "$have_gfx" -eq 0 ]; then
            have_gfx=1
            printf '%s\n' '[SystemSettings]'
        fi
        printf '%s\n' \
            '; Guard: never render at 0% screen scale (game often writes sg.ResolutionQuality=0)' \
            "r.ScreenPercentage=${screen_pct}" \
            'sg.ResolutionQuality=100'
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
        output::info "Engine.ini: Preset=${preset} + Medizin-Grafikoptionen (schreibgeschützt)"
    fi
    if [ -f "$cfg/GameUserSettings.ini" ]; then
        # ResolutionQuality=0 → blank/broken scaling + heavy hitching under Wine.
        # Game may rewrite it after exit; force 100 every launch (+ DesiredScreen).
        # Unlock first — previous launch may have chmod a-w'd this file.
        chmod u+w "$cfg/GameUserSettings.ini" 2>/dev/null || true
        if command -v python3 >/dev/null 2>&1; then
            if python3 - "$cfg/GameUserSettings.ini" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8", errors="replace")
n = t
was_zero = bool(re.search(r"(?m)^sg\.ResolutionQuality=0(?:\.0+)?\s*$", t))
n = re.sub(
    r"(?m)^(sg\.ResolutionQuality=)\d+(?:\.\d+)?\s*$",
    r"\g<1>100",
    n,
)
n = n.replace("bIsFirstTimeUserDevice=True", "bIsFirstTimeUserDevice=False")
# Keep desired size in sync with confirmed desktop res (avoids 1280 fallback).
for a, b in (
    ("DesiredScreenWidth", "1920"),
    ("DesiredScreenHeight", "1080"),
    ("LastUserConfirmedDesiredScreenWidth", "1920"),
    ("LastUserConfirmedDesiredScreenHeight", "1080"),
):
    n = re.sub(rf"(?m)^({re.escape(a)}=).*$", rf"\g<1>{b}", n)
if n != t:
    p.write_text(n, encoding="utf-8")
sys.exit(0 if was_zero else 1)
PY
            then
                type output::info >/dev/null 2>&1 \
                    && output::info "GameUserSettings: sg.ResolutionQuality → 100 (war 0 = Schwarzbild)" \
                    || true
            fi
        else
            sed -i -E 's/^sg\.ResolutionQuality=[0-9.]+/sg.ResolutionQuality=100/' \
                "$cfg/GameUserSettings.ini" 2>/dev/null || true
            sed -i 's/bIsFirstTimeUserDevice=True/bIsFirstTimeUserDevice=False/' \
                "$cfg/GameUserSettings.ini" 2>/dev/null || true
        fi
        # Locked after ensure_halo_video_settings (runs next) so both writers finish.
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
    local preset
    preset="$(recipe_halo_campaign_evolved::gfx_preset)"
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
    python3 - "$root" "$clear" "$exclusive" "$lowlat" "${max_fps:-0}" "$preset" <<'PY' || py_rc=$?
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
clear = sys.argv[2] == "1"
exclusive = sys.argv[3] == "1"
lowlat = sys.argv[4] == "1"
max_fps = sys.argv[5]
preset = (sys.argv[6] if len(sys.argv) > 6 else "balanced").strip().lower() or "balanced"


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

# Preset ladders tuned for RTX 2060 6GB / 1080p144 (balanced = Empfohlen).
_PRESET_MAP = {
    "ultra_low": {
        "all": "VeryLow",
        "upscale": "Performance",
    },
    "low": {
        "all": "Low",
        "upscale": "Medium",
    },
    "balanced": {
        "TextureQuality": "High",
        "GeometryQuality": "High",
        "LightingQuality": "High",
        "ReflectionsQuality": "Medium",
        "GlobalIlluminationQuality": "Medium",
        "EffectsQuality": "Medium",
        "AtmosphericsQuality": "Medium",
        "PostprocessingQuality": "Medium",
        "QualityPreset": "High",
        "upscale": "High",
    },
    "high": {
        "all": "High",
        "upscale": "High",
    },
    "ultra": {
        "all": "Ultra",
        "upscale": "Native",
    },
}


def apply_quality_preset(text: str, name: str) -> str:
    spec = _PRESET_MAP.get(name) or _PRESET_MAP["balanced"]
    n = text
    if "all" in spec:
        level = spec["all"]
        for k in _QUALITY_KEYS:
            n = set_key(n, k, level)
    else:
        for k in _QUALITY_KEYS:
            if k in spec:
                n = set_key(n, k, spec[k])
    up = spec.get("upscale")
    if up:
        n = set_key(n, "UpscalingQuality", up)
    return n


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
    # Qualitäts-Preset (Medizin) — overrides previous Low→Medium bump.
    n = apply_quality_preset(n, preset)
    if clear and preset in ("", "balanced", "high", "ultra"):
        # Clear-image still prefers High upscaler if preset left it low.
        uq = get_key(n, "UpscalingQuality")
        if uq in ("", "Low", "VeryLow", "Performance", "Medium") and preset == "balanced":
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
    try:
        gus.chmod(gus.stat().st_mode | 0o200)
    except OSError:
        pass
    t = gus.read_text(encoding="utf-8", errors="replace")
    n = t
    mode = "0" if exclusive else "1"
    for k in (
        "FullscreenMode",
        "LastConfirmedFullscreenMode",
        "PreferredFullscreenMode",
    ):
        n = re.sub(rf"(?m)^({re.escape(k)}=).*$", rf"\g<1>{mode}", n)
    # 0% scale = black frame / "missing" textures under Proton.
    n = re.sub(r"(?m)^(sg\.ResolutionQuality=).*$", r"\g<1>100", n)
    if not exclusive:
        n = re.sub(r"(?m)^(ResolutionSizeX=).*$", r"\g<1>1920", n)
        n = re.sub(r"(?m)^(ResolutionSizeY=).*$", r"\g<1>1080", n)
        n = re.sub(
            r"(?m)^(LastUserConfirmedResolutionSizeX=).*$", r"\g<1>1920", n
        )
        n = re.sub(
            r"(?m)^(LastUserConfirmedResolutionSizeY=).*$", r"\g<1>1080", n
        )
        n = re.sub(r"(?m)^(DesiredScreenWidth=).*$", r"\g<1>1920", n)
        n = re.sub(r"(?m)^(DesiredScreenHeight=).*$", r"\g<1>1080", n)
    if n != t:
        gus.write_text(n, encoding="utf-8")
        changed_any = True
    try:
        # Prevent in-game / Steam boot from writing ResolutionQuality=0 again.
        gus.chmod(0o444)
    except OSError:
        pass

sys.exit(0 if changed_any else 1)
PY
    if [ "$py_rc" -eq 0 ] && type output::info >/dev/null 2>&1; then
        output::info "Halo-Videoeinstellungen: Preset=${preset} + Medizin"
    fi
    # Always lock GUS after video pass (even when py reports "unchanged").
    chmod a-w "$root/Windows/GameUserSettings.ini" 2>/dev/null || true
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

        # gamescope / Steam-proton script set up their own display path — skip
        # our manual winewayland (would fight nested X or proton's Wayland setup).
        if recipe_halo_campaign_evolved::gamescope_wanted; then
            type output::info >/dev/null 2>&1 \
                && output::info "Host-Perf: gamescope aktiv — winewayland übersprungen" \
                || true
        elif recipe_halo_campaign_evolved::steam_proton_wanted; then
            type output::info >/dev/null 2>&1 \
                && output::info "Host-Perf: Steam-Proton-Skript — winewayland dem proton-Skript überlassen" \
                || true
        elif [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            recipe_halo_campaign_evolved::apply_winewayland || true
        fi
    fi

    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: Overlays aus, NVIDIA-Shader-Cache an" \
        || true
    return 0
}

recipe_halo_campaign_evolved::gamescope_wanted() {
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_GFX_GAMESCOPE:-0}"
}

# Medizin: launch via Steam's proton script (or steam:// if the user owns the app).
recipe_halo_campaign_evolved::steam_proton_wanted() {
    recipe_halo_campaign_evolved::_env_bool_on "${HALO_LAUNCH_VIA_STEAM:-0}"
}

recipe_halo_campaign_evolved::steam_owns_halo() {
    local lib
    for lib in \
        "${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" \
        "${HOME}/.local/share/Steam" \
        "${HOME}/.steam/steam" \
        "${HOME}/.var/app/com.valvesoftware.Steam/data/Steam"; do
        [ -n "$lib" ] || continue
        [ -f "$lib/steamapps/appmanifest_2806050.acf" ] && return 0
    done
    return 1
}

recipe_halo_campaign_evolved::find_proton_script() {
    local c tag="${PROTON_GE_TAG:-GE-Proton11-3}"
    # Prefer the recipe pin (PROTON_GE_TAG / PROTON_PATH after runtime_init).
    for c in \
        "${PROTON_PATH:+$PROTON_PATH/proton}" \
        "${WINE_RUNTIME_ROOT:+$WINE_RUNTIME_ROOT/proton}" \
        "${HOME}/.local/share/wine-software/runtime/proton-ge/${tag}/proton" \
        "${HOME}/.local/share/Steam/compatibilitytools.d/${tag}/proton" \
        "${HOME}/.local/share/Steam/steamapps/common/Proton - Experimental/proton"; do
        [ -n "$c" ] || continue
        if [ -f "$c" ] && [ -x "$c" ]; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# Point Steam's STEAM_COMPAT_DATA_PATH at our existing Wine prefix (pfx → prefix).
recipe_halo_campaign_evolved::ensure_steam_compat_data() {
    local root="${DATA_ROOT:-}" pfx compat
    [ -n "$root" ] || return 1
    pfx="${WINEPREFIX:-$root/prefix}"
    [ -d "$pfx" ] || return 1
    compat="$root/steam-compat"
    mkdir -p "$compat"
    ln -sfn "$pfx" "$compat/pfx"
    printf '%s' "$compat"
}

recipe_halo_campaign_evolved::_steam_shortcut_icon() {
    # Prefer Halo art for Steam library / “Starting game” dialog.
    local c
    for c in \
        "${RECIPE_DIR:-}/../../images/halo-campaign-evolved-icon.png" \
        "${PROJECT_ROOT:-}/images/halo-campaign-evolved-icon.png" \
        "${RECIPE_DIR:-}/../../images/rezeptor-icon.png" \
        "${PROJECT_ROOT:-}/images/rezeptor-icon.png"; do
        [ -f "$c" ] || continue
        # Resolve .. for a stable absolute path Steam can read.
        (cd "$(dirname "$c")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$c")")
        return 0
    done
    return 1
}

recipe_halo_campaign_evolved::_steam_grid_assets() {
    local c
    for c in \
        "${RECIPE_DIR:-}/assets/steam-grid" \
        "${PROJECT_ROOT:-}/recipes/halo-campaign-evolved/assets/steam-grid"; do
        [ -d "$c" ] && [ -f "$c/cover.png" ] || continue
        (cd "$c" && pwd -P)
        return 0
    done
    return 1
}

recipe_halo_campaign_evolved::_steam_nonsteam_script() {
    local s
    for s in \
        "${RECIPE_DIR:-}/assets/ensure_steam_nonsteam.py" \
        "${PROJECT_ROOT:-}/recipes/halo-campaign-evolved/assets/ensure_steam_nonsteam.py"; do
        [ -f "$s" ] || continue
        printf '%s' "$s"
        return 0
    done
    return 1
}

recipe_halo_campaign_evolved::steam_client_ready_p() {
    # Exact process name — never match our own shell cmdline containing the string.
    pgrep -x steamwebhelper >/dev/null 2>&1
}

# Orphan -child-update-ui left after a killed/crashed bootstrap — looks like "steam"
# but cannot launch games (no UI / no IPC).
recipe_halo_campaign_evolved::steam_orphan_update_ui_p() {
    pgrep -f '/ubuntu12_32/steam .*[-]child-update-ui' >/dev/null 2>&1 \
        && ! recipe_halo_campaign_evolved::steam_client_ready_p
}

recipe_halo_campaign_evolved::_steam_import_session_env() {
    # Pull X11 auth from the graphical session when Rezeptor was started without it.
    local pid key
    [ -n "${XAUTHORITY:-}" ] && [ -r "${XAUTHORITY}" ] && return 0
    for pid in $(pgrep -u "$(id -u)" -x plasmashell) \
        $(pgrep -u "$(id -u)" -x kwin_wayland) \
        $(pgrep -u "$(id -u)" -x gnome-shell); do
        [ -r "/proc/$pid/environ" ] || continue
        while IFS= read -r -d '' key; do
            case "$key" in
                XAUTHORITY=*|DISPLAY=*|WAYLAND_DISPLAY=*|XDG_RUNTIME_DIR=*|DBUS_SESSION_BUS_ADDRESS=*)
                    # key is already NAME=value from /proc/.../environ
                    export "$key"
                    ;;
            esac
        done < "/proc/$pid/environ"
        [ -n "${XAUTHORITY:-}" ] && [ -r "${XAUTHORITY}" ] && return 0
    done
    return 0
}

recipe_halo_campaign_evolved::halo_exe_running_p() {
    pgrep -f '/HaloCampaignEvolved\.exe' >/dev/null 2>&1 \
        || pgrep -f 'HaloCampaignEvolved\.exe$' >/dev/null 2>&1
}

recipe_halo_campaign_evolved::steam_stop_for_config() {
    local i
    recipe_halo_campaign_evolved::steam_running_p \
        || recipe_halo_campaign_evolved::steam_orphan_update_ui_p \
        || return 0
    type output::info >/dev/null 2>&1 \
        && output::info "Steam wird für Non-Steam-Eintrag kurz beendet…" || true
    pkill -x steamwebhelper 2>/dev/null || true
    pkill -x steam 2>/dev/null || true
    # Orphans: -child-update-ui and leftover sniper/webhelper after parent death.
    pkill -f '/ubuntu12_32/steam .*[-]child-update-ui' 2>/dev/null || true
    pkill -f '/ubuntu12_64/steamwebhelper' 2>/dev/null || true
    for i in $(seq 1 40); do
        recipe_halo_campaign_evolved::steam_running_p || break
        sleep 0.5
    done
    pkill -9 -f '/ubuntu12_32/steam' 2>/dev/null || true
    pkill -9 -f '/ubuntu12_64/steamwebhelper' 2>/dev/null || true
    pkill -9 -x steam 2>/dev/null || true
    pkill -9 -x steamwebhelper 2>/dev/null || true
    sleep 1
    if recipe_halo_campaign_evolved::steam_running_p \
        || pgrep -f '/ubuntu12_64/steamwebhelper' >/dev/null 2>&1; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Steam läuft noch — Non-Steam-Config könnte überschrieben werden" || true
    fi
    return 0
}

# Register Non-Steam shortcut + GE-Proton11-3 mapping. Prints APPID on stdout.
recipe_halo_campaign_evolved::ensure_steam_nonsteam_shortcut() {
    local exe="${1:?exe}" script proton_dir compat py_args=()
    script="$(recipe_halo_campaign_evolved::_steam_nonsteam_script || true)"
    [ -n "$script" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    python3 -c 'import vdf' >/dev/null 2>&1 || {
        type output::warning >/dev/null 2>&1 \
            && output::warning "Python-Modul vdf fehlt (pacman: python-vdf) — Steam-Non-Steam nicht möglich" \
            || true
        return 1
    }
    local proton
    proton="$(recipe_halo_campaign_evolved::find_proton_script || true)"
    [ -n "$proton" ] && [ -f "$proton" ] || return 1
    proton_dir="$(dirname "$proton")"
    compat="$(recipe_halo_campaign_evolved::ensure_steam_compat_data)" || return 1
    local steam_root="" acc=""
    for steam_root in \
        "${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" \
        "${HOME}/.local/share/Steam" \
        "${HOME}/.steam/steam"; do
        [ -n "$steam_root" ] && [ -d "$steam_root/userdata" ] && break
    done
    [ -d "${steam_root:-}/userdata" ] || return 1
    # Pick userdata with newest config (loginusers can be empty mid-shutdown).
    acc="$(
        find "$steam_root/userdata" -mindepth 2 -maxdepth 2 -type d -name config \
            -printf '%T@ %h\n' 2>/dev/null \
            | sort -nr | head -1 | awk '{print $2}' | xargs -r basename
    )"
    py_args=(
        python3 "$script"
        --exe "$exe"
        --proton-dir "$proton_dir"
        --compat-dir "$compat"
        --steam-root "$steam_root"
    )
    [[ "$acc" =~ ^[0-9]+$ ]] && py_args+=(--account-id "$acc")
    # Do not put gamescope into Steam LaunchOptions — nested gamescope under the
    # Steam client is fragile and was causing instant "failed to launch" errors.
    # HALO_GFX_GAMESCOPE still applies to the normal (non-Steam) start path.
    local icon=""
    icon="$(recipe_halo_campaign_evolved::_steam_shortcut_icon || true)"
    [ -n "$icon" ] && py_args+=(--icon "$icon")
    local grid=""
    grid="$(recipe_halo_campaign_evolved::_steam_grid_assets || true)"
    [ -n "$grid" ] && py_args+=(--grid-assets "$grid")
    local tool="${HALO_STEAM_PROTON:-GE-Proton11-3}"
    tool="${tool//$'\r'/}"
    tool="${tool## }"
    tool="${tool%% }"
    [ -n "$tool" ] || tool="GE-Proton11-3"
    py_args+=(--tool-name "$tool")
    # Caller stops Steam before write when needed.
    "${py_args[@]}"
}

# Start Steam the same way the desktop entry does: with a steam:// URL as argv.
# Bare `steam &` then a later URI often Fatal-Errors (platform modules / friends).
# One call: starts the client if needed, then runs the Non-Steam game.
recipe_halo_campaign_evolved::_steam_run_uri() {
    local uri="${1:?uri}" args=()
    recipe_halo_campaign_evolved::_steam_import_session_env || true
    command -v steam >/dev/null 2>&1 || return 1
    # systemd --user: same session as the application menu (avoids bare-steam crash).
    if command -v systemd-run >/dev/null 2>&1; then
        args=(systemd-run --user --quiet --collect)
        [ -n "${DISPLAY:-}" ] && args+=(--setenv="DISPLAY=${DISPLAY}")
        [ -n "${WAYLAND_DISPLAY:-}" ] && args+=(--setenv="WAYLAND_DISPLAY=${WAYLAND_DISPLAY}")
        [ -n "${XAUTHORITY:-}" ] && args+=(--setenv="XAUTHORITY=${XAUTHORITY}")
        [ -n "${XDG_RUNTIME_DIR:-}" ] && args+=(--setenv="XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}")
        [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
            && args+=(--setenv="DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}")
        if "${args[@]}" /usr/bin/steam "$uri" >/tmp/rezeptor-steam-rungame.log 2>&1; then
            return 0
        fi
    fi
    nohup /usr/bin/steam "$uri" >/tmp/rezeptor-steam-rungame.log 2>&1 &
    return 0
}

recipe_halo_campaign_evolved::_steam_check_or_write() {
    # Prints APPID=/BPID= lines. Writes shortcut only when --check fails.
    # If Steam is already running: never kill it just to tweak CompatTool —
    # launch with the existing shortcut and rewrite next time Steam is stopped.
    local exe="${1:?}" script compat steam_root="" proton proton_dir out icon="" pending
    script="$(recipe_halo_campaign_evolved::_steam_nonsteam_script || true)"
    compat="$(recipe_halo_campaign_evolved::ensure_steam_compat_data || true)"
    [ -n "$script" ] && [ -n "$compat" ] || return 1
    for steam_root in \
        "${HOME}/.local/share/Steam" \
        "${HOME}/.steam/steam"; do
        [ -d "$steam_root/userdata" ] && break
    done
    [ -d "${steam_root:-}/userdata" ] || return 1

    pending="${compat}/pending-nonsteam-rewrite"
    local tool="${HALO_STEAM_PROTON:-GE-Proton11-3}"
    tool="${tool//$'\r'/}"
    tool="${tool## }"
    tool="${tool%% }"
    [ -n "$tool" ] || tool="GE-Proton11-3"

    # Fast path: config already matches.
    if out="$(
        python3 "$script" --compat-dir "$compat" --steam-root "$steam_root" \
            --exe "$exe" --tool-name "$tool" --check \
            2>>/tmp/rezeptor-halo-steam-nonsteam.log
    )"; then
        rm -f "$pending" 2>/dev/null || true
        type output::info >/dev/null 2>&1 \
            && output::info "Host-Perf: Steam Non-Steam bereits gesetzt (Pfad/Optionen/${tool})" >&2 || true
        printf '%s\n' "$out"
        return 0
    fi

    # Steam läuft schon → nicht beenden. Bestehenden Eintrag nutzen, Config merken.
    if recipe_halo_campaign_evolved::steam_client_ready_p; then
        if out="$(
            python3 "$script" --compat-dir "$compat" --steam-root "$steam_root" \
                --exe "$exe" --dump-ids \
                2>>/tmp/rezeptor-halo-steam-nonsteam.log
        )"; then
            : >"$pending" 2>/dev/null || true
            type output::info >/dev/null 2>&1 \
                && output::info "Host-Perf: Steam läuft bereits — starte bestehenden Non-Steam-Eintrag (Config-Abweichung später, ohne Steam-Neustart)" >&2 || true
            printf '%s\n' "$out"
            return 0
        fi
        type output::warning >/dev/null 2>&1 \
            && output::warning "Steam läuft, aber Non-Steam-Eintrag fehlt — Steam wird kurz beendet, um ihn anzulegen" >&2 || true
    fi

    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: Steam Non-Steam + Kompatibilität + Startoptionen setzen…" >&2 || true
    # Only stop Steam when we must create/rewrite and the client is up (or orphaned).
    if recipe_halo_campaign_evolved::steam_client_ready_p \
        || recipe_halo_campaign_evolved::steam_running_p \
        || recipe_halo_campaign_evolved::steam_orphan_update_ui_p; then
        recipe_halo_campaign_evolved::steam_stop_for_config || true
        sleep 1
    fi
    proton="$(recipe_halo_campaign_evolved::find_proton_script || true)"
    [ -n "$proton" ] && [ -f "$proton" ] || return 1
    proton_dir="$(dirname "$proton")"
    icon="$(recipe_halo_campaign_evolved::_steam_shortcut_icon || true)"
    local grid=""
    grid="$(recipe_halo_campaign_evolved::_steam_grid_assets || true)"
    local -a write_args=(
        python3 "$script"
        --exe "$exe"
        --proton-dir "$proton_dir"
        --compat-dir "$compat"
        --steam-root "$steam_root"
        --tool-name "$tool"
    )
    [ -n "$icon" ] && write_args+=(--icon "$icon")
    [ -n "$grid" ] && write_args+=(--grid-assets "$grid")
    out="$("${write_args[@]}" 2>>/tmp/rezeptor-halo-steam-nonsteam.log)" || return 1
    rm -f "$pending" 2>/dev/null || true
    printf '%s\n' "$out"
    # Signal to caller that Steam was stopped / needs reload time.
    return 2
}

# Medizin HALO_LAUNCH_VIA_STEAM=1:
#   1) ensure Non-Steam shortcut + GE-Proton11-3 + launch options
#   2) steam steam://rungameid/<BPID>  (starts Steam if needed, then the game)
# Medizin off → caller uses normal Rezeptor Proton path (run_game fallthrough).
recipe_halo_campaign_evolved::run_via_steam_client() {
    local exe="${1:?exe}" appid="" bpid="" out rc=0 wrote=0 uri="" saw_helper=0 wait_i
    shift

    command -v steam >/dev/null 2>&1 || {
        type output::warning >/dev/null 2>&1 \
            && output::warning "steam nicht installiert — Non-Steam-Start unmöglich" || true
        return 1
    }

    set +e
    out="$(recipe_halo_campaign_evolved::_steam_check_or_write "$exe")"
    rc=$?
    set -e
    if [ "$rc" -eq 2 ]; then
        wrote=1
    elif [ "$rc" -ne 0 ]; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Steam-Non-Steam Config fehlgeschlagen — /tmp/rezeptor-halo-steam-nonsteam.log" || true
        return 1
    fi
    appid="$(printf '%s\n' "$out" | sed -n 's/^APPID=//p' | tail -1)"
    bpid="$(printf '%s\n' "$out" | sed -n 's/^BPID=//p' | tail -1)"
    [[ "$appid" =~ ^[0-9]+$ ]] || return 1
    if ! [[ "$bpid" =~ ^[0-9]+$ ]]; then
        bpid="$(python3 -c "print((int('${appid}') << 32) | 0x02000000)")"
    fi
    uri="steam://rungameid/${bpid}"
    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: Non-Steam „Halo Campaign Evolved (Rezeptor)“ AppID ${appid}" || true

    if [ "$wrote" -eq 1 ]; then
        # shortcuts.vdf just written — brief pause before Steam reads it.
        sleep 2
    fi

    # Clear zombies from a previous crashed autostart so this boot is clean.
    if recipe_halo_campaign_evolved::steam_orphan_update_ui_p; then
        recipe_halo_campaign_evolved::steam_stop_for_config || true
        sleep 1
    fi

    if recipe_halo_campaign_evolved::steam_client_ready_p; then
        type output::info >/dev/null 2>&1 \
            && output::info "Host-Perf: Steam läuft — starte Non-Steam-Spiel…" || true
    else
        type output::info >/dev/null 2>&1 \
            && output::info "Host-Perf: Steam starten und Non-Steam-Spiel laden…" || true
    fi
    recipe_halo_campaign_evolved::_steam_run_uri "$uri" || {
        type output::warning >/dev/null 2>&1 \
            && output::warning "Steam-Startbefehl fehlgeschlagen — siehe /tmp/rezeptor-steam-rungame.log" || true
        return 1
    }

    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: warte auf Halo unter Steam/Proton (erster Start kann einige Minuten dauern)…" || true
    for wait_i in $(seq 1 300); do
        if recipe_halo_campaign_evolved::halo_exe_running_p; then
            break
        fi
        if recipe_halo_campaign_evolved::steam_client_ready_p; then
            saw_helper=1
        elif [ "$saw_helper" -eq 1 ]; then
            type output::warning >/dev/null 2>&1 \
                && output::warning "Steam-Client abgestürzt während des Starts — Log: ~/.local/share/Steam/logs/console-linux.txt" || true
            return 1
        elif [ "$wait_i" -ge 90 ] \
            && ! recipe_halo_campaign_evolved::steam_running_p \
            && ! recipe_halo_campaign_evolved::steam_client_ready_p; then
            type output::warning >/dev/null 2>&1 \
                && output::warning "Steam ist nicht hochgekommen — siehe /tmp/rezeptor-steam-rungame.log und console-linux.txt" || true
            return 1
        fi
        sleep 1
    done
    if ! recipe_halo_campaign_evolved::halo_exe_running_p; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Steam hat „Halo Campaign Evolved (Rezeptor)“ nicht gestartet — Eintrag/GE-Proton11-3/Startoptionen in Steam prüfen" || true
        return 1
    fi
    type output::info >/dev/null 2>&1 \
        && output::info "Host-Perf: Halo läuft über Steam Non-Steam (warte auf Exit)…" || true
    while recipe_halo_campaign_evolved::halo_exe_running_p; do
        sleep 2
    done
    return 0
}

recipe_halo_campaign_evolved::detect_refresh_hz() {
    local hz
    hz="$(
        xrandr 2>/dev/null | awk '/[[:space:]][0-9.]+[[:space:]]*\*/{print $2; exit}' \
            | cut -d. -f1
    )"
    if [[ "${hz:-}" =~ ^[0-9]+$ ]] && [ "$hz" -ge 30 ] && [ "$hz" -le 360 ]; then
        printf '%s' "$hz"
        return 0
    fi
    hz="$(
        kscreen-doctor -o 2>/dev/null \
            | sed -n 's/.*[0-9]\+x[0-9]\+@\([0-9.]\+\).*\*.*/\1/p' \
            | head -1 | cut -d. -f1
    )"
    if [[ "${hz:-}" =~ ^[0-9]+$ ]] && [ "$hz" -ge 30 ] && [ "$hz" -le 360 ]; then
        printf '%s' "$hz"
        return 0
    fi
    printf '144'
}

# Prefer winex11 inside gamescope's nested Xwayland (strip winewayland overrides).
recipe_halo_campaign_evolved::prefer_winex11_for_gamescope() {
    local ov cleaned
    ov="${WINEDLLOVERRIDES:-}"
    cleaned="$(
        printf '%s' "$ov" | sed -E \
            -e 's/(^|;)winex11\.drv=[^;]*//g' \
            -e 's/(^|;)winewayland\.drv=[^;]*//g' \
            -e 's/;;+/;/g' -e 's/^;//' -e 's/;$//'
    )"
    if [ -n "$cleaned" ]; then
        export WINEDLLOVERRIDES="${cleaned};winewayland.drv=d;winex11.drv=b"
    else
        export WINEDLLOVERRIDES="winewayland.drv=d;winex11.drv=b"
    fi
    unset WINE_USE_EGL 2>/dev/null || true
    return 0
}

# Run Halo under wine / Steam-proton / gamescope. Always exec's (or returns
# non-zero). Caller may background the function for trainer co-launch.
# Args: exe [game args...]
recipe_halo_campaign_evolved::run_game() {
    local exe="${1:?exe}" base hz w h proton compat abs_exe steam_client
    shift
    abs_exe="$(readlink -f "$exe" 2>/dev/null || printf '%s' "$exe")"
    base="$(basename "$abs_exe")"
    cd "$(dirname "$abs_exe")" || return 1

    # Steam Non-Steam shortcut (Proton compat + launch options) or owned library copy.
    if recipe_halo_campaign_evolved::steam_proton_wanted; then
        # Do not fall through to gamescope/wine — that path hid Steam failures.
        if recipe_halo_campaign_evolved::run_via_steam_client "$abs_exe" "$@"; then
            return 0
        fi
        type output::warning >/dev/null 2>&1 \
            && output::warning "Steam-Non-Steam-Start fehlgeschlagen — siehe Log /tmp/rezeptor-halo-steam-nonsteam.log" || true
        return 1
    fi

    if recipe_halo_campaign_evolved::gamescope_wanted; then
        if ! command -v gamescope >/dev/null 2>&1; then
            type output::warning >/dev/null 2>&1 \
                && output::warning "gamescope nicht installiert — normaler Start" || true
        else
            recipe_halo_campaign_evolved::prefer_winex11_for_gamescope || true
            # Host session display for the gamescope process; child gets nested :N.
            if [ -z "${DISPLAY:-}" ] && [ -n "${HALO_HOST_DISPLAY:-}" ]; then
                export DISPLAY="$HALO_HOST_DISPLAY"
            fi
            hz="${HALO_GFX_GAMESCOPE_HZ:-$(recipe_halo_campaign_evolved::detect_refresh_hz)}"
            w="${HALO_GFX_GAMESCOPE_W:-1920}"
            h="${HALO_GFX_GAMESCOPE_H:-1080}"
            type output::info >/dev/null 2>&1 \
                && output::info "Host-Perf: Start über gamescope ${w}x${h}@${hz} (weniger Present-Lag)" \
                || true
            # Gamescope WSI breaks DXVK Vulkan instance → Halo "GPU not supported".
            export ENABLE_GAMESCOPE_WSI=0
            exec env ENABLE_GAMESCOPE_WSI=0 gamescope -f -b \
                -W "$w" -H "$h" \
                -w "$w" -h "$h" \
                -r "$hz" \
                --force-grab-cursor --force-windows-fullscreen --immediate-flips --rt \
                -- wine "./$base" "$@"
        fi
    fi

    # winewayland path: never leave host DISPLAY (XWayland lag).
    exec env -u DISPLAY wine "./$base" "$@"
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

# True if path is missing or smaller than min bytes (corrupt/old skip stubs).
recipe_halo_campaign_evolved::_file_smaller_than() {
    local path="${1:?}" min="${2:?}" sz
    [ -f "$path" ] || return 0
    sz="$(stat -c%s "$path" 2>/dev/null || echo 0)"
    [ "${sz:-0}" -lt "$min" ]
}

recipe_halo_campaign_evolved::_skip_intro_stub_mp4() {
    local assets stub
    assets="${RECIPE_DIR:-}/assets"
    if [ ! -f "$assets/skip-intro-LogoParade.mp4" ]; then
        assets="${PROJECT_ROOT:-}/recipes/halo-campaign-evolved/assets"
    fi
    stub="$assets/skip-intro-LogoParade.mp4"
    [ -f "$stub" ] || return 1
    printf '%s' "$stub"
}

# Skip LogoParade with a *valid* black MP4. Never rewrite Splash.bmp — a fake
# "BM...." stub caused AV@null at SecondsSinceStart=0 (UECC …B6516B5D…).
recipe_halo_campaign_evolved::ensure_skip_intro() {
    local root="${1:-}" movies splash logo splash_bmp stub
    [ -n "$root" ] && [ -d "$root" ] || return 0
    movies="$root/Meteorite/Content/Movies"
    splash="$root/Meteorite/Content/Splash"
    logo="$movies/LogoParade.mp4"
    splash_bmp="$splash/Splash.bmp"

    # Heal installs broken by the old invalid BMP stub (always).
    if [ -f "${splash_bmp}.rezeptor_bak" ] \
        && recipe_halo_campaign_evolved::_file_smaller_than "$splash_bmp" 1024; then
        cp -f "${splash_bmp}.rezeptor_bak" "$splash_bmp" || true
        type output::info >/dev/null 2>&1 \
            && output::info "Splash.bmp: kaputten Stub wiederhergestellt" || true
    fi

    if ! recipe_halo_campaign_evolved::_env_bool_on "${HALO_SKIP_INTRO:-0}"; then
        # Option off: put the real intro back when we have a backup.
        if [ -f "${logo}.rezeptor_bak" ]; then
            cp -f "${logo}.rezeptor_bak" "$logo" || true
        fi
        return 0
    fi

    [ -d "$movies" ] || return 0
    stub="$(recipe_halo_campaign_evolved::_skip_intro_stub_mp4 2>/dev/null || true)"
    if [ -z "$stub" ] || [ ! -f "$stub" ]; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Skip-Intro: gültiger Stub-MP4 fehlt — Intro bleibt" || true
        return 0
    fi

    if [ -f "$logo" ] && [ ! -f "${logo}.rezeptor_bak" ]; then
        # Only backup a real video (not a previous corrupt/tiny stub).
        if ! recipe_halo_campaign_evolved::_file_smaller_than "$logo" 100000; then
            cp -f "$logo" "${logo}.rezeptor_bak" || true
        fi
    fi
    if [ ! -f "${logo}.rezeptor_bak" ] \
        && recipe_halo_campaign_evolved::_file_smaller_than "$logo" 100000; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Skip-Intro: kein Original-Backup für LogoParade — übersprungen" \
            || true
        return 0
    fi
    cp -f "$stub" "$logo" || return 0
    type output::success >/dev/null 2>&1 \
        && output::success "Intro-Video gekürzt (gültiger Black-Stub; Splash unverändert)" \
        || true
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
    # Steam Non-Steam test path needs the client running.
    if recipe_halo_campaign_evolved::steam_proton_wanted; then
        return 0
    fi
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

# Wine installers write under prefix/drive_c/… — users expect the game at DATA_ROOT.
# Delegates to recipe_app_link (absolute symlink; relocate/repair refresh it).
recipe_halo_campaign_evolved::ensure_game_visible_at_data_root() {
    local root="${1:-}" core="${CORE_DIR:-}"
    [ -n "$root" ] && [ -d "$root" ] || return 0
    if type recipe_hooks::state_set >/dev/null 2>&1; then
        recipe_hooks::state_set GAME_ROOT "$root"
    fi
    export GAME_ROOT="$root"
    # Match recipe.yml app_link_name when RECIPE_YML is not loaded yet.
    export APP_LINK_NAME="${APP_LINK_NAME:-HaloCampaignEvolved}"
    if ! type recipe_app_link::ensure >/dev/null 2>&1; then
        if [ -z "$core" ] || [ ! -f "$core/recipe-app-link.sh" ]; then
            core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        fi
        # shellcheck source=/dev/null
        source "$core/recipe-app-link.sh" 2>/dev/null || true
    fi
    if type recipe_app_link::ensure >/dev/null 2>&1; then
        recipe_app_link::ensure || true
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
