# Referenz-Rezept: WISO Steuer (Portable)

**Zielgruppe: Rezept-Autoren.** Endnutzer-Hilfe steht in der GUI unter Rezept-Info (`info.de.txt` / `info.en.txt`), nicht hier.

Rezept-ID: `wiso-steuer` · Runtime: **Proton-GE** · Start: **`start.exe`** (nicht `wiso2026.exe` direkt)

## Warum Referenz?

Vollständige deklarative `install_steps`-Zerlegung in `recipe.yml` + App-Modul `core/recipe-wiso-steuer.sh`. Muster für:

- Portable-Quelle → Ziel (`prepare_source` / `deploy`)
- Prefix, winetricks, vcrun, Wine-Mono
- App-spezifische Module (`recipe_wiso::…`)
- Desktop-Eintrag, validate/repair/kill

Vorlage: `recipes/_template/` · Spezifikation: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)

## Architektur (kurz)

```
recipe.yml          → install_steps (Vertrag)
install.sh          → recipe_hooks::load install + recipe_install_steps::run
core/recipe-wiso-steuer.sh → module:-Schritte (Portable, Qt-Fix, Desktop, …)
validate.sh / repair.sh / kill.sh / uninstall.sh → Lifecycle
```

Getestete Version: `version_guaranteed` in `recipe.yml` (aktuell 33.05.3220).

## Wichtige Design-Entscheidungen

| Thema | Entscheidung |
|-------|----------------|
| Start | `start.exe` im Portable-Root (nicht EXE direkt) |
| Grafik | **wined3d**, kein DXVK (Qt/WebEngine) |
| Schriften | corefonts + Tahoma/Calibri, Segoe → Calibri/Tahoma |
| Qt-Netzwerk | `qnetworklistmanager.dll` umbenennen (sonst Start-Crash unter Wine) |
| Daten | Prefix unter `~/.local/share/wine-software/wiso-steuer/` — Portable-Ordner bleibt User-Eigentum |

## Smoke für Autoren

```bash
REZEPTOR_DEV=1 ./setup.sh
# Quelle = Portable-Ordner, Ziel = z. B. ~/Dokumente/WISO Steuer 2026
bash recipes/wiso-steuer/validate.sh
bash recipes/wiso-steuer/launch.sh   # dann Beenden in der GUI
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh         # nach Datei-Änderungen
```

## Bekannte Wine/Qt-Fallen (für Rezept-Logik)

| Symptom | Rezept-Seite |
|---------|----------------|
| Mono-/wineboot-Dialoge | `recipe_hooks::hint_wine_popup` — User muss OK/Installieren klicken |
| Absturz nach Sekunden | Qt-Netzwerk-Plugin + validate/repair |
| Header überlappt maximiert | keine Wine-Dekoration, Fenster-Modus (~1600×900) |
| Virtual-Desktop-Reste | `kill.sh` räumt `explorer.exe /desktop=wiso` auf |

Logs: `~/.local/share/wine-software/logs/wiso-steuer_*`

Weiter: [ENTWICKLER.md](ENTWICKLER.md) · [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) · [RECIPES.md](RECIPES.md)
