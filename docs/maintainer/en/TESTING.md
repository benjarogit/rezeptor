# Test matrix — Rezeptor, unified data root

See **[TEST-PLAN.md](TEST-PLAN.md)** for step-by-step QA.

| Recipe | Runtime | Smoke |
|--------|---------|-------|
| `photoshop` | Proton-GE | install → validate → launch |
| `wiso-steuer` | Proton-GE | source + target → install → start.exe launch |

Quick syntax checks:

```bash
bash -n recipes/photoshop/install.sh
bash -n recipes/wiso-steuer/install.sh
./scripts/recipe-lint.sh
```
