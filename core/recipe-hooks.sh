#!/usr/bin/env bash
# Rezeptor — einheitlicher Einstieg für alle Recipe-Hooks (install/launch/validate/repair/kill).
#
# Jedes Hook-Skript:
#   RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$RECIPE_DIR/../../core/recipe-hooks.sh"
#   recipe_hooks::load install   # launch | validate | repair | kill | minimal
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_hooks::die() {
    echo "ERROR: $*" >&2
    exit 1
}

recipe_hooks::paths_expand_tokens() {
    local p="${1:-}"
    [ -n "$p" ] || return 1
    p="${p//\{repo\}/${PROJECT_ROOT:-}}"
    p="${p//\{data_root\}/${DATA_ROOT:-}}"
    p="${p/#\~/$HOME}"
    echo "$p"
}

recipe_hooks::_source() {
    # shellcheck source=/dev/null
    source "$CORE_DIR/$1"
}

recipe_hooks::init_dirs() {
    [ -n "${RECIPE_DIR:-}" ] || recipe_hooks::die "RECIPE_DIR setzen vor recipe_hooks::load"
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$RECIPE_DIR/../.." && pwd)}"
    CORE_DIR="${CORE_DIR:-$PROJECT_ROOT/core}"
    # Immer dieses Rezept — kein vererbtes RECIPE_YML von einem anderen Rezept.
    RECIPE_YML="$RECIPE_DIR/recipe.yml"
    export PROJECT_ROOT RECIPE_DIR CORE_DIR RECIPE_YML
    [ -f "$RECIPE_YML" ] || recipe_hooks::die "recipe.yml fehlt: $RECIPE_YML"
}

recipe_hooks::load() {
    local profile="${1:-minimal}"
    export RECIPE_HOOK_PROFILE="$profile"
    recipe_hooks::init_dirs
    recipe_hooks::_source paths.sh
    recipe_hooks::_source recipe.sh
    recipe_export_env "$RECIPE_YML"
    recipe_hooks::_source output.sh

    case "$profile" in
        minimal) ;;
        install)
            recipe_hooks::_source security.sh
            recipe_hooks::_source env-file.sh
            recipe_hooks::_source wine-runtime.sh
            recipe_hooks::_source recipe-prefix.sh
            recipe_hooks::_source recipe-deploy.sh
            recipe_hooks::_source recipe-source.sh
            recipe_hooks::_source recipe-install.sh
            recipe_hooks::_source recipe-install-steps.sh
            recipe_hooks::_source recipe-winetricks.sh
            recipe_hooks::_source recipe-win10.sh
            recipe_hooks::_source recipe-vcrun.sh
            recipe_hooks::_source recipe-dotnet.sh
            recipe_hooks::_source recipe-wine-silent.sh
            recipe_hooks::wine_wrappers
            recipe_hooks::force_prefix
            export WINEARCH="${WINEARCH:-win64}"
            ;;
        launch)
            recipe_hooks::_source env-file.sh
            recipe_hooks::_source wine-runtime.sh
            recipe_hooks::_source recipe-dotnet.sh
            recipe_hooks::_source recipe-wine-silent.sh
            recipe_hooks::wine_wrappers
            recipe_hooks::force_prefix
            ;;
        validate)
            recipe_hooks::_source env-file.sh
            recipe_hooks::_source recipe-validate.sh
            ;;
        repair)
            recipe_hooks::_source env-file.sh
            recipe_hooks::_source wine-runtime.sh
            recipe_hooks::_source recipe-prefix.sh
            recipe_hooks::_source recipe-winetricks.sh
            recipe_hooks::_source recipe-win10.sh
            recipe_hooks::_source recipe-validate.sh
            recipe_hooks::_source recipe-vcrun.sh
            recipe_hooks::_source recipe-dotnet.sh
            recipe_hooks::_source recipe-wine-silent.sh
            recipe_hooks::wine_wrappers
            recipe_hooks::force_prefix
            ;;
        kill)
            recipe_hooks::_source wine-runtime.sh
            recipe_hooks::_source recipe-kill.sh
            recipe_hooks::force_prefix
            ;;
        *)
            recipe_hooks::die "Unbekanntes Profil: $profile (minimal|install|launch|validate|repair|kill)"
            ;;
    esac
    recipe_hooks::load_app_module
}

recipe_hooks::load_app_module() {
    local mod="recipe-${RECIPE_ID}.sh"
    local launch_mod="recipe-${RECIPE_ID}-launch.sh"
    local install_mod="recipe-${RECIPE_ID}-install.sh"
    local loaded=0

    case "${RECIPE_HOOK_PROFILE:-}" in
        launch)
            if [ -f "$CORE_DIR/$launch_mod" ]; then
                recipe_hooks::_source "$launch_mod"
                loaded=1
            elif [ -f "$CORE_DIR/$mod" ]; then
                recipe_hooks::_source "$mod"
                loaded=1
            fi
            [ "$loaded" -eq 1 ] || recipe_hooks::die "Launch-Modul fehlt: $launch_mod oder $mod"
            ;;
        install|repair)
            if [ -f "$CORE_DIR/$install_mod" ]; then
                recipe_hooks::_source "$install_mod"
                loaded=1
            elif [ -f "$CORE_DIR/$mod" ]; then
                recipe_hooks::_source "$mod"
                loaded=1
            fi
            # Optional when recipe.yml uses declarative install_steps only.
            if [ "$loaded" -eq 0 ] && ! grep -qE '^install_steps:' "$RECIPE_YML" 2>/dev/null; then
                recipe_hooks::die "Install-Modul fehlt: $install_mod oder $mod"
            fi
            ;;
        *)
            if [ -f "$CORE_DIR/$mod" ]; then
                recipe_hooks::_source "$mod"
            fi
            ;;
    esac
}

recipe_hooks::force_prefix() {
    export WINEPREFIX="$DATA_ROOT/prefix"
    export WINE_PREFIX="$DATA_ROOT/prefix"
}

recipe_hooks::_mono_missing() {
    local p="${WINEPREFIX:-}"
    [ -n "$p" ] || return 0
    if type recipe_dotnet::installed >/dev/null 2>&1; then
        recipe_dotnet::installed && return 1
        return 0
    fi
    [ -f "$p/drive_c/windows/mono/mono-2.0/bin/libmono-2.0-x86.dll" ] \
        || [ -f "$p/drive_c/windows/mono/mono-2.0/bin/libmono-2.0-x86_64.dll" ] \
        && return 1
    return 0
}

recipe_hooks::hint_wine_popup() {
    type output::user_action >/dev/null 2>&1 && output::user_action \
        "Wine-Fenster möglich — „Wine-Mono-Installation“: Installieren klicken; „Konfiguration wird aktualisiert“: OK/warten"
}

recipe_hooks::_with_mscoree_blocked() {
    local old="${WINEDLLOVERRIDES:-}"
    if recipe_hooks::_mono_missing; then
        export WINEDLLOVERRIDES="${old:+${old};}mscoree=d;mshtml=d;winemenubuilder.exe=d"
    fi
    "$@"
    local rc=$?
    export WINEDLLOVERRIDES="$old"
    return "$rc"
}

recipe_hooks::wine_wrappers() {
    wine() {
        recipe_wine_silent::run recipe_hooks::_with_mscoree_blocked wine_runtime::wine "$@"
    }
    winetricks() { wine_runtime::winetricks "$@"; }
    wineboot() {
        recipe_wine_silent::run recipe_hooks::_with_mscoree_blocked wine_runtime::wineboot "$@"
    }
    wineserver() { wine_runtime::wineserver "$@"; }
}

recipe_hooks::runtime_init() {
    export WINE_METHOD="${WINE_METHOD:-${RECIPE_RUNTIME:-proton-ge}}"
    wine_runtime::reset 2>/dev/null || true
    wine_runtime::init || return 1
    wine_runtime::export_env
    return 0
}

recipe_hooks::log_setup() {
    local prefix="${1:-${RECIPE_ID:-app}}"
    LOG_DIR="$(wine_software_logs_dir)"
    mkdir -p "$LOG_DIR"
    TIMESTAMP_ISO=$(date +%Y-%m-%d_%H-%M-%S)
    LOG_FILE="$LOG_DIR/${prefix}_${TIMESTAMP_ISO}.log"
    ERROR_LOG="$LOG_DIR/${prefix}_${TIMESTAMP_ISO}_errors.log"
    export LOG_FILE ERROR_LOG LOG_DIR TIMESTAMP_ISO
    if type recipe_wine_silent::session_begin >/dev/null 2>&1 \
        && [ "${RECIPE_WINE_SILENT:-}" = "1" ]; then
        recipe_wine_silent::session_begin
        trap 'recipe_wine_silent::session_end 2>/dev/null || true' EXIT
    fi
}

recipe_hooks::log_err() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE:-/dev/stderr}" >> "${ERROR_LOG:-/dev/null}"
}

recipe_hooks::emit_log_paths() {
    echo "RECIPE_LOG_FILE=${LOG_FILE:-}"
    echo "RECIPE_ERROR_LOG=${ERROR_LOG:-}"
}

recipe_hooks::run_exe_installer() {
    local exe="${1:-${RECIPE_INSTALLER_PATH:-}}"
    local log="${LOG_FILE:-/dev/null}"
    [ -f "$exe" ] || {
        recipe_hooks::log_err "Installer fehlt: ${exe:-?}"
        return 1
    }
    output::step "Installer: $(basename "$exe")"
    wine "$exe" /S >>"$log" 2>&1 || wine "$exe" /quiet /norestart >>"$log" 2>&1 \
        || wine "$exe" >>"$log" 2>&1 || return 1
    output::success "Installer ausgeführt"
    return 0
}

recipe_hooks::state_file() {
    echo "${DATA_ROOT}/recipe.env"
}

recipe_hooks::state_set() {
    recipe_hooks::_source env-file.sh 2>/dev/null || true
    env_file_set "$(recipe_hooks::state_file)" "$1" "$2"
}

recipe_hooks::state_get() {
    recipe_hooks::_source env-file.sh 2>/dev/null || true
    env_file_get "$(recipe_hooks::state_file)" "$1"
}

recipe_hooks::install_prepare_source() {
    recipe_install::prepare_source "$RECIPE_YML" "$DATA_ROOT"
}

recipe_hooks::install_prefix() {
    output::step "Wine initialisieren"
    recipe_hooks::runtime_init || return 1
    output::success "$(wine_runtime::describe 2>/dev/null || echo "Wine bereit")"
    output::step "Wine-Prefix"
    mkdir -p "$(dirname "$WINEPREFIX")"
    recipe_prefix::ensure "$WINEPREFIX" || return 1
    output::success "Prefix bereit"
    return 0
}

recipe_hooks::winetricks_packages() {
    local yml="${1:-$RECIPE_YML}" raw
    raw="$(grep -E '^winetricks:' "$yml" 2>/dev/null | head -1)" || return 0
    raw="${raw#winetricks:}"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw#\[}"
    raw="${raw%\]}"
    raw="${raw//,/ }"
    # shellcheck disable=SC2086
    set -- $raw
    local pkg
    for pkg in "$@"; do
        pkg="${pkg#"${pkg%%[![:space:]]*}"}"
        pkg="${pkg%"${pkg##*[![:space:]]}"}"
        pkg="${pkg#\"}"
        pkg="${pkg%\"}"
        [ -n "$pkg" ] && echo "$pkg"
    done
}

recipe_hooks::install_winetricks_from_recipe() {
    local pkg pct=20 wt_ok=0
    recipe_winetricks::stabilize_prefix
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        pct=$((pct + 10))
        [ "$pct" -gt 90 ] && pct=90
        output::progress "$pct" "winetricks: $pkg"
        output::step "winetricks: $pkg"
        if recipe_winetricks::run "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$pkg"; then
            output::success "$pkg"
        else
            recipe_hooks::log_err "winetricks $pkg fehlgeschlagen"
            wt_ok=1
        fi
    done < <(recipe_hooks::winetricks_packages)
    output::step "Windows 10 (Registry)"
    if recipe_win10::ensure; then
        output::success "win10"
    else
        recipe_hooks::log_err "win10 Registry fehlgeschlagen"
        wt_ok=1
    fi
    [ "$wt_ok" -eq 0 ]
}

recipe_hooks::find_exe() {
    local root="${1:-}"
    local glob="${2:-}"
    [ -n "$root" ] && [ -d "$root" ] || return 1
    [ -n "$glob" ] || glob="$(recipe_get "$RECIPE_YML" exe_glob 2>/dev/null || echo "**/*.exe")"
    local name="${glob##*/}"
    find "$root" -name "$name" -type f 2>/dev/null | head -1
}

recipe_hooks::fixed_installer_dir() {
    local raw resolved
    raw="$(recipe_get "$RECIPE_YML" installer_dir 2>/dev/null || true)"
    [ -n "$raw" ] || return 1
    resolved="$(recipe_hooks::paths_expand_tokens "$raw")"
    [ -d "$resolved" ] || return 1
    cd "$resolved" && pwd
}

recipe_hooks::require_portable_source() {
    if [ "${RECIPE_SOURCE_TYPE:-}" != "portable_folder" ]; then
        recipe_hooks::log_err "Erwartet portable_folder — erhalten: ${RECIPE_SOURCE_TYPE:-?}"
        return 1
    fi
    return 0
}

recipe_hooks::validate_prefix() {
    local failures=0
    if recipe_validate::prefix_initialized "$WINEPREFIX"; then
        recipe_validate::ok "Wine-Prefix ($WINEPREFIX)"
    else
        recipe_validate::fail "Wine-Prefix fehlt — installieren"
        failures=$((failures + 1))
    fi
    return "$failures"
}

recipe_hooks::validate_work_root() {
    local key="${1:-WORK_ROOT}" failures=0 root
    root="$(recipe_hooks::state_get "$key" 2>/dev/null || true)"
    if [ -n "$root" ] && [ -d "$root" ]; then
        recipe_validate::ok "Arbeitsordner: $root"
    else
        recipe_validate::fail "Arbeitsordner fehlt ($key in recipe.env)"
        failures=$((failures + 1))
    fi
    return "$failures"
}
