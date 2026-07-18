# Rezeptor documentation source

Bilingual MkDocs Material site (`docs/de/`, `docs/en/`).

- Config: `/mkdocs.yml`
- Deps: `/requirements-docs.txt`
- Deploy: `.github/workflows/docs.yml` → https://benjarogit.github.io/rezeptor/

```bash
pip install -r requirements-docs.txt
mkdocs serve
```

Author docs are also available in-app via **Help → Developer documentation…** (`launcher/ui_docs.py`).
