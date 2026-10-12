> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`ENR312_WIRING.md`](ENR312_WIRING.md).

# Power Safety — ENR312 Rotary Inverted Pendulum

**Date:** 2026-08-20 · **Revision:** `73c7d31`

> # ⛔ NO RATING IN THIS DOCUMENT HAS BEEN VERIFIED
> **This repository contains no datasheets** (verified: 0 matching PDFs). Every maximum
> rating below is `UNKNOWN`. Nothing here has been invented to fill a gap — where a number
> is not in a repository source, it says `UNKNOWN`.

---

## 1. Voltage rails

| Rail | Nominal | Source | Feeds | **Max rating** | Evidence |
|---|---|---|---|---|---|
| +12 V | 12 V DC | Edukit PSU from 110/220 V AC mains | IHM01A1 motor bridge → stepper windings | **UNKNOWN** | handout, manual |
| +5 V | 5 V | USB / Nucleo | Encoder supply (Red lead) | **UNKNOWN** | UCLA reference |
| +3.3 V | 3.3 V | Nucleo regulator | STM32 I/O | **UNKNOWN** | STM32F4 family |
| USB 5 V | 5 V | Host PC or USB adapter | Nucleo logic, ST-LINK | **UNKNOWN** | manual |

**Current ratings for every rail: UNKNOWN.**

---

## 2. Logic levels

| Interface | Level | Evidence | Risk |
|---|---|---|---|
| STM32 GPIO | 3.3 V | STM32F4 family | — |
| L6474 SPI + control | **UNKNOWN** (assumed 3.3 V via shield headers) | — | Unquantified |
| **Encoder A/B output** | **UNKNOWN — open collector; level set by the pull-up rail** | UCLA `main.c:101` | **See §4** |

---

## 3. Polarity and connectors — destructive-failure risks

| Item | Status | Action |
|---|---|---|
| PSU barrel connector polarity | **UNKNOWN** | **Measure with a multimeter before connecting.** Reverse polarity on a 12 V motor rail is typically destructive and immediate. |
| PSU connector type | **UNKNOWN** | Confirm mechanical fit; do not force |
| Motor lead order (Blue/Red/Green/Black → −A/+A/−B/+B) | `DOC-REF`, and **the reference itself warns of vendor reversal of White and Red** | Verify direction at low speed in EXP001; a swapped phase pair reverses rotation |
| Encoder lead order (Red/Black/White/Green) | `DOC-REF` | **Reversed supply leads may destroy the encoder.** Confirm Red = +5 V, Black = GND before connecting |
| Common ground | **UNKNOWN** | Confirm continuity, PSU-negative ↔ Nucleo GND, **power off** |

---

## 4. ⚠ The encoder 5 V / 3.3 V question — resolve before connecting

**This is the most likely way to damage the MCU during bring-up.**

The chain of facts:

1. The encoder is supplied at **5 V** (`Red → 5V`, UCLA `main.c:95`).
2. Its outputs are **open collector** (`main.c:101`) — they pull *down* only; the high
   level is whatever the pull-up rail is.
3. The reference relies on the STM32's **internal** pull-up (`GPIO_PULLUP` in
   `HAL_TIM_Encoder_MspInit`), which pulls to **3.3 V** — safe.
4. **But** if the rig has an **external** pull-up fitted to the **5 V** rail, the STM32
   input sees **5 V**.
5. **Whether STM32F401 PB4/PB5 tolerate 5 V is UNKNOWN in this repository** — there is no
   datasheet.

### Required before connecting the encoder signal lines

- [ ] Obtain the **STM32F401 datasheet**; record whether PB4/PB5 are 5 V-tolerant (`FT`).
- [ ] Inspect the rig for an **external pull-up** on the encoder A/B lines. Record its
      value and which rail it goes to.
- [ ] With the encoder powered and the MCU **disconnected**, measure the **idle high
      voltage** on the A and B lines against ground.
- [ ] **If that voltage exceeds the STM32 input rating, STOP.** Do not connect. A level
      shifter or a 3.3 V pull-up is required.

> The internal pull-up is only ~40 kΩ. EXP001's prediction **P4** exists partly to detect
> the failure mode where that is too weak for the open-collector output at speed (missed
> edges). If P4 shows missed edges, an external pull-up may be needed — and it **must** go
> to 3.3 V unless 5 V tolerance has been confirmed.

---

## 5. Conditions that must hold before power is applied

- [ ] **OI-1 resolved** — rig physically identified as stepper-based (not DC servo).
- [ ] All `UNKNOWN` items in `WIRING_MAP.md` §6 resolved or explicitly accepted.
- [ ] PSU polarity measured.
- [ ] Common ground confirmed.
- [ ] Encoder idle-high voltage measured and within the STM32 input rating.
- [ ] **The firmware about to be flashed was written for the pendulum pin map.**
      The inherited vehicle firmware **must not** be flashed with the IHM01A1 fitted — see
      `WIRING_MAP.md` §5.

---

## 6. Power-sequencing — ⚠ THE SOURCES CONFLICT

| Source | Sequence |
|---|---|
| `Edukit_Student_Lab_Handout.pdf` (safety box) | *"Power the supply **on last** and **off first**."* |
| `Edukit_..._Manual.pdf` §"System Power and Data Interface" | *"Power is **first** applied to the IHM01A1… The Edukit USB cable is **then** attached."* |

**These are opposite orders for the 12 V motor supply.**

### Decision for bring-up: follow the HANDOUT — logic first, motor supply last.

Reasons, in order:
1. The handout is the **ENR312 course document** — authoritative for this course, and it
   states the rule inside an explicit safety box.
2. It is the **safer** order regardless of authority: it allows firmware, communication
   and sensors to be verified with the actuator **de-energised**, which is exactly what
   this bring-up requires.
3. The manual's order describes routine operation of an already-verified rig, not
   first-time bring-up.

**Recorded, not silently chosen.** If a later source resolves this differently, update
here first.

### Power-on
1. Confirm the 12 V supply is **OFF** and the motor is connected (never connect the motor
   with the supply on — handout).
2. Connect USB → the Nucleo boots on logic power alone.
3. Verify communication, sensors, and a **dry run** with the actuator disabled.
4. **Only then** switch the 12 V supply on.

### Power-off
1. Command the rotor to rest.
2. **12 V supply OFF first.**
3. USB off.

---

## 7. Pre-power checklist

Print this. Tick physically.

```
[ ] STM32 supply verified          -- USB 5 V present, Nucleo enumerates
[ ] External actuator supply       -- 12 V measured at the PSU output, POLARITY CONFIRMED
[ ] Sensor supply verified         -- 5 V measured at the encoder Red lead
[ ] Grounds verified               -- continuity PSU-neg <-> Nucleo GND, power off
[ ] Signal voltage verified        -- encoder A/B idle-high measured, MCU disconnected
[ ] No signal exceeds STM32 rating -- compared against the STM32F401 datasheet
[ ] No output connected to output  -- pin conflicts checked, WIRING_MAP.md section 5
[ ] Motor power DISCONNECTED during logic bring-up
[ ] Emergency shutdown available   -- 12 V switch within operator reach
[ ] Correct firmware              -- built for the PENDULUM pin map, not the vehicle
[ ] Swing path clear
[ ] Second person present          -- REQUIRED for EXP005 (inverted)
```

**Every box must be ticked from a physical observation, not from this document.**

---

## 8. Emergency procedure

| Symptom | Action |
|---|---|
| Motor buzzing, stalling, or hot | **Cut 12 V immediately** |
| Arm running toward a limit | **Cut 12 V** |
| Pendulum oscillation growing | **Cut 12 V** — feedback sign inverted |
| Burning smell, smoke, discoloration | **Cut mains**, then investigate |
| Anything unexpected | **Cut power first, diagnose second** |

The 12 V switch is the primary emergency control and must stay within the operator's reach
throughout every powered run.
