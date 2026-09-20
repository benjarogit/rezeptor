#!/usr/bin/env bash
# Prototype helpers — sourced from install/launch/repair/validate (not a hook).

# Activision FE_Language is the ASCII code of the language initial:
# E=69 ENU, F=70 FRA, I=73 ITA, S=83 ESP, D=68 DEU. LCID 1031 = de-DE.
# Bollwurf ships German strings in the French textbible files (no german
# slot in art.rcf). Repair copies those to textbible_german.p3d, renames
# the fe_textbible language id french→german, overlays protostart.gfx
# (PRESS ENTER, same-length GFX replace), and sets FE_Language=68 so
# frontend chrome is DEU. A shorter replace blacks the title movie.
# Audio stays under audio\english\ (the patch replaces those loose files).
# FE=70 left APPUYEZ SUR ENTRÉE on the title (French chrome). No LANG/LC_ALL.
# Medizin PROTOTYPE_LANGUAGE=standard (aliases: en, vanilla) skips the
# overlay and uses ENU/69 (NA-SKU). Default remains de (Bollwurf patch).

# Dump art.rcf has textbible_{english,french,italian,spanish} only.
# No german/russian/dutch packs. Audio is english-only. DE needs the patch.
prototype::language_id() {
    case "${PROTOTYPE_LANGUAGE:-de}" in
        standard|vanilla|off|en|EN|enu|ENU|english|English) echo standard ;;
        fr|FR|fra|FRA|french|French) echo fr ;;
        it|IT|ita|ITA|italian|Italian) echo it ;;
        es|ES|esp|ESP|spanish|Spanish) echo es ;;
        *) echo de ;;
    esac
}

# Default standard = vanilla dump (no AzimCrew). venom/antivenom share one slot.
prototype::skin_id() {
    case "${PROTOTYPE_SKIN:-standard}" in
        venom|Venom) echo venom ;;
        antivenom|anti-venom|anti_venom|Anti-Venom) echo antivenom ;;
        *) echo standard ;;
    esac
}

# Parkour default on (Medizin). Loose startup_fig.p3d only — no Lua/ASI.
prototype::parkour_on() {
    case "${PROTOTYPE_PARKOUR:-1}" in
        0|false|no|off|FALSE|NO|OFF) return 1 ;;
        *) return 0 ;;
    esac
}

# PS3 HUD buttons default off.
prototype::ps3_buttons_on() {
    case "${PROTOTYPE_PS3_BUTTONS:-0}" in
        1|true|yes|on|TRUE|YES|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# 100% save default off. Never auto-restore on disable.
prototype::save_100_on() {
    case "${PROTOTYPE_SAVE_100:-0}" in
        1|true|yes|on|TRUE|YES|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# LanguageCode / LCID / FE_Language (ASCII of the initial).
# de: DEU / 1031 / 68 after remapping Bollwurf files into the german slot.
# standard: ENU / 1033 / 69 (dump english). fr/it/es: dump packs, no DE overlay.
prototype::lang_code() {
    case "$(prototype::language_id)" in
        standard) echo ENU ;;
        fr) echo FRA ;;
        it) echo ITA ;;
        es) echo ESP ;;
        *) echo DEU ;;
    esac
}

prototype::lang_lcid() {
    case "$(prototype::language_id)" in
        standard) echo 1033 ;;
        fr) echo 1036 ;;
        it) echo 1040 ;;
        es) echo 1034 ;;
        *) echo 1031 ;;
    esac
}

prototype::lang_fe() {
    case "$(prototype::language_id)" in
        standard) echo 69 ;;
        fr) echo 70 ;;
        it) echo 73 ;;
        es) echo 83 ;;
        *) echo 68 ;;
    esac
}

# Prefer the real game tree over Crack Backup/Steamless/prototypef.exe.
prototype::game_dir() {
    local root="${1:-}"
    [ -n "$root" ] && [ -d "$root" ] || return 1
    if [ -f "$root/prototypef.exe" ] && [ -f "$root/prototypeenginef.dll" ]; then
        echo "$root"
        return 0
    fi
    if [ -f "$root/Prototype/prototypef.exe" ] && [ -f "$root/Prototype/prototypeenginef.dll" ]; then
        echo "$root/Prototype"
        return 0
    fi
    local hit
    hit="$(find "$root" -type f -name 'prototypef.exe' ! -path '*/Crack Backup/*' 2>/dev/null | head -1)"
    [ -n "$hit" ] && [ -f "$hit" ] || return 1
    echo "$(cd "$(dirname "$hit")" && pwd)"
}

prototype::find_exe() {
    local dir
    dir="$(prototype::game_dir "${1:-}")" || return 1
    [ -f "$dir/prototypef.exe" ] || return 1
    echo "$dir/prototypef.exe"
}

# deploy_proton_graphics_dlls copies DXVK d3d11/dxgi, not d3d9. This game is DX9.
prototype::deploy_d3d9() {
    wine_runtime::init || return 1
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local root="${_WINE_RUNTIME_ROOT:-}"
    local src="$root/files/lib/wine/dxvk/i386-windows/d3d9.dll"
    local dest="$prefix/drive_c/windows/syswow64/d3d9.dll"
    [ -n "$prefix" ] && [ -d "$prefix/drive_c/windows/syswow64" ] || return 1
    [ -f "$src" ] || return 1
    cp -f "$src" "$dest"
}

prototype::apply_registry() {
    local game_dir="${1:-}"
    local win_dir=""
    [ -n "$game_dir" ] && [ -d "$game_dir" ] || return 0
    wine_runtime::init || return 1
    if type wine_runtime::winepath >/dev/null 2>&1; then
        win_dir="$(wine_runtime::winepath -w "$game_dir" 2>/dev/null || true)"
    fi
    [ -n "$win_dir" ] || win_dir="Z:${game_dir//\//\\}"
    local key path
    for key in \
        "HKLM\\Software\\Activision\\Prototype" \
        "HKLM\\Software\\Wow6432Node\\Activision\\Prototype" \
        "HKLM\\Software\\Wow6432Node\\Activision\\prototype"
    do
        wine_runtime::wine reg add "$key" /v Path /t REG_SZ /d "$win_dir" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        wine_runtime::wine reg add "$key" /v InstallExePath /t REG_SZ /d "$win_dir" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        wine_runtime::wine reg add "$key" /v EXEString /t REG_SZ /d "${win_dir}\\prototypef.exe" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        wine_runtime::wine reg add "$key" /v Version /t REG_SZ /d "1.000000" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        wine_runtime::wine reg add "$key" /v LanguageCode /t REG_SZ /d "$(prototype::lang_code)" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        wine_runtime::wine reg add "$key" /v LCID /t REG_SZ /d "$(prototype::lang_lcid)" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
        wine_runtime::wine reg add "$key" /v FE_Language /t REG_SZ /d "$(prototype::lang_fe)" /f \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    done
    path="$game_dir"
    recipe_hooks::state_set GAME_DIR "$path" || true
}

# 32-bit EXE is not LARGE_ADDRESS_AWARE (PE Characteristics 0x103). Set 0x20.
# deploy_mode=link writes the live prototypef.exe (source tree).
prototype::ensure_laa() {
    local exe="${1:-}"
    [ -n "$exe" ] && [ -f "$exe" ] && [ -w "$exe" ] || return 0
    python3 - "$exe" <<'PY' || true
import struct, sys
path = sys.argv[1]
with open(path, "r+b") as f:
    hdr = f.read(64)
    if len(hdr) < 64 or hdr[:2] != b"MZ":
        sys.exit(0)
    e_lfanew = struct.unpack_from("<I", hdr, 0x3C)[0]
    f.seek(e_lfanew)
    if f.read(4) != b"PE\0\0":
        sys.exit(0)
    f.seek(e_lfanew + 22)
    raw = f.read(2)
    if len(raw) != 2:
        sys.exit(0)
    chars = struct.unpack("<H", raw)[0]
    if chars & 0x20:
        sys.exit(0)
    f.seek(e_lfanew + 22)
    f.write(struct.pack("<H", chars | 0x20))
PY
}

prototype::laa_set() {
    local exe="${1:-}"
    [ -n "$exe" ] && [ -f "$exe" ] || return 1
    python3 - "$exe" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, "rb") as f:
    hdr = f.read(64)
    if len(hdr) < 64 or hdr[:2] != b"MZ":
        sys.exit(1)
    e_lfanew = struct.unpack_from("<I", hdr, 0x3C)[0]
    f.seek(e_lfanew + 22)
    raw = f.read(2)
    if len(raw) != 2:
        sys.exit(1)
    chars = struct.unpack("<H", raw)[0]
sys.exit(0 if chars & 0x20 else 1)
PY
}

prototype::pulse32_ok() {
    [ -e /usr/lib32/libpulse.so.0 ] || [ -e /usr/lib/i386-linux-gnu/libpulse.so.0 ]
}

# pci class 0300: 10de NVIDIA, 1002 AMD, 8086 Intel.
prototype::gpu_vendor() {
    local ids
    ids="$(lspci -n 2>/dev/null | awk '/ 0300: / { print tolower($3) }')"
    case "$ids" in
        *10de:*) echo nvidia ;;
        *1002:*) echo amd ;;
        *8086:*) echo intel ;;
        *) echo unknown ;;
    esac
}

prototype::primary_refresh_hz() {
    local line hz
    if command -v xrandr >/dev/null 2>&1; then
        line="$(xrandr --current 2>/dev/null | awk '/\*/ { print; exit }' || true)"
        hz="$(printf '%s' "$line" | grep -oE '[0-9]+(\.[0-9]+)?\*' | head -1 | tr -d '*' || true)"
        if [ -n "$hz" ]; then
            hz="$(awk -v v="$hz" 'BEGIN { printf "%.0f", v }')"
        fi
        if [ -n "$hz" ] && [ "$hz" -ge 30 ] && [ "$hz" -le 360 ] 2>/dev/null; then
            echo "$hz"
            return 0
        fi
    fi
    return 1
}

# 32-bit prototypef.exe: default DXVK 8 compiler threads and 5 swap images
# exhausted host VA after the 1280x800 frontend reset
# (VK_ERROR_OUT_OF_HOST_MEMORY + SURFACE_LOST). Prefix-scoped only.
prototype::write_dxvk_conf() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local conf
    [ -n "$prefix" ] && [ -d "$prefix" ] || return 1
    conf="$prefix/dxvk.conf"
    cat >"$conf" <<'EOF'
dxvk.numCompilerThreads = 2
d3d9.numBackBuffers = 2
d3d9.maxFrameLatency = 1
d3d9.deferSurfaceCreation = True
EOF
    export DXVK_CONFIG_FILE="${DXVK_CONFIG_FILE:-$conf}"
}

# Keep the last game-dir log so a hang still has evidence after Repair/Start.
prototype::rotate_game_log() {
    local f="${1:-}"
    [ -n "$f" ] && [ -f "$f" ] || return 0
    mv -f "$f" "${f}.prev" || true
}

# Prefix-only leftover stop. Exclusive FS / no HWND can hang WM_CLOSE
# (GNOME then shows steam_app_10150). Never a machine-wide pkill.
prototype::kill_prefix_leftovers() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local pid envf cmd in_prefix
    [ -n "$prefix" ] && [ -d "$prefix" ] || return 0
    for pid in /proc/[0-9]*; do
        pid="${pid#/proc/}"
        [ "$pid" = "$$" ] && continue
        [ "$pid" = "$PPID" ] && continue
        cmd="$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)"
        case "$cmd" in
            *prototypef.exe*|*p7trn.exe*|*ResChanger.exe*|*wineserver*|*'/wine '*|*'/wine64 '*|*start.exe*|*explorer.exe*)
                ;;
            *) continue ;;
        esac
        envf="/proc/${pid}/environ"
        in_prefix=0
        if { tr '\0' '\n' <"$envf" | grep -Fxq "WINEPREFIX=${prefix}"; } 2>/dev/null; then
            in_prefix=1
        fi
        [ "$in_prefix" -eq 1 ] || continue
        kill -9 "$pid" 2>/dev/null || true
    done
    return 0
}

# Host extras the recipe can set. No Mangohud, no Cachy Proton, no sysctl.
# NVIDIA / AMD / Intel after lspci. FPS cap = primary refresh when readable.
# esync/fsync stay Proton-11 default (do not set PROTON_NO_ESYNC).
prototype::apply_system_opt() {
    local vendor hz prefix cache
    vendor="$(prototype::gpu_vendor)"
    prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    case "$vendor" in
        nvidia)
            export DXVK_FILTER_DEVICE_NAME="${DXVK_FILTER_DEVICE_NAME:-NVIDIA}"
            if [ -n "$prefix" ]; then
                cache="$prefix/cache/dxvk"
                mkdir -p "$cache"
                export DXVK_STATE_CACHE_PATH="${DXVK_STATE_CACHE_PATH:-$cache}"
                export __GL_SHADER_DISK_CACHE="${__GL_SHADER_DISK_CACHE:-1}"
                export __GL_SHADER_DISK_CACHE_PATH="${__GL_SHADER_DISK_CACHE_PATH:-$cache}"
            fi
            ;;
        amd)
            export DXVK_FILTER_DEVICE_NAME="${DXVK_FILTER_DEVICE_NAME:-AMD}"
            ;;
        intel)
            export DXVK_FILTER_DEVICE_NAME="${DXVK_FILTER_DEVICE_NAME:-Intel}"
            ;;
    esac
    if [ -z "${DXVK_FRAME_RATE:-}" ]; then
        hz="$(prototype::primary_refresh_hz || true)"
        [ -n "$hz" ] && export DXVK_FRAME_RATE="$hz"
    fi
}

# --- Mod-Bundle (one Medizin toggle, one flat overlay) ---

_PROTOTYPE_BUNDLE_MARKER="rezeptor-mod-bundle.yml"

prototype::bundle_root() {
    echo "${RECIPE_DIR:-}/assets/mod-bundle"
}

prototype::_load_recipe_assets() {
    local f
    f="${CORE_DIR:-${PROJECT_ROOT:-}}/recipe-assets.sh"
    [ -f "$f" ] || f="${PROJECT_ROOT:-}/core/recipe-assets.sh"
    [ -f "$f" ] || return 1
    # shellcheck source=/dev/null
    source "$f"
}

# Fetch one pack from assets/mod-bundle/remote.yml when a public URL is set.
prototype::fetch_remote_pack() {
    local want="${1:-}" dest="${2:-}" meta file url sha
    local yml
    yml="$(prototype::bundle_root)/remote.yml"
    [ -f "$yml" ] || return 1
    prototype::_load_recipe_assets || return 1
    meta="$(python3 - "$yml" "$want" <<'PY'
from pathlib import Path
import sys
want = sys.argv[2]
cur = None
hit = None
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    s = line.strip()
    if s.startswith("- id:"):
        if cur and cur.get("id") == want:
            hit = cur
        cur = {"id": s.split(":", 1)[1].strip().strip('"')}
        continue
    if cur and ":" in s and not s.startswith("- "):
        key, val = s.split(":", 1)
        cur[key.strip()] = val.strip().strip('"')
if cur and cur.get("id") == want:
    hit = cur
if not hit:
    raise SystemExit(1)
print(hit.get("file", ""))
print(hit.get("sha256", ""))
print(hit.get("url", ""))
PY
)" || return 1
    file="$(printf '%s\n' "$meta" | sed -n '1p')"
    sha="$(printf '%s\n' "$meta" | sed -n '2p')"
    url="$(printf '%s\n' "$meta" | sed -n '3p')"
    [ -n "$dest" ] || dest="$(prototype::bundle_cache)/${file}"
    [ -n "$file" ] || return 1
    if [ -z "$url" ] || ! recipe_assets::is_public_share_url "$url"; then
        return 1
    fi
    recipe_assets::ensure "$dest" "$url" "$sha"
}

prototype::bundle_overlay() {
    echo "$(prototype::bundle_root)/overlay"
}

prototype::bundle_version() {
    local yml
    yml="$(prototype::bundle_root)/bundle.yml"
    [ -f "$yml" ] || { echo "1.0.0"; return 0; }
    awk '/^version:/ { gsub(/["'\'']/, "", $2); print $2; exit }' "$yml"
}

prototype::bundle_cache() {
    if type wine_software_base >/dev/null 2>&1; then
        echo "$(wine_software_base)/cache/prototype-mod-bundle"
    else
        echo "${HOME}/.local/share/wine-software/cache/prototype-mod-bundle"
    fi
}

# Default on when options.env has no key (Medizin default: true).
prototype::mod_bundle_on() {
    case "${PROTOTYPE_MOD_BUNDLE:-1}" in
        0|false|no|off|FALSE|NO|OFF) return 1 ;;
        *) return 0 ;;
    esac
}

_PROTOTYPE_DEU_LIST="rezeptor-deu-files.list"
_PROTOTYPE_DEU_STAMP=".rezeptor-deu-stamp"

prototype::deu_cache() {
    echo "$(prototype::bundle_cache)/deu-overlay"
}

prototype::deu_zip_path() {
    local z
    for z in \
        "${HOME}/Downloads/Prototype_DeuPatchBEP.zip" \
        "$(prototype::bundle_cache)/Prototype_DeuPatchBEP.zip"
    do
        [ -f "$z" ] && echo "$z" && return 0
    done
    return 1
}

prototype::deu_overlay_ready() {
    local ov
    ov="$(prototype::deu_cache)"
    [ -f "$ov/$_PROTOTYPE_DEU_STAMP" ] || return 1
    [ -f "$ov/art/hud/fe_textbible.p3d" ] || return 1
    [ -f "$ov/art/hud/textbible_french.p3d" ] || return 1
}

# Merge a patch tree into the cache overlay. Paths lowercased (Linux game dir).
prototype::deu_merge_tree() {
    local src="${1:-}" dest
    dest="$(prototype::deu_cache)"
    [ -n "$src" ] && [ -d "$src" ] || return 0
    python3 - "$src" "$dest" <<'PY'
import shutil, sys
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
skip_suffix = {".bat", ".exe", ".dll", ".reg"}
skip_name = {"setup.bat", "setup.exe", "rcf.exe", "deltree.exe", "erase.exe"}
dest.mkdir(parents=True, exist_ok=True)
for p in src.rglob("*"):
    if not p.is_file():
        continue
    name = p.name.lower()
    if name in skip_name or p.suffix.lower() in skip_suffix:
        continue
    rel = str(p.relative_to(src)).replace("\\", "/").lower()
    out = dest / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, out)
PY
}

# v1.0→v1.3 newest-wins. ~1.2GB loose p3d — cache only, never git (Allagga rule).
prototype::seed_deu_overlay() {
    prototype::deu_overlay_ready && return 0
    local zip work ov v1 v11 v12 v13
    if ! zip="$(prototype::deu_zip_path)"; then
        mkdir -p "$(prototype::bundle_cache)"
        prototype::fetch_remote_pack deu-patch \
            "$(prototype::bundle_cache)/Prototype_DeuPatchBEP.zip" || true
        zip="$(prototype::deu_zip_path)" || return 1
    fi
    ov="$(prototype::deu_cache)"
    work="$(prototype::bundle_cache)/deu-work"
    mkdir -p "$(prototype::bundle_cache)"
    if [ "$zip" != "$(prototype::bundle_cache)/Prototype_DeuPatchBEP.zip" ]; then
        cp -n "$zip" "$(prototype::bundle_cache)/Prototype_DeuPatchBEP.zip" 2>/dev/null || true
    fi
    rm -rf "$work" "$ov"
    mkdir -p "$work" "$ov"
    type output::info >/dev/null 2>&1 \
        && output::info "Deutsch-Patch: Overlay aus ZIP bauen (v1.0–1.3, Cache, nicht Git)" \
        || true
    v1="$work/v1"
    mkdir -p "$v1"
    7z x -y -o"$v1" "$zip" "Prototype Deutschpatch Bollwurf Edition Patch v1.0.exe" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    7z x -y -o"$v1/inner" "$v1/Prototype Deutschpatch Bollwurf Edition Patch v1.0.exe" setup.exe \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    7z x -y -o"$v1/out" "$v1/inner/setup.exe" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    prototype::deu_merge_tree "$v1/out"
    v11="$work/v11"
    7z x -y -o"$v11" "$zip" "Prototype Deutschpatch Bollwurf Edition Patch v1.1.exe" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    7z x -y -o"$v11/out" "$v11/Prototype Deutschpatch Bollwurf Edition Patch v1.1.exe" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    prototype::deu_merge_tree "$v11/out"
    v12="$work/v12"
    7z x -y -o"$v12" "$zip" "Prototype Deutschpatch Bollwurf Edition Patch v1.2.exe" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    7z x -y -o"$v12/out" "$v12/Prototype Deutschpatch Bollwurf Edition Patch v1.2.exe" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    prototype::deu_merge_tree "$v12/out"
    v13="$work/v13"
    7z x -y -o"$v13" "$zip" "Prototype Deutschpatch Bollwurf Edition Patch v1.3.rar" \
        >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    if command -v unrar >/dev/null 2>&1; then
        unrar x -o+ "$v13/Prototype Deutschpatch Bollwurf Edition Patch v1.3.rar" "$v13/out/" \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    else
        7z x -y -o"$v13/out" "$v13/Prototype Deutschpatch Bollwurf Edition Patch v1.3.rar" \
            >>"${LOG_FILE:-/dev/null}" 2>&1 || return 1
    fi
    prototype::deu_merge_tree "$v13/out"
    printf '%s\n' "1.4.0" >"$ov/$_PROTOTYPE_DEU_STAMP"
    rm -rf "$work"
    prototype::deu_overlay_ready
}

# Packed NIS .rz must be stashed (not deleted) so Standard can restore vanilla.
prototype::stash_packed_nis() {
    local game="${1:-}" list="${2:-}" f rel
    [ -n "$game" ] && [ -d "$game" ] || return 0
    for f in "$game/art/nis/"*.rz "$game/art/NIS/"*.rz; do
        [ -f "$f" ] || continue
        case "$f" in *.rezeptor_bak) continue ;; esac
        prototype::backup_original "$f"
        rel="${f#"$game"/}"
        [ -n "$list" ] && printf '%s\n' "$rel" >>"$list"
        rm -f "$f"
    done
}

prototype::restore_packed_nis() {
    local game="${1:-}" bak dest
    [ -n "$game" ] && [ -d "$game" ] || return 0
    for bak in "$game/art/nis/"*.rz.rezeptor_bak "$game/art/NIS/"*.rz.rezeptor_bak; do
        [ -f "$bak" ] || continue
        dest="${bak%.rezeptor_bak}"
        prototype::restore_bak "$dest"
    done
}

prototype::remove_deu_overlay() {
    local game="${1:-}" list rel ov
    [ -n "$game" ] && [ -d "$game" ] || return 0
    list="$game/$_PROTOTYPE_DEU_LIST"
    if [ -f "$list" ]; then
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            prototype::restore_or_remove "$game/$rel"
        done <"$list"
        rm -f "$list"
        prototype::restore_or_remove "$game/art/hud/textbible_german.p3d"
        prototype::restore_or_remove "$game/art/hud/protostart.gfx"
        prototype::restore_packed_nis "$game"
        return 0
    fi
    ov="$(prototype::deu_cache)"
    if [ -d "$ov" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rel="${f#"$ov"/}"
            case "$rel" in
                "$_PROTOTYPE_DEU_STAMP") continue ;;
            esac
            prototype::restore_or_remove "$game/$rel"
        done <<EOF
$(find "$ov" -type f | sort)
EOF
    fi
    prototype::restore_or_remove "$game/art/hud/textbible_german.p3d"
    prototype::restore_or_remove "$game/art/hud/protostart.gfx"
    prototype::restore_packed_nis "$game"
}

# Track a deu-overlay path so Standard can restore/remove it.
prototype::deu_list_add() {
    local game="${1:-}" rel="${2:-}" list
    [ -n "$game" ] && [ -n "$rel" ] || return 0
    list="$game/$_PROTOTYPE_DEU_LIST"
    [ -f "$list" ] || : >"$list"
    grep -Fxq "$rel" "$list" 2>/dev/null && return 0
    printf '%s\n' "$rel" >>"$list"
}

# FE=68 needs a german textbible slot + german fe_textbible id. Title chrome
# lives in protostart.gfx ($PRESS_BUTTON_TO_START), not only the registry.
prototype::apply_deu_frontend_german() {
    local game="${1:-}" dest src rcf
    [ -n "$game" ] && [ -d "$game" ] || return 1
    src="$game/art/hud/textbible_french.p3d"
    dest="$game/art/hud/textbible_german.p3d"
    [ -f "$src" ] || return 1
    if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then
        prototype::backup_original "$dest"
        cp -f "$src" "$dest" || return 1
    fi
    prototype::deu_list_add "$game" "art/hud/textbible_german.p3d"
    python3 - "$game/art/hud/fe_textbible.p3d" <<'PY' || return 1
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
old, new = b"\x08french\x00", b"\x08german\x00"
if old not in data and new not in data:
    sys.exit(1)
if old in data:
    data = data.replace(old, new, 1)
    path.write_bytes(data)
PY
    rcf="$game/art.rcf"
    dest="$game/art/hud/protostart.gfx"
    if [ -f "$rcf" ]; then
        mkdir -p "$(dirname "$dest")"
        python3 - "$rcf" "$dest" <<'PY' || return 1
import sys
from pathlib import Path
rcf = Path(sys.argv[1]).read_bytes()
dest = Path(sys.argv[2])
key = b"$PRESS_BUTTON_TO_START\x00"
label = b"DRUECKEN SIE ENTER"
# Scaleform GFX stores absolute offsets. A shorter replace (old 3-space pad
# was 22 vs 23) shifts Initialize01 and the title movie stays black.
if len(label) > len(key) - 1:
    sys.exit(1)
repl = label + (b" " * (len(key) - 1 - len(label))) + b"\x00"
magic = b"GFX\x08"
hit = rcf.find(key)
if hit < 0:
    sys.exit(1)
start = rcf.rfind(magic, 0, hit)
end = rcf.find(magic, hit)
if start < 0 or end <= start:
    sys.exit(1)
orig = rcf[start:end]
if key not in orig or len(repl) != len(key):
    sys.exit(1)
blob = orig.replace(key, repl, 1)
if len(blob) != len(orig) or key in blob or label not in blob:
    sys.exit(1)
dest.parent.mkdir(parents=True, exist_ok=True)
bak = Path(str(dest) + ".rezeptor_bak")
bak.write_bytes(orig)
dest.write_bytes(blob)
PY
        prototype::deu_list_add "$game" "art/hud/protostart.gfx"
    fi
    prototype::deu_frontend_ok "$game"
}

prototype::deu_frontend_ok() {
    local game="${1:-}"
    [ -n "$game" ] && [ -d "$game" ] || return 1
    [ -f "$game/art/hud/textbible_german.p3d" ] || return 1
    [ -f "$game/art/hud/fe_textbible.p3d" ] || return 1
    grep -aFq $'\x08german\x00' "$game/art/hud/fe_textbible.p3d" || return 1
    [ -f "$game/art/hud/protostart.gfx" ] || return 1
    grep -aFq "DRUECKEN SIE ENTER" "$game/art/hud/protostart.gfx" || return 1
    # Old pad dropped 1 byte; PreferLooseFiles then loaded a broken movie.
    if [ -f "$game/art.rcf" ]; then
        python3 - "$game/art.rcf" "$game/art/hud/protostart.gfx" <<'PY' || return 1
import sys
from pathlib import Path
rcf = Path(sys.argv[1]).read_bytes()
gfx = Path(sys.argv[2]).read_bytes()
key = b"$PRESS_BUTTON_TO_START\x00"
magic = b"GFX\x08"
hit = rcf.find(key)
start = rcf.rfind(magic, 0, hit) if hit >= 0 else -1
end = rcf.find(magic, hit) if hit >= 0 else -1
if hit < 0 or start < 0 or end <= start:
    sys.exit(1)
if len(gfx) != end - start:
    sys.exit(1)
if key in gfx:
    sys.exit(1)
PY
    fi
}

prototype::apply_deu_overlay() {
    local game="${1:-}" ov list rel dest
    [ -n "$game" ] && [ -d "$game" ] || return 0
    if [ "$(prototype::language_id)" != de ]; then
        prototype::remove_deu_overlay "$game"
        return 0
    fi
    if [ -f "$game/$_PROTOTYPE_DEU_LIST" ] \
        && [ -f "$game/art/hud/fe_textbible.p3d" ] \
        && [ -f "$game/art/hud/textbible_french.p3d" ]; then
        prototype::apply_deu_frontend_german "$game" || return 1
        return 0
    fi
    if ! prototype::seed_deu_overlay; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Deutsch-Patch: ZIP fehlt (Downloads, Cache, oder public MEGA-URL in remote.yml) — Sprache bleibt Standard ohne Overlay" \
            || true
        return 1
    fi
    ov="$(prototype::deu_cache)"
    list="$game/$_PROTOTYPE_DEU_LIST"
    prototype::remove_deu_overlay "$game"
    : >"$list"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$ov"/}"
        case "$rel" in
            "$_PROTOTYPE_DEU_STAMP") continue ;;
        esac
        dest="$game/$rel"
        mkdir -p "$(dirname "$dest")"
        prototype::backup_original "$dest"
        cp -f "$f" "$dest" || return 1
        printf '%s\n' "$rel" >>"$list"
    done <<EOF
$(find "$ov" -type f | sort)
EOF
    # v1.1 setup.bat: stash packed NIS so loose .p3d wins; Standard restores them.
    prototype::stash_packed_nis "$game" "$list"
    prototype::apply_deu_frontend_german "$game" || return 1
    return 0
}

prototype::skin_pack() {
    echo "$(prototype::bundle_root)/packs/skin-$(prototype::skin_id)"
}

prototype::skin_relpaths() {
    local p pack
    for p in venom antivenom; do
        pack="$(prototype::bundle_root)/packs/skin-$p"
        [ -d "$pack/art" ] || continue
        find "$pack/art" -type f | sed "s|^$pack/||"
    done | sort -u
}

prototype::remove_skin() {
    local game="${1:-}" rel
    [ -n "$game" ] && [ -d "$game" ] || return 0
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        prototype::restore_or_remove "$game/$rel"
    done <<EOF
$(prototype::skin_relpaths)
EOF
}

prototype::apply_skin() {
    local game="${1:-}" id pack rel dest
    [ -n "$game" ] && [ -d "$game" ] || return 0
    id="$(prototype::skin_id)"
    prototype::remove_skin "$game"
    [ "$id" != standard ] || return 0
    pack="$(prototype::skin_pack)"
    if [ ! -d "$pack/art" ]; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Skin-Pack fehlt: $id" \
            || true
        return 1
    fi
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$pack"/}"
        dest="$game/$rel"
        mkdir -p "$(dirname "$dest")"
        prototype::backup_original "$dest"
        cp -f "$f" "$dest" || return 1
    done <<EOF
$(find "$pack/art" -type f | sort)
EOF
}

# Parkour 1.2 Balanced sprint: only art/startup_fig.p3d. Sprint Fix uses
# art/startup_fig.p3d.rz (different path).
prototype::parkour_pack() {
    echo "$(prototype::bundle_root)/packs/parkour"
}

prototype::parkour_src() {
    echo "$(prototype::parkour_pack)/art/startup_fig.p3d"
}

prototype::apply_parkour() {
    local game="${1:-}" src dest ov
    [ -n "$game" ] && [ -d "$game" ] || return 0
    dest="$game/art/startup_fig.p3d"
    src="$(prototype::parkour_src)"
    ov="$(prototype::bundle_overlay)/art/startup_fig.p3d"
    if prototype::parkour_on; then
        if [ ! -f "$src" ]; then
            type output::warning >/dev/null 2>&1 \
                && output::warning "Parkour-Pack fehlt: $src" \
                || true
            return 1
        fi
        mkdir -p "$(dirname "$dest")"
        prototype::backup_original "$dest"
        cp -f "$src" "$dest" || return 1
        return 0
    fi
    # Off: put the overlay legal fig back (bak is vanilla, not the legal fig).
    if [ -f "$ov" ]; then
        mkdir -p "$(dirname "$dest")"
        prototype::backup_original "$dest"
        cp -f "$ov" "$dest" || return 1
    fi
}

prototype::ps3_pack() {
    echo "$(prototype::bundle_root)/packs/ps3-buttons"
}

prototype::ps3_relpaths() {
    local pack
    pack="$(prototype::ps3_pack)"
    [ -d "$pack/art" ] || return 0
    find "$pack/art" -type f | sed "s|^$pack/||"
}

prototype::remove_ps3_buttons() {
    local game="${1:-}" rel
    [ -n "$game" ] && [ -d "$game" ] || return 0
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        prototype::restore_or_remove "$game/$rel"
    done <<EOF
$(prototype::ps3_relpaths)
EOF
}

prototype::apply_ps3_buttons() {
    local game="${1:-}" pack rel dest
    [ -n "$game" ] && [ -d "$game" ] || return 0
    if ! prototype::ps3_buttons_on; then
        prototype::remove_ps3_buttons "$game"
        return 0
    fi
    pack="$(prototype::ps3_pack)"
    if [ ! -d "$pack/art/hud" ]; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "PS3-Buttons-Pack fehlt" \
            || true
        return 1
    fi
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$pack"/}"
        dest="$game/$rel"
        mkdir -p "$(dirname "$dest")"
        prototype::backup_original "$dest"
        cp -f "$f" "$dest" || return 1
    done <<EOF
$(find "$pack/art" -type f | sort)
EOF
}

prototype::save_100_pack() {
    echo "$(prototype::bundle_root)/packs/save-100"
}

# Proton writes Documents/Prototype (steamuser). Some docs mention Activision/.
prototype::save_dir() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local d userdir
    [ -n "$prefix" ] && [ -d "$prefix/drive_c/users" ] || return 1
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        [ -f "$d/slot-A.bin" ] && echo "$d" && return 0
    done <<EOF
$(find "$prefix/drive_c/users" -type d \( -path '*/Documents/Prototype' -o -path '*/Documents/Activision/Prototype' \) 2>/dev/null | sort)
EOF
    for userdir in \
        "$prefix/drive_c/users/steamuser" \
        "$prefix/drive_c/users/${USER:-}"
    do
        [ -d "$userdir" ] || continue
        echo "$userdir/Documents/Prototype"
        return 0
    done
    return 1
}

# Copy a live save aside before replacing it. Skip files already matching the pack.
prototype::backup_live_save() {
    local dest="${1:-}" packf="${2:-}" bakdir stamp
    [ -n "$dest" ] && [ -f "$dest" ] || return 0
    [ -f "$packf" ] || return 0
    cmp -s "$dest" "$packf" && return 0
    stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
    bakdir="$(dirname "$dest")/rezeptor-save-backup/${stamp}"
    mkdir -p "$bakdir"
    cp -f "$dest" "$bakdir/$(basename "$dest")" || true
}

prototype::apply_save_100() {
    local dest pack f name
    if ! prototype::save_100_on; then
        return 0
    fi
    pack="$(prototype::save_100_pack)"
    [ -f "$pack/slot-A.bin" ] || {
        type output::warning >/dev/null 2>&1 \
            && output::warning "100%-Spielstand-Pack fehlt" \
            || true
        return 1
    }
    dest="$(prototype::save_dir)" || {
        type output::warning >/dev/null 2>&1 \
            && output::warning "100%-Spielstand: Prefix-User-Ordner fehlt" \
            || true
        return 1
    }
    mkdir -p "$dest"
    for name in profile.bin slot-A.bin slot-B.bin slot-C.bin; do
        f="$pack/$name"
        [ -f "$f" ] || continue
        prototype::backup_live_save "$dest/$name" "$f"
        cp -f "$f" "$dest/$name" || return 1
    done
}

# Locke trainer sits next to the game AND under data_root/trainer/ so the
# existing „Trainer starten“ button can find it. Never inject at launch.
prototype::stage_trainer() {
    local game="${1:-}" src dest readme
    src="$(prototype::bundle_root)/tools/trainer"
    [ -n "$game" ] && [ -d "$game" ] || return 0
    [ -f "$src/prototype.v1001.p7trn.exe" ] || return 0
    mkdir -p "$game/rezeptor-trainer"
    cp -f "$src/prototype.v1001.p7trn.exe" "$game/rezeptor-trainer/"
    [ -f "$src/locke_de.nfo" ] && cp -f "$src/locke_de.nfo" "$game/rezeptor-trainer/"
    [ -f "$src/locke.nfo" ] && cp -f "$src/locke.nfo" "$game/rezeptor-trainer/"
    rm -f "$game/ResChanger.exe" "$game/prototype.v1001.p7trn.exe"
    readme="$game/rezeptor-trainer/README.txt"
    cat >"$readme" <<EOF
Prototype trainer (Locke +7) — staged by Rezeptor, not launched with the game.

This folder:
  $game/rezeptor-trainer/prototype.v1001.p7trn.exe

Also copied to the data-root trainer drop (GUI „Trainer starten“ while the game runs):
  ${DATA_ROOT:-<data_root>}/trainer/prototype.v1001.p7trn.exe

Hotkeys: NUM1–7 (see locke_de.nfo / locke.nfo).
EOF
    if [ -n "${DATA_ROOT:-}" ]; then
        dest="${DATA_ROOT}/trainer"
        mkdir -p "$dest"
        cp -f "$src/prototype.v1001.p7trn.exe" "$dest/"
        [ -f "$src/locke_de.nfo" ] && cp -f "$src/locke_de.nfo" "$dest/"
        [ -f "$src/locke.nfo" ] && cp -f "$src/locke.nfo" "$dest/"
        cp -f "$readme" "$dest/README.txt"
    fi
}

prototype::backup_original() {
    local dest="${1:-}"
    [ -n "$dest" ] && [ -f "$dest" ] || return 0
    [ -f "${dest}.rezeptor_bak" ] && return 0
    cp -f "$dest" "${dest}.rezeptor_bak" || true
}

prototype::restore_bak() {
    local dest="${1:-}"
    if [ -f "${dest}.rezeptor_bak" ]; then
        mv -f "${dest}.rezeptor_bak" "$dest" || true
    fi
}

# Restore a pre-bundle loose file, or delete the overlay copy if none existed.
prototype::restore_or_remove() {
    local dest="${1:-}"
    [ -n "$dest" ] || return 0
    if [ -f "${dest}.rezeptor_bak" ]; then
        prototype::restore_bak "$dest"
    else
        rm -f "$dest"
    fi
}

# Prefix d3d9 stays DXVK. Overlay is only the live 1.5.0 files.
prototype::copy_overlay() {
    local game="${1:-}" ov rel dest
    ov="$(prototype::bundle_overlay)"
    [ -n "$game" ] && [ -d "$game" ] && [ -d "$ov" ] || return 1
    # Portable: no process substitution. Overlay paths have no spaces.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$ov"/}"
        dest="$game/$rel"
        mkdir -p "$(dirname "$dest")"
        case "$rel" in
            binkw32.dll|art/*|movies/*)
                prototype::backup_original "$dest"
                ;;
        esac
        cp -f "$f" "$dest" || return 1
    done <<EOF
$(find "$ov" -type f | sort)
EOF
}

# One sweep: old overlay leftovers next to the EXE. Prefix DXVK d3d9 stays.
prototype::strip_game_leftovers() {
    local game="${1:-}"
    [ -n "$game" ] && [ -d "$game" ] || return 0
    rm -f \
        "$game/ReShade32.dll" \
        "$game/d3d9.dll" \
        "$game/dxgi.dll" \
        "$game/ReShade.ini" \
        "$game/ReShade.log" \
        "$game/LICENSE-RESHADE.txt" \
        "$game/PrototypeReborn.ini" \
        "$game/JackieRealistic.ini" \
        "$game/ReShadePreset.ini" \
        "$game/defa.ini" \
        "$game/dez.ini" \
        "$game/init.lua" \
        "$game/wings.lua" \
        "$game/enable_dlc.rcf" \
        "$game/Texmod.exe" \
        "$game/ResChanger.exe" \
        "$game/art/startup_tod.p3d.rz" \
        "$game/art/startup_tod.p3d.rz.rezeptor_bak"
    rm -rf "$game/reshade-shaders" "$game/reshade-cache" "$game/art/packages/missions/wings"
}

# Ultimate ASI Loader (PrototypeFix binkw32) forwards Bink to this name.
# Without it, _BinkOpen is a stub and the first intro movie kills the process.
prototype::ensure_bink_hooked() {
    local game="${1:-}"
    [ -n "$game" ] && [ -d "$game" ] || return 0
    [ -f "$game/binkw32.dll.rezeptor_bak" ] || return 1
    cp -f "$game/binkw32.dll.rezeptor_bak" "$game/binkw32Hooked.dll"
}

# Allagga / P2 Style .tpf are TexMod 2006. They cannot hook under Proton
# without that GUI injector, so do not copy them next to the EXE.
prototype::strip_inactive_texmod() {
    local game="${1:-}" cache
    cache="$(prototype::bundle_cache)"
    [ -n "$game" ] && [ -d "$game" ] || return 0
    [ -d "$cache" ] || return 0
    local f
    for f in "$cache"/*.tpf; do
        [ -f "$f" ] || continue
        rm -f "$game/$(basename "$f")"
    done
}

prototype::apply_gamelaunch_vcdiff() {
    local game="${1:-}" exe patch xd dest rc
    exe="$game/prototypef.exe"
    patch="$(prototype::bundle_root)/tools/prototypef.vcdiff"
    xd="$(prototype::bundle_root)/tools/xdelta3-3.1.0-i686.exe"
    [ -f "$exe" ] && [ -f "$patch" ] || return 0
    [ -f "${exe}.rezeptor_bak" ] && return 0
    prototype::backup_original "$exe"
    dest="${exe}.rezeptor_new"
    rm -f "$dest"
    rc=1
    if command -v xdelta3 >/dev/null 2>&1; then
        xdelta3 -d -f -s "${exe}.rezeptor_bak" "$patch" "$dest" \
            >>"${LOG_FILE:-/dev/null}" 2>&1 && rc=0 || rc=1
    elif [ -f "$xd" ] && type wine_runtime::wine >/dev/null 2>&1; then
        wine_runtime::init || true
        cp -f "$xd" "$game/_rezeptor_xdelta3.exe"
        cp -f "$patch" "$game/_rezeptor_prototypef.vcdiff"
        (
            cd "$game" || exit 1
            wine_runtime::wine "./_rezeptor_xdelta3.exe" -d -f \
                -s "prototypef.exe.rezeptor_bak" \
                "_rezeptor_prototypef.vcdiff" \
                "prototypef.exe.rezeptor_new"
        ) >>"${LOG_FILE:-/dev/null}" 2>&1 && rc=0 || rc=1
        rm -f "$game/_rezeptor_xdelta3.exe" "$game/_rezeptor_prototypef.vcdiff"
    fi
    if [ "$rc" -eq 0 ] && [ -f "$dest" ] && [ -s "$dest" ]; then
        mv -f "$dest" "$exe" || true
        return 0
    fi
    rm -f "$dest"
    prototype::restore_bak "$exe"
    # Expected on this Steamless dump: vcdiff does not match. Keep original.
    # Do not emit @warn / progress — the GUI would look like a failure.
    if [ -n "${LOG_FILE:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)] Mod-Bundle: EXE-Patch (vcdiff) skipped (Steamless dump; original EXE kept)" >>"$LOG_FILE"
    fi
    return 0
}

prototype::write_bundle_marker() {
    local game="${1:-}" ver
    ver="$(prototype::bundle_version)"
    cat >"$game/$_PROTOTYPE_BUNDLE_MARKER" <<EOF
id: prototype-mod-bundle
version: $ver
d3d9: dxvk-prefix
pin: desktop-reset-windowed
present: borderless
language: $(prototype::language_id)
skin: $(prototype::skin_id)
sprint: on
parkour: $(prototype::parkour_on && echo on || echo off)
ps3_buttons: $(prototype::ps3_buttons_on && echo on || echo off)
save_100: $(prototype::save_100_on && echo on || echo off)
trainer: ready
deu: $(prototype::language_id)
EOF
}

prototype::remove_mod_bundle() {
    local game="${1:-}" cache
    [ -n "$game" ] && [ -d "$game" ] || return 0
    cache="$(prototype::bundle_cache)"
    prototype::restore_bak "$game/binkw32.dll"
    prototype::restore_bak "$game/prototypef.exe"
    prototype::restore_bak "$game/art/hud/protolegalscreen.gfx"
    prototype::restore_bak "$game/movies/activisionRadicalLogos.bik"
    prototype::restore_bak "$game/movies/attract.bik"
    prototype::restore_or_remove "$game/art/startup_fig.p3d"
    prototype::strip_game_leftovers "$game"
    rm -f \
        "$game/binkw32Hooked.dll" \
        "$game/prototype_fix.asi" \
        "$game/prototype_fix.ini" \
        "$game/force_desktop_res.asi" \
        "$game/force_desktop_res.log" \
        "$game/d3d9.log" \
        "$game/prototype.v1001.p7trn.exe" \
        "$game/$_PROTOTYPE_BUNDLE_MARKER"
    rm -rf "$game/rezeptor-trainer"
    prototype::restore_or_remove "$game/art/alex/alex_fig.p3d.rz"
    prototype::restore_or_remove "$game/art/startup_fig.p3d.rz"
    prototype::remove_skin "$game"
    prototype::remove_ps3_buttons "$game"
    prototype::remove_deu_overlay "$game"
    if [ -d "$cache" ]; then
        local f
        for f in "$cache"/*.tpf; do
            [ -f "$f" ] || continue
            rm -f "$game/$(basename "$f")"
        done
    fi
}

# Atomic apply (or strip) of the assembled overlay next to prototypef.exe.
prototype::apply_mod_bundle() {
    local game="${1:-}" ov
    [ -n "$game" ] && [ -d "$game" ] || return 0
    if ! prototype::mod_bundle_on; then
        prototype::remove_mod_bundle "$game"
        prototype::apply_save_100 || true
        type output::info >/dev/null 2>&1 && output::info "Mod-Bundle: aus" || true
        return 0
    fi
    ov="$(prototype::bundle_overlay)"
    if [ ! -d "$ov" ] || [ ! -f "$ov/prototype_fix.asi" ] || [ ! -f "$ov/force_desktop_res.asi" ]; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Mod-Bundle: Overlay fehlt unter assets/mod-bundle/overlay" \
            || true
        return 1
    fi
    prototype::rotate_game_log "$game/d3d9.log"
    prototype::write_dxvk_conf || true
    prototype::copy_overlay "$game" || return 1
    prototype::strip_game_leftovers "$game"
    if ! prototype::ensure_bink_hooked "$game"; then
        type output::warning >/dev/null 2>&1 \
            && output::warning "Mod-Bundle: Original-Bink (binkw32Hooked.dll) fehlt — Intro-Filme stürzen ab" \
            || true
    fi
    prototype::apply_gamelaunch_vcdiff "$game" || true
    prototype::strip_inactive_texmod "$game"
    prototype::apply_deu_overlay "$game" || true
    prototype::apply_skin "$game" || true
    prototype::apply_parkour "$game" || true
    prototype::apply_ps3_buttons "$game" || true
    prototype::apply_save_100 || true
    prototype::stage_trainer "$game"
    prototype::write_bundle_marker "$game"
    type output::success >/dev/null 2>&1 \
        && output::success "Mod-Bundle $(prototype::bundle_version) gelegt (PrototypeFix + No-Intro + Desktop-Pin windowed, Sprint-Fix, Parkour=$(prototype::parkour_on && echo on || echo off), Skin=$(prototype::skin_id), Sprache=$(prototype::language_id), PS3=$(prototype::ps3_buttons_on && echo on || echo off), Save100=$(prototype::save_100_on && echo on || echo off), Trainer bereit, nicht injiziert)" \
        || true
    return 0
}

prototype::bundle_marker_current() {
    local game="${1:-}" want have
    [ -n "$game" ] && [ -f "$game/$_PROTOTYPE_BUNDLE_MARKER" ] || return 1
    want="$(prototype::bundle_version)"
    have="$(awk '/^version:/ { gsub(/["'\'']/, "", $2); print $2; exit }' "$game/$_PROTOTYPE_BUNDLE_MARKER")"
    [ -n "$have" ] && [ "$have" = "$want" ]
}

prototype::bundle_critical_ok() {
    local game="${1:-}"
    [ -n "$game" ] || return 1
    [ -f "$game/$_PROTOTYPE_BUNDLE_MARKER" ] || return 1
    prototype::bundle_marker_current "$game" || return 1
    [ -f "$game/prototype_fix.asi" ] || return 1
    [ -f "$game/force_desktop_res.asi" ] || return 1
    [ -f "$game/binkw32Hooked.dll" ] || return 1
    [ ! -e "$game/ReShade32.dll" ] || return 1
    [ ! -e "$game/dxgi.dll" ] || return 1
    [ ! -e "$game/d3d9.dll" ] || return 1
    [ -f "$game/art/hud/protolegalscreen.gfx" ] || return 1
    [ -f "$game/art/startup_fig.p3d" ] || return 1
    [ ! -e "$game/init.lua" ] || return 1
    [ ! -e "$game/wings.lua" ] || return 1
    [ ! -e "$game/enable_dlc.rcf" ] || return 1
    [ ! -e "$game/art/packages/missions/wings/wings.p3d" ] || return 1
    [ ! -e "$game/art/startup_tod.p3d.rz" ] || return 1
    [ ! -e "$game/ResChanger.exe" ] || return 1
    grep -q '^BorderlessWindow = true' "$game/prototype_fix.ini" 2>/dev/null || return 1
    [ -f "$game/art/alex/alex_fig.p3d.rz" ] || return 1
    [ -f "$game/rezeptor-trainer/prototype.v1001.p7trn.exe" ] || return 1
    if prototype::parkour_on; then
        [ -f "$(prototype::parkour_src)" ] || return 1
        [ -f "$game/art/startup_fig.p3d" ] || return 1
        cmp -s "$game/art/startup_fig.p3d" "$(prototype::parkour_src)" || return 1
    else
        [ -f "$game/art/startup_fig.p3d" ] || return 1
        prototype::parkour_matches "$game" && return 1
    fi
    if prototype::ps3_buttons_on; then
        [ -f "$game/art/hud/fecontrollerimage.gfx" ] || return 1
        prototype::ps3_matches "$game" || return 1
    else
        prototype::ps3_matches "$game" && return 1
    fi
    if prototype::save_100_on; then
        prototype::save_100_matches || return 1
    fi
    case "$(prototype::skin_id)" in
        venom|antivenom)
            [ -f "$game/art/packages/powers/alex_armour/alex_armour.p3d.rz" ] || return 1
            ;;
        standard)
            prototype::skin_matches_pack "$game" venom && return 1
            prototype::skin_matches_pack "$game" antivenom && return 1
            ;;
    esac
    if [ "$(prototype::language_id)" = de ]; then
        [ -f "$game/art/hud/fe_textbible.p3d" ] || return 1
        [ -f "$game/art/hud/textbible_french.p3d" ] || return 1
        prototype::deu_frontend_ok "$game" || return 1
    else
        [ ! -f "$game/$_PROTOTYPE_DEU_LIST" ] || return 1
    fi
}

prototype::skin_matches_pack() {
    local game="${1:-}" id="${2:-}" live pack
    live="$game/art/packages/powers/alex_armour/alex_armour.p3d.rz"
    pack="$(prototype::bundle_root)/packs/skin-$id/art/packages/powers/alex_armour/alex_armour.p3d.rz"
    [ -f "$live" ] && [ -f "$pack" ] && cmp -s "$live" "$pack"
}

prototype::parkour_matches() {
    local game="${1:-}" live src
    live="$game/art/startup_fig.p3d"
    src="$(prototype::parkour_src)"
    [ -f "$live" ] && [ -f "$src" ] && cmp -s "$live" "$src"
}

prototype::ps3_matches() {
    local game="${1:-}" pack live
    pack="$(prototype::ps3_pack)/art/hud/fecontrollerimage.gfx"
    live="$game/art/hud/fecontrollerimage.gfx"
    [ -f "$live" ] && [ -f "$pack" ] && cmp -s "$live" "$pack"
}

prototype::save_100_matches() {
    local dest pack
    dest="$(prototype::save_dir)" || return 1
    pack="$(prototype::save_100_pack)"
    [ -f "$dest/slot-A.bin" ] && [ -f "$pack/slot-A.bin" ] || return 1
    cmp -s "$dest/slot-A.bin" "$pack/slot-A.bin"
}
