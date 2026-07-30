# Updates (Post-Install-Patches)

Generisches Update-Framework für Rezepte mit Patches nach der Erstinstallation (z. B. ElAmigos-Updates).

**Nicht gemeint:** App-/Rezept-Bundle-Updates von Rezeptor (`rezeptor-update.sh`) — siehe [LAUNCHER.md](LAUNCHER.md).

## Vertrag (`recipe.yml`)

| Feld | Bedeutung |
|------|-----------|
| `fix_kind: none\|optional\|required` | Schalter „Rezept kann Updates“ |
| `update: update.sh` | **Pflicht** wenn `fix_kind != none` (Lint ERROR sonst) |
| `install_steps` → `apply_updates` | Optional: Updates schon bei der Installation anwenden |

Hook `update.sh`:

```bash
recipe_hooks::load update
recipe_hooks::runtime_init || exit 1
recipe_updates::apply_all
```

## Erkennung (Hybrid)

1. **Unter der Install-Quelle** (Auto): Ordner `updates/`, `Updates/` oder `update/` mit nummerierten Unterordnern `1 - …`, `2 - …`
2. **Oder** direkt unter dem Root: nummerierte Ordner `1 - …`
3. **Plus** separates Feld **Update / Fix** im Quellen-Dialog (`RECIPE_UPDATE_ROOT` / Alias `RECIPE_FIX_ROOT`)

Sortierung: **numerisch** nach führender Zahl (`1` vor `2` vor `10`).

Jede Einheit: Ordner mit `.exe` (+ optional `.bin`) oder einzelne `.exe`.

## GUI

- **Installieren:** optional Update-Feld; verschachtelte `updates/` werden automatisch gefunden.
- **Mehr → Update anwenden…:** eigener Dialog nur für die Update-Quelle (wenn installiert und `fix_kind != none`).
- Idempotenz: angewandte IDs in `recipe.env` als `APPLIED_UPDATES=1,2,…` — erneutes Anwenden überspringt sie.

## Core-API

Siehe [CORE-API.md](CORE-API.md#updates--recipe-updatessh--recipe-isosh) — Kurz:

| Funktion | Rolle |
|----------|--------|
| `recipe_updates::discover` | Geordnete `ID\|PATH`-Liste |
| `recipe_updates::roots_from_env` | Roots aus Env |
| `recipe_updates::apply_all` | Ausführen + State |
| `recipe_updates::status` | Log/Validate |

ISO großer Spiel-Packs: `core/recipe-iso.sh` — **Mount** (`udisksctl`), kein Voll-Extract.

## Beispiel-Layout

```
Halo Campaign Evolved/          ← Quelle
  Halo Campaign Evolved.iso
  updates/
    1 - Halo … update …/
      *.exe
      elamigos-1.bin

# oder separates Update-Root:
… update 29.07.2026/
  1 - …
```

Referenz-Rezept: `halo-campaign-evolved`.

## Weiter

- [RECIPE-AUTHORING.md](RECIPE-AUTHORING.md) · [CORE-API.md](CORE-API.md) · [LAUNCHER.md](LAUNCHER.md) · [ENTWICKLER.md](ENTWICKLER.md)
