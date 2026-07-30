#!/usr/bin/env bash
# Spiel-/Installer-ISOs zugänglich machen — Mount statt Voll-Extract (UDF/große ISOs).
#
# Env nach erfolgreichem Mount:
#   RECIPE_ISO_PATH, RECIPE_ISO_MOUNT, RECIPE_ISO_LOOP (Device, optional)
# State-Datei: ${DATA_ROOT}/iso-mounts.env (für Cleanup)
set -eu
(set -o pipefail 2>/dev/null) || true

recipe_iso::_err() {
    echo "ERROR: $*" >&2
}

recipe_iso::_info() {
    type output::info >/dev/null 2>&1 && output::info "$1" || echo "$1"
}

recipe_iso::_step() {
    type output::step >/dev/null 2>&1 && output::step "$1" || echo "→ $1"
}

recipe_iso::_state_file() {
    echo "${DATA_ROOT:-/tmp}/iso-mounts.env"
}

recipe_iso::_record() {
    local iso="$1" mount="$2" loop="${3:-}"
    local f
    f="$(recipe_iso::_state_file)"
    mkdir -p "$(dirname "$f")" 2>/dev/null || true
    {
        echo "ISO=${iso}"
        echo "MOUNT=${mount}"
        [ -n "$loop" ] && echo "LOOP=${loop}"
    } >>"$f"
}

# Find a single .iso under dir (maxdepth 1), prefer newest / name match.
recipe_iso::find_in_dir() {
    local dir="$1" f best="" best_m=0 m
    [ -d "$dir" ] || return 1
    shopt -s nullglob
    for f in "$dir"/*.iso "$dir"/*.ISO; do
        [ -f "$f" ] || continue
        m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        if [ -z "$best" ] || [ "$m" -ge "$best_m" ]; then
            best="$f"
            best_m="$m"
        fi
    done
    shopt -u nullglob
    [ -n "$best" ] || return 1
    echo "$best"
}

# True if path is an ISO file.
recipe_iso::is_iso_file() {
    local p="${1:-}"
    [ -n "$p" ] && [ -f "$p" ] || return 1
    [[ "${p,,}" == *.iso ]]
}

# Mount ISO via udisksctl.
# Mountpunkt nur über RECIPE_ISO_MOUNT (nicht via stdout/$() — GUI-Tags @step/@info
# würden sonst den Pfad verunreinigen und detect_installer scheitern lassen).
recipe_iso::mount() {
    local iso="$1"
    local out loop="" mount="" line dev

    [ -f "$iso" ] || {
        recipe_iso::_err "ISO fehlt: $iso"
        return 1
    }
    iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"

    if ! command -v udisksctl >/dev/null 2>&1; then
        recipe_iso::_err "udisksctl fehlt — bitte udisks2 installieren (ISO-Mount)"
        return 1
    fi

    recipe_iso::_step "ISO mounten: $(basename "$iso")"

    out="$(udisksctl loop-setup -f "$iso" --no-user-interaction 2>&1)" || {
        recipe_iso::_err "loop-setup fehlgeschlagen: $out"
        return 1
    }
    # "Mapped file … as /dev/loopX."
    if [[ "$out" =~ (/dev/loop[0-9]+) ]]; then
        loop="${BASH_REMATCH[1]}"
    else
        recipe_iso::_err "Kein Loop-Device in: $out"
        return 1
    fi

    # Prefer partition if present (rare for ElAmigos UDF)
    dev="$loop"
    if [ -b "${loop}p1" ]; then
        dev="${loop}p1"
    fi

    out="$(udisksctl mount -b "$dev" --no-user-interaction 2>&1)" || {
        # try whole disk
        if [ "$dev" != "$loop" ]; then
            out="$(udisksctl mount -b "$loop" --no-user-interaction 2>&1)" || {
                recipe_iso::_err "ISO-Mount fehlgeschlagen: $out"
                udisksctl loop-delete -b "$loop" --no-user-interaction 2>/dev/null || true
                return 1
            }
            dev="$loop"
        else
            recipe_iso::_err "ISO-Mount fehlgeschlagen: $out"
            udisksctl loop-delete -b "$loop" --no-user-interaction 2>/dev/null || true
            return 1
        fi
    }

    # "Mounted /dev/loopX at /run/media/…"
    if [[ "$out" =~ \ at\ (/.*)[\.\"]*$ ]]; then
        mount="${BASH_REMATCH[1]}"
        mount="${mount%.}"
        mount="${mount%\"}"
    else
        # Fallback: findmnt
        mount="$(findmnt -n -o TARGET -S "$dev" 2>/dev/null | head -1 || true)"
    fi
    [ -n "$mount" ] && [ -d "$mount" ] || {
        recipe_iso::_err "Mountpunkt unbekannt nach: $out"
        udisksctl unmount -b "$dev" --no-user-interaction 2>/dev/null || true
        udisksctl loop-delete -b "$loop" --no-user-interaction 2>/dev/null || true
        return 1
    }

    recipe_iso::_record "$iso" "$mount" "$loop"
    export RECIPE_ISO_PATH="$iso"
    export RECIPE_ISO_MOUNT="$mount"
    export RECIPE_ISO_LOOP="$loop"
    recipe_iso::_info "ISO gemountet: $mount"
    return 0
}

recipe_iso::umount_recorded() {
    local f iso mount loop
    f="$(recipe_iso::_state_file)"
    [ -f "$f" ] || return 0
    iso="" mount="" loop=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ISO=*) iso="${line#ISO=}" ;;
            MOUNT=*)
                mount="${line#MOUNT=}"
                if [ -n "$mount" ] && findmnt -n "$mount" >/dev/null 2>&1; then
                    if command -v udisksctl >/dev/null 2>&1; then
                        udisksctl unmount -m "$mount" --no-user-interaction 2>/dev/null || true
                    else
                        umount "$mount" 2>/dev/null || true
                    fi
                fi
                mount=""
                ;;
            LOOP=*)
                loop="${line#LOOP=}"
                if [ -n "$loop" ] && command -v udisksctl >/dev/null 2>&1; then
                    udisksctl loop-delete -b "$loop" --no-user-interaction 2>/dev/null || true
                fi
                loop=""
                ;;
        esac
    done <"$f"
    rm -f "$f" 2>/dev/null || true
}

# Resolve work root from ISO file or folder containing ISO. Prints mount/dir.
# Prefer existing setup.exe tree over mounting.
# Nach Mount: Pfad aus RECIPE_ISO_MOUNT (mount selbst schreibt nicht auf stdout).
recipe_iso::ensure_accessible() {
    local path="$1"
    local iso mount

    [ -n "$path" ] || return 1

    if recipe_iso::is_iso_file "$path"; then
        recipe_iso::mount "$path" || return 1
        printf '%s\n' "${RECIPE_ISO_MOUNT}"
        return 0
    fi

    if [ -d "$path" ]; then
        # Already has installer beside bins?
        if [ -f "$path/setup.exe" ] || [ -f "$path/Setup.exe" ] \
            || [ -f "$path/Set-up.exe" ]; then
            printf '%s\n' "$(cd "$path" && pwd)"
            return 0
        fi
        iso="$(recipe_iso::find_in_dir "$path" 2>/dev/null || true)"
        if [ -n "$iso" ]; then
            recipe_iso::mount "$iso" || return 1
            printf '%s\n' "${RECIPE_ISO_MOUNT}"
            return 0
        fi
        printf '%s\n' "$(cd "$path" && pwd)"
        return 0
    fi

    recipe_iso::_err "Kein ISO/Ordner: $path"
    return 1
}
