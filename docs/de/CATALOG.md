# Rezept-Katalog

Rezeptor listet Anwendungen als **Rezepte**. Der Katalog unterscheidet Herkunft und Vertrauen —
nicht jede Quelle ist gleichwertig.

## Offizielle Rezepte (mitgeliefert)

Im Repository unter `recipes/<id>/` gebündelt, indexiert in `recipes/catalog.json` (`trust: official`).

Beispiele: Photoshop, WISO Steuer, House of Ashes, ZA4-Trainer.

Diese Rezepte werden mit Rezeptor ausgeliefert und durch CI (`recipe-lint`, Manifest-Check) abgesichert.

## Community-Rezepte

Eigene oder geteilte Rezepte liegen unter `recipes/community/<id>/`.

Anlegen z. B. mit:

```bash
./scripts/new-recipe.sh --community meine-app "Meine App"
```

Community-Einträge sind **nicht** automatisch offiziell geprüft — Autor und Inhalt liegen in deiner Verantwortung.

## Mehrere Quellen (Multi-Source)

Rezeptor kann Rezepte aus mehreren Quellen zusammenführen:

| Quelle | Typisch |
|--------|---------|
| Lokales Repo | Offizielle + `recipes/community/` |
| `catalog.json` auf GitHub | Remote-Index zum Nachinstallieren |

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

Weitere Details: [ENTWICKLER.md](ENTWICKLER.md) · [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md)
