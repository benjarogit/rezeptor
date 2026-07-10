# Test-Matrix — Rezeptor, einheitlicher Daten-Root

Schritt-für-Schritt-QA: **[TEST-PLAN.md](TEST-PLAN.md)**. Englische Vollversion: [maintainer/en/TEST-PLAN.md](../en/TEST-PLAN.md).

| Rezept | Runtime | Smoke |
|--------|---------|-------|
| `photoshop` | Proton-GE | install → validate → launch |
| `wiso-steuer` | Proton-GE | Quelle + Ziel → install → start.exe launch |

Schnelle Syntax-Checks:

```bash
bash -n recipes/photoshop/install.sh
bash -n recipes/wiso-steuer/install.sh
./scripts/recipe-lint.sh
```
