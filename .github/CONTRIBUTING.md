# Contributing

Please use the curated docs — this file only exists so GitHub’s Community health check finds a CONTRIBUTING entry.

| | |
|--|--|
| **Deutsch** | [docs/de/CONTRIBUTING.md](../docs/de/CONTRIBUTING.md) |
| **English** | [docs/en/CONTRIBUTING.md](../docs/en/CONTRIBUTING.md) |
| **Docs site** | [benjarogit.github.io/rezeptor](https://benjarogit.github.io/rezeptor/) |
| **Recipe ideas** | [Recipe Submission](https://github.com/benjarogit/rezeptor/issues/new?template=recipe_submission.md) |

Before opening a PR: `make validate` and `make test` (see the docs above).
Optional Python unit tests (same as CI matrix): `make pytest` after `pip install -r requirements-dev.txt` and host/distro PyQt6.

`main` is protected: open a PR (direct pushes are blocked). CI job `validate` (aggregator over shell + Python matrix) must pass before merge; approving reviews are optional for the solo maintainer.
