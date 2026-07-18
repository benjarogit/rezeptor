# Rezeptor — Markendesign

## Idee
Rezeptkarte + Prüfsiegel: steht für "getestete, garantierte Rezepte" statt
Trial-and-Error. Der Haken im Siegel ist derselbe, der später als
Status-Icon für "getestet" im GUI wiederkehrt — Logo und UI teilen sich
ein Symbol.

Produkt-UI, README und Dokumentation bleiben zweisprachig (Deutsch + Englisch).

## Farben

| Rolle              | Hex       | Verwendung                              |
|--------------------|-----------|------------------------------------------|
| Anthrazit (Basis)   | `#1C1C1A` | Hintergrund, Icon-Grundform              |
| Kupfer (Akzent)     | `#B87333` | Primär-Button, aktives Rezept, Siegel   |
| Grün (Erfolg)       | `#639922` | "Getestet"-Status                       |
| Amber (Warnung)     | `#d9a441` | "Experimentell"-Status                  |
| Pergament (Text)    | `#EDE6D6` | Text auf dunklem Grund                  |

## GUI (verbindlich)

Produkt-UI immer **Fluent Dark** + Kupfer — kein System-Light-Hybrid, kein PyQtDarkTheme.
Umsetzung: `launcher/ui_fluent.py` (`Theme.DARK`, `setThemeColor("#B87333")`) und Host-QSS in `ui_styles.py`.
Fluent-Widgets nicht mit Host-QSS „übermalen“. Details: [LAUNCHER.md](LAUNCHER.md).

## Dateien
- `images/rezeptor-icon.svg` / `docs/assets/rezeptor-icon.svg` — quadratisch, Fenster-/App-Icon
- `docs/assets/rezeptor-wordmark.svg` — Icon + Schriftzug, Titelleiste, README, Website
