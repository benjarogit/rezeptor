# Steam-Wrapper-Rezepte

Muster für Steam-Spiele mit **BYOS** (Bring Your Own Source): Rezeptor verteilt weder Spiel noch Online-Fix.
Referenz-Rezept: `house-of-ashes` — siehe auch `recipes/_template-steam-game/`.

## Prinzip

1. Spiel bleibt in der **normalen Steam-Bibliothek** (echte AppID, z. B. `1281590`).
2. Rezeptor legt **keinen** Steam-Eintrag an und ändert Steam nicht.
3. **Installieren** verknüpft den Spielordner (`deploy_mode: link`), prüft Fix-Dateien und schreibt einen **Launch-Wrapper** unter `~/.local/share/wine-software/<id>/`.
4. **Starten** in Rezeptor startet die EXE über **Rezeptor Proton-GE** (Fallback: Steam GE-Proton) — nicht über die Steam-UI „Play“.

## Spacewar / FakeAppId

Viele Online-Fixes erwarten `SteamAppId=480` (**Spacewar**, kostenloses Valve-Tool).

| Begriff | Bedeutung |
|---------|-----------|
| **RealAppId** | Echte Steam-App des Spiels (compatdata-Prefix) |
| **FakeAppId** | Meist `480` — Steam-API für den Fix |
| **compatdata** | Steam-Proton-Prefix des Spiels; Rezeptor nutzt ihn, legt keinen neuen Prefix an |

Voraussetzungen (typisch):

- Steam läuft und ist angemeldet
- Spacewar für den **Start** (nicht für die reine Einrichtung): `steam steam://install/480` — Install öffnet den Steam-Dialog, blockiert die Einrichtung nicht
- Spiel mindestens einmal über Steam mit Proton/GE gestartet (compatdata vorhanden)
- Fix-Stack im Spielordner (BYOS — Rezeptor liefert keinen Fix)

Während des Spielens zeigt Steam oft **Spacewar**, nicht den Spieltitel.

## Wrapper-Inhalt (vereinfacht)

Der Wrapper setzt u. a.:

- `SteamAppId` / `SteamGameId` = FakeAppId
- `STEAM_COMPAT_DATA_PATH` = compatdata der RealAppId
- `WINEDLLOVERRIDES` für OnlineFix-DLLs
- Proton-Skript: Rezeptor-GE → Steam GE-Proton

Details: `recipes/house-of-ashes/launch.sh`, `recipes/_template-steam-game/install.sh`.

## Deinstallieren

**Deinstallieren** in Rezeptor entfernt nur:

- Rezeptor-Eintrag und State
- Launch-Wrapper unter `data_root`

**Nicht** entfernt werden:

- Das Steam-Spiel
- Der Online-Fix im Spielordner
- Spacewar in der Bibliothek

Siehe `recipes/house-of-ashes/uninstall.sh`.

## Neues Steam-Spiel-Rezept

```bash
./scripts/new-recipe.sh --type steam-game mein-spiel "Mein Spiel"
```

`steam_appid`, `steam_fake_appid`, Fix-Pfade und `exe_glob` in `recipe.yml` anpassen.
