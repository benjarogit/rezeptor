# Trust & manifest

Rezeptor separates **catalog trust** (origin) from **file integrity** (hashes).

## Catalog (`recipes/catalog.json`)

GUI index: `id`, name, category, `path`, summaries, and a **`trust`** field.

| Value | Meaning |
|-------|---------|
| `official` | Bundled / officially maintained |
| `community` | Community / external — not automatically reviewed |

Community recipes under `recipes/community/<id>/` do **not** appear in the official catalog by default and typically have **no** manifest entry → GUI “untrusted”.

Multi-source: Settings → recipe sources (`trusted` flags there are separate). External recipes run scripts — review before install.

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
| Release / AppImage / Flatpak | Strict hash checks |
| `REZEPTOR_DEV=1` | Bypass / developer workflow |
| Git checkout (auto-sync) | Trust does **not** silently stay green after sync — the manifest must not be quietly regenerated as “ok”; the user must re-confirm trust for changed recipes |

Before a PR after file changes, always run `./scripts/recipe-manifest.sh` and commit `recipes/manifest.json`.

The generator hashes only **top-level** dirs `recipes/<id>/` that contain `recipe.yml`, and skips names with a `_` prefix (`_template*`).  
`recipes/community/<id>/` is one level deeper, so it is also out of the manifest (there is no separate community-path skip branch).

## Release assets

GitHub releases include `SHA256SUMS` for the `tar.gz`, AppImage, and `rezeptor-recipes-*.tar.gz` (Flatpak may follow in a separate upload):

```bash
sha256sum -c SHA256SUMS
```

Recipe sync downloads that recipes tarball, verifies its SHA256 against `SHA256SUMS`, then installs into the user overlay with a separate `manifest.overlay.json` — same hash rules as the bundled manifest.

No GPG/cosign signing in the repo — integrity via SHA256 sums.

## Proton-GE

`core/runtime.lock` pins tag, URL, and `PROTON_GE_SHA256`. Download verifies the hash.

## Next

- [Recipe catalog](CATALOG.md)
- [Contributing](CONTRIBUTING.md)
- [GUI launcher](LAUNCHER.md)
