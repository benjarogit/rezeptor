#!/usr/bin/env bash
# Installations-Workflow: Quelltyp → Action-Kette (extract → detect → deploy → Fix).
#
# Export nach recipe_install::prepare_source:
#   RECIPE_SOURCE_TYPE  portable_folder | installer_file | installer_folder
#   RECIPE_WORK_ROOT    Ordner mit installiertem Inhalt
#   RECIPE_INSTALLER_PATH  (bei installer_*)

recipe_install::_validate_path() {
    local path="$1"
    local label="${2:-path}"
    if type security::validate_path >/dev/null 2>&1; then
        if ! security::validate_path "$path"; then
            recipe_install::_err "Unsafe $label (blocked by security policy): $path"
            return 1
        fi
    fi
    if [ -z "$path" ]; then
        recipe_install::_err "Missing $label"
        return 1
    fi
    if [[ "$path" == *".."* ]]; then
        recipe_install::_err "Unsafe $label (path traversal): $path"
        return 1
    fi
    return 0
}

recipe_install::_step() {
    type output::step >/dev/null 2>&1 && output::step "$1" || echo "→ $1"
}

recipe_install::_info() {
    type output::info >/dev/null 2>&1 && output::info "$1" || echo "$1"
}

recipe_install::_success() {
    type output::success >/dev/null 2>&1 && output::success "$1" || echo "OK: $1"
}

recipe_install::_err() {
    echo "ERROR: $*" >&2
    type log_err >/dev/null 2>&1 && log_err "$*"
}

recipe_install::normalize_portable_root() {
    local root="$1"
    [ -n "$root" ] && [ -d "$root" ] || return 1
    root="$(cd "$root" && pwd)"
    case "$(basename "$root")" in
        Steuersoftware*) root="$(cd "$(dirname "$root")" && pwd)" ;;
    esac
    echo "$root"
}

recipe_install::looks_portable() {
    local root="$1"
    [ -d "$root" ] || return 1
    [ -f "$root/start.exe" ] || [ -f "$root/Start.exe" ] && return 0
    find "$root" -maxdepth 1 -type d -name 'Steuersoftware*' 2>/dev/null | grep -q .
}

recipe_install::detect_content_type() {
    local root="$1"
    if recipe_install::looks_portable "$root"; then
        echo "portable_folder"
        return 0
    fi
    if recipe_deploy::detect_installer "$root" >/dev/null 2>&1; then
        echo "installer_folder"
        return 0
    fi
    return 1
}

recipe_install::_resolve_input() {
    if [ -n "${RECIPE_INSTALLER_PATH:-}" ] && [ -f "${RECIPE_INSTALLER_PATH}" ]; then
        echo "installer_file"
        return 0
    fi
    if [ -n "${RECIPE_ARCHIVE_PATH:-}" ] && [ -f "${RECIPE_ARCHIVE_PATH}" ]; then
        echo "archive"
        return 0
    fi
    if [ -n "${RECIPE_YML:-}" ] && [ -f "${RECIPE_YML}" ]; then
        local sk
        sk="$(recipe_get "$RECIPE_YML" source_kind 2>/dev/null || true)"
        if [ "$sk" = "fixed_path" ]; then
            echo "fixed_path"
            return 0
        fi
    fi
    if [ -n "${RECIPE_SOURCE_ROOT:-}" ] && [ -d "${RECIPE_SOURCE_ROOT}" ]; then
        echo "folder"
        return 0
    fi
    return 1
}

recipe_install::_expect_portable() {
    local install_type="$1"
    case "$install_type" in
        portable_launch|portable_bootstrap|game_portable) return 0 ;;
    esac
    return 1
}

recipe_install::_expect_installer() {
    local install_type="$1"
    case "$install_type" in
        installer_offline|game_install|adobe_offline) return 0 ;;
    esac
    return 1
}

recipe_install::_validate_install_type() {
    local install_type="$1"
    case "$install_type" in
        installer_offline|portable_launch|portable_bootstrap|game_install|game_portable|adobe_offline|portable)
            return 0
            ;;
    esac
    recipe_install::_err "Unbekannter install_type: $install_type"
    return 1
}

recipe_install::_validate_source_kind() {
    local source_kind="$1"
    case "$source_kind" in
        folder|installer|archive|fixed_path) return 0 ;;
    esac
    recipe_install::_err "Unbekannter source_kind: $source_kind"
    return 1
}

recipe_install::prepare_source() {
    local recipe_yml="${1:?recipe.yml}"
    local data_root="${2:?data_root}"
    local install_type="" source_kind="" deploy_mode="" target_dir=""
    local input="" work_root="" resolved="" installer=""

    export RECIPE_YML="$recipe_yml"
    install_type="$(recipe_get "$recipe_yml" install_type 2>/dev/null || echo portable_launch)"
    source_kind="$(recipe_get "$recipe_yml" source_kind 2>/dev/null || echo folder)"
    recipe_install::_validate_install_type "$install_type" || return 1
    recipe_install::_validate_source_kind "$source_kind" || return 1
    deploy_mode="${RECIPE_DEPLOY_MODE:-$(recipe_get "$recipe_yml" deploy_mode 2>/dev/null || echo copy)}"
    target_dir="${RECIPE_TARGET_DIR:-}"
    if [ -n "$target_dir" ]; then
        target_dir="${target_dir/#\~/$HOME}"
        target_dir="$(printf '%s' "$target_dir" | sed 's|^//|/|')"
        case "$target_dir" in
            //*) target_dir="${HOME}/${target_dir#//}" ;;
        esac
    fi

    input="$(recipe_install::_resolve_input)" || {
        recipe_install::_err "Keine Quelle — Ordner, Installer, Archiv oder installer_dir (fixed_path)"
        return 1
    }

    case "$input" in
        archive)
            work_root="$(recipe_source::staging_dir "$data_root" "${RECIPE_ID:-app}")/extract"
            rm -rf "$work_root" 2>/dev/null || true
            mkdir -p "$work_root"
            recipe_install::_validate_path "${RECIPE_ARCHIVE_PATH}" archive || return 1
            recipe_install::_step "Archiv entpacken"
            recipe_source::extract_archive "${RECIPE_ARCHIVE_PATH}" "$work_root" || {
                recipe_install::_err "Archiv konnte nicht entpackt werden"
                return 1
            }
            resolved="$(recipe_install::detect_content_type "$work_root")" || {
                recipe_install::_err "Archivinhalt unklar — weder Portable noch Installer erkannt"
                return 1
            }
            ;;
        installer_file)
            installer="${RECIPE_INSTALLER_PATH}"
            recipe_install::_validate_path "$installer" installer || return 1
            work_root="$(cd "$(dirname "$installer")" && pwd)"
            resolved="installer_file"
            ;;
        fixed_path)
            local raw dir
            raw="$(recipe_get "$recipe_yml" installer_dir 2>/dev/null || true)"
            [ -n "$raw" ] || {
                recipe_install::_err "fixed_path ohne installer_dir in recipe.yml"
                return 1
            }
            dir="${raw//\{repo\}/${PROJECT_ROOT:-}}"
            dir="${dir//\{data_root\}/${data_root}}"
            dir="${dir/#\~/$HOME}"
            [ -d "$dir" ] || {
                recipe_install::_err "Installer-Ordner fehlt: $dir"
                return 1
            }
            work_root="$(cd "$dir" && pwd)"
            if recipe_install::_expect_installer "$install_type"; then
                resolved="installer_folder"
            else
                resolved="$(recipe_install::detect_content_type "$work_root")" || resolved="installer_folder"
            fi
            ;;
        folder)
            work_root="$(recipe_install::normalize_portable_root "${RECIPE_SOURCE_ROOT}")" || {
                recipe_install::_err "Quellordner ungültig: ${RECIPE_SOURCE_ROOT}"
                return 1
            }
            if recipe_install::_expect_portable "$install_type"; then
                resolved="portable_folder"
            elif recipe_install::_expect_installer "$install_type"; then
                resolved="installer_folder"
            else
                resolved="$(recipe_install::detect_content_type "$work_root")" || resolved="portable_folder"
            fi
            ;;
    esac

    if [ "$resolved" = "installer_folder" ]; then
        recipe_install::_step "Installer im Ordner suchen"
        installer="$(recipe_deploy::detect_installer "$work_root")" || {
            recipe_install::_err "Keine Installationsdatei im Ordner — setup.exe / install.exe / *.msi?"
            return 1
        }
        recipe_install::_info "Installer: $(basename "$installer")"
        resolved="installer_file"
    fi

    if [ "$resolved" = "portable_folder" ]; then
        recipe_install::_validate_path "$work_root" work_root || return 1
        if [ -n "$target_dir" ]; then
            recipe_install::_validate_path "$target_dir" target_dir || return 1
            recipe_install::_step "Portable installieren (Quelle → Ziel)"
            recipe_install::_info "Quelle: $work_root"
            recipe_install::_info "Ziel: $target_dir"
            work_root="$(recipe_deploy::sync_portable "$work_root" "$target_dir" "$deploy_mode")" || {
                recipe_install::_err "Kopieren nach $target_dir fehlgeschlagen"
                return 1
            }
            recipe_install::_success "Installiert unter $work_root"
        fi
    fi

    if [ "$resolved" = "installer_file" ] && [ -z "$installer" ] && [ -n "${RECIPE_INSTALLER_PATH:-}" ]; then
        installer="${RECIPE_INSTALLER_PATH}"
    fi

    export RECIPE_SOURCE_TYPE="$resolved"
    export RECIPE_WORK_ROOT="$work_root"
    [ -n "$installer" ] && export RECIPE_INSTALLER_PATH="$installer"
    return 0
}

recipe_install::apply_fix() {
    local fix="${1:-${RECIPE_FIX_ROOT:-}}"
    local log="${2:-${LOG_FILE:-/dev/null}}"
    local wine_cmd="${3:-wine}"

    [ -n "$fix" ] || return 0
    [ -e "$fix" ] || {
        recipe_install::_err "Fix-Pfad existiert nicht: $fix"
        return 1
    }

    if [ -f "$fix" ] && [[ "${fix,,}" == *.exe ]]; then
        recipe_install::_step "Patch-Installer: $(basename "$fix")"
        "$wine_cmd" "$fix" /S >>"$log" 2>&1 \
            || "$wine_cmd" "$fix" /quiet /norestart >>"$log" 2>&1 \
            || "$wine_cmd" "$fix" >>"$log" 2>&1 || {
            recipe_install::_err "Patch-Installer fehlgeschlagen: $fix"
            return 1
        }
        recipe_install::_success "Patch-Installer ausgeführt"
        return 0
    fi

    if [ -d "$fix" ]; then
        recipe_install::_step "Patch-Ordner: $(basename "$fix")"
        local ran=0 ok=0 f
        shopt -s nullglob 2>/dev/null || true
        for f in "$fix"/*.exe "$fix"/*/*.exe; do
            [ -f "$f" ] || continue
            ran=1
            if "$wine_cmd" "$f" /S >>"$log" 2>&1 || "$wine_cmd" "$f" >>"$log" 2>&1; then
                ok=$((ok + 1))
            else
                recipe_install::_err "Patch-EXE fehlgeschlagen: $f"
            fi
        done
        shopt -u nullglob 2>/dev/null || true
        if [ "$ran" -eq 0 ]; then
            if command -v rsync >/dev/null 2>&1; then
                rsync -a "$fix/" "${RECIPE_WORK_ROOT:-.}/" >>"$log" 2>&1 || {
                    recipe_install::_err "Patch-Ordner kopieren fehlgeschlagen"
                    return 1
                }
            else
                cp -a "$fix/." "${RECIPE_WORK_ROOT:-.}/" >>"$log" 2>&1 || return 1
            fi
        elif [ "$ok" -eq 0 ]; then
            recipe_install::_err "Alle Patch-EXEs fehlgeschlagen"
            return 1
        fi
        recipe_install::_success "Patch-Ordner verarbeitet"
        return 0
    fi

    recipe_install::_err "Fix muss .exe oder Ordner sein: $fix"
    return 1
}
