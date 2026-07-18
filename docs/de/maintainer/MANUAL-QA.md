# Manuelle QA-Checkliste — Rezeptor

**Voraussetzung:** Beide Rezepte sind **deinstalliert**. Launcher zeigt „nicht installiert“.  
**Repo für Updates:** `benjarogit/rezeptor` (privat). Nach Commit/Push/Release testen.

Abhaken in Reihenfolge. Bei Fail: stoppen, Notiz, weiter erst nach Fix.

---

## 0 — Startzustand

| # | Aktion | OK wenn |
|---|--------|---------|
| 0.1 | `./setup.sh` | Fenster öffnet, Version sichtbar |
| 0.2 | Photoshop + WISO Status | beide **nicht installiert** / Installieren sichtbar |
| 0.3 | Keine Hash-Warnung | kein „Hash mismatch“ / Trust-Fehler |
| 0.4 | Hilfe → Entwickler-Dokumentation | Liste ohne „(User)“; Abstände lesbar; WISO = Referenz-Rezept |

---

## 1 — Photoshop: Install → Nutzen → Lifecycle

| # | Aktion | OK wenn |
|---|--------|---------|
| 1.1 | Installieren | Progress läuft (%), endet ohne Fehler |
| 1.2 | Status nach Install | installiert / Starten aktiv |
| 1.3 | Prüfen | Progress + Exit OK (grün) |
| 1.4 | Starten | Photoshop-Fenster |
| 1.5 | Beenden | Progress; Prozess weg |
| 1.6 | Nochmal Starten | öffnet wieder |
| 1.7 | PSD öffnen (Doppelklick / Öffnen mit) | Datei in PS |
| 1.8 | Reparieren | Progress; danach Prüfen grün |
| 1.9 | Beenden | sauber |

---

## 2 — WISO: Install → Nutzen → Lifecycle

| # | Aktion | OK wenn |
|---|--------|---------|
| 2.1 | Installieren (Quelle Portable, Ziel z. B. Dokumente) | Progress; ggf. Wine-Dialoge OK/Installieren |
| 2.2 | Prüfen | grün |
| 2.3 | Starten | WISO-Fenster |
| 2.4 | Beenden | weg |
| 2.5 | Reparieren | Progress; Prüfen grün |

---

## 3 — Updates

| # | Aktion | OK wenn |
|---|--------|---------|
| 3.1 | Hilfe → Updates prüfen (bei aktueller VERSION) | „kein neueres Release“ **oder** korrektes neues Tag |
| 3.2 | Test „Update verfügbar“: lokal `echo 3.0.3 > VERSION`, Launcher neu, Updates prüfen | Update auf Release (z. B. 3.1.0) angeboten |
| 3.3 | Update installieren | läuft durch; VERSION wieder Release-Stand |
| 3.4 | `echo 3.1.0 > VERSION` falls nötig | Titel/Footer stimmen |

---

## 4 — Fehler melden

| # | Aktion | OK wenn |
|---|--------|---------|
| 4.1 | Fehler auf GitHub melden | Report-Datei; Zwischenablage; Browser mit Issue-Vorlage |
| 4.2 | Vorlage | Abschnitte sinnvoll; Logs einfügbar |

---

## 5 — Entwickler-Doku (Inhalt)

| # | Aktion | OK wenn |
|---|--------|---------|
| 5.1 | ENTWICKLER / RECIPE-AUTHORING | klar für Autoren |
| 5.2 | Referenz-Rezept WISO | Architektur/Muster, **kein** Enduser-Handbuch-Ton |
| 5.3 | Abstände/Überschriften | lesbar, nicht zusammengequetscht |

---

## 6 — Deinstallieren (zuletzt)

| # | Aktion | OK wenn |
|---|--------|---------|
| 6.1 | Photoshop Deinstallieren | Progress; Status „nicht installiert“ |
| 6.2 | WISO Deinstallieren | Progress; Prefix weg; Portable-Ordner bleibt |
| 6.3 | Launcher neu laden | beide wieder Installieren |

---

## 7 — Optional: Frisch-Install nach Uninstall

| # | Aktion | OK wenn |
|---|--------|---------|
| 7.1 | Photoshop nochmal Installieren | wie 1.1–1.4 |
| 7.2 | WISO nochmal Installieren | wie 2.1–2.3 |

---

**Fail-Notiz:** Schritt-ID + Screenshot/Log-Pfad unter `~/.local/share/wine-software/logs/`
