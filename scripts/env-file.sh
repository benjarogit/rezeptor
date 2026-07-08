#!/usr/bin/env bash
# Safe key=value env files (no source — avoids command substitution)

env_file_set() {
    local file="$1" key="$2" value="$3"
    local tmp line found=0
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
    local file="$1" key="$2" line
    [ -f "$file" ] || return 1
    line="$(grep -m1 "^${key}=" "$file" 2>/dev/null)" || return 1
    line="${line#${key}=}"
    eval "printf '%s' $line"
}

env_file_load_export() {
    local file="$1" line
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*) continue ;;
            *=*) eval "export $line" ;;
        esac
    done < "$file"
}
