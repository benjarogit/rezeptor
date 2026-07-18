# Manual QA checklist — Rezeptor

**Prerequisite:** Both recipes are **uninstalled**. Launcher shows “not installed”.  
**Update repo:** `benjarogit/rezeptor`. Test after commit/push/release.

Check items in order. On failure: stop, note it, continue only after a fix.

---

## 0 — Starting state

| # | Action | OK when |
|---|--------|---------|
| 0.1 | `./setup.sh` | Window opens, version visible |
| 0.2 | Photoshop + WISO status | both **not installed** / Install visible |
| 0.3 | No hash warning | no “Hash mismatch” / trust error |
| 0.4 | Help → Developer documentation | list without “(User)”; spacing readable; WISO = reference recipe |

---

## 1 — Photoshop: Install → Use → Lifecycle

| # | Action | OK when |
|---|--------|---------|
| 1.1 | Install | Progress runs (%), ends without error |
| 1.2 | Status after install | installed / Launch active |
| 1.3 | Validate | Progress + exit OK (green) |
| 1.4 | Launch | Photoshop window |
| 1.5 | Quit | Progress; process gone |
| 1.6 | Launch again | opens again |
| 1.7 | Open PSD (double-click / Open with) | file in PS |
| 1.8 | Repair | Progress; then Validate green |
| 1.9 | Quit | clean |

---

## 2 — WISO: Install → Use → Lifecycle

| # | Action | OK when |
|---|--------|---------|
| 2.1 | Install (portable source, target e.g. Documents) | Progress; Wine dialogs OK/Install if any |
| 2.2 | Validate | green |
| 2.3 | Launch | WISO window |
| 2.4 | Quit | gone |
| 2.5 | Repair | Progress; Validate green |

---

## 3 — Updates

| # | Action | OK when |
|---|--------|---------|
| 3.1 | Help → Check for updates (current VERSION) | “no newer release” **or** correct new tag |
| 3.2 | Test “update available”: locally `echo 3.0.3 > VERSION`, relaunch, check updates | update to release (e.g. 3.1.0) offered |
| 3.3 | Install update | completes; VERSION back to release |
| 3.4 | `echo 3.1.0 > VERSION` if needed | title/footer match |

---

## 4 — Report a bug

| # | Action | OK when |
|---|--------|---------|
| 4.1 | Report error on GitHub | report file; clipboard; browser with issue template |
| 4.2 | Template | sections sensible; logs pasteable |

---

## 5 — Developer docs (content)

| # | Action | OK when |
|---|--------|---------|
| 5.1 | ENTWICKLER / RECIPE-AUTHORING | clear for authors |
| 5.2 | WISO reference recipe | architecture/patterns tone, **not** end-user handbook |
| 5.3 | Spacing/headings | readable, not cramped |

---

## 6 — Uninstall (last)

| # | Action | OK when |
|---|--------|---------|
| 6.1 | Uninstall Photoshop | Progress; status “not installed” |
| 6.2 | Uninstall WISO | Progress; prefix gone; portable folder remains |
| 6.3 | Reload launcher | both show Install again |

---

## 7 — Optional: fresh install after uninstall

| # | Action | OK when |
|---|--------|---------|
| 7.1 | Install Photoshop again | as 1.1–1.4 |
| 7.2 | Install WISO again | as 2.1–2.3 |

---

**Failure note:** step ID + screenshot/log path under `~/.local/share/wine-software/logs/`
