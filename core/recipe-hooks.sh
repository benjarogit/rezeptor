#!/usr/bin/env bash
# Rezeptor — einheitlicher Einstieg für alle Recipe-Hooks (install/launch/validate/repair/kill).
#
# Jedes Hook-Skript:
#   RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$RECIPE_DIR/../../core/recipe-hooks.sh"
#   recipe_hooks::load install   # launch | validate | repair | kill | update | minimal
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
    # PROJECT_ROOT: Env, sonst nach oben wandern bis core/ existiert
    # (recipes/<id> und recipes/community/<id>).
    if [ -z "${PROJECT_ROOT:-}" ]; then
        local _walk="$RECIPE_DIR"
        PROJECT_ROOT=""
        while [ "$_walk" != "/" ]; do
            if [ -d "$_walk/core" ] && [ -f "$_walk/core/recipe-hooks.sh" ]; then
                PROJECT_ROOT="$_walk"
                break
            fi
            _walk="$(cd "$_walk/.." && pwd)"
        done
        [ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(cd "$RECIPE_DIR/../.." && pwd)"
    fi
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
    # Rezept-Optionen (Medizin-Menü) → DATA_ROOT/options.env
    if [ -n "${DATA_ROOT:-}" ] && [ -f "${DATA_ROOT}/options.env" ]; then
        recipe_hooks::_source env-file.sh 2>/dev/null || true
        if type env_file_load_export >/dev/null 2>&1; then
            env_file_load_export "${DATA_ROOT}/options.env" 2>/dev/null || true
        fi
    fi

    case "$profile" in
        minimal) ;;
        install)
            recipe_hooks::_source security.sh
            recipe_hooks::_source env-file.sh
            recipe_hooks::_source wine-runtime.sh
            recipe_hooks::_source recipe-prefix.sh
            recipe_hooks::_source recipe-deploy.sh
            recipe_hooks::_source recipe-source.sh
            recipe_hooks::_source recipe-iso.sh
            recipe_hooks::_source recipe-install.sh
            recipe_hooks::_source recipe-updates.sh
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
        update)
            recipe_hooks::_source security.sh
            recipe_hooks::_source env-file.sh
            recipe_hooks::_source wine-runtime.sh
            recipe_hooks::_source recipe-prefix.sh
            recipe_hooks::_source recipe-source.sh
            recipe_hooks::_source recipe-iso.sh
            recipe_hooks::_source recipe-install.sh
            recipe_hooks::_source recipe-updates.sh
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
            recipe_hooks::_source recipe-guard.sh
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
            recipe_hooks::die "Unbekanntes Profil: $profile (minimal|install|launch|validate|repair|kill|update)"
            ;;
    esac
    recipe_hooks::load_app_module
}

recipe_hooks::load_app_module() {
    local mod="recipe-${RECIPE_ID}.sh"
    local launch_mod="recipe-${RECIPE_ID}-launch.sh"
    local install_mod="recipe-${RECIPE_ID}-install.sh"
    local loaded=0
    local runtime=""

    case "${RECIPE_HOOK_PROFILE:-}" in
        launch)
            if [ -f "$CORE_DIR/$launch_mod" ]; then
                recipe_hooks::_source "$launch_mod"
                loaded=1
            elif [ -f "$CORE_DIR/$mod" ]; then
                recipe_hooks::_source "$mod"
                loaded=1
            fi
            # launch.sh ist der Einstieg — Core-Modul nur optional (Photoshop/WISO).
            # Steam/Trainer/Portable brauchen keines (sonst: „Launch-Modul fehlt“).
            return 0
            ;;
        install|repair|update)
            if [ -f "$CORE_DIR/$install_mod" ]; then
                recipe_hooks::_source "$install_mod"
                loaded=1
            elif [ -f "$CORE_DIR/$mod" ]; then
                recipe_hooks::_source "$mod"
                loaded=1
            fi
            # Optional when recipe.yml uses declarative install_steps only.
            if [ "$loaded" -eq 0 ] && [ "${RECIPE_HOOK_PROFILE:-}" != "update" ] \
                && ! grep -qE '^install_steps:' "$RECIPE_YML" 2>/dev/null; then
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
        "Es können Wine-Fenster erscheinen — bei „Wine-Mono-Installation“ auf Installieren klicken; bei „Konfiguration wird aktualisiert“ OK wählen oder kurz warten"
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
    : >"$LOG_FILE"
    : >"$ERROR_LOG"
    {
        echo "=== Rezeptor session ==="
        echo "time=$(date -Iseconds 2>/dev/null || date)"
        echo "recipe=${RECIPE_ID:-} name=${RECIPE_NAME:-}"
        echo "hook_profile=${RECIPE_HOOK_PROFILE:-}"
        echo "data_root=${DATA_ROOT:-}"
        echo "wineprefix=${WINEPREFIX:-}"
        echo "session=${LAUNCHER_SESSION_ID:-}"
        echo "host=$(uname -a 2>/dev/null || true)"
        [ -f "${PROJECT_ROOT:-}/VERSION" ] && echo "rezeptor=$(tr -d '[:space:]' <"${PROJECT_ROOT}/VERSION")"
        echo "========================"
    } >>"$LOG_FILE"
    if type recipe_wine_silent::session_begin >/dev/null 2>&1 \
        && [ "${RECIPE_WINE_SILENT:-}" = "1" ]; then
        recipe_wine_silent::session_begin
        trap 'recipe_wine_silent::session_end 2>/dev/null || true' EXIT
    fi
}

recipe_hooks::log_err() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE:-/dev/stderr}" >> "${ERROR_LOG:-/dev/null}"
}

recipe_hooks::log_warn() {
    echo "[$(date '+%H:%M:%S')] WARN: $*" | tee -a "${LOG_FILE:-/dev/stderr}" >> "${ERROR_LOG:-/dev/null}"
}

recipe_hooks::emit_log_paths() {
    echo "RECIPE_LOG_FILE=${LOG_FILE:-}"
    echo "RECIPE_ERROR_LOG=${ERROR_LOG:-}"
    # GUI kann die Pfade anzeigen; Tail hilft bei Support ohne stille Adobe-Logs
    if [ -n "${ERROR_LOG:-}" ] && [ -f "${ERROR_LOG}" ] && [ -s "${ERROR_LOG}" ]; then
        echo "RECIPE_ERROR_LOG_TAIL_BEGIN"
        tail -n 80 "$ERROR_LOG" 2>/dev/null || true
        echo "RECIPE_ERROR_LOG_TAIL_END"
    fi
}

# Inno Setup /LANG= Name aus Host-Locale (ohne /LANG erscheint der Sprachdialog
# auch bei /VERYSILENT — typisch ElAmigos/Inno).
recipe_hooks::installer_lang() {
    local loc="${LC_MESSAGES:-${LANG:-${LC_ALL:-en_US.UTF-8}}}"
    loc="${loc%%.*}"
    loc="${loc%%_*}"
    loc="${loc,,}"
    case "$loc" in
        de) echo german ;;
        fr) echo french ;;
        es) echo spanish ;;
        it) echo italian ;;
        pl) echo polish ;;
        pt) echo brazilianportuguese ;;
        ru) echo russian ;;
        nl) echo dutch ;;
        cs) echo czech ;;
        hu) echo hungarian ;;
        tr) echo turkish ;;
        uk) echo ukrainian ;;
        *) echo english ;;
    esac
}

# Installer-Familie: inno | nsis | msi | unknown (ein Lauf, keine Flag-Kaskade).
recipe_hooks::installer_family() {
    local exe="${1:-}"
    [ -n "$exe" ] && [ -f "$exe" ] || {
        echo unknown
        return 0
    }
    case "${exe,,}" in
        *.msi)
            echo msi
            return 0
            ;;
    esac
    # Prozesssubstitution statt $(head …): Command-Substitution verwirft NULL-Bytes
    # und bash warnt dabei sichtbar in der GUI-Live-Ausgabe.
    if grep -aq 'Inno Setup' < <(head -c 524288 "$exe" 2>/dev/null); then
        echo inno
        return 0
    fi
    if grep -aqi 'Nullsoft\.NSIS\|Nullsoft Install System' \
        < <(head -c 524288 "$exe" 2>/dev/null); then
        echo nsis
        return 0
    fi
    echo unknown
}

# Windows-Installationsziel für Inno /DIR= (unter Prefix drive_c).
recipe_hooks::installer_wine_dir() {
    if [ -n "${RECIPE_INSTALLER_DIR:-}" ]; then
        printf '%s\n' "$RECIPE_INSTALLER_DIR"
        return 0
    fi
    case "${RECIPE_ID:-}" in
        halo-campaign-evolved)
            echo 'C:\Games\HaloCampaignEvolved'
            ;;
        *)
            if [ -n "${RECIPE_ID:-}" ]; then
                printf 'C:\\Games\\%s\n' "$RECIPE_ID"
            fi
            ;;
    esac
}

# Offline-EXE: genau ein Aufruf je Familie — kein ||-Stapel (sonst mehrere GUIs bei Abbruch).
recipe_hooks::run_exe_silent() {
    local exe="$1"
    local log="${2:-${LOG_FILE:-/dev/null}}"
    local wine_cmd="${3:-wine}"
    local lang dir base family wine_dir rc=0
    [ -f "$exe" ] || return 1
    lang="$(recipe_hooks::installer_lang)"
    family="$(recipe_hooks::installer_family "$exe")"
    dir="$(cd "$(dirname "$exe")" && pwd)"
    base="$(basename "$exe")"
    wine_dir="$(recipe_hooks::installer_wine_dir || true)"

    type output::info >/dev/null 2>&1 && output::info "Installer-Typ: $family" || true

    (
        cd "$dir" || exit 1
        case "$family" in
            inno)
                if [ -n "$wine_dir" ]; then
                    "$wine_cmd" "$base" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART \
                        "/LANG=$lang" "/DIR=$wine_dir" >>"$log" 2>&1
                else
                    "$wine_cmd" "$base" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART \
                        "/LANG=$lang" >>"$log" 2>&1
                fi
                ;;
            msi)
                "$wine_cmd" msiexec /i "$base" /qn /norestart >>"$log" 2>&1
                ;;
            nsis)
                "$wine_cmd" "$base" /S >>"$log" 2>&1
                ;;
            *)
                # Unbekannt: einmal NSIS-übliches /S — kein GUI-Fallback-Stapel
                "$wine_cmd" "$base" /S >>"$log" 2>&1
                ;;
        esac
    ) || rc=$?

    if [ "$rc" -ne 0 ]; then
        type output::error >/dev/null 2>&1 \
            && output::error "Installer abgebrochen oder still fehlgeschlagen (exit $rc)" \
            || echo "ERROR: Installer fehlgeschlagen (exit $rc)" >&2
        return "$rc"
    fi
    return 0
}

recipe_hooks::run_exe_installer() {
    local exe="${1:-${RECIPE_INSTALLER_PATH:-}}"
    local log="${LOG_FILE:-/dev/null}"
    [ -f "$exe" ] || {
        recipe_hooks::log_err "Installer fehlt: ${exe:-?}"
        return 1
    }
    output::step "Installer: $(basename "$exe")"
    recipe_hooks::run_exe_silent "$exe" "$log" wine || return 1
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

# Deinstallation: Desktop + gewählter DATA_ROOT + kanonischer data_root (data_root.path).
# Portable-/Spielordner außerhalb von DATA_ROOT bleiben unberührt (z. B. WISO-Portable).
recipe_hooks::purge_recipe_data() {
    local canonical="" chosen="${DATA_ROOT:-}"
    local raw=""

    recipe_hooks::_source recipe-desktop.sh 2>/dev/null || true
    if type recipe_desktop::remove >/dev/null 2>&1; then
        recipe_desktop::remove || true
    fi

    raw="$(recipe_get "$RECIPE_YML" data_root 2>/dev/null || true)"
    if [ -n "$raw" ]; then
        if type paths_expand >/dev/null 2>&1; then
            canonical="$(paths_expand "$raw")"
        else
            canonical="$(recipe_hooks::paths_expand_tokens "$raw" 2>/dev/null || true)"
        fi
    fi
    [ -n "$canonical" ] || canonical="$(recipe_data_root "${RECIPE_ID:-}")"

    recipe_hooks::_purge_dir_safe() {
        local d="${1:-}"
        [ -n "$d" ] && [ -d "$d" ] || return 0
        # Nur offensichtlich fatale Ziele blockieren
        if [ "$d" = "/" ] || [ "$d" = "$HOME" ] || [ "$d" = "/home" ] || [ "$d" = "/usr" ] || [ "$d" = "/etc" ]; then
            echo "ERROR: unsicherer Löschpfad: $d" >&2
            return 1
        fi
        rm -rf "$d"
        return 0
    }

    # Vom Nutzer gewähltes Ziel nur löschen, wenn Rezeptor dort Daten angelegt hat.
    # Sonst würde ein Tippfehler (z. B. Spiele-Sammelordner statt Spielordner)
    # fremde Daten mitnehmen.
    recipe_hooks::_is_rezeptor_data_dir() {
        local d="${1:-}"
        [ -n "$d" ] && [ -d "$d" ] || return 1
        [ -e "$d/recipe.env" ] && return 0
        [ -e "$d/data_root.path" ] && return 0
        [ -e "$d/iso-mounts.env" ] && return 0
        [ -d "$d/prefix" ] && return 0
        [ -d "$d/staging" ] && return 0
        # Leerer Ordner: nichts fremdes zu verlieren
        [ -z "$(ls -A "$d" 2>/dev/null)" ] && return 0
        return 1
    }

    if [ -n "$chosen" ] && [ -d "$chosen" ]; then
        if recipe_hooks::_is_rezeptor_data_dir "$chosen"; then
            recipe_hooks::_purge_dir_safe "$chosen" || true
        else
            local keep="Ordner behalten (keine Rezeptor-Daten gefunden): $chosen"
            type output::warning >/dev/null 2>&1 \
                && output::warning "$keep" \
                || echo "WARN: $keep" >&2
        fi
    fi
    if [ -n "$canonical" ] && [ -d "$canonical" ]; then
        if [ -z "$chosen" ] || [ "$canonical" != "$chosen" ]; then
            recipe_hooks::_purge_dir_safe "$canonical" || true
        fi
    fi
    return 0
}
