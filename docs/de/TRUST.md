# Trust & Manifest

Rezeptor trennt **Katalog-Vertrauen** (Herkunft) von **Datei-Integrität** (Hashes).

## Katalog (`recipes/catalog.json`)

Index für die GUI: `id`, Name, Kategorie, `path`, Kurzbeschreibungen, Feld **`trust`**.

| Wert | Bedeutung |
|------|-----------|
| `official` | Mitgeliefert / offiziell gepflegt |
| Community / extern | Nicht automatisch geprüft |

Community-Rezepte unter `recipes/community/<id>/` erscheinen **nicht** automatisch im offiziellen Katalog und haben typischerweise **keinen** Manifest-Eintrag → GUI „untrusted“.

Mehrquellen: Einstellungen → Rezept-Quellen. Externe Rezepte führen Skripte aus — vor Install prüfen.

## Manifest (`recipes/manifest.json`)

SHA256 über alle Dateien pro offiziellem Rezept:

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
- CI: `make recipe-manifest-check` (Diff gegen regeneriertes Manifest muss leer sein)
- Verifikation: `launcher/recipe_trust.py` (`verify_recipe_trust`)

### Wann streng / wann locker

| Kontext | Verhalten |
|---------|-----------|
| Release / AppImage | Strenge Hash-Prüfung |
| `REZEPTOR_DEV=1` | Bypass / Entwickler-Workflow |
| Git-Checkout | Auto-Sync des Manifests oft erlaubt |

Vor PR nach Dateiänderungen immer `./scripts/recipe-manifest.sh` und Commit von `recipes/manifest.json`.

Vorlagen `_template*` und Community sind vom Manifest-Generator ausgeschlossen (`_`-Prefix / Community-Pfad).

## Release-Assets

GitHub Release enthält `SHA256SUMS` für `tar.gz` und AppImage:

```bash
sha256sum -c SHA256SUMS
```

Kein GPG-/Cosign-Signing im Repo — Integrität über SHA256-Summen.

## Proton-GE

`core/runtime.lock` pinnt Tag, URL und `PROTON_GE_SHA256`. Download prüft den Hash.

## Weiter

- [Rezept-Katalog](CATALOG.md)
- [Mitwirken](CONTRIBUTING.md)
- [GUI-Launcher](LAUNCHER.md)
