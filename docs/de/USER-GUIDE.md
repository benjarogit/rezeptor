# Benutzerhandbuch

Bedienung der Rezeptor-GUI. Rezept-Autoren: siehe [Entwickler-Übersicht](ENTWICKLER.md).

## Oberfläche

| Element | Rolle |
|---------|--------|
| **Sidebar** | Rezeptliste (ca. 240 px), Status-Pille, Suche/Reihenfolge |
| **Hauptbereich** | Übersicht, Quelle/Ziel, Infotexte |
| **Primary-CTA** | Kontextaktion (Installieren / Starten / …) |
| **Mehr ▾** | Sekundäraktionen (Reparieren, Validieren, Deinstallieren, …) |
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

## Status & Validierung

- Optional **Validieren beim Start** (Einstellungen)
- **F5** / Validieren: strukturierte `OK:` / `FAIL:` / `WARN:`-Ausgabe
- Grün = getestet / bereit; Amber = Warnung; Fehler = Handlungsbedarf

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
