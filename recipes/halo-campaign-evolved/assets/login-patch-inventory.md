# Halo CE — Login-Patch-Inventar (Build ElAmigos/RUNE)

**ImageBase:** `0x140000000`

> **Status seit 2026-08-05: historisch.** Der Login läuft über die MSVC-Runtime 14.40+
> aus dem Release (siehe erster Abschnitt). Das Rezept wendet **keinen** dieser Patches
> mehr an und verändert die Spieldatei nicht. Was hier steht, ist die VA-Karte der
> Login-Pfade und ein Protokoll der Sackgassen — nützlich für künftige Analysen,
> keine Anleitung zum Patchen.

## MSVCP crash lesson (2026-08-05) — root cause, not a Wine bug

`EXCEPTION_ACCESS_VIOLATION reading 0x0` at `SecondsSinceStart=0`, dumps `UECC-AB8F5DA5…`
and `UECC-8FD41D08…`, `rip = MSVCP140+0x13080`, `rax=0`, `rcx = rsi+8`:

```
libHttpClient +0x16aa1  XTaskQueueCreate
libHttpClient +0x15fca  port init      -> vtbl+0x50
libHttpClient +0x14257  thunk, rcx += 0x30 (std::mutex)
libHttpClient +0x17700  std::mutex::lock -> _Mtx_lock
MSVCP140      +0x13080  mov rax,[rsi+8]; mov rax,[rax]   <-- vptr == 0
```

- `libHttpClient.Win32.dll` imports **only** `_Mtx_lock/_Mtx_unlock/_Cnd_wait/_Cnd_broadcast`,
  **not** `_Mtx_init_in_situ` — MSVC toolset ≥ 14.40, constexpr `std::mutex`, zero-init storage.
  (`PartyWin.dll` / `PlayFabMultiplayerWin.dll` still import `*_init_in_situ` — older builds.)
- msvcp140 **14.29** (winetricks `vcrun2019`) still calls through the `stl_critical_section`
  vtable at `mtx+8` that nobody created. **14.50** locks a raw SRWLOCK at `mtx+0x10` — no vptr.
- Windows never hits it: the release installs its own `_CommonRedist/vcredist/2022/VC_redist.x64.exe`
  (**14.50.35719**). Fix = do the same (`ensure_modern_crt`); no binary patch, no stub.
- **Wrong for 3 days:** the 25 KB `libHttpClient` stub. It hid the crash and replaced it with the
  spinner, because a stub cannot signal XAsync completion callbacks. Not the DLL — the CRT.
- Also falsified: `IXMLHttpRequest2`/msxml6. This build imports **WINHTTP** directly, no msxml.

## Crash lesson (2026-08-02)

`EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff` after Enter:

- Cause: **entry stubs** on `LoginWithUIXsapi` / `FUN_146e54c80` / error-object builders
- Those functions must **fill out-params**; `ret` left callers with `-1` pointers
- Fix: **JMP to real success epilogs** + XAL force-success; stub **only** fail/show UI

## Spinner lesson (2026-08-02, „Anmelden…“ forever)

Four cooperating bugs:

1. **`146E5CEA9` JMP `5CFAD`** — success branch needs live user in `rsi` (`[r15+0x238]`). Offline null → deref hang/AV, never completes UI.
2. **`146E4AF00` binder stub** — binder sets widget `+0xb0 = 1` (login-complete). Stub → promise never resolves → spinner.
3. **OSS `+0x2fc` clears not patched** (was full-only) — `5DBEC` / `EEF5AC` write 0 after attempt; readers alone insufficient.
4. **Title JMP→epilog + AutoLogin full-stub** — skip alone left spinner because LoginWithUI/binder never ran; vanilla title alone is worse (see black-screen).

**Fix (2026-08-02c hybrid):**
- Title **JMP success epilog** (RouterLogin hang/black offline)
- AutoLogin **must invoke LWUI body** then `mov al,1` (binder runs; not entry-stub)
- keep `JNE 5CFAD`; null path builder + **live binder**; OSS boot mid+
- **Superseded 04f:** on OSS class do **not** `call [rax+0xd0]` — see Spinner class C below.

## Fail-UI lesson (2026-08-02d, Anmelde-Fenster + fehlgeschlagen)

Hybrid 02c still left Anmelden fail after Enter:

- Cause: AutoLogin stub called `[rax+0xd0]` (LoginWithUI) **without** `xor edx,edx`.
  `rdx` = local user → LWUI copies to `rsi`; garbage/non-null → **CFAD** path (expects real user)
  instead of null path builder + binder. CFAD offline → fail object / Anmelde-UI.
- Vanilla `89450` already only set `r8d=0` (same rdx hazard); `89470` was multi-step (fail toast @`895b6`), rewritten to same stub.
- **Fix (historical 02d):** both stubs: `xor edx,edx; xor r8d,r8d; call [rax+0xd0]; mov al,1; ret`.
- **Still wrong after 04f:** `[rax+0xd0]` on OSS = self. Current: empty TDelegate + **abs `call 5CCB0`**.

## Residual fail after xor edx (2026-08-04, Crash einmal + Anmeldung fehlgeschlagen)

Post-guard retest: E714 gone; one Worker/execute@0 dump (`UECC-39275…`); then fail toast.

Gate is **not only** AutoLogin `rdx`. In `LoginWithUIXsapi`:

```
mov rsi, [r15+0x238]   ; manager user object
test rsi, rsi
jne 5CFAD              ; non-null → CFAD (XAL), not null path
```

Offline manager can hold a **non-null stub user** → CFAD even when AutoLogin passes null `rdx`.
Also B2 Alpha residual was **never in PATCHES** (skill only): status≠`-1` @`F1BAB`.

**Fix (mid):**
- `146E5CEA6`: `xor esi,esi` + 7 NOPs (9B) → always null fallthrough → `call 54c80` + binder  
  (do **not** JMP CFAD; do **not** leave bare JNE)
- B2 toast/Alpha: `F1BAB` NOP jne; `F1D62` JMP epilog; `F2063` NOP je; toast switch `7D81D`/`7E08B`

## Spinner class C (2026-08-04, Anmelden forever with force-null + 55200)

After force-null + toast skip, UI stuck on **„Anmelden…“** (no fail toast, no crash).

- **Cause (earlier):** null path forced `call 55200` (Empty-Success / `5534b`) + twin NOPs `805E7`/`7F9F7` + `7A2B0` skip fail-attach. Success object type does **not** finish the UMG promise the way the fail object + binder does offline; toast-skip hides fail text but needs the fail *object* shape.
- **Wrong:** treat 55200 as always “better” than 54c80 once toast is skipped.
- **Fix:** keep **vanilla `call 54c80` @ `5CEBC`**; **do not** twin-NOP or JMP-skip fail-attach; suppress toast via `7D81D`/`B2` only. Binder `4AF00` still runs and completes UI.

## Spinner class C′ (2026-08-04f, recursive AutoLogin)

Still **„Anmelden…“** forever with 54c80 + binder + force-null + progress-disable — no toast/crash.

- **Cause:** OSS vtable `0x14bc7be28`: slot `+0xd0` = **`89450`**, slot `+0x118` = **`89470`**. Real `LoginWithUI` body is **`5CCB0`** (other vtables’ `+0xd0` only). Hybrid stub `call [rax+0xd0]` re-entered `89450` → infinite recursion after title Enter.
- **Wrong (inventory 02d):** “`89450` vtable+0xd0 = LoginWithUI” — false on this class.
- **Fix:** `89470` = direct `call 5CCB0` with empty stack `TDelegate` in `r8`, `xor edx,edx`, `mov al,1` (43B). `89450` = `jmp 89470` (only 32B room). Never `call [rax+0xd0]` from either.

## Null-vcall lesson (2026-08-02e, UECC-E714 / F7CB / F2A6)

Three identical dumps after hybrid/xor path: `EXCEPTION_ACCESS_VIOLATION` **execute @0**, `RIP=0`, `RAX=0x14be965e0`.

- Cause: `FUN_147017ca0` @ `147017d69`: `call [rax+0x4e0]` — PE `.rdata` vtbl slot **+0x4e0 = NULL** (neighbor +0x4d8=`0x1458ad440` live). Fail-resolve arm @`d71` does `xor ecx; call [0+0x4e0]` (also AV); `d71` is a **JE target**.
- Not CFAD/fail-UI; not fixed by more `xor edx`. Same `RAX` every crash → deterministic pure-virt/bad-iface, not random corruption.
- **Fix (slim+):** `147017d66` region → `jmp 147017d83` (empty result byte=0); keep `d71` entry as `jmp d83`. No entry-stub on builders.

## Black-screen lesson (2026-08-02c)

Symptom: after deploy with **title vanilla**, black frame + **desktop mouse** + KWin „reagiert nicht“; dump `UECC-…559C_0000` is often kill-stack (AV@0 / `SecondsSinceStart=0`), not root cause.

- **Cause:** vanilla title Enter opens **RouterLogin** (`64ce0` / both JE branches) → offline hang, no Anmelden UI.
- **Not fixable by** dumping the kill crash alone; hang precedes dump.
- **Wrong fix:** title vanilla hoping RouterLogin completes (spinner lesson #4 incomplete).
- **Right hybrid:** title skip **and** AutoLogin must **call** LoginWithUI (binder), not stub over the call.

## Safe strategy

```
Title handlers 8a270 / 8a750 / 8acf0 / 8af50
  → JMP success epilog (skip RouterLogin hang offline)
LoginWithUIXsapi (5ccb0)
  → RUNS (not stubbed)
  → force rsi=0 @5CEA6 → null path
  → null session: 54c80 + 4AF00 binder (complete UI; toast skipped)
  → with session: CFAD path (avoid offline)
  → XAL acquire + HRESULT force-success
Fail UI (0c910 / 23750 / 23820 / …)
  → stub (void / unused)
Object builders (54c80 / 55200 / …)
  → MUST RUN (used after Enter); prefer 54c80 null path offline
Binder 4AF00
  → MUST RUN (completion bit)
AutoLogin 89450 / 89470
  → 89470: **mov al,1; ret** (04h+; not call 5CCB0 — empty-delegate 5CCB0 still class C)
  → 89450: jmp 89470  (NOT call [rax+0xd0] — that slot IS 89450)
Title (mid 04j)
  → NOP flag-JE + vanilla call [rax+0x128] empty SharedPtr + NOP je-fail
  → vanilla call 64ce0; inside 64ce0: **64D08 jmp 64D2C** (success arm → SP→6c210)
  → do NOT pure-JMP title epilog; do NOT empty-call 6c210; do NOT ret-stub 64ce0 entry
```

## Active roots

| VA | Aktion |
|----|--------|
| Title `8A2A3`/`8A783` | **NOP flag-JE** (not slim pure-JMP epilog — that → spinner) |
| Title `8A2B0`/`8A790` | **vanilla** `call [rax+0x128]` empty SharedPtr (not AL/LWUI) |
| Title `8A2C3`/`8A7A3` | **NOP je-fail** → fall-through notify path |
| Title `call 64ce0` | **vanilla** (main `8A37B`, twins) |
| **`146E64D08`** | **jmp `64D2C`** — skip 244e0+magic; success arm builds notify SP → `6c210` |
| `146E8AC16` | Twin epilog only: insert `mov al,1` (vanilla omitted it) |
| `146E0C910` / `0C150` / `0CE30` | Fail-object builders (show-only; not 54c80) |
| `23750` / `23820`… | Show UI stubs |
| `146E7D81D` / `7E08B` | Toast switch → `mov al,1` + JMP epilog (not case 8 / Fehlercode Alpha) |
| `146E7D817` / `7E085` | Type-table JNZ long-path → NOP |
| `146E5CEBC` | **vanilla** `call 54c80` — do **not** retarget 55200 (class-C spinner) |
| `146E5CEA6` | **force rsi=0** (`xor esi,esi`+NOPs) — manager `+0x238` non-null offline → was CFAD fail |
| `146EF1BAB` / `F1D62` / `F2063` | B2 status/Alpha: NOP jne / JMP epilog / NOP je |
| ~~`146E805E7` / `7F9F7` twin NOP~~ | **reverted** — forced 55200 → spinner |
| ~~`146E7A2B0` JMP cleanup~~ | **reverted** — skipped fail-attach → spinner |
| `146E4AF00` | **Binder LIVE** (was wrongly stubbed; completes login UI) |
| `146E14F57` | OSS setter: always `+0x2fc = 1` |
| `146E5DBEC` / `EEF5AC` | LoginWithUI clear → write 1 (not 0) |
| `146E881A4` / `58A63` / … | direct `+0x2fc` readers → imm 1 |
| `146A89470` | AutoLogin: **`mov al,1; ret`** (not `[rax+0xd0]`, not empty-`5CCB0`) |
| `146A89450` | `jmp 89470` (slot +0xd0 on OSS vtbl — was recursive) |
| `147017d66` | Null-vcall guard: skip `call [vtbl+0x4e0]` / fail-arm → empty @`d83` (E714 RIP=0) |
| ~~`146E5CEA9` JMP CFAD~~ | **reverted** — null rsi crash/spinner |
| ~~`146E4AF00` ret stub~~ | **reverted** — spinner |
| ~~`146E64CE0` entry ret / empty title→`6c210`~~ | **reverted** — black / spinner (04i); short-circuit only @`64D08` |
| FNames `OnLoginFailed*` / Meteorite Failure | rename → Ignore/Success (Blueprint softener) |
| ~~`HaloOnline.*` / `OnlineXsapi.*` / `Common.*` loc keys~~ | **reverted** — Missing String Table Entry |

## String-table lesson (2026-08-02)

Do **not** rename FText keys `Namespace.Key` (e.g. `HaloOnline.FailedToLoginToPlatform`).
UE locres lookup misses → UI body **\"Missing String Table Entry\"**.
Safe softens: delegates, `E*::` enum names, XAL result FNames only.

## Residual fail after Enter

`54c80` builds fail object + binder completes; toast short-path skipped so no fail text.
Do **not** stub `54c80` / `91f3c0` / `4AF00` (out-params / shared poster / completion).
Do **not** force Empty-Success `55200` on null path once toast is skipped (class-C spinner).

## Runtime (das, was das Rezept tatsächlich tut)

| Komponente | Zweck |
|------------|--------|
| msvcp140 **14.40+** aus `_CommonRedist` | constexpr `std::mutex` — 14.29 = AV in `_Mtx_lock` |
| `libHttpClient` original | Real XAsync completions (stub → spinner) |
| RUNE `Offline=1` + `LoadDll` | Crack |
| `Engine.ini` nur Render-CVars | **kein** OSS-Override — `DefaultPlatformService=Null` = stiller Exit |
| `SteamDeck=1` | XAL meldet sich im Spielprozess an (kein `XALApp.exe`) |
| DirectML aus | DXCore unter Proton unvollständig |
| Steam beendet | Pflicht beim Start |
| EXE | **unverändert** |
