# Trust & manifest

Rezeptor separates **catalog trust** (origin) from **file integrity** (hashes).

## Catalog (`recipes/catalog.json`)

GUI index: `id`, name, category, `path`, summaries, and a **`trust`** field.

| Value | Meaning |
|-------|---------|
| `official` | Bundled / officially maintained |
| Community / external | Not automatically reviewed |

Community recipes under `recipes/community/<id>/` do **not** appear in the official catalog by default and typically have **no** manifest entry → GUI “untrusted”.

Multi-source: Settings → recipe sources. External recipes run scripts — review before install.

## Manifest (`recipes/manifest.json`)

SHA256 over all files per official recipe:

```json
{
  "version": 1,
  "recipes": {
    "<id>": {
      "files": { "recipe.yml": "sha256:…", "install.sh": "sha256:…" }
    }
  }
}
```

- Generator: `./scripts/recipe-manifest.sh`
- CI: `make recipe-manifest-check` (diff against regenerated manifest must be empty)
- Verification: `launcher/recipe_trust.py` (`verify_recipe_trust`)

### When strict / when loose

| Context | Behavior |
|---------|----------|
| Release / AppImage | Strict hash checks |
| `REZEPTOR_DEV=1` | Bypass / developer workflow |
| Git checkout | Manifest auto-sync often allowed |

Before a PR after file changes, always run `./scripts/recipe-manifest.sh` and commit `recipes/manifest.json`.

Templates `_template*` and community are excluded from the manifest generator (`_` prefix / community path).

## Release assets

GitHub releases include `SHA256SUMS` for the `tar.gz` and AppImage:

```bash
sha256sum -c SHA256SUMS
```

No GPG/cosign signing in the repo — integrity via SHA256 sums.

## Proton-GE

`core/runtime.lock` pins tag, URL, and `PROTON_GE_SHA256`. Download verifies the hash.

## Next

- [Recipe catalog](CATALOG.md)
- [Contributing](CONTRIBUTING.md)
- [GUI launcher](LAUNCHER.md)
