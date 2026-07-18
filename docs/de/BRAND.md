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

In `setThemeColor()` (siehe Code-Beispiel) wird `#B87333` als Theme-Akzent
gesetzt — das reicht, damit Fluent-Widgets automatisch konsistent bleibt.

## Dateien
- `rezeptor-icon.svg` — quadratisch, für Fenster-Icon / App-Icon
  (in .ico/.png konvertieren je nach Plattform)
- `rezeptor-wordmark.svg` — Icon + Schriftzug, für Titelleiste, README, Website
