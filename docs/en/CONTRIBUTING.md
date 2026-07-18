# Contributing

Contributions to recipes, launcher, core, and docs are welcome. Keep changes small, testable, and free of secrets.

## Development environment

```bash
git clone https://github.com/benjarogit/rezeptor.git
cd rezeptor
# Distro: python-pyqt6, bats-core, shellcheck (names vary)
pip install --user PyQt6-Fluent-Widgets   # optional
make validate
make test
REZEPTOR_DEV=1 ./setup.sh
```

Docs locally:

```bash
pip install -r requirements-docs.txt
mkdocs serve
```

## Quality gate

Before every PR:

```bash
make validate          # shellcheck, syntax, compile, recipes-check, lint, manifest
make test              # bats
./scripts/recipe-lint.sh
./scripts/recipe-manifest.sh   # after recipe file changes → commit
```

`make validate` → `shellcheck` covers only `core/`, `recipes/photoshop`, `recipes/wiso-steuer`, `launcher/`, `scripts/`.  
`bash -n` (`syntax` target) covers all `recipes/*/*.sh`; for other recipes also run `./scripts/recipe-lint.sh`.

## Recipes

1. `./scripts/new-recipe.sh …` or GUI **New recipe…**
2. `recipe.yml` + hooks per [Developer overview](ENTWICKLER.md)
3. Test with a real source (Install → Validate → Repair → Launch → Uninstall)
4. Update the manifest
5. No app binaries in the repo (BYOS)

Ideas: [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md).

## Docs & translations

- Mirror pages under `docs/de/` and `docs/en/` (same filenames)
- UI strings: [Translations](CONTRIBUTING-TRANSLATIONS.md)
- Brand: [BRAND](BRAND.md) — no purple themes

## Git notes

- SemVer via the `VERSION` file — bump only when a release is intended
- No editor-agent co-author trailers in commits
- Do not commit secrets (tokens, private installers)

## Next

- [Project layout](PROJECT-LAYOUT.md)
- [Trust & manifest](TRUST.md)
- [Release & AppImage](maintainer/RELEASE.md)
