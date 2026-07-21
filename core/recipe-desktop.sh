#!/usr/bin/env bash
# Rezeptor — Menü- und Desktop-Verknüpfungen (alle Rezepte).
#
# recipe_desktop::install  — applications/ + Schreibtisch/Desktop
# recipe_desktop::remove   — Einträge + Theme-Icons entfernen
# recipe_desktop::refresh_if_present — nur wenn schon angelegt (Reparatur)
#
# Voraussetzung: RECIPE_DIR, PROJECT_ROOT, DATA_ROOT, RECIPE_ID, RECIPE_NAME
# (über recipe_hooks::load / recipe_export_env).

recipe_desktop::_escape() {
    printf '%s' "${1:-}" | sed 's/[\\"]/\\&/g'
}

recipe_desktop::_theme_name() {
    echo "rezeptor-${RECIPE_ID:?}"
}

recipe_desktop::_desktop_name() {
    echo "rezeptor-${RECIPE_ID:?}.desktop"
}

recipe_desktop::_app_dir() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
}

recipe_desktop::_icon_dir() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
}

recipe_desktop::_marker() {
    echo "${DATA_ROOT:?}/.rezeptor-desktop"
}

recipe_desktop::_desktop_dirs() {
    # Alle Kandidaten (Dedup später) — Bazzite/KDE: xdg, XDG_DESKTOP_DIR, DE/EN-Namen.
    local desk="" d
    desk="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    for d in \
        "${XDG_DESKTOP_DIR:-}" \
        "$desk" \
        "$HOME/Schreibtisch" \
        "$HOME/Desktop" \
        "$HOME/desktop" \
        "$HOME/Desktop-Ordner" \
        "$HOME/Área de Trabalho"; do
        [ -n "$d" ] || continue
        printf '%s\n' "$d"
    done
}

recipe_desktop::_unique_existing_dirs() {
    local d seen=""
    while IFS= read -r d; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        case "|$seen|" in
            *"|$d|"*) continue ;;
        esac
        seen="${seen}|$d"
        printf '%s\n' "$d"
    done
}

recipe_desktop::_icon_src() {
    local raw="" src=""
    raw="$(recipe_get "${RECIPE_YML:?}" icon 2>/dev/null || true)"
    if [ -n "$raw" ]; then
        src="$(recipe_hooks::paths_expand_tokens "$raw" 2>/dev/null || true)"
        [ -z "$src" ] && src="$(paths_expand "$raw" 2>/dev/null || true)"
        [ -n "$src" ] && [ -f "$src" ] && { echo "$src"; return 0; }
    fi
    # Fallback: images/<id>-icon.png / bekannte Alt-Namen
    for src in \
        "${PROJECT_ROOT}/images/${RECIPE_ID}-icon.png" \
        "${PROJECT_ROOT}/images/AdobePhotoshop-icon.png" \
        "${PROJECT_ROOT}/images/wiso-steuer-icon.png" \
        "${PROJECT_ROOT}/images/house-of-ashes-icon.png"; do
        [ -f "$src" ] && { echo "$src"; return 0; }
    done
    # WISO: ICO aus Portable
    if [ "$RECIPE_ID" = "wiso-steuer" ]; then
        local portable="" ico=""
        if [ -f "${DATA_ROOT}/portable.env" ]; then
            portable="$(grep -E '^WISO_PORTABLE_ROOT=' "${DATA_ROOT}/portable.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        fi
        if [ -n "$portable" ] && [ -d "$portable" ]; then
            ico="$(find "$portable" -maxdepth 3 -name 'wisoakt.ico' -type f 2>/dev/null | head -1 || true)"
            [ -n "$ico" ] && [ -f "$ico" ] && { echo "$ico"; return 0; }
        fi
    fi
    return 1
}

recipe_desktop::_install_icons() {
    local theme icon_src icon_dir s
    theme="$(recipe_desktop::_theme_name)"
    icon_dir="$(recipe_desktop::_icon_dir)"
    icon_src="$(recipe_desktop::_icon_src || true)"
    [ -n "$icon_src" ] && [ -f "$icon_src" ] || {
        echo "Icon=application-x-executable"
        return 0
    }

    mkdir -p "$icon_dir"
    if command -v magick >/dev/null 2>&1; then
        for s in 48 64 128 256; do
            mkdir -p "$icon_dir/${s}x${s}/apps"
            magick "${icon_src}[0]" -resize "${s}x${s}" \
                "$icon_dir/${s}x${s}/apps/${theme}.png" 2>/dev/null || true
        done
    else
        mkdir -p "$icon_dir/48x48/apps"
        cp -f "$icon_src" "$icon_dir/48x48/apps/${theme}.png" 2>/dev/null || true
    fi

    if [ -f "$icon_dir/48x48/apps/${theme}.png" ] || [ -f "$icon_dir/64x64/apps/${theme}.png" ]; then
        command -v gtk-update-icon-cache >/dev/null 2>&1 \
            && gtk-update-icon-cache -f -t "$icon_dir" 2>/dev/null || true
        echo "Icon=${theme}"
        return 0
    fi
    # Absoluter Pfad als letzter Fallback (PNG/SVG)
    case "$icon_src" in
        *.png|*.svg|*.xpm) echo "Icon=${icon_src}" ;;
        *) echo "Icon=application-x-executable" ;;
    esac
}

recipe_desktop::_categories() {
    case "${RECIPE_ID}" in
        photoshop) echo "Graphics;2DGraphics;RasterGraphics;" ;;
        wiso-steuer) echo "Office;Finance;" ;;
        house-of-ashes|za4-trainer) echo "Game;" ;;
        *) echo "Utility;" ;;
    esac
}

recipe_desktop::_extra_keys() {
    case "${RECIPE_ID}" in
        photoshop)
            cat <<'EOF'
StartupWMClass=Photoshop.exe
MimeType=image/vnd.adobe.photoshop;image/x-photoshop;application/x-photoshop;image/psd;application/psd;
EOF
            ;;
        wiso-steuer)
            cat <<'EOF'
StartupWMClass=start.exe
Keywords=tax;steuer;wiso;buhl;
EOF
            ;;
        house-of-ashes)
            echo "StartupWMClass=HouseOfAshes.exe"
            ;;
        za4-trainer)
            echo "StartupWMClass=ZA4-Trainer.exe"
            ;;
    esac
}

recipe_desktop::_exec_and_path() {
    # stdout: erste Zeile = Exec=, zweite = Path=
    local launch="${RECIPE_DIR}/launch.sh"
    local data_esc prefix_esc launch_esc root_esc
    data_esc="$(recipe_desktop::_escape "${DATA_ROOT}")"
    prefix_esc="$(recipe_desktop::_escape "${WINEPREFIX:-${DATA_ROOT}/prefix}")"
    launch_esc="$(recipe_desktop::_escape "$launch")"

    if [ "$RECIPE_ID" = "wiso-steuer" ] && [ -x "${DATA_ROOT}/bin/wiso-launch.sh" ]; then
        local wlaunch portable
        wlaunch="$(recipe_desktop::_escape "${DATA_ROOT}/bin/wiso-launch.sh")"
        portable=""
        if [ -f "${DATA_ROOT}/portable.env" ]; then
            portable="$(grep -E '^WISO_PORTABLE_ROOT=' "${DATA_ROOT}/portable.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        fi
        root_esc="$(recipe_desktop::_escape "${portable:-$DATA_ROOT}")"
        echo "env WINEPREFIX=\"${prefix_esc}\" WISO_PORTABLE_ROOT=\"${root_esc}\" \"${wlaunch}\""
        echo "${root_esc}"
        return 0
    fi

    echo "env WINEPREFIX=\"${prefix_esc}\" DATA_ROOT=\"${data_esc}\" SCR_PATH=\"${data_esc}\" bash \"${launch_esc}\" %F"
    echo "${data_esc}"
}

recipe_desktop::install() {
    local app_dir desk_name dest icon_line name comment exec_line path_line desk d
    local -a exec_path

    [ -n "${RECIPE_ID:-}" ] || return 1
    [ -n "${DATA_ROOT:-}" ] || return 1
    [ -x "${RECIPE_DIR}/launch.sh" ] || return 1

    app_dir="$(recipe_desktop::_app_dir)"
    desk_name="$(recipe_desktop::_desktop_name)"
    name="${RECIPE_NAME:-$RECIPE_ID}"
    comment="${name} via Rezeptor"
    mkdir -p "$app_dir"

    icon_line="$(recipe_desktop::_install_icons)"
    mapfile -t exec_path < <(recipe_desktop::_exec_and_path)
    exec_line="${exec_path[0]:-}"
    path_line="${exec_path[1]:-$DATA_ROOT}"
    [ -n "$exec_line" ] || return 1

    dest="${app_dir}/${desk_name}"
    cat >"$dest" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=${name}
Comment=${comment}
Exec=${exec_line}
Path=${path_line}
Categories=$(recipe_desktop::_categories)
Terminal=false
StartupNotify=true
$(recipe_desktop::_extra_keys)
${icon_line}
EOF
    chmod 644 "$dest" 2>/dev/null || true

    # Nur eine Verknüpfung: rezeptor-<id>.desktop — Legacy-Aliase entfernen (keine Duplikate)
    case "$RECIPE_ID" in
        photoshop)
            rm -f \
                "${app_dir}/photoshop.desktop" \
                "${app_dir}/Adobe Photoshop 2021.desktop" \
                "${app_dir}/Adobe Photoshop.desktop" \
                "${app_dir}/photoshopCC.desktop" \
                2>/dev/null || true
            rm -f "${app_dir}"/photoshop.desktop.bak.* 2>/dev/null || true
            ;;
        wiso-steuer)
            rm -f "${app_dir}/wiso-steuer.desktop" 2>/dev/null || true
            ;;
    esac

    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$app_dir" 2>/dev/null || true

    # Auf jedes existierende Desktop-Verzeichnis legen (nicht nur das erste).
    while IFS= read -r d; do
        # Alte Doppel-Einträge vom Schreibtisch entfernen
        case "$RECIPE_ID" in
            photoshop)
                rm -f "$d/photoshop.desktop" 2>/dev/null || true
                find "$d" -maxdepth 1 -type f \( -iname '*photoshop*' ! -name "$desk_name" \) \
                    -delete 2>/dev/null || true
                ;;
            wiso-steuer)
                rm -f "$d/wiso-steuer.desktop" 2>/dev/null || true
                ;;
        esac
        cp -f "$dest" "$d/${desk_name}" 2>/dev/null || true
        chmod +x "$d/${desk_name}" 2>/dev/null || true
    done < <(recipe_desktop::_desktop_dirs | recipe_desktop::_unique_existing_dirs)

    mkdir -p "$DATA_ROOT" 2>/dev/null || true
    printf '1\n' >"$(recipe_desktop::_marker)" 2>/dev/null || true
    return 0
}

recipe_desktop::remove() {
    local app_dir icon_dir theme desk_name d s
    [ -n "${RECIPE_ID:-}" ] || return 1
    app_dir="$(recipe_desktop::_app_dir)"
    icon_dir="$(recipe_desktop::_icon_dir)"
    theme="$(recipe_desktop::_theme_name)"
    desk_name="$(recipe_desktop::_desktop_name)"

    rm -f \
        "${app_dir}/${desk_name}" \
        "${app_dir}/photoshop.desktop" \
        "${app_dir}/Adobe Photoshop 2021.desktop" \
        "${app_dir}/Adobe Photoshop.desktop" \
        "${app_dir}/photoshopCC.desktop" \
        "${app_dir}/wiso-steuer.desktop" \
        2>/dev/null || true
    rm -f "${app_dir}"/photoshop.desktop.bak.* 2>/dev/null || true

    if [ -d "${app_dir}/wine" ]; then
        find "${app_dir}/wine" -type f \( -iname "*${RECIPE_ID}*" -o -iname '*photoshop*' -o -iname '*wiso*' \) \
            -delete 2>/dev/null || true
    fi

    while IFS= read -r d; do
        rm -f \
            "$d/${desk_name}" \
            "$d/photoshop.desktop" \
            "$d/wiso-steuer.desktop" \
            2>/dev/null || true
        if [ "$RECIPE_ID" = "photoshop" ]; then
            find "$d" -maxdepth 1 -type f \( -iname '*photoshop*' -o -iname '*adobe*photoshop*' \) \
                -delete 2>/dev/null || true
        fi
        if [ "$RECIPE_ID" = "wiso-steuer" ]; then
            find "$d" -maxdepth 1 -type f \( -iname '*wiso*' \) -delete 2>/dev/null || true
        fi
    done < <(recipe_desktop::_desktop_dirs | recipe_desktop::_unique_existing_dirs)

    # Sicherheitsnetz: kanonischer Dateiname irgendwo unter $HOME (flach)
    if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
        find "$HOME" -maxdepth 3 -type f -name "$desk_name" -delete 2>/dev/null || true
    fi

    for s in 16 22 24 32 48 64 128 256 512; do
        rm -f "${icon_dir}/${s}x${s}/apps/${theme}.png" 2>/dev/null || true
        [ "$RECIPE_ID" = "photoshop" ] && rm -f "${icon_dir}/${s}x${s}/apps/photoshop.png" 2>/dev/null || true
        [ "$RECIPE_ID" = "wiso-steuer" ] && rm -f "${icon_dir}/${s}x${s}/apps/wiso-steuer-wine.png" 2>/dev/null || true
    done
    rm -f "${icon_dir}/scalable/apps/${theme}.svg" 2>/dev/null || true

    command -v gtk-update-icon-cache >/dev/null 2>&1 \
        && [ -d "$icon_dir" ] && gtk-update-icon-cache -f -t "$icon_dir" 2>/dev/null || true
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$app_dir" 2>/dev/null || true
    # KDE: Menü-/Desktop-Cache anstoßen (falls vorhanden)
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental 2>/dev/null || true
    command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 --noincremental 2>/dev/null || true

    if [ -n "${DATA_ROOT:-}" ]; then
        rm -f "$(recipe_desktop::_marker)" 2>/dev/null || true
    fi
    return 0
}

recipe_desktop::refresh_if_present() {
    local app_dir desk_name
    app_dir="$(recipe_desktop::_app_dir)"
    desk_name="$(recipe_desktop::_desktop_name)"
    if [ -f "$(recipe_desktop::_marker)" ] \
        || [ -f "${app_dir}/${desk_name}" ] \
        || [ -f "${app_dir}/photoshop.desktop" ] \
        || [ -f "${app_dir}/wiso-steuer.desktop" ]; then
        recipe_desktop::install
        return $?
    fi
    return 0
}
