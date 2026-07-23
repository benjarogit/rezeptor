# Trust & Manifest

Rezeptor trennt **Katalog-Vertrauen** (Herkunft) von **Datei-Integrität** (Hashes).

## Katalog (`recipes/catalog.json`)

Index für die GUI: `id`, Name, Kategorie, `path`, Kurzbeschreibungen, Feld **`trust`**.

| Wert | Bedeutung |
|------|-----------|
| `official` | Mitgeliefert / offiziell gepflegt |
| `community` | Community / extern — nicht automatisch geprüft |

Community-Rezepte unter `recipes/community/<id>/` erscheinen **nicht** automatisch im offiziellen Katalog und haben typischerweise **keinen** Manifest-Eintrag → GUI „untrusted“.

Mehrquellen: Einstellungen → Rezept-Quellen (`trusted`-Flags dort separat). Externe Rezepte führen Skripte aus — vor Install prüfen.

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
| Release / AppImage / Flatpak | Strenge Hash-Prüfung |
| `REZEPTOR_DEV=1` | Bypass / Entwickler-Workflow |
| Git-Checkout (Auto-Sync) | Nach Sync gilt Trust **nicht** stillschweigend weiter — Manifest darf nicht heimisch „grün“ regeneriert werden; Nutzer muss geänderten Rezepten erneut vertrauen |

Vor PR nach Dateiänderungen immer `./scripts/recipe-manifest.sh` und Commit von `recipes/manifest.json`.

Der Generator hasht nur **Top-Level**-Ordner `recipes/<id>/` mit `recipe.yml` und überspringt Namen mit `_`-Prefix (`_template*`).  
`recipes/community/<id>/` liegt eine Ebene tiefer und fällt daher ebenfalls aus dem Manifest (kein eigener Community-Skip-Zweig).

## Release-Assets

GitHub Release enthält `SHA256SUMS` für `tar.gz`, AppImage und `rezeptor-recipes-*.tar.gz` (Flatpak ggf. separat):

```bash
sha256sum -c SHA256SUMS
```

Rezept-Sync lädt dieses Bundle, prüft SHA256 gegen `SHA256SUMS` und schreibt ins User-Overlay mit `manifest.overlay.json` — dieselben Hash-Regeln wie beim mitgelieferten Manifest.

Kein GPG-/Cosign-Signing im Repo — Integrität über SHA256-Summen.

## Proton-GE

`core/runtime.lock` pinnt Tag, URL und `PROTON_GE_SHA256`. Download prüft den Hash.

## Weiter

- [Rezept-Katalog](CATALOG.md)
- [Mitwirken](CONTRIBUTING.md)
- [GUI-Launcher](LAUNCHER.md)
