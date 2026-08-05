# Halo CE — Ghidra + GDB (Kurz)

**Vollständiger Leitfaden:** [halo-analyse-leitfaden.md](halo-analyse-leitfaden.md)  
**Patch-Inventar (historisch):** [login-patch-inventory.md](login-patch-inventory.md)

> Gelöst ist der Login über die MSVC-Runtime 14.40+ aus dem Release, **nicht** über
> EXE-Patches. Das Rezept verändert die Spieldatei nicht mehr; die Trace-Werkzeuge
> bleiben als Nachschlagewerk für künftige Analysen.

## Schnellstart

```bash
# 1) EXE für Ghidra kopieren
bash recipes/halo-campaign-evolved/assets/prepare-ghidra.sh

# 2) Live-Trace (Steam aus!)
bash recipes/halo-campaign-evolved/assets/trace-login.sh --attach
```

## Ghidra MCP (Cursor)

- Ghidra öffnen → Projekt **HaloRE** → `HaloCampaignEvolved_vanilla.exe` analysieren
- MCP-Server Port **8089** starten (siehe Leitfaden §3)
- `~/.cursor/mcp.json` ist bereits konfiguriert

## ImageBase

`0x140000000` — Navigation mit **G** + VA aus `login-patch-inventory.md`
