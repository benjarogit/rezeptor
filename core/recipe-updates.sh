#!/usr/bin/env bash
# Geordnete Post-Install-Updates (ElAmigos-Patches u. ä.).
#
# Konvention unter einem Root:
#   updates/ | Updates/ | update/   → Unterordner „1 - …“, „2 - …“
#   auch: updates/<Paketname>/1 - …/ (ElAmigos-Wrapper ohne .exe im Zwischenordner)
#   oder direkt nummerierte Ordner „1 - …“ unter dem Root
#   oder einzelne .exe unter dem Root (eine Einheit)
#
# Env: RECIPE_UPDATE_ROOT / RECIPE_FIX_ROOT (Alias), RECIPE_SOURCE_ROOT, RECIPE_WORK_ROOT
# State: APPLIED_UPDATES=1,2,3 in recipe.env (führende Nummern / IDs)
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_updates::_log() {
    type output::step >/dev/null 2>&1 && output::step "$1" || echo "→ $1"
}

recipe_updates::_info() {
    type output::info >/dev/null 2>&1 && output::info "$1" || echo "$1"
}

recipe_updates::_ok() {
    type output::success >/dev/null 2>&1 && output::success "$1" || echo "OK: $1"
}

recipe_updates::_err() {
    echo "ERROR: $*" >&2
    type recipe_hooks::log_err >/dev/null 2>&1 && recipe_hooks::log_err "$*"
}

# Leading integer from "1 - Name" / "10-foo" / basename.
recipe_updates::_unit_id() {
    local name="$1" n
    if [[ "$name" =~ ^([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    # Fallback: sanitized basename
    n="$(printf '%s' "$name" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_//;s/_$//')"
    [ -n "$n" ] || n="u"
    echo "$n"
}

recipe_updates::_is_numbered_dir() {
    local base
    base="$(basename "$1")"
    [[ "$base" =~ ^[0-9]+([[:space:]]*-|-) ]]
}

# True if dir looks like an update package (has .exe, optionally .bin).
recipe_updates::_dir_is_unit() {
    local d="$1" f
    [ -d "$d" ] || return 1
    shopt -s nullglob
    for f in "$d"/*.exe "$d"/*.EXE; do
        [ -f "$f" ] || continue
        shopt -u nullglob
        return 0
    done
    shopt -u nullglob
    return 1
}

# Print "ID|PATH" lines for units under one scan root (unsorted).
recipe_updates::_scan_root() {
    local root="$1" sub base id path f
    [ -n "$root" ] && [ -d "$root" ] || return 0
    root="$(cd "$root" && pwd)"

    for sub in updates Updates update; do
        if [ -d "$root/$sub" ]; then
            recipe_updates::_scan_numbered_or_exes "$root/$sub"
            return 0
        fi
    done

    # Numbered dirs directly under root?
    local any=0
    shopt -s nullglob
    for path in "$root"/*; do
        [ -d "$path" ] || continue
        if recipe_updates::_is_numbered_dir "$path" && recipe_updates::_dir_is_unit "$path"; then
            any=1
            break
        fi
    done
    shopt -u nullglob
    if [ "$any" -eq 1 ]; then
        recipe_updates::_scan_numbered_or_exes "$root"
        return 0
    fi

    # Single package dir (has exe + optional bin) without number — id from name
    if recipe_updates::_dir_is_unit "$root"; then
        # Prefer nested "1 - …" if only one child package
        local children=0 child=""
        shopt -s nullglob
        for path in "$root"/*; do
            [ -d "$path" ] || continue
            if recipe_updates::_dir_is_unit "$path"; then
                children=$((children + 1))
                child="$path"
            fi
        done
        shopt -u nullglob
        if [ "$children" -eq 1 ] && [ -n "$child" ]; then
            base="$(basename "$child")"
            id="$(recipe_updates::_unit_id "$base")"
            echo "${id}|${child}"
            return 0
        fi
        if [ "$children" -gt 1 ]; then
            recipe_updates::_scan_numbered_or_exes "$root"
            return 0
        fi
        # Root itself is the package
        base="$(basename "$root")"
        id="$(recipe_updates::_unit_id "$base")"
        # Prefer numbered child name already handled; use 1 if no digit
        [[ "$base" =~ ^[0-9]+ ]] || id="1"
        echo "${id}|${root}"
        return 0
    fi

    # Loose .exe at root
    shopt -s nullglob
    for f in "$root"/*.exe "$root"/*.EXE; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        id="$(recipe_updates::_unit_id "$base")"
        [[ "$base" =~ ^[0-9]+ ]] || id="1"
        echo "${id}|${f}"
    done
    shopt -u nullglob
}

recipe_updates::_scan_numbered_or_exes() {
    local root="$1" path base id f child
    shopt -s nullglob
    for path in "$root"/*; do
        if [ -d "$path" ] && recipe_updates::_dir_is_unit "$path"; then
            base="$(basename "$path")"
            id="$(recipe_updates::_unit_id "$base")"
            echo "${id}|${path}"
        elif [ -d "$path" ]; then
            # ElAmigos o. Ä.: updates/<Name>/1 - …/ (Wrapper ohne .exe)
            for child in "$path"/*; do
                if [ -d "$child" ] && recipe_updates::_dir_is_unit "$child"; then
                    base="$(basename "$child")"
                    id="$(recipe_updates::_unit_id "$base")"
                    echo "${id}|${child}"
                elif [ -f "$child" ] && [[ "${child,,}" == *.exe ]]; then
                    base="$(basename "$child")"
                    id="$(recipe_updates::_unit_id "$base")"
                    echo "${id}|${child}"
                fi
            done
        elif [ -f "$path" ] && [[ "${path,,}" == *.exe ]]; then
            base="$(basename "$path")"
            id="$(recipe_updates::_unit_id "$base")"
            echo "${id}|${path}"
        fi
    done
    shopt -u nullglob
}

# Discover ordered units from one or more roots. Prints "ID|PATH" sorted numerically by ID.
recipe_updates::discover() {
    local root line
    local -a lines=()
    for root in "$@"; do
        [ -n "$root" ] || continue
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            lines+=("$line")
        done < <(recipe_updates::_scan_root "$root")
    done
    if [ "${#lines[@]}" -eq 0 ]; then
        return 0
    fi
    # Sort by numeric ID (field before |); stable path as tiebreaker
    printf '%s\n' "${lines[@]}" | sort -t'|' -k1,1n -k2,2
}

# Candidate roots from env (update field + source/work for nested updates/).
recipe_updates::roots_from_env() {
    local r seen=""
    for r in \
        "${RECIPE_UPDATE_ROOT:-}" \
        "${RECIPE_FIX_ROOT:-}" \
        "${RECIPE_SOURCE_ROOT:-}" \
        "${RECIPE_WORK_ROOT:-}"; do
        [ -n "$r" ] || continue
        [ -e "$r" ] || continue
        case " $seen " in
            *" $r "*) continue ;;
        esac
        seen="${seen} ${r}"
        printf '%s\n' "$r"
    done
}

recipe_updates::_applied_list() {
    local raw
    raw="$(recipe_hooks::state_get APPLIED_UPDATES 2>/dev/null || true)"
    printf '%s' "$raw"
}

recipe_updates::_is_applied() {
    local id="$1" raw
    raw="$(recipe_updates::_applied_list)"
    [ -n "$raw" ] || return 1
    case ",${raw}," in
        *",${id},"*) return 0 ;;
    esac
    return 1
}

recipe_updates::_mark_applied() {
    local id="$1" raw new
    raw="$(recipe_updates::_applied_list)"
    if [ -z "$raw" ]; then
        new="$id"
    else
        case ",${raw}," in
            *",${id},"*) return 0 ;;
        esac
        new="${raw},${id}"
    fi
    recipe_hooks::state_set APPLIED_UPDATES "$new"
}

# Run one update unit (dir with exe, or single exe path).
recipe_updates::apply_unit() {
    local unit="$1"
    local log="${2:-${LOG_FILE:-/dev/null}}"
    local wine_cmd="${3:-wine}"
    local exe="" dir f

    [ -n "$unit" ] || return 1
    if [ -f "$unit" ] && [[ "${unit,,}" == *.exe ]]; then
        exe="$unit"
        dir="$(cd "$(dirname "$unit")" && pwd)"
    elif [ -d "$unit" ]; then
        dir="$(cd "$unit" && pwd)"
        shopt -s nullglob
        for f in "$dir"/*.exe "$dir"/*.EXE; do
            [ -f "$f" ] || continue
            # Prefer non-setup helpers named *update* / first exe
            exe="$f"
            [[ "${f,,}" == *update* ]] && break
        done
        shopt -u nullglob
    else
        recipe_updates::_err "Update-Einheit fehlt: $unit"
        return 1
    fi

    [ -n "$exe" ] && [ -f "$exe" ] || {
        recipe_updates::_err "Keine Update-EXE in: $unit"
        return 1
    }

    recipe_updates::_log "Update: $(basename "$exe")"
    if type recipe_hooks::run_exe_silent >/dev/null 2>&1; then
        recipe_hooks::run_exe_silent "$exe" "$log" "$wine_cmd" || {
            recipe_updates::_err "Update fehlgeschlagen: $exe"
            return 1
        }
    else
        (
            cd "$dir" || exit 1
            "$wine_cmd" "$(basename "$exe")" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART >>"$log" 2>&1
        ) || {
            recipe_updates::_err "Update fehlgeschlagen: $exe"
            return 1
        }
    fi
    recipe_updates::_ok "Update $(basename "$exe")"
    return 0
}

# Apply all discovered updates in order; skip already applied IDs.
recipe_updates::apply_all() {
    local log="${1:-${LOG_FILE:-/dev/null}}"
    local wine_cmd="${2:-wine}"
    local -a roots=()
    local line id path applied=0 skipped=0 failed=0

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        roots+=("$line")
    done < <(recipe_updates::roots_from_env)

    if [ "${#roots[@]}" -eq 0 ]; then
        recipe_updates::_info "Keine Update-Quelle — übersprungen"
        return 0
    fi

    local -a units=()
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        units+=("$line")
    done < <(recipe_updates::discover "${roots[@]}")

    if [ "${#units[@]}" -eq 0 ]; then
        recipe_updates::_info "Keine Update-Pakete gefunden — übersprungen"
        return 0
    fi

    recipe_updates::_log "Updates: ${#units[@]} Paket(e)"
    for line in "${units[@]}"; do
        id="${line%%|*}"
        path="${line#*|}"
        if recipe_updates::_is_applied "$id"; then
            recipe_updates::_info "Update $id bereits angewandt — skip"
            skipped=$((skipped + 1))
            continue
        fi
        if recipe_updates::apply_unit "$path" "$log" "$wine_cmd"; then
            recipe_updates::_mark_applied "$id"
            applied=$((applied + 1))
        else
            failed=$((failed + 1))
            return 1
        fi
    done

    recipe_updates::_ok "Updates fertig (neu=$applied skip=$skipped)"
    return 0
}

recipe_updates::status() {
    local raw
    raw="$(recipe_updates::_applied_list)"
    if [ -n "$raw" ]; then
        recipe_updates::_info "Angewandte Updates: $raw"
    else
        recipe_updates::_info "Angewandte Updates: (keine)"
    fi
}
