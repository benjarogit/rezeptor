#!/usr/bin/env bats
# Halo Campaign Evolved — Spielordner-Ableitung, RUNE-Stack, MSVC-Runtime-Gate

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    PROJECT_ROOT="$ROOT"
    export PROJECT_ROOT
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-halo-campaign-evolved.sh"
}

@test "game root climbs out of Binaries/Win64" {
    # Nickname-/Sprachdateien liegen im Spielordner, nicht neben der EXE
    game="$BATS_TEST_TMPDIR/Games/HaloCampaignEvolved"
    mkdir -p "$game/Meteorite/Binaries/Win64"
    run recipe_halo_campaign_evolved::game_root_from_exe_dir \
        "$game/Meteorite/Binaries/Win64"
    [ "$status" -eq 0 ]
    [ "$output" = "$game" ]
}

@test "game root keeps a flat layout unchanged" {
    flat="$BATS_TEST_TMPDIR/Games/Flat"
    mkdir -p "$flat"
    run recipe_halo_campaign_evolved::game_root_from_exe_dir "$flat"
    [ "$status" -eq 0 ]
    [ "$output" = "$flat" ]
}

@test "steam_emu.ini keeps Offline=1 LoadDll SelfProtect" {
    emu="$BATS_TEST_TMPDIR/steam_emu.ini"
    cat >"$emu" <<'EOF'
[Settings]
AppId=2806050
UserName=test
Offline=1
Overlays=1
LobbyEnabled=1
EOF
    recipe_halo_campaign_evolved::_patch_steam_emu_ini "$emu"
    grep -qE '^Offline=1$' "$emu"
    grep -qE '^LoadDll=RUNE64.dll$' "$emu"
    grep -qE '^SelfProtect=0$' "$emu"
    grep -qE '^Overlays=0$' "$emu"
}

@test "ensure_rune_crack copies RUNE64 next to every steam_api64" {
    root="$BATS_TEST_TMPDIR/game"
    steam="$root/Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64"
    extras="$root/DigitalExtras/Engine/Binaries/ThirdParty/Steamworks/Steamv163/Win64"
    exe="$root/Meteorite/Binaries/Win64"
    mkdir -p "$steam" "$extras" "$exe"
    echo rune >"$exe/RUNE64.dll"
    echo api >"$steam/steam_api64.dll"
    echo api >"$extras/steam_api64.dll"
    printf 'Offline=1\n' >"$steam/steam_emu.ini"
    printf 'Offline=1\n' >"$extras/steam_emu.ini"
    # minimal output stubs
    output::info() { :; }
    output::success() { :; }
    recipe_halo_campaign_evolved::ensure_rune_crack "$root" "$exe"
    [ -f "$steam/RUNE64.dll" ]
    [ -f "$extras/RUNE64.dll" ]
    grep -qE '^Offline=1$' "$steam/steam_emu.ini"
    grep -qE '^LoadDll=RUNE64.dll$' "$extras/steam_emu.ini"
}

@test "ensure_offline_ini original mode: no Lumen HWRT, no OnlineSubsystem" {
    # Known-good morning session used Original-Modus only. Forcing
    # r.Lumen.HardwareRayTracing=* under vkd3d → black screen + AV after intro.
    # DefaultPlatformService=Null → silent exit. GrainQuantization=0 → banding.
    export DATA_ROOT="$BATS_TEST_TMPDIR/data"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=0
    export HALO_GFX_VRAM_6GB=0
    export HALO_GFX_VRR=0
    export HALO_GFX_LOW_LATENCY=0
    # Ultra = no auto VRAM caps (unless HALO_GFX_VRAM_6GB=1).
    export HALO_GFX_PRESET=ultra
    cfg="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    mkdir -p "$cfg"
    recipe_halo_campaign_evolved::ensure_offline_ini
    ini="$cfg/Engine.ini"
    [ -f "$ini" ]
    ! grep -qE '^r\.Lumen\.' "$ini"
    ! grep -qE '^r\.Streaming\.PoolSize=' "$ini"
    ! grep -qE '^r\.FilmGrain=' "$ini"
    ! grep -qE '^r\.OneFrameThreadLag=' "$ini"
    ! grep -qE '^r\.Tonemapper\.GrainQuantization=' "$ini"
    ! grep -qE '^\[OnlineSubsystem\]$' "$ini"
    grep -qE '^bAgreeToCrashUpload=0$' "$ini"
}

@test "ensure_offline_ini repairs sg.ResolutionQuality=0 (CRLF)" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_rq"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=0 HALO_GFX_VRAM_6GB=0 HALO_GFX_VRR=0 HALO_GFX_LOW_LATENCY=0
    export HALO_GFX_PRESET=ultra
    cfg="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    mkdir -p "$cfg"
    printf '%s\r\n' '[ScalabilityGroups]' 'sg.ResolutionQuality=0' 'sg.ShadowQuality=3' \
        >"$cfg/GameUserSettings.ini"
    recipe_halo_campaign_evolved::ensure_offline_ini
    grep -qE '^sg\.ResolutionQuality=100' "$cfg/GameUserSettings.ini"
}

@test "ensure_dxvk_cache_sane removes empty state cache" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_dxvk"
    export WINEPREFIX="$DATA_ROOT/prefix"
    d="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/dxvk"
    mkdir -p "$d"
    : >"$d/dead.dxvk.bin"
    : >"$d/dead.dxvk.lut"
    printf 'x' >"$d/ok.dxvk.bin"
    recipe_halo_campaign_evolved::ensure_dxvk_cache_sane
    [ ! -f "$d/dead.dxvk.bin" ]
    [ -f "$d/ok.dxvk.bin" ]
}

@test "find_trainer_exe prefers Trainer/Plus names under trainer/" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data"
    mkdir -p "$DATA_ROOT/trainer"
    printf 'MZ' >"$DATA_ROOT/trainer/other.exe"
    printf 'MZ' >"$DATA_ROOT/trainer/Halo Campaign Evolved v1.0 Plus 16 Trainer.exe"
    run recipe_halo_campaign_evolved::find_trainer_exe
    [ "$status" -eq 0 ]
    [[ "$output" == *Plus*Trainer.exe ]]
}

@test "ensure_game_visible_at_data_root creates HaloCampaignEvolved symlink" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data"
    game="$DATA_ROOT/prefix/drive_c/Games/HaloCampaignEvolved"
    mkdir -p "$game/Meteorite/Binaries/Win64"
    output::info() { :; }
    output::success() { :; }
    output::warning() { :; }
    recipe_halo_campaign_evolved::ensure_game_visible_at_data_root "$game"
    [ -L "$DATA_ROOT/HaloCampaignEvolved" ]
    [ "$(readlink -f "$DATA_ROOT/HaloCampaignEvolved")" = "$(readlink -f "$game")" ]
}

@test "ensure_offline_ini VRAM preset is opt-in" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data2"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=0
    export HALO_GFX_VRAM_6GB=1
    export HALO_GFX_PRESET=ultra
    mkdir -p "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    recipe_halo_campaign_evolved::ensure_offline_ini
    ini="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/Engine.ini"
    grep -qE '^r\.Streaming\.PoolSize=2048$' "$ini"
    ! grep -qE '^r\.FilmGrain=' "$ini"
}

@test "ensure_offline_ini balanced preset applies soft VRAM caps" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_bal"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=0
    export HALO_GFX_VRAM_6GB=0
    export HALO_GFX_VRR=0
    export HALO_GFX_LOW_LATENCY=0
    export HALO_GFX_PRESET=balanced
    mkdir -p "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    recipe_halo_campaign_evolved::ensure_offline_ini
    ini="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/Engine.ini"
    grep -qE '^r\.Streaming\.PoolSize=2048$' "$ini"
    grep -qE '^r\.ScreenPercentage=100$' "$ini"
}

@test "ensure_offline_ini ultra_low uses ScreenPercentage 85" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_ul"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=0 HALO_GFX_VRAM_6GB=0 HALO_GFX_VRR=0 HALO_GFX_LOW_LATENCY=0
    export HALO_GFX_PRESET=ultra_low
    mkdir -p "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    recipe_halo_campaign_evolved::ensure_offline_ini
    grep -qE '^r\.ScreenPercentage=85$' \
        "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/Engine.ini"
}

@test "prepare-ghidra.sh copies vanilla exe path" {
    run bash "$PROJECT_ROOT/recipes/halo-campaign-evolved/assets/prepare-ghidra.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *Usage* ]]
}

@test "vanilla_exe_path prefers pre_xsapi_patch backup" {
    run bash -c "
source '$PROJECT_ROOT/core/recipe-hooks.sh'
source '$PROJECT_ROOT/core/recipe-halo-campaign-evolved.sh'
tmpdir=\$(mktemp -d)
exe=\"\$tmpdir/HaloCampaignEvolved.exe\"
bak=\"\$exe.pre_xsapi_patch\"
printf 'MZ' >\"\$exe\"
printf 'MZ-backup' >\"\$bak\"
out=\$(recipe_halo_campaign_evolved::vanilla_exe_path \"\$exe\")
[ \"\$out\" = \"\$bak\" ] && echo ok
rm -rf \"\$tmpdir\"
"
    [ "$status" -eq 0 ]
    [[ "$output" == *ok* ]]
}

@test "crt_version_ok gates on the 14.40 constexpr-mutex boundary" {
    # libHttpClient zero-inits std::mutex; msvcp140 < 14.40 derefs a null vptr
    run recipe_halo_campaign_evolved::crt_version_ok "14.29.30156.0"
    [ "$status" -ne 0 ]
    run recipe_halo_campaign_evolved::crt_version_ok "14.40.33810.0"
    [ "$status" -eq 0 ]
    run recipe_halo_campaign_evolved::crt_version_ok "14.50.35719.0"
    [ "$status" -eq 0 ]
    run recipe_halo_campaign_evolved::crt_version_ok ""
    [ "$status" -ne 0 ]
}

@test "ensure_real_http_client restores the original over a stub" {
    dir="$BATS_TEST_TMPDIR/Win64"
    mkdir -p "$dir"
    head -c 258320 /dev/zero >"$dir/libHttpClient.Win32.dll.orig"
    head -c 25600 /dev/zero >"$dir/libHttpClient.Win32.dll"
    output::info() { :; }
    output::success() { :; }
    output::warning() { :; }
    run recipe_halo_campaign_evolved::ensure_real_http_client "$dir"
    [ "$status" -eq 0 ]
    [ "$(stat -c%s "$dir/libHttpClient.Win32.dll")" -eq 258320 ]
}

@test "ensure_halo_video_settings clears blur; default keeps borderless" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_vid"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=1
    export HALO_GFX_EXCLUSIVE_FS=0
    cfg="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/invalid_id"
    mkdir -p "$cfg" "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    cat >"$cfg/HaloGlobalGameUserSettings.ini" <<'INI'
[HaloUserSettings]
bMotionBlur=True
bScreenShake=True
bChromaticAberration=True
bHUDParallax=True
bMouseSmoothingEnabled=True
bMouseAccelerationEnabled=True
INI
    cat >"$cfg/HaloLocalGameUserSettings.ini" <<'INI'
[HaloUserSettings]
bBorderlessFullscreen=False
bVSync=True
ResolutionSizeX=800
ResolutionSizeY=600
INI
    printf '%s\n' '[/Script/Engine.GameUserSettings]' 'FullscreenMode=2' 'ResolutionSizeY=1022' \
        >"$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/GameUserSettings.ini"
    recipe_halo_campaign_evolved::ensure_halo_video_settings
    grep -qE '^bMotionBlur=False$' "$cfg/HaloGlobalGameUserSettings.ini"
    grep -qE '^bMouseAccelerationEnabled=False$' "$cfg/HaloGlobalGameUserSettings.ini"
    grep -qE '^bMouseSmoothingEnabled=False$' "$cfg/HaloGlobalGameUserSettings.ini"
    grep -qE '^bBorderlessFullscreen=True$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^FullscreenMode=1$' "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/GameUserSettings.ini"
    grep -qE '^ResolutionSizeY=1080$' "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/GameUserSettings.ini"
}

@test "ensure_offline_ini low latency writes OneFrameThreadLag" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_ll"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=0 HALO_GFX_VRAM_6GB=0 HALO_GFX_VRR=0
    export HALO_GFX_LOW_LATENCY=1
    export HALO_GFX_PRESET=ultra
    cfg="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    mkdir -p "$cfg"
    recipe_halo_campaign_evolved::ensure_offline_ini
    grep -qE '^r\.OneFrameThreadLag=0$' "$cfg/Engine.ini"
    grep -qE '^r\.GTSyncType=1$' "$cfg/Engine.ini"
    grep -qE '^r\.FinishCurrentFrame=1$' "$cfg/Engine.ini"
    grep -qE '^bEnableMouseSmoothing=False$' "$cfg/Engine.ini"
    # Game deletes a writable Engine.ini — we lock it.
    [ ! -w "$cfg/Engine.ini" ]
}

@test "apply_host_perf sets vkd3d swapchain latency to 1" {
    export HALO_GFX_LOW_LATENCY=1
    export HALO_GFX_GAMESCOPE=0
    export WAYLAND_DISPLAY=wayland-0
    export DISPLAY=:0
    export WINEDLLOVERRIDES="d3d12=n"
    export PROTON_PATH="/home/benny/.local/share/wine-software/runtime/proton-ge/GE-Proton11-3"
    unset VKD3D_SWAPCHAIN_LATENCY_FRAMES
    recipe_halo_campaign_evolved::apply_host_perf
    [ "${VKD3D_SWAPCHAIN_LATENCY_FRAMES}" = "1" ]
}

@test "gamescope path skips winewayland and forces winex11 overrides" {
    export HALO_GFX_LOW_LATENCY=1
    export HALO_GFX_GAMESCOPE=1
    export HALO_LAUNCH_VIA_STEAM=0
    export WAYLAND_DISPLAY=wayland-0
    export DISPLAY=:0
    export WINEDLLOVERRIDES="d3d12=n"
    export PROTON_PATH="/home/benny/.local/share/wine-software/runtime/proton-ge/GE-Proton11-3"
    recipe_halo_campaign_evolved::apply_host_perf
    # winewayland must not be enabled when gamescope will nest X11
    [[ "${WINEDLLOVERRIDES}" != *"winewayland.drv=b"* ]]
    recipe_halo_campaign_evolved::prefer_winex11_for_gamescope
    [[ "${WINEDLLOVERRIDES}" == *"winewayland.drv=d"* ]]
    [[ "${WINEDLLOVERRIDES}" == *"winex11.drv=b"* ]]
}

@test "steam proton path links compat pfx to existing prefix" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/halo_data"
    export WINEPREFIX="$DATA_ROOT/prefix"
    mkdir -p "$WINEPREFIX/drive_c"
    run recipe_halo_campaign_evolved::ensure_steam_compat_data
    [ "$status" -eq 0 ]
    [ -L "$DATA_ROOT/steam-compat/pfx" ]
    [ "$(readlink -f "$DATA_ROOT/steam-compat/pfx")" = "$(readlink -f "$WINEPREFIX")" ]
}

@test "steam proton wanted skips manual winewayland" {
    export HALO_GFX_LOW_LATENCY=1
    export HALO_GFX_GAMESCOPE=0
    export HALO_LAUNCH_VIA_STEAM=1
    export WAYLAND_DISPLAY=wayland-0
    export DISPLAY=:0
    export WINEDLLOVERRIDES="d3d12=n"
    export PROTON_PATH="/home/benny/.local/share/wine-software/runtime/proton-ge/GE-Proton11-3"
    recipe_halo_campaign_evolved::apply_host_perf
    [[ "${WINEDLLOVERRIDES}" != *"winewayland.drv=b"* ]]
    [ -n "${DISPLAY:-}" ]
}

@test "apply_winewayland disables x11drv and unsets DISPLAY" {
    export WAYLAND_DISPLAY=wayland-0
    export DISPLAY=:0
    export WINEDLLOVERRIDES="d3d12=n"
    export PROTON_PATH="/home/benny/.local/share/wine-software/runtime/proton-ge/GE-Proton11-3"
    recipe_halo_campaign_evolved::apply_winewayland
    [[ "$WINEDLLOVERRIDES" == *winewayland.drv=b* ]]
    [[ "$WINEDLLOVERRIDES" == *winex11.drv=d* ]]
    [ -z "${DISPLAY:-}" ]
    [ "${WINE_DISABLE_FULLSCREEN_HACK:-}" = "1" ]
}

@test "ensure_nvapi_dlls copies nvapi64 into prefix" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_nv"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export PROTON_PATH="/home/benny/.local/share/wine-software/runtime/proton-ge/GE-Proton11-3"
    mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/windows/syswow64"
    # Skip if this machine has no GE-Proton11 tree (CI without runtime).
    if [ ! -f "$PROTON_PATH/files/lib/wine/nvapi/x86_64-windows/nvapi64.dll" ]; then
        skip "GE-Proton11-3 nvapi not present"
    fi
    recipe_halo_campaign_evolved::ensure_nvapi_dlls
    [ -f "$WINEPREFIX/drive_c/windows/system32/nvapi64.dll" ]
}

@test "ensure_halo_video_settings applies balanced preset; Reflex + FPS cap" {
    export DATA_ROOT="$BATS_TEST_TMPDIR/data_med"
    export WINEPREFIX="$DATA_ROOT/prefix"
    export HALO_GFX_CLEAR_IMAGE=1
    export HALO_GFX_EXCLUSIVE_FS=0
    export HALO_GFX_LOW_LATENCY=1
    export HALO_GFX_MAX_FPS=141
    export HALO_GFX_PRESET=balanced
    cfg="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/invalid_id"
    mkdir -p "$cfg" "$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows"
    cat >"$cfg/HaloGlobalGameUserSettings.ini" <<'INI'
[HaloUserSettings]
bMotionBlur=True
INI
    cat >"$cfg/HaloLocalGameUserSettings.ini" <<'INI'
[HaloUserSettings]
bBorderlessFullscreen=True
bVSync=True
QualityPreset=VeryLow
TextureQuality=VeryLow
UpscalingQuality=Low
LowLatencyMode=Default
MaximumFrameRate=-1
bFrameGeneration=True
INI
    printf '%s\n' '[/Script/Engine.GameUserSettings]' 'FullscreenMode=1' \
        >"$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Meteorite/Saved/Config/Windows/GameUserSettings.ini"
    recipe_halo_campaign_evolved::ensure_halo_video_settings
    grep -qE '^QualityPreset=High$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^TextureQuality=High$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^ReflectionsQuality=Medium$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^UpscalingQuality=High$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^LowLatencyMode=VendorSpecific$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^MaximumFrameRate=141$' "$cfg/HaloLocalGameUserSettings.ini"
    grep -qE '^bFrameGeneration=False$' "$cfg/HaloLocalGameUserSettings.ini"
}

@test "ensure_skip_intro heals corrupt Splash.bmp and uses valid LogoParade stub" {
    export PROJECT_ROOT
    export RECIPE_DIR="$PROJECT_ROOT/recipes/halo-campaign-evolved"
    export HALO_SKIP_INTRO=1
    root="$BATS_TEST_TMPDIR/HaloCampaignEvolved"
    movies="$root/Meteorite/Content/Movies"
    splash="$root/Meteorite/Content/Splash"
    mkdir -p "$movies" "$splash"
    # Simulate previous buggy deploy: tiny stubs + real backups
    head -c 200000 /dev/urandom >"$movies/LogoParade.mp4.rezeptor_bak"
    printf '\x00\x00\x00\x18ftypmp42' >"$movies/LogoParade.mp4"
    head -c 50000 /dev/urandom >"$splash/Splash.bmp.rezeptor_bak"
    printf 'BM\x00\x00\x00\x00' >"$splash/Splash.bmp"
    output::info() { :; }
    output::success() { :; }
    output::warning() { :; }
    recipe_halo_campaign_evolved::ensure_skip_intro "$root"
    # Splash must be restored (never left as fake BM header)
    [ "$(stat -c%s "$splash/Splash.bmp")" -eq 50000 ]
    # LogoParade must be the shipped valid stub, not the 12-byte fake
    [ "$(stat -c%s "$movies/LogoParade.mp4")" -gt 1000 ]
    [ "$(stat -c%s "$movies/LogoParade.mp4")" -lt 50000 ]
    # Real original remains backed up
    [ "$(stat -c%s "$movies/LogoParade.mp4.rezeptor_bak")" -eq 200000 ]
}
