## Summary

<!-- What changed and why (1–3 bullets). -->

## Test plan

- [ ] `make validate` (and ideally `make test` / `make pytest`; CI aggregator job is still named `validate`)
- [ ] `make test` (or note why skipped)
- [ ] Manual check if UI / recipe / Flatpak / AppImage touched:

## Docs

- [ ] No doc update needed, or updated `docs/de` + `docs/en` (and README if user-facing)

## Merge gate

`main` requires a green `validate` check. Do not merge with a red CI run.
