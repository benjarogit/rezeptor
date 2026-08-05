# Halo Campaign Evolved — Analyse-Leitfaden (Ghidra + GDB)

Systematisch vorgehen: **erst statisch verstehen, dann live messen, dann gezielt eingreifen** — nicht raten.

---

## Ergebnis (2026-08-05): es war die MSVC-Runtime, kein EXE-Patch

Der Xbox-/XAL-Login funktioniert offline, **ohne jede Änderung an der Spieldatei**:

- `libHttpClient.Win32.dll` ist mit MSVC-Toolset ≥ 14.40 gebaut (constexpr `std::mutex`,
  Speicher nur genullt, kein `_Mtx_init_in_situ`-Import). `msvcp140` **14.29** aus
  winetricks `vcrun2019` liest dort einen vtable-Zeiger, den nie jemand angelegt hat →
  `EXCEPTION_ACCESS_VIOLATION reading 0x0` in `MSVCP140!_Mtx_lock` direkt nach
  `XTaskQueueCreate`.
- Fix: `ensure_modern_crt` entpackt die CRT **14.50** aus dem release-eigenen
  `_CommonRedist/…/VC_redist.x64.exe` ins Prefix, `launch.sh` erzwingt sie als
  `native,builtin`. Genau das tut der Windows-Installer auch.
- Falsche Fährten (drei Tage): der 25-KB-`libHttpClient`-Stub (kann keine
  XAsync-Completion signalisieren → Endlos-Spinner), der `version.dll`-Proxy
  (lädt sich unter Wine rekursiv → `c0000142`) und die gesamte EXE-Patch-Ebene.
  Alle drei sind aus dem Rezept entfernt.

Die Patch-Tabellen in `login-patch-inventory.md` sind damit **Historie**: nützlich als
Karte der Login-Pfade, aber nichts davon wird noch angewendet.

---

## 0. Voraussetzungen auf deinem Rechner

| Tool | Bei dir | Prüfen |
|------|---------|--------|
| Ghidra 12.1.2 | `/opt/ghidra` | `ghidra --help` oder `pacman -Q ghidra` |
| GDB | `/usr/bin/gdb` | `gdb --version` |
| Proton-GE (Rezeptor) | via Rezeptor | Reparieren einmal grün |
| **Steam beendet** | manuell | `pgrep -x steam; pgrep -x steamwebhelper` → beides leer |

**Wichtig (wie unter Windows mit RUNE):**

- Steam **komplett** beenden (auch `steamwebhelper`)
- Antivirus/Defender: Spielordner ausnehmen (RUNE64 wird sonst gelöscht)
- **Kein** Xbox-`hosts`-Block im Wine-Prefix (führt zu LoginFailed — Rezept entfernt das bewusst)
- Linux-Internet darf an bleiben; die Anmeldung läuft im Offline-Pfad des Cracks, ein echtes Microsoft-Konto ist nie im Spiel

---

## 1. Einmalig: Analyse-EXE vorbereiten

```bash
cd /home/benny/Dokumente/photoshopCClinux
bash recipes/halo-campaign-evolved/assets/prepare-ghidra.sh
```

Ergebnis:

- **`~/Dokumente/halo-ce-ghidra/HaloCampaignEvolved_vanilla.exe`**  
  (Kopie von `*.pre_xsapi_patch`, falls vorhanden — sonst der EXE selbst; beide sind
  seit dem Entfernen der Patch-Ebene bit-identisch)

Optional anderer Ordner: `HALO_GHIDRA_HOME=/pfad bash prepare-ghidra.sh`

Optional Headless-Import (10–30 Min, ~230 MB EXE):

```bash
bash recipes/halo-campaign-evolved/assets/prepare-ghidra.sh --import
```

---

## 2. Ghidra GUI einrichten

### 2.1 Starten

```bash
ghidra
# oder: /opt/ghidra/ghidraRun
```

### 2.2 Projekt anlegen (wichtig — Ghidra-Dialog)

Ghidra legt **keinen** fertigen `ghidra`-Unterordner an. Du wählst ein **übergeordnetes Verzeichnis** + gibst einen **Projektnamen** ein.

1. **File → New Project…**
2. **Non-Shared Project** → **Next**
3. **Project Directory:** auf **Durchsuchen** klicken  
   → zu **`/home/benny/Dokumente/halo-ce-ghidra`** navigieren  
   → diesen Ordner **auswählen** (nicht in einen leeren Unterordner `ghidra` klicken, den es nicht gibt)
4. **Project Name:** `HaloRE` → **Finish**  
   Ghidra erzeugt dann z. B. `~/Dokumente/halo-ce-ghidra/HaloRE.rep`
5. **File → Import File…** → `~/Dokumente/halo-ce-ghidra/HaloCampaignEvolved_vanilla.exe`
6. Import-Dialog:
   - Format: **Portable Executable (PE)**
   - Language: **x86:LE:64:default**
   - Compiler: **windows**
7. **Yes** bei „Analyze now“

**Warum nicht `~/.local/...`?**  
Unter KDE ist `.local` oft **ausgeblendet** (Strg+H = versteckte Dateien). Deshalb nutzen wir `~/Dokumente/halo-ce-ghidra`.

**Falls der Dialog den Ordner nicht anzeigt:** Pfad oben **eintippen**:
`/home/benny/Dokumente/halo-ce-ghidra`

### 2.3 ImageBase prüfen (Pflicht)

1. **Window → Memory Map**
2. Erste Region: **Image Base = `140000000`**
3. Navigation: **G** → `146E8A280` (Titel/Login-Handler) — muss gültiger Code sein

Wenn ImageBase abweicht, stimmen alle VAs in `login-patch-inventory.md` nicht.

### 2.4 Nützliche Ghidra-Fenster

- **Listing** — Disassembly
- **Decompiler** — pseudocode (Fenster neben Listing)
- **Symbol Tree → Functions**
- **References → Show References to** (auf VA rechtsklicken)

### 2.5 Erste statische Schritte

| Schritt | Ghidra | Ziel |
|---------|--------|------|
| A | **G** → `146E55200` | Wer baut „Anmelden fehlgeschlagen“? (XRefs) |
| B | **G** → `146E8A280` | Titel-Enter-Funktion, alle `je`/`call` |
| C | **G** → `146E2C5F0` | XAL Login async — Caller |
| D | Rechtsklick → References | Caller-Kette dokumentieren |

Vollständige VA-Tabelle: `login-patch-inventory.md`

---

## 3. Ghidra MCP in Cursor (bereits bei dir konfiguriert)

Deine `~/.cursor/mcp.json`:

- Bridge: `/home/benny/Dokumente/rezeptor-maintainer-local/ghidra-mcp`
- Ghidra HTTP: **`http://127.0.0.1:8089`**
- Ghidra-Pfad: `/opt/ghidra`

### 3.1 MCP aktivieren (jede Analyse-Session)

1. **Ghidra starten** und Projekt **HaloRE** öffnen
2. `HaloCampaignEvolved_vanilla.exe` im CodeBrowser öffnen (Doppelklick)
3. Extension **Ghidra MCP** aktivieren:
   - **File → Configure → Plugins** (oder Developer) — MCP-Plugin ankreuzen
   - **Edit → Tool Options → Miscellaneous → Ghidra MCP HTTP Server**
   - Port: **8089** (wie in `.env` von ghidra-mcp)
   - Server **Start** / Auto-start aktivieren
4. **Cursor neu verbinden**: MCP-Status grün; `list_instances` sollte eine Instanz zeigen

### 3.2 Typische MCP-Befehle an den Agent

- „Liste Funktionen mit XRef zu `146E55200`“
- „Decompile ab `146E8A280`“
- „Wer ruft `146E2C5F0` auf?“

Ohne laufendes Ghidra mit offenem Programm antwortet MCP leer.

---

## 4. Live-Trace (GDB unter Wine)

Die laufende EXE ist immer die unveränderte — das Rezept patcht nichts mehr, der Trace
zeigt also den echten Flow.

### 4.1 Trace starten

GDB unter Wine ist fragil. Das Skript fängt bekannte Fallstricke ab
(`continue -a`, `file`-Mismatch, `tee`/Ctrl+C, Intro-Attach, Hot-Path-BPs).

```bash
# Hänger bereinigen (falls nötig):
bash recipes/halo-campaign-evolved/assets/trace-login.sh --kill

# Empfohlen: Rezeptor + Attach
bash recipes/halo-campaign-evolved/assets/trace-login.sh --attach
```

Ablauf:
1. Terminal: `--attach` starten  
2. Rezeptor: Halo starten → **Schritt A** Enter (Fenster da)  
3. Titel „[Enter] ZUM STARTEN DRÜCKEN“ → **Schritt B** Enter (GDB attach)  
4. Terminal zeigt „Login-Trace AKTIV“ / Continuing → **Enter im Spiel**  
5. `[HIT]`-Zeilen lesen; beenden: Ctrl+C → `quit`  

(`--full` nur wenn nötig — mehr Breakpoints.)

### 4.2 Ablauf im Spiel

1. Warten bis **Titel** erscheint (GDB = langsamer Start, normal)
2. **Enter** drücken
3. Falls **Anmelden** sichtbar: kurz warten / ggf. klicken
4. Terminal beobachten: Zeilen `[HIT] …` + Backtrace
5. Beenden: **Ctrl+C** im Terminal (löst nur GDB; Spiel läuft weiter) oder Spiel schließen

Log: `~/.local/share/wine-software/logs/halo-login-trace_*.log`

### 4.3 Log an Agent

Reicht ein Ausschnitt:

```
[HIT] Title_LoginUI_Branch (8A2A3)
#0  ...
#1  ...
```

Nur die **feuernden** VAs zählen — daraus kommt **eine** gezielte Erkenntnis, nicht zehn neue Patches.

---

## 5. Ghidra Debugger (optional, gleiche Adressen)

Wenn GDB läuft, funktioniert auch:

1. Ghidra **Debugger → Configure and launch → gdb**
2. Program: Proton-`wine64` (Pfad aus `which wine` nach Rezeptor-Runtime)
3. Args: Pfad zu `HaloCampaignEvolved.exe`
4. Breakpoints an VAs aus `login-patch-inventory.md`

Für den Einstieg reicht meist `trace-login.sh`.

---

## 6. Steam-Hardblock (Rezeptor)

`launch.sh` und `trace-login.sh` brechen ab, wenn Steam noch läuft.  
Nur für Tests: `HALO_ALLOW_STEAM=1 bash …`

---

## 7. Was wir bewusst nicht tun

| Idee | Warum nicht |
|------|-------------|
| Xbox in `hosts` blocken | Connection refused → LoginFailed-Dialog |
| Internet global abschalten | unnötig; RUNE ist offline |
| EXE patchen | Whack-a-Mole; die Ursache lag in der CRT (siehe „Ergebnis“ oben) |
| `libHttpClient` durch Stub ersetzen | signalisiert keine XAsync-Completion → Endlos-Spinner |
| `version.dll`-Proxy | lädt sich unter Wine rekursiv → `c0000142` |

---

## 8. Intro / FMV (später)

Aktuell **kein** dedizierter Intro-Skip-Patch. Nach Login-Flow in Ghidra suchen nach:

- `MoviePlayer`, `PlayMovie`, `StartupMovies`, `Slate` Splash

Erst Login sauber, dann Intro per Trace + Ghidra.

---

## 9. Checkliste vor jeder Analyse-Session

- [ ] Steam aus (`pgrep -x steam` und `pgrep -x steamwebhelper` leer)
- [ ] `prepare-ghidra.sh` ausgeführt
- [ ] Ghidra: ImageBase `140000000`
- [ ] `trace-login.sh --attach` + Log mit `[HIT]`
- [ ] Ghidra XRefs zum feuernden VA
- [ ] **Eine** Hypothese pro Durchlauf prüfen

---

## Dateien in diesem Rezept

| Datei | Rolle |
|-------|--------|
| `prepare-ghidra.sh` | Analyse-EXE + optional Headless-Import |
| `trace-login.sh` | GDB Live-Trace |
| `login-patch-inventory.md` | VA-Karte der Login-Pfade (historische Patch-Tabelle) |
| `ghidra-login-trace.md` | Kurzreferenz Breakpoints |
