# Rezept-Katalog

Rezeptor listet Anwendungen als **Rezepte**. Der Katalog unterscheidet Herkunft und Vertrauen —
nicht jede Quelle ist gleichwertig.

## Offizielle Rezepte (mitgeliefert)

Im Repository unter `recipes/<id>/` gebündelt, indexiert in `recipes/catalog.json` (`trust: official`).
CI sichert sie ab (`recipe-lint`, Manifest-Check).

Aktuell **6** offizielle Produktrezepte in **5** Kategorien.

### Grafik & Design

| ID | Name | Beschreibung |
|----|------|--------------|
| `photoshop` | Adobe Photoshop CC 2021 | Standard-Offline-Installer (22.0.0.35) unter Proton-GE |
| `photoshop-m0nkrus` | Adobe Photoshop CC 2021 (m0nkrus 22.1.1.138) | Vollpack inkl. Neural Filters / missing_libs / GenP (optional) |

### Video & Schnitt

| ID | Name | Beschreibung |
|----|------|--------------|
| `premiere` | Adobe Premiere Pro 2024 | Proton-GE. NVIDIA: CUDA via nvidia-libs. AMD/Intel: oft nur Software-Renderer |

### Finanzen & Steuer

| ID | Name | Beschreibung |
|----|------|--------------|
| `wiso-steuer` | WISO Steuer (Portable) | Portable unter Proton-GE — Quelle wählen, in Zielordner kopieren, starten |

### Dokumente & PDF

| ID | Name | Beschreibung |
|----|------|--------------|
| `master-pdf-editor` | Master PDF Editor | MSI 5.9 unter Proton-GE — Pack mit Setup + optional `crack/` |

### Spiele

| ID | Name | Beschreibung |
|----|------|--------------|
| `halo-campaign-evolved` | Halo Campaign Evolved | ElAmigos/RUNE, Grafik-Presets (Default Empfohlen RTX 2060), optional Steam Non-Steam, BYOS-Trainer |

Vorlagen unter `recipes/_template*` und Einträge unter `recipes/community/` sind **keine** mitgelieferten Produktrezepte.

## Community-Rezepte

Eigene oder geteilte Rezepte liegen unter `recipes/community/<id>/`.

Anlegen z. B. mit:

```bash
./scripts/new-recipe.sh --community meine-app "Meine App"
```

Community-Einträge sind **nicht** automatisch offiziell geprüft — Autor und Inhalt liegen in deiner Verantwortung.

## Rezept-Sync (Updates ohne App-Neuinstallation)

Packaged Builds haben ein read-only `recipes/`-Verzeichnis. Neuere **offizielle** Rezepte kommen über das GitHub-Release-Asset `rezeptor-recipes-<version>.tar.gz` (Eintrag in `SHA256SUMS`).

| Teil | Ort |
|------|-----|
| Overlay | `~/.local/share/rezeptor/recipes/` (gewinnt bei gleicher `id`) |
| Overlay-Manifest | `~/.local/share/rezeptor/manifest.overlay.json` |
| State | `~/.local/share/rezeptor/sync-state.json` |

In der GUI: **Hilfe → Rezepte aktualisieren…** (auch leise nach dem Start). Übernahme erst nach Bestätigung.

Katalog-Felder:

| Feld | Bedeutung |
|------|-----------|
| `min_app_version` | Rezept braucht diese Rezeptor-Version (Core-APIs). Ältere Apps: **blocked** — App updaten. |
| `deprecated` | Nicht neu installieren; vorhandene Daten werden nicht automatisch gelöscht. |

## Rezept-Optionen (Medizin)

Dauerhafte Einstellungen pro Rezept (nicht „einmal installieren“). Button **Medizin** (Icon `kit-medical`) **neben** **Mehr** (eigener Button) öffnet einen Dialog mit Schaltern, **Choice-Combos** und Erklärungstext. Werte in `{data_root}/options.env` steuern Install/Reparieren/Start.

Nach dem Umschalten kann der Primary-CTA zu **„Jetzt reparieren“** werden — einmal ausführen, damit Prefs/Prefix nachziehen.

Sinnvoll nur, wenn die Option Verhalten ändert (z. B. Feature opt-out). Nicht für Aktionen, die Install/Reparatur ohnehin erledigen.

Photoshop: drei UI-Schalter (`PHOTOSHOP_UI_HOME_SCREEN`, `PHOTOSHOP_UI_RICH_TOOLTIPS`, `PHOTOSHOP_UI_MODERN_NEW`), Default `false` — siehe [Benutzerhandbuch](USER-GUIDE.md#medizin-rezept-optionen).

Halo: Qualitäts-Preset (`HALO_GFX_PRESET`, Default `balanced` / Empfohlen RTX 2060), Grafik-Toggles, optional **Start über Steam** + Proton-Choice — siehe [Benutzerhandbuch](USER-GUIDE.md#medizin-rezept-optionen).

```yaml
options:
  - id: gfx_preset
    env: HALO_GFX_PRESET
    type: choice
    default: balanced
    choices:
      - id: balanced
        label: { de: "Empfohlen …", en: "Recommended …" }
    label: { de: "…", en: "…" }
    tip: { de: "…", en: "…" }
  - id: nvidia_libs
    env: PREMIERE_NVIDIA_LIBS
    type: bool
    default: true
    when: nvidia
    label: { de: "…", en: "…" }
    tip: { de: "…", en: "…" }
```

## Mehrere Quellen (Multi-Source)

Rezeptor kann Rezepte aus mehreren Quellen zusammenführen:

| Quelle | Typisch |
|--------|---------|
| Lokales Repo | Offizielle + `recipes/community/` |
| Release-Rezept-Bundle | Overlay-Sync für offizielle Rezepte |
| `catalog.json` auf GitHub | Remote-Index für Community / BYOS |

!!! warning "Vertrauen prüfen"
    Rezepte aus externen Quellen führen Skripte auf deinem System aus.
    Prüfe `recipe.yml` und Hooks, bevor du installierst. Die GUI kann bei abweichendem Vertrauen warnen (`trust`).

## Ausblenden vs. Deinstallieren

| Aktion | Wirkung |
|--------|---------|
| **Ausblenden** | Rezept verschwindet aus der Liste; **Daten bleiben** (`~/.local/share/wine-software/<id>/`). Später wieder sichtbar machen. |
| **Deinstallieren** | Ruft `uninstall.sh` auf und entfernt Rezeptor-State, Verknüpfungen und den gewählten `data_root` vollständig (`recipe_hooks::purge_recipe_data`). |

Portable Ordner oder Steam-Spiele **außerhalb** von `data_root` bleiben bei Deinstallation unangetastet (siehe [STEAM-WRAPPER.md](STEAM-WRAPPER.md)).

## Runtime: Proton-GE

Alle Rezepte setzen **Proton-GE** voraus (`core/runtime.lock`). Kein System-Wine-Fallback in Rezept-Skripten.
Grafik-DLLs kommen über `wine_runtime::deploy_proton_graphics_dlls()` — kein winetricks-dxvk.

Weitere Details: [ENTWICKLER.md](ENTWICKLER.md) · [TRUST.md](TRUST.md) · [UNINSTALL.md](UNINSTALL.md)
