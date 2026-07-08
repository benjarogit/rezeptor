#!/usr/bin/env bash
# Lint official recipe directories (includes _template for CI).
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES="$ROOT/recipes"

REQUIRED_KEYS=(id name data_root runtime install_type source_kind fix_kind)
REQUIRED_HOOKS=(install launch validate repair kill)
OPTIONAL_HOOKS=(uninstall)
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
        [ -n "$val" ] || lint_warn "$base: fixed_path ohne installer_dir"
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

if [ "$errors" -gt 0 ]; then
    echo "recipe-lint: $errors Fehler, $warnings Warnungen" >&2
    exit 1
fi
echo "recipe-lint: OK ($warnings Warnungen)"
exit 0
