#!/usr/bin/env bash
# Lint official recipe directories (includes _template for CI).
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES="$ROOT/recipes"

REQUIRED_KEYS=(id name icon data_root runtime install_type source_kind fix_kind)
REQUIRED_HOOKS=(install launch validate repair kill uninstall)
OPTIONAL_HOOKS=()
INSTALL_TYPES=(installer_offline portable_launch portable_bootstrap game_install game_portable adobe_offline portable)
SOURCE_KINDS=(folder installer archive fixed_path)
FIX_KINDS=(none optional required)
ALLOWED_ROOT_SH=(install launch validate repair kill uninstall)

errors=0
warnings=0

lint_err() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
lint_warn() { echo "WARN: $*" >&2; warnings=$((warnings + 1)); }

recipe_get() {
    local file="$1" key="$2" line
    line=$(grep -E "^${key}:" "$file" 2>/dev/null | head -1) || return 1
    line="${line#*:}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%$'\r'}"
    line="${line#\"}"
    line="${line%\"}"
    echo "$line"
}

lint_forbidden_patterns() {
    local base="$1" f="$2"
    if grep -qE 'winetricks[[:space:]].*dxvk|winetricks[[:space:]]+dxvk' "$f" 2>/dev/null; then
        lint_err "$base: $(basename "$f"): winetricks dxvk verboten — wine_runtime::deploy_proton_graphics_dlls nutzen"
    fi
    if grep -qE 'command[[:space:]]+-v[[:space:]]+wine[[:space:]]|WINE=.*(/usr/bin/wine|wine$)' "$f" 2>/dev/null; then
        if grep -qE 'system.wine|System-Wine|fallback.*wine' "$f" 2>/dev/null; then
            lint_err "$base: $(basename "$f"): System-Wine-Fallback verboten — nur Proton-GE"
        fi
    fi
    if grep -qE 'winetricks[[:space:]].*winecfg|winetricks[[:space:]]+win10' "$f" 2>/dev/null \
        && grep -qE 'recipe_win10::ensure|settings[[:space:]]+win10' "$f" 2>/dev/null; then
        lint_err "$base: $(basename "$f"): doppeltes win10 (winetricks + recipe_win10) — nur recipe_win10::ensure"
    fi
}

lint_recipe_dir() {
    local dir="$1"
    local yml="$dir/recipe.yml"
    local id base hook val f rel

    [ -f "$yml" ] || { lint_err "$dir: recipe.yml fehlt"; return; }
    base="$(basename "$dir")"

    for key in "${REQUIRED_KEYS[@]}"; do
        val="$(recipe_get "$yml" "$key" 2>/dev/null || true)"
        [ -n "$val" ] || lint_err "$base: Pflichtfeld fehlt: $key"
    done

    # Icon-Datei muss existieren ({repo}/images/… oder relativ)
    icon="$(recipe_get "$yml" icon 2>/dev/null || true)"
    if [ -n "$icon" ]; then
        icon_path="${icon//\{repo\}/$ROOT}"
        icon_path="${icon_path/#\~/$HOME}"
        if [ ! -f "$icon_path" ]; then
            lint_err "$base: icon-Datei fehlt: $icon"
        fi
    fi

    id="$(recipe_get "$yml" id 2>/dev/null || true)"
    runtime="$(recipe_get "$yml" runtime 2>/dev/null || true)"
    install_type="$(recipe_get "$yml" install_type 2>/dev/null || true)"
    source_kind="$(recipe_get "$yml" source_kind 2>/dev/null || true)"
    fix_kind="$(recipe_get "$yml" fix_kind 2>/dev/null || true)"
    source_formats="$(recipe_get "$yml" source_formats 2>/dev/null || true)"

    if [ "$runtime" != "proton-ge" ] && [ "$runtime" != "system" ]; then
        lint_err "$base: runtime muss proton-ge oder system sein (ist: $runtime)"
    fi

    case " $install_type " in
        *" adobe_offline "*|*" portable "*) lint_warn "$base: install_type '$install_type' ist deprecated — bitte migrieren" ;;
    esac
    local ok=0
    for t in "${INSTALL_TYPES[@]}"; do
        [ "$install_type" = "$t" ] && ok=1 && break
    done
    [ "$ok" -eq 1 ] || lint_err "$base: unbekannter install_type: $install_type"

    ok=0
    for t in "${SOURCE_KINDS[@]}"; do
        [ "$source_kind" = "$t" ] && ok=1 && break
    done
    [ "$ok" -eq 1 ] || lint_err "$base: unbekannter source_kind: $source_kind"

    ok=0
    for t in "${FIX_KINDS[@]}"; do
        [ "$fix_kind" = "$t" ] && ok=1 && break
    done
    [ "$ok" -eq 1 ] || lint_err "$base: unbekannter fix_kind: $fix_kind"

    if [ "$source_kind" = "archive" ] && [ -z "$source_formats" ]; then
        lint_err "$base: source_kind=archive erfordert source_formats"
    fi
    if [ "$source_kind" = "fixed_path" ]; then
        val="$(recipe_get "$yml" installer_dir 2>/dev/null || true)"
        [ -n "$val" ] || lint_err "$base: fixed_path erfordert installer_dir"
    fi

    deploy_mode="$(recipe_get "$yml" deploy_mode 2>/dev/null || echo copy)"
    if [ "$install_type" = "portable_launch" ] && [ "$deploy_mode" = "copy" ]; then
        val="$(recipe_get "$yml" target_default 2>/dev/null || true)"
        [ -n "$val" ] || lint_warn "$base: portable_launch+copy ohne target_default"
    fi

    # install_type rule packs
    case "$install_type" in
        portable_launch|portable_bootstrap|game_portable)
            val="$(recipe_get "$yml" exe_glob 2>/dev/null || true)"
            [ -n "$val" ] || val="$(recipe_get "$yml" portable_root 2>/dev/null || true)"
            [ -n "$val" ] || lint_err "$base: portable install_type braucht exe_glob oder portable_root"
            ;;
        installer_offline|game_install|adobe_offline)
            if [ "$source_kind" = "fixed_path" ]; then
                val="$(recipe_get "$yml" installer_dir 2>/dev/null || true)"
                [ -n "$val" ] || lint_err "$base: installer install_type + fixed_path braucht installer_dir"
            fi
            ;;
    esac

    if ! grep -qE '^install_steps:' "$yml" 2>/dev/null; then
        lint_err "$base: install_steps fehlt (Pflicht)"
    fi

    # version_guaranteed ohne version_detect → keine Quelle-Prüfung in der GUI
    vg="$(recipe_get "$yml" version_guaranteed 2>/dev/null || true)"
    if [ -n "$vg" ]; then
        if ! grep -qE '^version_detect:' "$yml" 2>/dev/null; then
            lint_err "$base: version_guaranteed gesetzt, aber version_detect fehlt (Versionserkennung Pflicht)"
        fi
    fi

    for hook in "${REQUIRED_HOOKS[@]}"; do
        val="$(recipe_get "$yml" "$hook" 2>/dev/null || true)"
        [ -n "$val" ] || { lint_err "$base: Hook fehlt in recipe.yml: $hook"; continue; }
        f="$dir/$val"
        [ -f "$f" ] || lint_err "$base: Hook-Datei fehlt: $val"
        [ -x "$f" ] || lint_err "$base: Hook nicht ausführbar: $val"
    done

    for hook in "${OPTIONAL_HOOKS[@]}"; do
        val="$(recipe_get "$yml" "$hook" 2>/dev/null || true)"
        [ -z "$val" ] && continue
        f="$dir/$val"
        [ -f "$f" ] || lint_err "$base: optionale Hook-Datei fehlt: $val"
        [ -x "$f" ] || lint_err "$base: optionale Hook nicht ausführbar: $val"
    done

    shopt -s nullglob
    for f in "$dir"/*.sh; do
        rel="$(basename "$f")"
        local allowed=0
        for a in "${ALLOWED_ROOT_SH[@]}"; do
            [ "$rel" = "$a.sh" ] && allowed=1 && break
        done
        [ "$allowed" -eq 1 ] || lint_err "$base: unbekanntes Root-Skript: $rel (nur Hooks erlaubt)"
    done
    shopt -u nullglob

    for f in "$dir"/install.sh "$dir"/launch.sh "$dir"/validate.sh "$dir"/repair.sh "$dir"/kill.sh "$dir"/uninstall.sh; do
        [ -f "$f" ] || continue
        grep -q 'recipe-hooks\.sh' "$f" 2>/dev/null \
            || lint_err "$base: $(basename "$f") muss core/recipe-hooks.sh nutzen"
        lint_forbidden_patterns "$base" "$f"
    done

    # Deinstallation muss vollständig sein (kein „teilweise weg → GUI denkt noch installiert“)
    if [ -f "$dir/uninstall.sh" ]; then
        if ! grep -qE 'recipe_hooks::purge_recipe_data' "$dir/uninstall.sh" 2>/dev/null; then
            lint_err "$base: uninstall.sh muss recipe_hooks::purge_recipe_data aufrufen (kompletter Wipe inkl. data_root.path)"
        fi
        if grep -qE 'recipe_hooks::load[[:space:]]+kill' "$dir/uninstall.sh" 2>/dev/null; then
            lint_err "$base: uninstall.sh darf nicht 'load kill' nutzen (Proton/wineserver-Hang) — load minimal + pkill"
        fi
        # Halbherziges Aufräumen ohne Purge: nur Prefix / nur recipe.env
        if grep -qE 'rm[[:space:]]+-rf[[:space:]]+"\$\{?DATA_ROOT\}?/prefix"|rm[[:space:]]+-f.*"\$\(recipe_hooks::state_file' "$dir/uninstall.sh" 2>/dev/null \
            && ! grep -qE 'recipe_hooks::purge_recipe_data' "$dir/uninstall.sh" 2>/dev/null; then
            lint_err "$base: uninstall.sh räumt unvollständig auf — purge_recipe_data Pflicht"
        fi
    fi

    for f in "$dir"/install.sh "$dir"/launch.sh "$dir"/repair.sh; do
        [ -f "$f" ] || continue
        if grep -qE 'curl\s+[^|]+\|\s*(ba)?sh' "$f" 2>/dev/null; then
            lint_warn "$base: $(basename "$f"): curl|bash Muster"
        fi
        if grep -qE '\beval\b' "$f" 2>/dev/null; then
            lint_warn "$base: $(basename "$f"): eval gefunden"
        fi
    done
}

for dir in "$RECIPES"/*/; do
    [ -d "$dir" ] || continue
    lint_recipe_dir "$dir"
done

# Schema / install_steps structure
if [ -f "$ROOT/scripts/recipe-schema-check.py" ]; then
    if ! python3 "$ROOT/scripts/recipe-schema-check.py"; then
        errors=$((errors + 1))
    fi
fi

if [ "$errors" -gt 0 ]; then
    echo "recipe-lint: $errors Fehler, $warnings Warnungen" >&2
    exit 1
fi
echo "recipe-lint: OK ($warnings Warnungen)"
exit 0
