#!/usr/bin/env bash
# Master PDF Editor 5 — MSI-Install + Finalize (WORK_ROOT + optional BYOS-Fix aus Pack).

recipe_master_pdf_editor::find_exe() {
    local prefix="${WINEPREFIX:-${WINE_PREFIX:-}}"
    local cand=""
    [ -n "$prefix" ] && [ -d "$prefix" ] || return 1
    for cand in \
        "$prefix/drive_c/Program Files/Code Industry/Master PDF Editor 5/MasterPDFEditor.exe" \
        "$prefix/drive_c/Program Files (x86)/Code Industry/Master PDF Editor 5/MasterPDFEditor.exe" \
        "$prefix/drive_c/Program Files/Master PDF Editor 5/MasterPDFEditor.exe" \
        "$prefix/drive_c/Program Files/Code Industry/Master PDF Editor/MasterPDFEditor.exe"; do
        if [ -f "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    cand="$(find "$prefix/drive_c/Program Files" "$prefix/drive_c/Program Files (x86)" \
        -name 'MasterPDFEditor.exe' -type f 2>/dev/null | head -1 || true)"
    [ -n "$cand" ] && [ -f "$cand" ] || return 1
    echo "$cand"
}

# BYOS: optional MasterPDFEditor.exe under fix/ (or common pack subfolders) next to the MSI.
# Rezeptor ships neither the MSI nor any fix binary.
recipe_master_pdf_editor::find_fix_exe() {
    local root="" parent="" sub=""
    if [ -n "${RECIPE_SOURCE_ROOT:-}" ] && [ -d "${RECIPE_SOURCE_ROOT}" ]; then
        root="${RECIPE_SOURCE_ROOT}"
    elif [ -n "${RECIPE_INSTALLER_PATH:-}" ] && [ -f "${RECIPE_INSTALLER_PATH}" ]; then
        parent="$(cd "$(dirname "${RECIPE_INSTALLER_PATH}")" && pwd)"
        root="$parent"
    fi
    [ -n "$root" ] || return 1
    for sub in fix Fix online_fix; do
        if [ -f "$root/$sub/MasterPDFEditor.exe" ]; then
            echo "$root/$sub/MasterPDFEditor.exe"
            return 0
        fi
    done
    # Silent pack-layout aliases (folder names vary by pack; not advertised in UI).
    for sub in crack Crack patch Patch; do
        if [ -f "$root/$sub/MasterPDFEditor.exe" ]; then
            echo "$root/$sub/MasterPDFEditor.exe"
            return 0
        fi
    done
    return 1
}

recipe_master_pdf_editor::apply_fix() {
    local installed="${1:-}" fix=""
    [ -n "$installed" ] && [ -f "$installed" ] || return 1
    fix="$(recipe_master_pdf_editor::find_fix_exe || true)"
    if [ -z "$fix" ]; then
        type output::info >/dev/null 2>&1 \
            && output::info "Kein BYOS-Fix (fix/MasterPDFEditor.exe) im Pack — MSI-Build bleibt" \
            || true
        return 0
    fi
    if [ ! -f "${installed}.rezeptor-pre-fix" ]; then
        cp -f "$installed" "${installed}.rezeptor-pre-fix" || true
    fi
    # Migrate old backup name if present.
    if [ -f "${installed}.rezeptor-pre-crack" ] && [ ! -f "${installed}.rezeptor-pre-fix" ]; then
        mv -f "${installed}.rezeptor-pre-crack" "${installed}.rezeptor-pre-fix" 2>/dev/null || true
    fi
    cp -f "$fix" "$installed" || {
        type output::error >/dev/null 2>&1 && output::error "BYOS-Fix konnte nicht übernommen werden"
        return 1
    }
    type output::success >/dev/null 2>&1 && output::success "BYOS-Fix übernommen"
    return 0
}

# msiexec /qn hängt unter Wine oft nach Dateikopie — Timeout + Erfolg wenn EXE da.
recipe_master_pdf_editor::run_msi() {
    local exe="${RECIPE_INSTALLER_PATH:-}" log="${LOG_FILE:-/dev/null}"
    local wine_bin="${WINE64:-${WINE:-wine}}"
    local dir base rc=0 timeout_s="${MPE_MSI_TIMEOUT:-480}"

    [ -f "$exe" ] || {
        type output::error >/dev/null 2>&1 && output::error "MSI fehlt: ${exe:-?}"
        return 1
    }
    dir="$(cd "$(dirname "$exe")" && pwd)"
    base="$(basename "$exe")"
    type output::step >/dev/null 2>&1 && output::step "MSI: $base (max ${timeout_s}s)"
    type output::info >/dev/null 2>&1 && output::info "Installer-Typ: msi"

    (
        cd "$dir" || exit 1
        if command -v timeout >/dev/null 2>&1; then
            timeout --signal=TERM --kill-after=30 "$timeout_s" \
                "$wine_bin" msiexec /i "$base" /qn /norestart >>"$log" 2>&1
        else
            "$wine_bin" msiexec /i "$base" /qn /norestart >>"$log" 2>&1
        fi
    )
    rc=$?

    if recipe_master_pdf_editor::find_exe >/dev/null 2>&1; then
        pkill -9 -f 'msiexec\.exe' 2>/dev/null || true
        type output::success >/dev/null 2>&1 && output::success "MSI: MasterPDFEditor.exe vorhanden"
        return 0
    fi
    if [ "$rc" -ne 0 ]; then
        type output::error >/dev/null 2>&1 && output::error "MSI fehlgeschlagen (exit $rc)"
        return 1
    fi
    type output::error >/dev/null 2>&1 && output::error "MSI ohne MasterPDFEditor.exe"
    return 1
}

recipe_master_pdf_editor::finalize() {
    local exe dir
    type output::progress >/dev/null 2>&1 && output::progress 90 "Master PDF Editor finden"
    exe="$(recipe_master_pdf_editor::find_exe || true)"
    if [ -z "$exe" ]; then
        type output::error >/dev/null 2>&1 && output::error "MasterPDFEditor.exe nach MSI nicht gefunden"
        return 1
    fi
    dir="$(cd "$(dirname "$exe")" && pwd)"
    recipe_hooks::state_set WORK_ROOT "$dir"
    recipe_hooks::state_set GAME_EXE "$exe"
    type output::success >/dev/null 2>&1 && output::success "Installiert: $(basename "$exe")"
    type output::info >/dev/null 2>&1 && output::info "Pfad: $dir"

    type output::progress >/dev/null 2>&1 && output::progress 95 "BYOS-Fix aus Pack"
    recipe_master_pdf_editor::apply_fix "$exe" || true
    return 0
}
