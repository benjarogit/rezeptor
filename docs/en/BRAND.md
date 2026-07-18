# Rezeptor — Brand design

## Concept

Recipe card + verification seal: stands for “tested, guaranteed recipes” instead of
trial-and-error. The checkmark in the seal is the same one that later returns as the
“tested” status icon in the GUI — logo and UI share one symbol.

Product UI, README, and docs stay bilingual (English + German).

## Colors

| Role              | Hex       | Usage                                    |
|-------------------|-----------|------------------------------------------|
| Anthracite (base) | `#1C1C1A` | Background, icon base shape              |
| Copper (accent)   | `#B87333` | Primary button, active recipe, seal      |
| Green (success)   | `#639922` | “Tested” status                          |
| Amber (warning)   | `#d9a441` | “Experimental” status                    |
| Parchment (text)  | `#EDE6D6` | Text on dark background                  |

## GUI (required)

Product UI is always **Fluent Dark** + copper — no system-light hybrid, no PyQtDarkTheme.
Implementation: `launcher/ui_fluent.py` (`Theme.DARK`, `setThemeColor("#B87333")`) and host QSS in `ui_styles.py`.
Do not override Fluent widgets with host QSS. Details: [LAUNCHER.md](LAUNCHER.md).

## Files

- `images/rezeptor-icon.svg` / `docs/assets/rezeptor-icon.svg` — square, window/app icon
- `docs/assets/rezeptor-wordmark.svg` — icon + wordmark, title bar, README, website
