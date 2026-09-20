#!/usr/bin/env bats
# Prototype 1.5.0 overlay: no ReShade, no Wings Lua. Sprint + DE default + Standard skin.

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ASI_C="$ROOT/recipes/prototype/assets/mod-bundle/tools/force_desktop_res.c"
    HELP="$ROOT/recipes/prototype/helpers.sh"
    BUNDLE="$ROOT/recipes/prototype/assets/mod-bundle"
    export RECIPE_DIR="$ROOT/recipes/prototype"
}

_critical_stub() {
    local tmp="$1"
    printf '%s\n' 'id: prototype-mod-bundle' 'version: 1.5.0' 'skin: standard' 'language: standard' \
        >"$tmp/rezeptor-mod-bundle.yml"
    : >"$tmp/prototype_fix.asi"
    : >"$tmp/force_desktop_res.asi"
    : >"$tmp/binkw32Hooked.dll"
    mkdir -p "$tmp/art/hud" "$tmp/art/alex" "$tmp/rezeptor-trainer"
    : >"$tmp/art/hud/protolegalscreen.gfx"
    : >"$tmp/art/startup_fig.p3d"
    : >"$tmp/art/alex/alex_fig.p3d.rz"
    : >"$tmp/rezeptor-trainer/prototype.v1001.p7trn.exe"
    printf '%s\n' 'BorderlessWindow = true' >"$tmp/prototype_fix.ini"
}

@test "force_desktop_res pins Reset/Windowed and does not load ReShade" {
    grep -q 'Windowed = TRUE' "$ASI_C"
    grep -q 'no reshade' "$ASI_C"
    grep -q 'IAT Direct3DCreate9 pinned' "$ASI_C"
    ! grep -q 'LoadLibraryA(RESHADE_DLL)' "$ASI_C"
    ! grep -q 'ReShade32.dll' "$ASI_C"
    ! grep -q 'VK_RELOAD' "$ASI_C"
    ! grep -q 'OVERLAY_TIMEOUT_MS' "$ASI_C"
    ! grep -q 'reshade queue reload' "$ASI_C"
    ! grep -q 'reshade overlay auto-closed' "$ASI_C"
    ! grep -q 'd3d9 wrap' <<<"$(grep -E 'LoadLibraryA\(\"d3d9' "$ASI_C" || true)"
}

@test "apply_mod_bundle sweeps leftover ReShade wrap DLLs" {
    grep -q 'prototype::strip_game_leftovers' "$HELP"
    grep -q '"\$game/ReShade32.dll"' "$HELP"
    grep -q '"\$game/d3d9.dll"' "$HELP"
    grep -q '"\$game/dxgi.dll"' "$HELP"
    ! grep -q 'prototype::strip_reshade_runtime' "$HELP"
    ! grep -q 'prototype::pin_reshade_preset' "$HELP"
    ! grep -q 'prototype::reborn_preset_ok' "$HELP"
    ! grep -q 'prototype::d3dcompiler_native' "$HELP"
}

@test "remote.yml lists deu-patch sha256 and has no MEGA file-manager URL" {
    remote="$BUNDLE/remote.yml"
    [ -f "$remote" ]
    grep -q 'id: deu-patch' "$remote"
    grep -q 'sha256:  fbbd62485f2b9a2ddf910f16b1456237a6b86b560786265932b2655328fbd642' "$remote"
    ! grep -E '^[[:space:]]*url:[[:space:]]*.*/fm/' "$remote"
}

@test "overlay does not ship ReShade, Wings Lua, or TexMod injector" {
    ! [ -e "$BUNDLE/overlay/ReShade32.dll" ]
    ! [ -e "$BUNDLE/overlay/ReShade.ini" ]
    ! [ -e "$BUNDLE/overlay/init.lua" ]
    ! [ -e "$BUNDLE/overlay/wings.lua" ]
    ! [ -e "$BUNDLE/overlay/enable_dlc.rcf" ]
    ! [ -e "$BUNDLE/overlay/art/packages/missions/wings/wings.p3d" ]
    ! [ -e "$BUNDLE/overlay/Texmod.exe" ]
    ! [ -d "$BUNDLE/overlay/reshade-shaders" ]
    ! grep -q 'reshade-official' "$BUNDLE/bundle.yml"
    ! grep -q 'smokys-wings' "$BUNDLE/bundle.yml"
}

@test "bundle 1.5.0 and helper syntax" {
    grep -q 'version: "1.5.0"' "$BUNDLE/bundle.yml"
    bash -n "$HELP"
    bash -n "$ROOT/recipes/prototype/launch.sh"
    bash -n "$ROOT/recipes/prototype/kill.sh"
    bash -n "$ROOT/recipes/prototype/repair.sh"
    bash -n "$ROOT/recipes/prototype/validate.sh"
    bash -n "$ROOT/recipes/prototype/install.sh"
}

@test "bundle_critical_ok requires 1.5.0 defaults and rejects leftover ReShade32" {
    tmp="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$HELP"
    export PROTOTYPE_PARKOUR=0 PROTOTYPE_LANGUAGE=standard PROTOTYPE_PS3_BUTTONS=0 \
        PROTOTYPE_SAVE_100=0 PROTOTYPE_SKIN=standard
    _critical_stub "$tmp"
    prototype::bundle_critical_ok "$tmp"
    : >"$tmp/ReShade32.dll"
    ! prototype::bundle_critical_ok "$tmp"
    rm -f "$tmp/ReShade32.dll"
    : >"$tmp/d3d9.dll"
    ! prototype::bundle_critical_ok "$tmp"
    rm -f "$tmp/d3d9.dll"
    : >"$tmp/init.lua"
    ! prototype::bundle_critical_ok "$tmp"
    rm -f "$tmp/init.lua"
    : >"$tmp/enable_dlc.rcf"
    ! prototype::bundle_critical_ok "$tmp"
    rm -f "$tmp/enable_dlc.rcf"
    : >"$tmp/ResChanger.exe"
    ! prototype::bundle_critical_ok "$tmp"
    rm -rf "$tmp"
}

@test "strip_game_leftovers removes hook leftovers not prefix DXVK" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/art/packages/missions/wings" "$tmp/reshade-shaders"
    : >"$tmp/ReShade32.dll"
    : >"$tmp/d3d9.dll"
    : >"$tmp/dxgi.dll"
    : >"$tmp/ReShade.ini"
    : >"$tmp/init.lua"
    : >"$tmp/wings.lua"
    : >"$tmp/enable_dlc.rcf"
    : >"$tmp/art/packages/missions/wings/wings.p3d"
    : >"$tmp/Texmod.exe"
    : >"$tmp/prototype_fix.asi"
    # shellcheck source=/dev/null
    source "$HELP"
    prototype::strip_game_leftovers "$tmp"
    [ ! -e "$tmp/ReShade32.dll" ]
    [ ! -e "$tmp/d3d9.dll" ]
    [ ! -e "$tmp/dxgi.dll" ]
    [ ! -e "$tmp/ReShade.ini" ]
    [ ! -e "$tmp/init.lua" ]
    [ ! -e "$tmp/wings.lua" ]
    [ ! -e "$tmp/enable_dlc.rcf" ]
    [ ! -e "$tmp/art/packages/missions/wings" ]
    [ ! -e "$tmp/Texmod.exe" ]
    [ -f "$tmp/prototype_fix.asi" ]
    rm -rf "$tmp"
}

@test "launch does not auto-inject the Locke trainer" {
    ! grep -q 'p7trn' "$ROOT/recipes/prototype/launch.sh"
    ! grep -q 'spawn_trainer' "$ROOT/recipes/prototype/launch.sh"
    grep -q 'exec wine' "$ROOT/recipes/prototype/launch.sh"
    [ -f "$BUNDLE/tools/trainer/prototype.v1001.p7trn.exe" ]
}

@test "ResChanger stays in tools and is not in the overlay" {
    [ -f "$BUNDLE/tools/reschanger/ResChanger.exe" ]
    ! [ -e "$BUNDLE/overlay/ResChanger.exe" ]
    grep -q 'force_desktop_res' "$BUNDLE/bundle.yml"
}

@test "sprint fix and skin packs ship; default skin is standard" {
    [ -f "$BUNDLE/overlay/art/alex/alex_fig.p3d.rz" ]
    [ -f "$BUNDLE/overlay/art/startup_fig.p3d.rz" ]
    [ -f "$BUNDLE/packs/skin-venom/art/packages/powers/alex_armour/alex_armour.p3d.rz" ]
    [ -f "$BUNDLE/packs/skin-antivenom/art/packages/powers/alex_armour/alex_armour.p3d.rz" ]
    # shellcheck source=/dev/null
    source "$HELP"
    unset PROTOTYPE_SKIN || true
    [ "$(prototype::skin_id)" = standard ]
    PROTOTYPE_SKIN=venom
    [ "$(prototype::skin_id)" = venom ]
    PROTOTYPE_SKIN=antivenom
    [ "$(prototype::skin_id)" = antivenom ]
    PROTOTYPE_SKIN=off
    [ "$(prototype::skin_id)" = standard ]
    PROTOTYPE_SKIN=vanilla
    [ "$(prototype::skin_id)" = standard ]
}

@test "language default is de with FE 68; standard strips to ENU/69" {
    # shellcheck source=/dev/null
    source "$HELP"
    unset PROTOTYPE_LANGUAGE || true
    [ "$(prototype::language_id)" = de ]
    [ "$(prototype::lang_fe)" = 68 ]
    [ "$(prototype::lang_code)" = DEU ]
    PROTOTYPE_LANGUAGE=en
    [ "$(prototype::language_id)" = standard ]
    [ "$(prototype::lang_fe)" = 69 ]
    [ "$(prototype::lang_code)" = ENU ]
    PROTOTYPE_LANGUAGE=standard
    [ "$(prototype::language_id)" = standard ]
    [ "$(prototype::lang_fe)" = 69 ]
}

@test "skin apply is mutually exclusive on the powers slot" {
    tmp="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$HELP"
    mkdir -p "$tmp/art/packages/powers/alex_armour"
    PROTOTYPE_SKIN=venom
    prototype::apply_skin "$tmp"
    [ -f "$tmp/art/packages/powers/alex_armour/alex_armour.p3d.rz" ]
    venom_sum="$(cksum "$tmp/art/packages/powers/alex_armour/alex_armour.p3d.rz" | awk '{print $1}')"
    PROTOTYPE_SKIN=antivenom
    prototype::apply_skin "$tmp"
    anti_sum="$(cksum "$tmp/art/packages/powers/alex_armour/alex_armour.p3d.rz" | awk '{print $1}')"
    [ "$venom_sum" != "$anti_sum" ]
    PROTOTYPE_SKIN=standard
    prototype::apply_skin "$tmp"
    [ ! -e "$tmp/art/packages/powers/alex_armour/alex_armour.p3d.rz" ]
    unset PROTOTYPE_SKIN || true
    prototype::apply_skin "$tmp"
    [ ! -e "$tmp/art/packages/powers/alex_armour/alex_armour.p3d.rz" ]
    rm -rf "$tmp"
}

@test "standard language restores packed NIS from backup" {
    tmp="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$HELP"
    mkdir -p "$tmp/art/nis"
    printf 'vanilla-nis\n' >"$tmp/art/nis/cut.rz"
    prototype::stash_packed_nis "$tmp" "$tmp/rezeptor-deu-files.list"
    [ ! -e "$tmp/art/nis/cut.rz" ]
    [ -f "$tmp/art/nis/cut.rz.rezeptor_bak" ]
    PROTOTYPE_LANGUAGE=standard
    prototype::remove_deu_overlay "$tmp"
    [ -f "$tmp/art/nis/cut.rz" ]
    grep -q vanilla-nis "$tmp/art/nis/cut.rz"
    rm -rf "$tmp"
}

@test "recipe.yml medicine choices default to bundle+de+standard skin" {
    grep -q 'env: PROTOTYPE_LANGUAGE' "$ROOT/recipes/prototype/recipe.yml"
    grep -q 'env: PROTOTYPE_SKIN' "$ROOT/recipes/prototype/recipe.yml"
    grep -q 'default: de' "$ROOT/recipes/prototype/recipe.yml"
    grep -A6 'env: PROTOTYPE_SKIN' "$ROOT/recipes/prototype/recipe.yml" | grep -q 'default: standard'
    ! grep -q 'Venom (Default)' "$ROOT/recipes/prototype/recipe.yml"
    ! grep -q 'Englisch (kein Patch' "$ROOT/recipes/prototype/recipe.yml"
    ! grep -q 'd3dcompiler_47' "$ROOT/recipes/prototype/recipe.yml"
}

@test "deu protostart.gfx replace is same-length and rewrites a short leftover" {
    grep -q 'len(blob) != len(orig)' "$HELP"
    ! grep -q 'DRUECKEN SIE ENTER   \\x00' "$HELP"
    tmp="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$HELP"
    mkdir -p "$tmp/art/hud"
    printf 'french-bible\n' >"$tmp/art/hud/textbible_french.p3d"
    printf 'x\x08french\x00y' >"$tmp/art/hud/fe_textbible.p3d"
    python3 - "$tmp/art.rcf" "$tmp/art/hud/protostart.gfx" <<'PY'
from pathlib import Path
import sys
key = b"$PRESS_BUTTON_TO_START\x00"
chunk = b"GFX\x08" + b"\x00" * 64 + b"protostart\x00" + key + b"Initialize01\x00"
chunk += b"\x00" * 32
nxt = b"GFX\x08" + b"next"
Path(sys.argv[1]).write_bytes(b"RCF\x00" + chunk + nxt)
# Simulate the old 1-byte-short overlay the title loader refused to paint.
short = chunk.replace(key, b"DRUECKEN SIE ENTER   \x00", 1)
assert len(short) == len(chunk) - 1
Path(sys.argv[2]).write_bytes(short)
PY
    short_len="$(wc -c <"$tmp/art/hud/protostart.gfx")"
    ! prototype::deu_frontend_ok "$tmp"
    prototype::apply_deu_frontend_german "$tmp"
    live_len="$(wc -c <"$tmp/art/hud/protostart.gfx")"
    [ "$live_len" -eq $((short_len + 1)) ]
    grep -aFq "DRUECKEN SIE ENTER" "$tmp/art/hud/protostart.gfx"
    grep -aFq $'\x08german\x00' "$tmp/art/hud/fe_textbible.p3d"
    ! grep -aFq $'$PRESS_BUTTON_TO_START\x00' "$tmp/art/hud/protostart.gfx"
    prototype::deu_frontend_ok "$tmp"
    rm -rf "$tmp"
}
