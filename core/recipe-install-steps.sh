#!/usr/bin/env bash
# Declarative install_steps runner — reads recipe.yml via scripts/recipe-yaml-read.py
#
# Usage (from install.sh after recipe_hooks::load install):
#   recipe_install_steps::run
#
# Optional: RECIPE_INSTALL_STEPS_FILE for tests.

recipe_install_steps::_reader() {
    local root="${PROJECT_ROOT:-}"
    if [ -z "$root" ] && [ -n "${RECIPE_DIR:-}" ]; then
        root="$(cd "$RECIPE_DIR/../.." && pwd)"
    fi
    echo "${root}/scripts/recipe-yaml-read.py"
}

recipe_install_steps::_expand() {
    local p="${1:-}"
    [ -n "$p" ] || return 0
    p="${p//\{repo\}/${PROJECT_ROOT:-}}"
    p="${p//\{data_root\}/${DATA_ROOT:-}}"
    p="${p//\{recipe\}/${RECIPE_DIR:-}}"
    p="${p/#\~/$HOME}"
    echo "$p"
}

recipe_install_steps::_json_get() {
    # Usage: _json_get '{"type":"a","x":"y"}' x
    local json="$1" key="$2"
    python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2],""); print(v if not isinstance(v, (dict,list)) else json.dumps(v))' "$json" "$key"
}

recipe_install_steps::_json_get_list() {
    local json="$1" key="$2"
    python3 -c '
import json,sys
d=json.loads(sys.argv[1])
v=d.get(sys.argv[2], [])
if isinstance(v, list):
    for x in v:
        print(x)
elif v:
    print(v)
' "$json" "$key"
}

recipe_install_steps::call_module() {
    local name="$1"
    local fn="${name%%::*}"
    local meth="${name#*::}"
    if [ "$fn" = "$name" ] || [ -z "$meth" ]; then
        recipe_hooks::log_err "module: erwartet namespace::function (ist: $name)"
        return 1
    fi
    if ! type "$name" >/dev/null 2>&1; then
        recipe_hooks::log_err "module: Funktion fehlt: $name"
        return 1
    fi
    "$name"
}

recipe_install_steps::copy_asset() {
    local src dest mode
    src="$(recipe_install_steps::_expand "$1")"
    dest="$(recipe_install_steps::_expand "$2")"
    mode="${3:-755}"
    [ -n "$src" ] && [ -f "$src" ] || {
        # Relative to RECIPE_DIR
        if [ -f "${RECIPE_DIR}/$1" ]; then
            src="${RECIPE_DIR}/$1"
        else
            recipe_hooks::log_err "copy_asset: Quelle fehlt: $1"
            return 1
        fi
    }
    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest"
    chmod "$mode" "$dest" 2>/dev/null || true
    output::success "Asset: $(basename "$dest")"
}

recipe_install_steps::run_winetricks_list() {
    local pkg pct=20 wt_ok=0
    recipe_winetricks::stabilize_prefix
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            vcrun2019|vcrun2015)
                output::step "Visual C++ Runtime ($pkg)"
                if recipe_vcrun::ensure "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log"; then
                    output::success "$pkg"
                else
                    recipe_hooks::log_err "$pkg fehlgeschlagen"
                    wt_ok=1
                fi
                continue
                ;;
            dotnet48|dotnet40)
                output::step "Wine-Mono / .NET ($pkg)"
                if recipe_dotnet::ensure "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log"; then
                    output::success "$pkg"
                else
                    recipe_hooks::log_err "$pkg fehlgeschlagen"
                    wt_ok=1
                fi
                continue
                ;;
            win10)
                output::step "Windows 10 (Registry)"
                if recipe_win10::ensure; then
                    output::success "win10"
                else
                    recipe_hooks::log_err "win10 fehlgeschlagen"
                    wt_ok=1
                fi
                continue
                ;;
        esac
        pct=$((pct + 8))
        [ "$pct" -gt 90 ] && pct=90
        output::progress "$pct" "winetricks: $pkg"
        output::step "winetricks: $pkg"
        if recipe_winetricks::run "${LOG_DIR}/winetricks_${pkg}_${TIMESTAMP_ISO}.log" "$pkg"; then
            output::success "$pkg"
        else
            recipe_hooks::log_err "winetricks $pkg fehlgeschlagen"
            wt_ok=1
        fi
    done
    [ "$wt_ok" -eq 0 ]
}

recipe_install_steps::step() {
    local json="$1"
    local typ
    typ="$(recipe_install_steps::_json_get "$json" type)"
    case "$typ" in
        prepare_source)
            output::progress 5 "Quelle vorbereiten"
            recipe_hooks::install_prepare_source || return 1
            ;;
        require_portable)
            recipe_hooks::require_portable_source || return 1
            if [ -n "${RECIPE_WORK_ROOT:-}" ]; then
                recipe_hooks::state_set WORK_ROOT "$RECIPE_WORK_ROOT"
            fi
            ;;
        prefix)
            recipe_hooks::install_prefix || return 1
            if [ -n "${RECIPE_WORK_ROOT:-}" ]; then
                recipe_hooks::state_set WORK_ROOT "$RECIPE_WORK_ROOT"
            fi
            ;;
        winetricks)
            # packages from step, else from recipe.yml
            local pkgs
            pkgs="$(recipe_install_steps::_json_get_list "$json" packages)"
            if [ -z "$pkgs" ]; then
                recipe_hooks::install_winetricks_from_recipe || return 1
            else
                recipe_install_steps::run_winetricks_list <<<"$pkgs" || return 1
            fi
            ;;
        deploy_graphics)
            output::step "Proton-GE Grafik-DLLs"
            wine_runtime::deploy_proton_graphics_dlls || return 1
            ;;
        run_installer)
            recipe_hooks::run_exe_installer || return 1
            ;;
        stabilize_prefix)
            recipe_winetricks::stabilize_prefix
            ;;
        win10)
            output::step "Windows 10 (Registry)"
            recipe_win10::ensure || return 1
            output::success "win10"
            ;;
        fonts_registry)
            recipe_hooks::_source recipe-fonts.sh
            recipe_fonts::registry || true
            ;;
        emit_log_paths)
            recipe_hooks::emit_log_paths
            ;;
        module)
            local name
            name="$(recipe_install_steps::_json_get "$json" name)"
            recipe_install_steps::call_module "$name" || return 1
            ;;
        copy_asset)
            local src dest mode
            src="$(recipe_install_steps::_json_get "$json" src)"
            dest="$(recipe_install_steps::_json_get "$json" dest)"
            mode="$(recipe_install_steps::_json_get "$json" mode)"
            recipe_install_steps::copy_asset "$src" "$dest" "${mode:-755}" || return 1
            ;;
        env_set)
            local file key value
            file="$(recipe_install_steps::_json_get "$json" file)"
            key="$(recipe_install_steps::_json_get "$json" key)"
            value="$(recipe_install_steps::_expand "$(recipe_install_steps::_json_get "$json" value)")"
            file="$(recipe_install_steps::_expand "${file:-portable.env}")"
            case "$file" in
                /*) ;;
                *) file="${DATA_ROOT}/${file}" ;;
            esac
            env_file_set "$file" "$key" "$value"
            ;;
        progress)
            local pct label
            pct="$(recipe_install_steps::_json_get "$json" pct)"
            label="$(recipe_install_steps::_json_get "$json" label)"
            output::progress "${pct:-0}" "${label:-}"
            ;;
        vcrun)
            output::step "Visual C++ Runtime"
            recipe_vcrun::ensure "${LOG_DIR}/winetricks_vcrun_${TIMESTAMP_ISO}.log" || return 1
            output::success "vcrun"
            ;;
        dotnet)
            output::step "Wine-Mono / .NET"
            recipe_dotnet::ensure "${LOG_DIR}/winetricks_dotnet48_${TIMESTAMP_ISO}.log" || return 1
            output::success "dotnet"
            ;;
        *)
            recipe_hooks::log_err "Unbekannter install_step: $typ"
            return 1
            ;;
    esac
    return 0
}

recipe_install_steps::run() {
    local yml="${RECIPE_YML:-}"
    local reader line rc=0
    [ -n "$yml" ] && [ -f "$yml" ] || {
        echo "ERROR: RECIPE_YML fehlt" >&2
        return 1
    }
    reader="$(recipe_install_steps::_reader)"
    [ -f "$reader" ] || {
        echo "ERROR: recipe-yaml-read.py fehlt: $reader" >&2
        return 1
    }

    if [ -z "${LOG_FILE:-}" ]; then
        recipe_hooks::log_setup "${RECIPE_ID:-app}_Install"
    fi
    export RECIPE_INSTALL_STEPS_RUNNING=1

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if ! recipe_install_steps::step "$line"; then
            rc=1
            break
        fi
    done < <(python3 "$reader" "$yml" --install-steps-lines)

    if [ "$rc" -ne 0 ]; then
        output::error "Installation unvollständig — Rezeptor → Reparieren"
        recipe_hooks::emit_log_paths
        return 11
    fi
    output::success "${RECIPE_NAME:-Rezept} installiert"
    output::progress 100 "Fertig"
    recipe_hooks::emit_log_paths
    return 0
}
