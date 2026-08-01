# Benutzerhandbuch

Bedienung der Rezeptor-GUI. Rezept-Autoren: siehe [Entwickler-Übersicht](ENTWICKLER.md).

## Oberfläche

| Element | Rolle |
|---------|--------|
| **Sidebar** | Rezeptliste, Statuspunkt (Warn-Icon nur bei Teilweise / nicht freigegeben), Suche/Reihenfolge |
| **Hauptbereich** | Übersicht, Quelle/Ziel, Infotexte |
| **Primary-CTA** | Kontextaktion (Installieren / Starten / Freigeben / **Jetzt reparieren** / …) |
| **Mehr ▾** | Sekundäraktionen (Validieren, Deinstallieren, …) |
| **Medizin** | Eigener Button neben Mehr — dauerhafte Rezept-Optionen (siehe unten) |
| **Vorgang / Activity** | Humanisierte Log-Zeilen aus Hook-Skripten |

Thema: Fluent Dark + Kupfer (`#B87333`) — siehe [Marke](BRAND.md).

## Typischer Ablauf

1. Rezept wählen
2. **Quelle** speichern (Pfad zum Installer / Portable / EXE)
3. Ggf. **Ziel** (Portable-Zielordner)
4. **Installieren**
5. Optional: Validieren (F5 oder Menü)
6. **Starten**
7. Bei Problemen: **Reparieren** (behebt Abweichungen, installiert nicht neu)
8. **Deinstallieren** entfernt Rezeptor-State vollständig — Portable/Steam außerhalb bleiben

## Medizin (Rezept-Optionen)

Button **Medizin** (Verbandskasten-Icon) neben **Mehr** — nicht im Mehr-Menü.

Dauerhafte Schalter pro Rezept (`options.env`). Nach dem Umschalten erscheint oft der Primary-Button **„Jetzt reparieren“** — einmal tippen, sonst bleiben die alten Einstellungen aktiv.

### Photoshop (CC 2021)

Unter Wine sind manche Windows-UI-Features fragil. Rezeptor setzt deshalb standardmäßig sichere Prefs (kein Startbildschirm, Tooltips aus, Legacy-Neu-Dialog). Wenn es bei dir unter Windows-Feeling stabil läuft, kannst du einzeln freigeben:

| Option | Wirkung |
|--------|---------|
| Startbildschirm (Home) | Wie unter Windows — bei weißem/leerem Workspace wieder aus + Reparieren |
| Animierte / ausführliche Tooltips | Kann Textwerkzeug/Plugins stören |
| Moderner Neu-Dialog | Großer Neu-Dialog — kann schwarze Felder / weiße Fläche auslösen |

Standard jeweils **aus**. Details auch in den Tipps im Medizin-Dialog.

## Status & Validierung

- Optional **Validieren beim Start** (Einstellungen)
- **F5** / Validieren: strukturierte `OK:` / `FAIL:` / `WARN:`-Ausgabe
- Grün = getestet / bereit; Amber = Warnung; Fehler = Handlungsbedarf
- Sidebar-Warn-Icon = Reparatur oder Freigabe nötig — nicht bei „nicht installiert“

## Einstellungen

Datei: `~/.local/share/wine-software/rezeptor/settings.json`

Typische Optionen:

| Einstellung | Wirkung |
|-------------|---------|
| Sprache | `de` / `en` (weitere über Locale-Manifest) |
| Entwicklermodus | Entspricht `REZEPTOR_DEV=1` |
| Validieren beim Start | Auto-Validate |
| Log-Aufbewahrung | Alte Logs aufräumen |
| Archiv-Passwörter | Für geschützte Archive |
| Rezept-Quellen | Extra-Kataloge / Pfade |
| Ausgeblendete Rezepte | Nur Liste; Daten bleiben |

## Ausblenden vs. Deinstallieren

| Aktion | Wirkung |
|--------|---------|
| **Ausblenden** | Verschwindet aus der Liste; Daten bleiben |
| **Deinstallieren** | `uninstall.sh` → `purge_recipe_data` (Desktop + data_root) |

Details: [Deinstallation](UNINSTALL.md) · [Katalog](CATALOG.md)

## Updates

Releases von GitHub; Auto-Update wo angeboten. Nach dem Update `sha256sum` der Assets prüfen, wenn du manuell lädst.

## Hilfe & Bugs

- In-App: **Hilfe → Entwickler-Dokumentation…** (Autoren-Seiten)
- GitHub Issues / Bug-Report-Vorlage (Zwischenablage kann den Report-Body enthalten)
- Session-ID steht im Report-File, nicht in der Statusleiste

## Weiter

- [Schnellstart](GETTING-STARTED.md)
- [Trust & Manifest](TRUST.md)
- [GUI-Launcher (technisch)](LAUNCHER.md)
