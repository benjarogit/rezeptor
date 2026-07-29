#!/usr/bin/env bash
# m0nkrus-style Photoshop pack extras (ISO sibling files).
# Pack root typically contains:
#   *.iso, Neural Filters*.exe (SFX), ps2021_missing_libs.7z,
#   optional VC_redist / GenP (GenP is NOT auto-run — ISO is pre-patched).

recipe_photoshop_pack::looks_like_pack_root() {
    local root="${1:-}"
    local has_iso=0 has_extra=0 f
    [ -n "$root" ] && [ -d "$root" ] || return 1
    shopt -s nullglob 2>/dev/null || true
    for f in "$root"/*.iso "$root"/*.ISO; do
        [ -f "$f" ] || continue
        has_iso=1
        break
    done
    for f in "$root"/*[Nn]eural* "$root"/ps2021_missing_libs.7z "$root"/*[Gg]en[Pp]*; do
        [ -e "$f" ] || continue
        has_extra=1
        break
    done
    shopt -u nullglob 2>/dev/null || true
    [ "$has_iso" -eq 1 ] && [ "$has_extra" -eq 1 ]
}

recipe_photoshop_pack::resolve_pack_root() {
    local cand="" saved=""
    if [ -n "${RECIPE_PACK_ROOT:-}" ] && recipe_photoshop_pack::looks_like_pack_root "${RECIPE_PACK_ROOT}"; then
        echo "${RECIPE_PACK_ROOT}"
        return 0
    fi
    if [ -n "${RECIPE_INSTALLER_PATH:-}" ] && [ -f "${RECIPE_INSTALLER_PATH}" ]; then
        cand="$(dirname "${RECIPE_INSTALLER_PATH}")"
        if recipe_photoshop_pack::looks_like_pack_root "$cand"; then
            echo "$cand"
            return 0
        fi
    fi
    if [ -n "${RECIPE_SOURCE_ROOT:-}" ] && recipe_photoshop_pack::looks_like_pack_root "${RECIPE_SOURCE_ROOT}"; then
        echo "${RECIPE_SOURCE_ROOT}"
        return 0
    fi
    # Repair / zweiter Lauf: zuletzt genutzter Pack-Root aus recipe.env
    if [ -n "${DATA_ROOT:-}" ] && type env_file_get >/dev/null 2>&1; then
        saved="$(env_file_get "${DATA_ROOT}/recipe.env" RECIPE_PACK_ROOT 2>/dev/null || true)"
        if [ -n "$saved" ] && recipe_photoshop_pack::looks_like_pack_root "$saved"; then
            echo "$saved"
            return 0
        fi
    fi
    return 1
}

recipe_photoshop_pack::_persist_pack_root() {
    local pack_root="$1"
    [ -n "${DATA_ROOT:-}" ] || return 0
    [ -n "$pack_root" ] || return 0
    if type env_file_set >/dev/null 2>&1; then
        env_file_set "${DATA_ROOT}/recipe.env" RECIPE_PACK_ROOT "$pack_root" || true
    fi
}

recipe_photoshop_pack::_wine_user() {
    local prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    if [ -d "$prefix/drive_c/users/steamuser" ]; then
        echo "steamuser"
    else
        echo "${USER:-$(id -un)}"
    fi
}

recipe_photoshop_pack::_find_in_pack() {
    # root may contain spaces (m0nkrus pack folders) — quote root, glob pattern only.
    local root="$1" pattern="$2" f
    local -a matches=()
    [ -n "$root" ] && [ -d "$root" ] || return 1
    [ -n "$pattern" ] || return 1
    shopt -s nullglob nocaseglob 2>/dev/null || true
    # shellcheck disable=SC2206
    matches=("$root"/$pattern)
    shopt -u nullglob nocaseglob 2>/dev/null || true
    for f in "${matches[@]}"; do
        [ -f "$f" ] || continue
        printf '%s\n' "$f"
        return 0
    done
    return 1
}

# Unpack ipp*/opencv DLLs into the Photoshop install dir (pack FAQ).
recipe_photoshop_pack::apply_missing_libs() {
    local pack_root="$1" ps_path="" libs="" tmp="" ps_exe=""
    libs="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "ps2021_missing_libs.7z")" || {
        output::info "Pack: keine ps2021_missing_libs.7z — übersprungen"
        return 0
    }
    if type photoshop::find_exe >/dev/null 2>&1; then
        ps_exe="$(photoshop::find_exe "${WINEPREFIX:-}" 2>/dev/null || true)"
        [ -n "$ps_exe" ] && [ -f "$ps_exe" ] && ps_path="$(dirname "$ps_exe")"
    fi
    [ -n "$ps_path" ] && [ -d "$ps_path" ] \
        || ps_path="$(recipe_photoshop::_install_path 2021 2>/dev/null || true)"
    [ -d "$ps_path" ] || {
        recipe_hooks::log_err "Pack missing_libs: Photoshop-Ordner nicht gefunden"
        return 1
    }
    # m0nkrus-ISO liefert die DLLs oft schon mit — dann fertig
    if [ -f "$ps_path/ippcvm7.dll" ] && [ -f "$ps_path/opencv_world440.dll" ]; then
        output::success "Pack: missing_libs bereits im Photoshop-Ordner"
        return 0
    fi
    command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1 || {
        recipe_hooks::log_err "Pack missing_libs: 7z fehlt"
        return 1
    }
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/ps-missing-libs.XXXXXX")"
    if ! 7z x -y -o"$tmp" "$libs" >/dev/null 2>&1 && ! 7za x -y -o"$tmp" "$libs" >/dev/null 2>&1; then
        rm -rf "$tmp"
        recipe_hooks::log_err "Pack missing_libs: Entpacken fehlgeschlagen"
        return 1
    fi
    if [ -d "$tmp/ps2021_missing_libs" ]; then
        cp -f "$tmp/ps2021_missing_libs"/*.dll "$ps_path/" 2>/dev/null || true
    else
        find "$tmp" -type f -name '*.dll' -exec cp -f {} "$ps_path/" \; 2>/dev/null || true
    fi
    rm -rf "$tmp"
    if [ -f "$ps_path/ippcvm7.dll" ] || [ -f "$ps_path/opencv_world440.dll" ]; then
        output::success "Pack: missing_libs nach $ps_path"
        return 0
    fi
    recipe_hooks::log_err "Pack missing_libs: DLLs nicht im Photoshop-Ordner"
    return 1
}

# Neural Filters SFX → Wine AppData PluginData (pack default Path=%APPDATA%\…\PluginData).
recipe_photoshop_pack::apply_neural_filters() {
    local pack_root="$1" sfx="" dest="" user prefix
    sfx="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "*Neural*Filters*.exe")" \
        || sfx="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "*Neural*.exe")" || {
        output::info "Pack: kein Neural-Filters-SFX — übersprungen"
        return 0
    }
    prefix="${WINEPREFIX:-${DATA_ROOT}/prefix}"
    user="$(recipe_photoshop_pack::_wine_user)"
    dest="$prefix/drive_c/users/$user/AppData/Roaming/Adobe/UXP/PluginsStorage/PHSP/22/Internal/com.adobe.nfp.gallery/PluginData"
    mkdir -p "$dest" || return 1
    command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1 || {
        recipe_hooks::log_err "Pack Neural Filters: 7z fehlt"
        return 1
    }
    output::step "Neural Filters aus Pack entpacken"
    if ! 7z x -y -o"$dest" "$sfx" >/dev/null 2>&1 && ! 7za x -y -o"$dest" "$sfx" >/dev/null 2>&1; then
        recipe_hooks::log_err "Pack Neural Filters: Entpacken fehlgeschlagen"
        return 1
    fi
    # SFX stub / config noise
    rm -f "$dest"/*.sfx "$dest"/config.txt 2>/dev/null || true
    if find "$dest" -type f -name 'manifest.json' 2>/dev/null | head -1 | grep -q .; then
        output::success "Pack: Neural Filters → $dest"
        return 0
    fi
    recipe_hooks::log_err "Pack Neural Filters: keine manifest.json unter PluginData"
    return 1
}

# Optional VC++ from pack if present (recipe_vcrun usually already covered it).
recipe_photoshop_pack::apply_vc_redist_hint() {
    local pack_root="$1" vc=""
    vc="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "*VC*redist*.exe")" \
        || vc="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "*Visual*C++*.exe")" || {
        return 0
    }
    output::info "Pack enthält VC-Redist ($(basename "$vc")) — Runtime kommt über recipe_vcrun"
    return 0
}

# Extract GenP rar once under DATA_ROOT/cache/genp — echo path to GenP GUI exe.
# Prefer AdobeCC*GenP*.exe (Resources): RunMe.exe exits immediately under Wine.
recipe_photoshop_pack::prepare_genp() {
    local pack_root="" rar="" dest="" runme="" genp=""
    pack_root="$(recipe_photoshop_pack::resolve_pack_root 2>/dev/null || true)"
    [ -n "$pack_root" ] || {
        recipe_hooks::log_err "GenP: kein Pack-Root (RECIPE_PACK_ROOT / Pack-Ordner)"
        return 1
    }
    rar="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "*GenP*.rar")" \
        || rar="$(recipe_photoshop_pack::_find_in_pack "$pack_root" "*GenP*.7z")" || {
        recipe_hooks::log_err "GenP: keine GenP-.rar/.7z im Pack ($pack_root)"
        return 1
    }
    dest="${DATA_ROOT}/cache/genp"
    mkdir -p "$dest" || return 1
    genp="$(find "$dest" -type f -iname 'AdobeCC*GenP*.exe' 2>/dev/null | head -1 || true)"
    [ -n "$genp" ] || genp="$(find "$dest" -type f -iname '*GenP*.exe' ! -iname 'RunMe.exe' 2>/dev/null | head -1 || true)"
    runme="$(find "$dest" -type f -iname 'RunMe.exe' 2>/dev/null | head -1 || true)"
    if [ -z "$runme" ] && [ -z "$genp" ]; then
        command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1 || {
            recipe_hooks::log_err "GenP: 7z fehlt zum Entpacken"
            return 1
        }
        output::step "GenP aus Pack entpacken" >&2
        if ! 7z x -y -o"$dest" "$rar" >/dev/null 2>&1 && ! 7za x -y -o"$dest" "$rar" >/dev/null 2>&1; then
            recipe_hooks::log_err "GenP: Entpacken fehlgeschlagen"
            return 1
        fi
        genp="$(find "$dest" -type f -iname 'AdobeCC*GenP*.exe' 2>/dev/null | head -1 || true)"
        [ -n "$genp" ] || genp="$(find "$dest" -type f -iname '*GenP*.exe' ! -iname 'RunMe.exe' 2>/dev/null | head -1 || true)"
        runme="$(find "$dest" -type f -iname 'RunMe.exe' 2>/dev/null | head -1 || true)"
    fi
    if [ -n "$genp" ] && [ -f "$genp" ]; then
        printf '%s\n' "$genp"
        return 0
    fi
    if [ -n "$runme" ] && [ -f "$runme" ]; then
        printf '%s\n' "$runme"
        return 0
    fi
    recipe_hooks::log_err "GenP: GenP.exe / RunMe.exe nach Entpacken nicht gefunden"
    return 1
}

# Launch GenP GUI under Proton (user must click Cure). ISO is usually pre-patched.
recipe_photoshop_pack::_genp_wine_photoshop_path() {
    local unix="" wine_rel=""
    if type photoshop::find_exe >/dev/null 2>&1; then
        unix="$(photoshop::find_exe "${WINEPREFIX:-${WINE_PREFIX:-}}" 2>/dev/null || true)"
    fi
    if [ -n "$unix" ] && [[ "$unix" == *"/drive_c/"* ]]; then
        wine_rel="${unix#*/drive_c/}"
        printf 'C:\\%s\n' "${wine_rel//\//\\}"
        return 0
    fi
    printf '%s\n' 'C:\Program Files\Adobe\Adobe Photoshop 2021\Photoshop.exe'
}

recipe_photoshop_pack::_copy_genp_path_clipboard() {
    local path="$1"
    [ -n "$path" ] || return 0
    if command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$path" | wl-copy 2>/dev/null || true
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$path" | xclip -selection clipboard 2>/dev/null || true
    elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$path" | xsel --clipboard --input 2>/dev/null || true
    fi
}

recipe_photoshop_pack::run_genp() {
    local exe="" wine_bin="" exe_dir="" ps_wine=""
    exe="$(recipe_photoshop_pack::prepare_genp)" || return 1
    wine_runtime::init || return 1
    wine_runtime::export_env || true
    # Match Proton launch (WINEFSYNC): mismatch with running wineserver → GenP exits instantly
    export WINEFSYNC=1
    wine_bin="$(command -v wine 2>/dev/null || true)"
    [ -n "$wine_bin" ] || {
        recipe_hooks::log_err "GenP: wine nicht im PATH (Proton-GE)"
        return 1
    }
    exe_dir="$(dirname "$exe")"
    ps_wine="$(recipe_photoshop_pack::_genp_wine_photoshop_path)"
    recipe_photoshop_pack::_copy_genp_path_clipboard "$ps_wine"
    output::step "GenP starten — Photoshop → Pille → Dateiname Strg+V"
    output::info "GenP: $exe"
    # GenP GetOpenFileName: InitialDir steuert GenP (meist …\Adobe) — vorauswählen unmöglich
    output::info "Zwischenablage/Einfügen: $ps_wine"
    # cwd = GenP-Ordner (HotKeySet.dll/Neben-EXEs); GUI blockiert bis Fenster zu
    (
        cd "$exe_dir" || exit 1
        wine "./$(basename "$exe")"
    ) >>"${LOG_FILE:-/dev/null}" 2>&1 || true
    output::success "GenP-Fenster beendet (Cure ggf. manuell gesetzt)"
    return 0
}

# Medizin: PHOTOSHOP_GENP_ON_REPAIR=1 → GenP bei Reparatur
recipe_photoshop_pack::maybe_run_genp_on_repair() {
    case "${PHOTOSHOP_GENP_ON_REPAIR:-0}" in
        1|true|yes|on|ON) ;;
        *)
            output::info "GenP bei Reparatur aus (Medizin) — ISO laut Pack vorgepatcht"
            return 0
            ;;
    esac
    recipe_photoshop_pack::run_genp
}

recipe_photoshop_pack::apply_extras() {
    local pack_root="" _err=0
    pack_root="$(recipe_photoshop_pack::resolve_pack_root 2>/dev/null || true)"
    [ -n "$pack_root" ] || {
        output::info "Kein m0nkrus-Pack-Root erkannt — nur Offline-ISO-Install"
        return 0
    }
    export RECIPE_PACK_ROOT="$pack_root"
    recipe_photoshop_pack::_persist_pack_root "$pack_root"
    output::step "Pack-Extras ($pack_root)"
    output::info "GenP nicht auto — bei Bedarf Medizin / Mehr → GenP (ISO vorgepatcht)"
    recipe_photoshop_pack::apply_vc_redist_hint "$pack_root" || true
    recipe_photoshop_pack::apply_missing_libs "$pack_root" || _err=1
    recipe_photoshop_pack::apply_neural_filters "$pack_root" || _err=1
    return "$_err"
}
