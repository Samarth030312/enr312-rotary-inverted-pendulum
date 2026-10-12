> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`ENR312_WIRING.md`](ENR312_WIRING.md).

# Hardware Inventory — ENR312 Rotary Inverted Pendulum

**Date:** 2026-08-20 · **Repository revision:** `73c7d31` · **Status: NOT PHYSICALLY VERIFIED**

> ## ⚠ NOTHING IN THIS DOCUMENT HAS BEEN SEEN
> Every entry is transcribed from repository sources. No hardware has ever been attached
> to this machine (`st-info --probe` → 0 programmers). **No component has been physically
> identified.** Confirm each row against the parts in front of you before connecting
> anything.

---

## Confidence vocabulary

| Level | Meaning |
|---|---|
| **COURSE** | Stated by an ENR312 course document (handout/manual). Authoritative for *what the student is issued*. |
| **REFERENCE** | From the UCLA Edukit project. Same shield and MCU, so a strong prior — **but not this rig**. |
| **LOCAL** | Read directly from this repository's own firmware/`.ioc`. Authoritative for the *vehicle* application only. |
| **UNKNOWN** | Not present in any repository source. **Must be physically verified or obtained from a datasheet.** |

**No row in this document is `PHYSICALLY VERIFIED`.** That column stays `NO` until a human
inspects the rig.

---

## 1. System-level

| Field | Value | Source | Confidence |
|---|---|---|---|
| Rig name | STEVAL-EDUKIT01 | `Edukit_Student_Lab_Handout.pdf` | COURSE |
| Composition | NUCLEO-F401RE + X-NUCLEO-IHM01A1 + NEMA17 stepper + encoder | handout | COURSE |
| Supply | 12 V DC (motor) + USB 5 V (logic) | handout + manual | COURSE |
| Mains input to PSU | 110 V or 220 V AC | manual §"System Power and Data Interface" | COURSE |
| Control rate | 500 Hz (2 ms) | handout | COURSE |
| Assembly guide | **UNKNOWN** — manual links to external guides not present in this repository | manual line 3289 | UNKNOWN |

> **⚠ OPEN ITEM OI-1 — RIG IDENTITY IS DISPUTED.** `docs/references/ENR312.pdf` (the
> course outline) describes sessions 9–10 as an inverted pendulum driven by a **DC servo
> motor**, not a stepper. The lab handout names the STEVAL-EDUKIT01 with a NEMA17 stepper.
> **These cannot both be true.** Resolve by inspection *before* anything else.

---

## 2. Processor board

| Field | Value | Source | Confidence |
|---|---|---|---|
| Manufacturer / model | STMicroelectronics NUCLEO-F401RE | handout, manual | COURSE |
| MCU | STM32F401RETx, Cortex-M4F | `.ioc`, `Makefile`, linker script | **LOCAL** |
| Core clock | 84 MHz (HSI 16 MHz → PLL M=8, N=84, P=2) | `Core/Src/main.c` `SystemClock_Config` | **LOCAL** |
| Flash / RAM | 512 KB / 96 KB | `STM32F401RETX_FLASH.ld` | **LOCAL** |
| Logic level | 3.3 V | implied by STM32F4 family | **UNKNOWN** — no datasheet in repo |
| 5 V-tolerant pins | **UNKNOWN** | — | **UNKNOWN — MUST BE VERIFIED** |
| Logic supply | USB 5 V, or from the shield | manual | COURSE |
| Programmer | On-board ST-LINK over USB | manual | COURSE |

> The MCU identity is the **one** hardware fact this repository can assert with local
> evidence: this project's own firmware builds and links for STM32F401RETx.

---

## 3. Motor driver shield

| Field | Value | Source | Confidence |
|---|---|---|---|
| Model | X-NUCLEO-IHM01A1 | handout, manual | COURSE |
| Driver IC | STMicroelectronics L6474 | manual §4 | COURSE |
| Mounting | Arduino-style headers on the Nucleo | manual | COURSE |
| Interface to MCU | SPI + GPIO (STCK, DIR, RESET, FLAG, CS) | UCLA BSP | REFERENCE |
| Microstepping | 1/16 (`L6474_STEP_SEL_1_16`) | `l6474_target_config.h:177` | REFERENCE |
| Phase current (TVAL) | **800 mA** | `l6474_target_config.h:105` | REFERENCE |
| Overcurrent threshold (OCD_TH) | **2250 mA** | `l6474_target_config.h:146` | REFERENCE |
| `TON_MIN` / `TOFF_MIN` | 3 / 3 (register units) | `l6474_target_config.h:126,133` | REFERENCE |
| Motor supply input | 12 V (from the Edukit PSU) | handout | COURSE |
| Max motor supply rating | **UNKNOWN** | — | **UNKNOWN — no datasheet in repo** |
| Logic supply | **UNKNOWN** (assumed from Nucleo) | — | **UNKNOWN** |

> **The TVAL and OCD values are the reference rig's settings, not a measured property of
> your motor.** The motor is rated 2.0 A/phase (below); the reference runs it at 0.8 A.
> **Do not raise TVAL without a thermal justification.**

---

## 4. Stepper motor

| Field | Value | Source | Confidence |
|---|---|---|---|
| Model | NEMA-17 **17HS19-2004S** | UCLA `main.c:77` | REFERENCE |
| Family | NEMA-17 | handout | COURSE |
| Full-step angle | 1.8° (200 steps/rev) | implied by NEMA-17 standard | REFERENCE |
| Rated current | **2.0 A/phase** (from the `-2004S` suffix) | part number | REFERENCE |
| Operating current as configured | 0.8 A (TVAL) | `l6474_target_config.h` | REFERENCE |
| Holding torque | **UNKNOWN** | — | **UNKNOWN** |
| Winding resistance / inductance | **UNKNOWN** | — | **UNKNOWN** |
| Lead colours → IHM01A1 terminals | Blue→−A, Red→+A, Green→−B, Black→+B | UCLA `main.c:79–88` | REFERENCE |
| Extension-cable variant | White replaces Blue | UCLA `main.c:90` | REFERENCE |

> **⚠ WIRING WARNING TRANSCRIBED FROM THE REFERENCE** (`main.c:88–91`):
> *"Please note that motors have been received from the vendor showing reversal of Motor
> White and Motor Red. Check rotor operation after assembly and in initial testing."*
> **Treat the lead-colour mapping as unverified.**

---

## 5. Pendulum angle encoder

| Field | Value | Source | Confidence |
|---|---|---|---|
| Model | **LPD3806-600BM-G5-24C** | UCLA `main.c:76`, manual | REFERENCE + COURSE |
| Type | Incremental quadrature optical, 2-channel (A/B) | manual | COURSE |
| Resolution | 600 pulses/rev → **2400 counts/rev** with X4 decode | manual, UCLA | COURSE + REFERENCE |
| Angular resolution | 0.15 °/count = 6.667 counts/° | manual Table 2 | COURSE |
| Output type | **Open collector** — requires pull-up | UCLA `main.c:101` | REFERENCE |
| Supply | 5 V (Red = 5 V, Black = GND) | UCLA `main.c:95–98` | REFERENCE |
| Signal leads | White → "GPIO Dir3", Green → "GPIO Dir2" | UCLA `main.c:97–98` | REFERENCE |
| Supply voltage rating range | **UNKNOWN** (`-G5-` suffix suggests 5 V) | — | **UNKNOWN** |
| Output logic level | **UNKNOWN** — open collector, so it is set by the pull-up rail | — | **UNKNOWN — CRITICAL, see below** |
| Current draw | **UNKNOWN** | — | **UNKNOWN** |
| Index (Z) channel | **UNKNOWN** — not used by the reference | — | **UNKNOWN** |

> ## ⚠ THE MOST DANGEROUS UNKNOWN IN THIS INVENTORY
> The encoder is supplied at **5 V** and its outputs are **open collector**. An open-collector
> output pulled up to **5 V** would present **5 V to an STM32 input**.
>
> The UCLA reference relies on the STM32's **internal** pull-up, which pulls to **3.3 V** —
> safe. But if the rig has an **external** pull-up fitted to the 5 V rail, the input sees
> 5 V.
>
> **Whether STM32F401 PB4/PB5 are 5 V-tolerant is UNKNOWN in this repository — no datasheet
> is present.** Do not connect the encoder signal lines until this is resolved from the
> STM32F401 datasheet *and* the actual pull-up arrangement is inspected. See
> `POWER_SAFETY.md` §4.

---

## 6. Power supply

| Field | Value | Source | Confidence |
|---|---|---|---|
| Type | Edukit DC power supply unit | manual | COURSE |
| Output | 12 V DC | handout | COURSE |
| Current rating | **UNKNOWN** | — | **UNKNOWN** |
| Connector type / polarity | **UNKNOWN** | — | **UNKNOWN — MUST BE VERIFIED** |
| Mains input | 110 V or 220 V AC | manual | COURSE |

> **Connector polarity is UNKNOWN and is a destructive-failure risk.** Verify with a
> multimeter before connecting. See `POWER_SAFETY.md` §3.

---

## 7. Mechanical

| Field | Value | Source | Confidence |
|---|---|---|---|
| Rotor arm length `r` | **0.14 m** | manual Table 2 | COURSE |
| Pendulum length `l` | **0.235 m** (vertical separation, rotor arm → pendulum mass) | manual Table 2 | COURSE |
| Pendulum mass | **UNKNOWN** | — | **UNKNOWN** |
| Rotor inertia `I_rotor` | **UNKNOWN** (appears only inside a lumped term) | — | **UNKNOWN** |
| Coupling (motor → arm) | **UNKNOWN** — direct drive assumed, not stated | — | **UNKNOWN** |
| Gear ratio | **UNKNOWN** — no gearbox mentioned anywhere | — | **UNKNOWN** |

> **⚠ CONFLICT.** The manual gives `l = 0.235 m`, but Tutorials 5/12 give `ω_g²` values
> (55.85 and 57.01 (rad/s)²) which, through `ω_g² = g/(L·0.6805)`, imply
> **L ≈ 0.253–0.258 m**. These may be different quantities (a physical separation versus an
> effective model length) or an inconsistency. **Recorded, not resolved** — see
> `PHYSICAL_PARAMETERS.md`.

---

## 8. Not present and not required

| Item | Note |
|---|---|
| Rotor angle sensor | **None exists, by design.** The rotor position is *commanded and remembered*, not measured (EXP001 §2.1). |
| Current sensing | Not exposed to the application |
| Limit switches | **UNKNOWN** — none referenced anywhere. Travel limits are enforced in software only |
| Index/home switch | **UNKNOWN** — none referenced |

---

## 9. Documentation gaps

**No datasheet of any kind exists in this repository** (`find docs -iname '*.pdf'` matching
datasheet/L6474/IHM01A1/Nucleo/LPD3806/17HS19 → **0**).

Before power-up, obtain and record:

1. **STM32F401 datasheet** — 5 V tolerance of PB4/PB5. *Blocking for encoder connection.*
2. **X-NUCLEO-IHM01A1 user manual** — motor supply range, jumper configuration, logic rails.
3. **LPD3806 datasheet** — supply range, output configuration, required pull-up.
4. **17HS19-2004S datasheet** — winding resistance/inductance, holding torque, thermal limits.
5. **Edukit assembly guide** — referenced by the manual but not in this repository.

Until these exist, every `UNKNOWN` above stays `UNKNOWN`.
