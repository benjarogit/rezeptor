# Deinstallation

Harter Vertrag: nach Uninstall ist die GUI bei **Nicht installiert**, und unter `~/.local/share/wine-software/<id>/` bleiben **keine** Rezeptor-Reste.

## Pflicht in jedem Rezept

1. `uninstall:` in `recipe.yml` zeigt auf `uninstall.sh`
2. Skript nutzt `recipe_hooks::load minimal`
3. Skript ruft **`recipe_hooks::purge_recipe_data`** auf
4. Kein `recipe_hooks::load kill` (Proton/Hang)

Vorlage und CI (`recipes-check`, `tests/uninstall-purge.bats`) erzwingen das.

## Was `purge_recipe_data` entfernt

Reihenfolge:

1. `recipe_desktop::remove` (Menü- + Desktop-Verknüpfungen, Icons) — best effort
2. Gewählten `DATA_ROOT` (GUI-Ziel / `data_root.path`)
3. Kanonischen `data_root` aus YAML, falls verschieden und noch vorhanden

Enthalten typischerweise: `prefix/`, `recipe.env`, Marker, Staging, Wrapper unter dem Rezept-Datenort.

Sicherheit: Löschen von `/`, `$HOME`, `/usr`, `/etc` usw. wird blockiert.

## Was bewusst bleibt

| Bleibt | Warum |
|--------|--------|
| Portable-Ordner außerhalb von `DATA_ROOT` | User-Eigentum (z. B. WISO unter `~/Dokumente/…`) |
| Steam-Spielordner / Online-Fix | BYOS; Wrapper entfernt nur Rezeptor-State |
| Geteiltes Proton-GE unter `runtime/proton-ge/` | Wird von anderen Rezepten genutzt |
| Launcher-Settings | Global unter `…/rezeptor/settings.json` |

## Minimalbeispiel `uninstall.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RECIPE_DIR/../../core/recipe-hooks.sh"
recipe_hooks::load minimal
# optional: pkill app processes
recipe_hooks::purge_recipe_data
```

## Verboten

- Nur `prefix/` oder nur `recipe.env` löschen
- „Soft uninstall“, der die GUI als installiert stehen lässt
- Deinstall-Logik in Rezepten neu erfinden statt `purge_recipe_data`

## Manueller Check

1. Installieren → Uninstall
2. GUI zeigt „Nicht installiert“
3. `ls ~/.local/share/wine-software/<id>/` → leer/fehlend
4. Portable/Steam außerhalb noch vorhanden (falls zuvor so genutzt)

## Weiter

- [Core-API](CORE-API.md) — `purge_recipe_data`
- [Benutzerhandbuch](USER-GUIDE.md) — Ausblenden vs. Deinstallieren
