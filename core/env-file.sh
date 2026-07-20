#!/usr/bin/env bash
# Safe key=value env files (no source — avoids command substitution)
# Writers use printf %q; readers only accept %q-safe tokens (no bare eval of file text).

# True if raw is a backslash-escaped %q token (no unescaped shell metacharacters).
env_file::_is_backslash_q_safe() {
    local s="$1" i=0 c
    [ -n "$s" ] || return 1
    [[ "$s" != *\'* && "$s" != *\"* ]] || return 1
    while [ "$i" -lt "${#s}" ]; do
        c="${s:i:1}"
        if [ "$c" = '\' ]; then
            i=$((i + 1))
            [ "$i" -lt "${#s}" ] || return 1
            i=$((i + 1))
            continue
        fi
        case "$c" in
            [A-Za-z0-9_./:@%+=,~^-]) ;;
            *) return 1 ;;
        esac
        i=$((i + 1))
    done
    return 0
}

# Decode a single value produced by printf %q (or reject unsafe input).
env_file::_decode_q() {
    local raw="$1" decoded
    # Bare word as emitted by %q for simple paths/tokens
    if [[ "$raw" =~ ^[A-Za-z0-9_./:@%+=,~^-]+$ ]]; then
        printf '%s' "$raw"
        return 0
    fi
    # Single-quoted or $'...' forms from %q — eval as assignment RHS only
    if [[ "$raw" == \'?*\' || "$raw" == \'\' || "$raw" == \$\'*\' ]]; then
        eval "decoded=$raw"
        printf '%s' "$decoded"
        return 0
    fi
    # Backslash-escaped %q (e.g. /tmp/my\ portable/root)
    if env_file::_is_backslash_q_safe "$raw"; then
        eval "decoded=$raw"
        printf '%s' "$decoded"
        return 0
    fi
    return 1
}

env_file_set() {
    local file="$1" key="$2" value="$3"
    local tmp line found=0
    if type security::sanitize_input >/dev/null 2>&1; then
        key="$(security::sanitize_input "$key")"
    fi
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    tmp="$(mktemp "${file}.XXXXXX")"
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "${key}="*)
                    printf '%s=%q\n' "$key" "$value" >> "$tmp"
                    found=1
                    ;;
                *)
                    printf '%s\n' "$line" >> "$tmp"
                    ;;
            esac
        done < "$file"
    fi
    if [ "$found" -eq 0 ]; then
        printf '%s=%q\n' "$key" "$value" >> "$tmp"
    fi
    mv -f "$tmp" "$file"
}

env_file_write() {
    local file="$1"
    shift
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    : > "$file"
    while [ $# -ge 2 ]; do
        printf '%s=%q\n' "$1" "$2" >> "$file"
        shift 2
    done
}

env_file_get() {
    local file="$1" key="$2" line raw
    [ -f "$file" ] || return 1
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    line="$(grep -m1 "^${key}=" "$file" 2>/dev/null)" || return 1
    raw="${line#${key}=}"
    env_file::_decode_q "$raw"
}

env_file_load_export() {
    local file="$1" line key raw value
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*) continue ;;
            *=*)
                key="${line%%=*}"
                raw="${line#*=}"
                [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
                value="$(env_file::_decode_q "$raw")" || continue
                printf -v "$key" '%s' "$value"
                export "$key"
                ;;
        esac
    done < "$file"
}
