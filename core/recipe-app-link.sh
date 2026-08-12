#!/usr/bin/env bash
# Symlink in DATA_ROOT → real app/game folder (absolute target).
# Priority: GAME_ROOT → GAME_DIR → WISO_PORTABLE_ROOT → WORK_ROOT
# Optional recipe.yml key: app_link_name (default: RECIPE_ID)

recipe_app_link::_canonical() {
    local p="${1:-}"
    [ -n "$p" ] || return 1
    [ -e "$p" ] || [ -L "$p" ] || return 1
    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$p" 2>/dev/null && return 0
    fi
    if [ -d "$p" ]; then
        (cd "$p" && pwd -P) 2>/dev/null && return 0
    fi
    # File or broken-ish path: resolve parent + basename
    local parent base
    parent="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
    base="$(basename "$p")"
    echo "${parent}/${base}"
}

recipe_app_link::_state_or_env() {
    local key="$1" val=""
    # Avoid ${!key:-} under set -u (indirect + default is fragile across bash builds).
    case "$key" in
        GAME_ROOT) val="${GAME_ROOT:-}" ;;
        GAME_DIR) val="${GAME_DIR:-}" ;;
        WORK_ROOT) val="${WORK_ROOT:-}" ;;
        WISO_PORTABLE_ROOT) val="${WISO_PORTABLE_ROOT:-}" ;;
        *) val="" ;;
    esac
    if [ -z "$val" ] && type recipe_hooks::state_get >/dev/null 2>&1; then
        val="$(recipe_hooks::state_get "$key" 2>/dev/null || true)"
    fi
    echo "$val"
}

recipe_app_link::_portable_root() {
    local val=""
    val="$(recipe_app_link::_state_or_env WISO_PORTABLE_ROOT)"
    if [ -z "$val" ] && [ -n "${DATA_ROOT:-}" ] && [ -f "${DATA_ROOT}/portable.env" ]; then
        if type env_file_get >/dev/null 2>&1; then
            val="$(env_file_get "${DATA_ROOT}/portable.env" WISO_PORTABLE_ROOT 2>/dev/null || true)"
        else
            val="$(grep -E '^WISO_PORTABLE_ROOT=' "${DATA_ROOT}/portable.env" 2>/dev/null \
                | head -1 | cut -d= -f2- || true)"
            val="${val%\"}"
            val="${val#\"}"
        fi
    fi
    echo "$val"
}

# Resolve absolute directory that should be linked. Empty = nothing to link.
recipe_app_link::resolve_target() {
    local cand="" key
    for key in GAME_ROOT GAME_DIR; do
        cand="$(recipe_app_link::_state_or_env "$key")"
        if [ -n "$cand" ] && [ -d "$cand" ]; then
            recipe_app_link::_canonical "$cand"
            return 0
        fi
    done
    cand="$(recipe_app_link::_portable_root)"
    if [ -n "$cand" ] && [ -d "$cand" ]; then
        recipe_app_link::_canonical "$cand"
        return 0
    fi
    cand="$(recipe_app_link::_state_or_env WORK_ROOT)"
    if [ -n "$cand" ] && [ -d "$cand" ]; then
        recipe_app_link::_canonical "$cand"
        return 0
    fi
    return 1
}

recipe_app_link::link_name() {
    local raw="" name
    if [ -n "${RECIPE_YML:-}" ] && [ -f "$RECIPE_YML" ] && type recipe_get >/dev/null 2>&1; then
        raw="$(recipe_get "$RECIPE_YML" app_link_name 2>/dev/null || true)"
    fi
    if [ -z "$raw" ]; then
        raw="${RECIPE_ID:-app}"
    fi
    # Sanitize: keep alnum, dot, underscore, hyphen; collapse others to -
    name="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//')"
    [ -n "$name" ] || name="${RECIPE_ID:-app}"
    # Never collide with reserved DATA_ROOT entries
    case "$name" in
        prefix|recipe.env|portable.env|bin|logs|options.env|data_root.path)
            name="${RECIPE_ID:-app}-app"
            ;;
    esac
    echo "$name"
}

recipe_app_link::link_path() {
    local data="${DATA_ROOT:-}" name
    [ -n "$data" ] || return 1
    name="$(recipe_app_link::link_name)"
    echo "${data}/${name}"
}

# Create/refresh absolute symlink. Never clobber a real file/dir.
# Returns 0 on success or nothing-to-do; 1 only on hard failure.
recipe_app_link::ensure() {
    local data="${DATA_ROOT:-}" target="" link="" cur="" want=""
    [ -n "$data" ] && [ -d "$data" ] || return 0

    target="$(recipe_app_link::resolve_target 2>/dev/null || true)"
    [ -n "$target" ] && [ -d "$target" ] || return 0

    link="$(recipe_app_link::link_path)" || return 0
    want="$(recipe_app_link::_canonical "$target" 2>/dev/null || echo "$target")"

    if [ -L "$link" ]; then
        cur="$(readlink -f "$link" 2>/dev/null || true)"
        if [ -n "$cur" ] && [ "$cur" = "$(readlink -f "$want" 2>/dev/null || echo "$want")" ]; then
            return 0
        fi
        rm -f "$link"
    elif [ -e "$link" ]; then
        cur="$(readlink -f "$link" 2>/dev/null || true)"
        if [ -n "$cur" ] && [ "$cur" = "$(readlink -f "$want" 2>/dev/null || echo "$want")" ]; then
            return 0
        fi
        if type output::info >/dev/null 2>&1; then
            output::info "App-Link übersprungen — $(basename "$link") existiert bereits (kein Symlink)"
        fi
        return 0
    fi

    if ln -sfn "$want" "$link" 2>/dev/null; then
        if type output::success >/dev/null 2>&1; then
            output::success "App-Link: $link → $want"
        fi
        return 0
    fi
    if type output::warning >/dev/null 2>&1; then
        output::warning "App-Link unter $data konnte nicht angelegt werden"
    fi
    return 0
}

# Emit OK/WARN via recipe_validate::* when available; else plain lines.
# Does not fail validate (WARN only). Optionally refreshes link if target exists.
recipe_app_link::validate() {
    local data="${DATA_ROOT:-}" target="" link="" cur="" want=""
    local _ok _warn
    if type recipe_validate::ok >/dev/null 2>&1; then
        _ok() { recipe_validate::ok "$*"; }
        _warn() { recipe_validate::warn "$*"; }
    else
        _ok() { echo "OK: $*"; }
        _warn() { echo "WARN: $*"; }
    fi

    [ -n "$data" ] && [ -d "$data" ] || return 0

    target="$(recipe_app_link::resolve_target 2>/dev/null || true)"
    link="$(recipe_app_link::link_path 2>/dev/null || true)"
    [ -n "$link" ] || return 0

    if [ -z "$target" ] || [ ! -d "$target" ]; then
        if [ -L "$link" ] || [ -e "$link" ]; then
            _warn "App-Link $(basename "$link") vorhanden, Zielordner fehlt"
        fi
        return 0
    fi

    want="$(recipe_app_link::_canonical "$target" 2>/dev/null || echo "$target")"

    # Refresh broken/stale symlink when target is known
    if [ ! -e "$link" ] || [ -L "$link" ]; then
        recipe_app_link::ensure >/dev/null 2>&1 || true
    fi

    if [ -L "$link" ]; then
        cur="$(readlink -f "$link" 2>/dev/null || true)"
        if [ -n "$cur" ] && [ -d "$cur" ] \
            && [ "$cur" = "$(readlink -f "$want" 2>/dev/null || echo "$want")" ]; then
            _ok "App-Link $(basename "$link") → Programmordner"
            return 0
        fi
        _warn "App-Link $(basename "$link") zeigt nicht auf den Programmordner"
        return 0
    fi
    if [ -e "$link" ]; then
        cur="$(readlink -f "$link" 2>/dev/null || true)"
        if [ -n "$cur" ] && [ "$cur" = "$(readlink -f "$want" 2>/dev/null || echo "$want")" ]; then
            _ok "App-Ordner $(basename "$link") (kein Symlink nötig)"
            return 0
        fi
        _warn "App-Link $(basename "$link") fehlt — Name von echter Datei/Ordner belegt"
        return 0
    fi
    _warn "App-Link $(basename "$link") fehlt — Reparieren"
    return 0
}
