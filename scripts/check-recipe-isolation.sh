#!/usr/bin/env bash
# Enforce recipe sandbox: no official recipe-id literals in shared core/launcher,
# and no recipe A sourcing recipe B (or another recipe's core module).
set -eu
(set -o pipefail 2>/dev/null) || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

err() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

# Official recipe ids (catalog folders with recipe.yml, skip templates).
ids=()
for yml in "$ROOT"/recipes/*/recipe.yml "$ROOT"/recipes/community/*/recipe.yml; do
    [ -f "$yml" ] || continue
    case "$yml" in
        */_*) continue ;;
    esac
    id="$(basename "$(dirname "$yml")")"
    ids+=("$id")
done

# Family modules may mention products; id-specific core/recipe-<id>* is allowed.
is_family_module() {
    case "$(basename "$1")" in
        recipe-adobe-setup.sh|recipe-lightroom-stubs.sh) return 0 ;;
    esac
    return 1
}

is_id_specific_core() {
    local base
    base="$(basename "$1")"
    local id
    for id in "${ids[@]}"; do
        case "$base" in
            "recipe-${id}.sh"|"recipe-${id}-"*) return 0 ;;
        esac
        # photoshop-m0nkrus may share recipe-photoshop-*.sh
        case "$id" in
            *-*)
                local stem="${id%%-*}"
                case "$base" in
                    "recipe-${stem}.sh"|"recipe-${stem}-"*) return 0 ;;
                esac
                ;;
        esac
    done
    return 1
}

# Quoted id, case-arm id, or ${RECIPE_ID:-id} default.
id_literal_hits() {
    local file="$1" id="$2"
    python3 - "$file" "$id" <<'PY'
import re, sys
path, rid = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
pats = [
    re.compile(r'(["\'])' + re.escape(rid) + r'\1'),
    re.compile(r'(?m)^[ \t]*(?:' + re.escape(rid) + r')(?:\)|\|)'),
    re.compile(r':-' + re.escape(rid) + r'[}]'),
]
hits = []
for i, line in enumerate(text.splitlines(), 1):
    if line.lstrip().startswith("#"):
        continue
    for pat in pats:
        if pat.search(line):
            hits.append(f"{i}:{line.strip()}")
            break
if hits:
    print("\n".join(hits))
    sys.exit(1)
sys.exit(0)
PY
}

echo "Isolation: scanning shared core/launcher for recipe-id literals…"
while IFS= read -r -d '' f; do
    rel="${f#"$ROOT"/}"
    if is_family_module "$f" || is_id_specific_core "$f"; then
        continue
    fi
    for id in "${ids[@]}"; do
        hits="$(id_literal_hits "$f" "$id" || true)"
        if [ -n "$hits" ]; then
            err "$rel: recipe-id literal '$id'"
            printf '%s\n' "$hits" | sed 's/^/    /' >&2
        fi
    done
done < <(find "$ROOT/core" "$ROOT/launcher" -type f \( -name '*.sh' -o -name '*.py' \) -print0)

echo "Isolation: scanning recipe scripts for cross-source…"
# recipes/A must not source recipes/B or core/recipe-B-* except family / own stem.
for yml in "$ROOT"/recipes/*/recipe.yml "$ROOT"/recipes/community/*/recipe.yml; do
    [ -f "$yml" ] || continue
    case "$yml" in
        */_*) continue ;;
    esac
    dir="$(dirname "$yml")"
    rid="$(basename "$dir")"
    stem="${rid%%-*}"
    shopt -s nullglob
    for f in "$dir"/*.sh; do
        while IFS= read -r line; do
            case "$line" in
                *source*|*"."[[:space:]]*) ;;
                *) continue ;;
            esac
            # recipes/<other>/
            if echo "$line" | grep -qE 'recipes/[^/]+/'; then
                other="$(echo "$line" | sed -n 's/.*recipes\/\([^/]*\)\/.*/\1/p')"
                if [ -n "$other" ] && [ "$other" != "$rid" ] && [ "$other" != "community" ]; then
                    err "$(basename "$dir")/$(basename "$f"): sources recipes/$other/"
                fi
            fi
            # core/recipe-<mod>
            if echo "$line" | grep -qE 'recipe-[a-z0-9-]+\.sh'; then
                mod="$(echo "$line" | sed -n 's/.*\(recipe-[a-z0-9-]*\.sh\).*/\1/p')"
                [ -n "$mod" ] || continue
                case "$mod" in
                    recipe-hooks.sh|recipe-install.sh|recipe-desktop.sh|recipe-prefix.sh|recipe-validate.sh|recipe-winetricks.sh|recipe-win10.sh|recipe-vcrun.sh|recipe-dotnet.sh|recipe-wine-silent.sh|recipe-source.sh|recipe-iso.sh|recipe-updates.sh|recipe-install-steps.sh|recipe-deploy.sh|recipe-app-link.sh|recipe-relocate.sh|recipe-kill.sh|recipe-assets.sh) continue ;;
                    recipe-adobe-setup.sh|recipe-lightroom-stubs.sh) continue ;;
                    "recipe-${rid}.sh"|"recipe-${rid}-"*) continue ;;
                    "recipe-${stem}.sh"|"recipe-${stem}-"*) continue ;;
                esac
                # Unknown recipe-<something>.sh — flag if it matches another official id stem
                for id in "${ids[@]}"; do
                    other_stem="${id%%-*}"
                    case "$mod" in
                        "recipe-${id}.sh"|"recipe-${id}-"*|"recipe-${other_stem}.sh"|"recipe-${other_stem}-"*)
                            if [ "$id" != "$rid" ] && [ "$other_stem" != "$stem" ]; then
                                err "$(basename "$dir")/$(basename "$f"): sources $mod (other recipe)"
                            fi
                            ;;
                    esac
                done
            fi
        done < "$f"
    done
    shopt -u nullglob
done

if [ "$errors" -gt 0 ]; then
    echo "check-recipe-isolation: $errors Fehler" >&2
    exit 1
fi
echo "check-recipe-isolation: OK"
