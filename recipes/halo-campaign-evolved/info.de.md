# Halo Campaign Evolved

Getestetes Pack: **Halo.Campaign.Evolved.Premium.Edition.MULTi13-ElAmigos** (g4u / ElAmigos).

Offline-Installer unter Proton-GE: ISO mounten → `setup.exe` (still) → optionale nummerierte Updates.

## Was dieses Rezept löst

Das Spiel will beim Start ein Xbox-/Microsoft-Konto anmelden. Dieses Rezept richtet alles so ein, dass **keine Anmeldung nötig ist** — die Kampagne läuft offline.

Unter Linux kam eine zweite Hürde dazu: das Spiel bringt eine **neuere Microsoft-Laufzeitumgebung** mit, als sie sonst in einem Wine-Prefix landet. Mit der älteren Version stürzte das Spiel beim Anmeldeversuch sofort ab. Rezeptor installiert die passende Version jetzt automatisch aus dem Redist-Ordner, der dem Spiel beiliegt. Dafür ist nichts zu tun — Installieren bzw. Reparieren erledigt das.

## Steam

- **Steam muss nicht installiert sein.** Das Pack bringt seine eigene Steam-Ersatzschicht mit und läuft offline.
- **Optional Medizin „Start über Steam“:** Rezeptor legt einen Non-Steam-Shortcut an und startet über den Client (Prefix bleibt Rezeptor). Steam wird nur beendet, wenn der Shortcut fehlt oder neu geschrieben werden muss — nicht bei jedem Start.
- Ohne Steam-Medizin: **Steam vorher beenden** (auch `steamwebhelper`), sonst kann der Offline-Start mit RUNE kollidieren.

Prüfen: `pgrep -x steam` / `pgrep -x steamwebhelper`.

## Quelle und Ziel

- **Quelle:** Pack-Ordner mit der ISO, **oder** die ISO direkt — nichts umbenennen
- Optional unter der Quelle: `updates/` mit `1 - …/` (auch `updates/<Name>/1 - …/`)
- Oder separates Update-Feld / **Mehr → Update anwenden**
- **Ziel:** freier Ordner auf einer Platte mit genug Platz. Der Windows-Installer schreibt das Spiel technisch nach `prefix/drive_c/Games/…` (Wine). Rezeptor legt zusätzlich den sichtbaren Ordner **`HaloCampaignEvolved/`** im Ziel an (Link auf denselben Baum) — dort liegen die Spieldateien, wenn du den Zielordner öffnest. Daneben: `prefix/`, `recipe.env`, optional `mods/`.

## Updates

Siehe [UPDATES.md](UPDATES.md). ElAmigos-Pakete: Ordner `1 - Halo … update …/` mit `.exe` + `elamigos-1.bin`.

## Koop / Online

**Online-Koop ist mit dieser Installation nicht möglich.** Der gemeinsame Kampagnenmodus hängt an den Halo-Onlinediensten und braucht ein echtes, angemeldetes Konto mit gekauftem Spiel. Dieses Rezept spielt bewusst ohne Anmeldung — dafür startet die Kampagne allein zuverlässig offline.

Ein „GDK / OnlineFix“ aus der Community zielt auf die Microsoft-Store-Variante (AppX/Developer Mode) und läuft unter Proton nicht. Der Hinweis „Spacewar installieren“ aus manchen Anleitungen passt zu diesem Paket nicht.

**Lokal am selben Rechner** kann Splitscreen funktionieren (zweiter Controller, Fireteam im Menü) — ohne Extra-Dateien und ohne Steam. Das ist kein Online-Koop.

## Mods & Grafik (Medizin)

Unter **Medizin**:

- **Qualitäts-Preset** (`HALO_GFX_PRESET`): Sehr niedrig → Ultra. Default **Empfohlen (RTX 2060 / 1080p144)** — scharf und flüssig; Soft-VRAM-Caps an. Ultra ohne Soft-Caps.
- Einzel-Toggles (**Klares Bild**, **Low-Latency**, **VRR**, **gamescope**, **6‑GB-Caps erzwingen**) bleiben Feintuning über dem Preset.
- **Start über Steam** (optional): Non-Steam-Shortcut „… (Rezeptor)“ mit Proton-Choice und Steam-Grid-Art; Soft-Low-Latency unter Steam. Braucht `python-vdf`.

Immer aktiv: MSVC-Runtime, RUNE, echte `libHttpClient`. Standard bleibt **Original-Modus** ohne erzwungene Lumen-HWRT-CVars (Schwarzbild-Falle unter Proton).

**Intro kürzen:** ersetzt nur `LogoParade.mp4` durch ein gültiges kurzes Schwarz-Video — `Splash.bmp` wird nicht angefasst (kaputte Stubs → Sofort-Absturz).

Community-Mods liefert Rezeptor **nicht mit** (BYOS). Ablage:

`<Datenordner>/mods/` (bei Standardpfad: `~/.local/share/wine-software/halo-campaign-evolved/mods/`)

Dort liegt eine `README.txt` mit der Ordnerstruktur (`ue4ss/`, `viewmodels/`, …). Option einschalten → **Reparieren** oder **Starten**.

**Skulls freischalten:** vor dem ersten Aktivieren wird der Spielstand unter `backups/` gesichert.

**Trainer (optional):** Rezeptor liefert keinen Trainer. Getestet: **`Halo.Campaign.Evolved.v1.0-v20260729.Plus.16.Trainer-FLiNG`**. In Medizin beim Ordner-Icon die `.exe` oder einen Trainer-Ordner wählen (wird nach `<Datenordner>/trainer/` kopiert) — oder manuell dorthin legen. **„Trainer mitstarten“** an → beim Start öffnet sich der Trainer nach einigen Sekunden im **gleichen** Wine-Prefix. Andere Trainer möglich, ohne Garantie.

## Hinweise

- **Shader laden** („START DER MJOLNIR-SYSTEME“ / Fortschrittsbalken im Hauptmenü): normal, vor allem beim ersten Start oder nach Grafik-/Treiberwechsel. Kann **mehrere Minuten** dauern — Spiel nicht beenden, sonst beginnt es von vorn. Danach noch 1–2 Minuten im Menü warten, bevor du eine Mission startest (weniger Ruckler beim Bewegen).
- **Grafik / Eingabe:** Preset setzt die Qualitätsleiter; **Klares Bild** = nur Effekte aus. **Weniger Eingabe-Verzögerung** (Standard an): winewayland / Soft-LL unter Steam, vkd3d-Frame-Queue, FPS nahe Hz. Log: `Preset=…`, `winewayland.drv aktiv`, `gamescope`, oder Steam-Shortcut-AppID. Fenster fehlt → Optionen aus oder Plasma-X11.
- Xbox/XAL-Anmeldung läuft immer **im Spielprozess** (`SteamDeck=1`) — nötig unter Proton, kein Medizin-Schalter.
- ISO wird **gemountet** (kein Voll-Extract der ~66 GiB); derselbe Datenträger wird wiederverwendet (kein Mehrfach-Mount).
- Setup läuft still (Inno `/VERYSILENT` + `/LANG` + `/DIR=`). Keine Klick-Kette bei Abbruch.
- **Nickname / Spielsprache:** Bei stiller Installation entfällt der ElAmigos-Wizard. Nach dem Install öffnet Rezeptor optional den Spielordner — dort ggf. Config-Dateien anpassen (oder im Spiel nach dem ersten Start).
- Die Spieldatei selbst wird **nicht verändert**. Alles passiert im Wine-Prefix und in den Konfigurationsdateien.
- BYOS: Rezeptor liefert keine Download-Links — Pack-Titel unter „Wonach suchen“ im Quellen-Dialog.
