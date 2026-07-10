# Rezeptor — Brand design

## Concept

Recipe card + verification seal: stands for “tested, guaranteed recipes” instead of
trial-and-error. The checkmark in the seal is the same one that later returns as the
“tested” status icon in the GUI — logo and UI share one symbol.

## Colors

| Role              | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| Anthracite (base) | `#1C1C1A` | Background, icon base shape              |
| Copper (accent)   | `#B87333` | Primary button, active recipe, seal      |
| Green (success)   | `#639922` | “Tested” status                          |
| Amber (warning)   | `#d9a441` | “Experimental” status                    |
| Parchment (text)  | `#EDE6D6` | Text on dark background                  |

In `setThemeColor()` (see code example), `#B87333` is set as the theme accent —
that is enough for Fluent widgets to stay consistent automatically.

## Files

- `rezeptor-icon.svg` — square, for window icon / app icon
  (convert to .ico/.png per platform)
- `rezeptor-wordmark.svg` — icon + wordmark, for title bar, README, website
