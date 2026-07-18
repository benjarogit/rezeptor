# Validate & Repair

Vertrag zwischen `validate.sh`, `repair.sh` und der GUI. **Reparieren ≠ neu installieren.**

## Validate

### Pflichtverhalten

1. `recipe_hooks::load validate`
2. Strukturierte Zeilen:
   - `OK: …` (stdout)
   - `FAIL: …` (stderr) — zählt als Fehler
   - `WARN: …` (stderr) — **kein** Exit-Fehler
3. Optional GUI-Fortschritt: `output::progress_begin` / `tick` / `done`
4. Exit **0** wenn keine `FAIL`; Exit **1** bei mindestens einem `FAIL`

### Empfohlene Checks

Nutze `core/recipe-validate.sh`:

```bash
recipe_validate::prefix_initialized "$WINEPREFIX" || failures=$((failures+1))
recipe_validate::windows_version "$WINEPREFIX" || true   # oder fail je nach Rezept
recipe_validate::ok "Prefix vorhanden"
```

App-spezifisch: EXE-Pfade, Portable-Root, Fix-Dateien (Steam), Versionsgarantie.

### Version

Bei `version_guaranteed` + `version_detect` in `recipe.yml`: Abweichung oft als `WARN` (nicht zwingend hart failen — je nach Rezeptpolitik). Lint verlangt `version_detect`, wenn `version_guaranteed` gesetzt ist.

---

## Repair

### Pflichtverhalten

1. `recipe_hooks::load repair`
2. Zuerst `validate.sh` (oder äquivalente Checks)
3. Wenn alles OK: höchstens Sync (Fonts/Grafik/Desktop-Refresh)
4. Wenn FAIL: **nur fehlende** Komponenten nachziehen
5. Erneut validieren
6. Exit **0** Erfolg; Exit **11** unvollständig (GUI-Retry möglich)

### Erlaubt / Verboten

| Erlaubt | Verboten |
|---------|----------|
| `recipe_winetricks::run` für fehlende Pakete | Volles `install_steps` / Neuinstallation |
| `recipe_win10::ensure` | winetricks winecfg |
| `recipe_vcrun::ensure` / `recipe_dotnet::ensure` | System-Wine-Fallback |
| `wine_runtime::deploy_proton_graphics_dlls` | winetricks dxvk |
| Desktop `refresh_if_present` | `load kill` |

### Muster (Pseudocode)

```bash
recipe_hooks::load repair
# … validate …
if [[ $failures -eq 0 ]]; then
  # optional: fonts/graphics sync
  exit 0
fi
# gezielte Fixes nur für FAIL-Punkte
# validate erneut
```

### Sonderfälle

- **WISO:** fehlender Prefix → Fehler „bitte Installieren“, kein Repair-from-scratch
- **Photoshop:** oft Fonts/Grafik/Post-Install auch bei grünem Validate syncen

---

## CI

`make recipes-check` verlangt `validate:` und `repair:` in jeder `recipe.yml`.  
Manuell: bewusst etwas kaputt machen → Reparieren → Validate grün.

## Weiter

- [Core-API](CORE-API.md)
- [Deinstallation](UNINSTALL.md)
- [Log-Protokoll](LOG-PROTOCOL.md)
