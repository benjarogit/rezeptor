# Rezept-Katalog

Rezeptor listet Anwendungen als **Rezepte**. Der Katalog unterscheidet Herkunft und Vertrauen —
nicht jede Quelle ist gleichwertig.

## Offizielle Rezepte (mitgeliefert)

Im Repository unter `recipes/<id>/` gebündelt, indexiert in `recipes/catalog.json` (`trust: official`).

Beispiele: Photoshop, Premiere Pro, WISO Steuer, House of Ashes, ZA4-Trainer.

Diese Rezepte werden mit Rezeptor ausgeliefert und durch CI (`recipe-lint`, Manifest-Check) abgesichert.

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

Optionale Schalter in `recipe.yml` unter `options:` erscheinen als Button **Medizin** (Icon `kit-medical`) neben **Mehr**. Werte liegen in `{data_root}/options.env` und gelten bei Install/Reparieren/Start.

```yaml
options:
  - id: nvidia_libs
    env: PREMIERE_NVIDIA_LIBS
    type: bool
    default: true
    when: nvidia   # optional: nur auf NVIDIA-Hosts anzeigen
    label: { de: "CUDA / nvidia-libs", en: "CUDA / nvidia-libs" }
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
