# Reference pattern: Single EXE / trainer (direct launch)

**Audience: recipe authors.** Example recipe: `za4-trainer`

## When to use this pattern

Not a portable suite and not a large offline installer, but a **single Windows `.exe`** (trainer, small tool, “direct launch”). Often with `steam_appid`: target is a subfolder of the Steam game directory.

| GUI | Meaning |
|-----|---------|
| **Source** | The `.exe` (BYOS) |
| **Target** | Folder to copy/run into (often Steam game + `steam_target_folder`) |

In the GUI it is still **Source** / **Target** — not a special “trainer path” label.

## Typical `recipe.yml` corners

- `source_kind: installer` (or similar) — pick one file
- `steam_appid` + optional `steam_target_folder` (default often `Trainer`)
- Prefix: own Rezeptor prefix **or** Steam compatdata — document per recipe
- `version_detect`: e.g. `pe_contains` / `filename_regex` for the EXE family

## Pitfalls

| Pitfall | Note |
|---------|------|
| Game must exist | No useful target without the Steam game installed |
| EXE ≠ game | Trainer runs against the game; Proton/bitness must match |
| Not an online-fix stack | Different pattern → [STEAM-WRAPPER.md](STEAM-WRAPPER.md) |

Quick start: [ENTWICKLER.md](ENTWICKLER.md) · Spec: [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
