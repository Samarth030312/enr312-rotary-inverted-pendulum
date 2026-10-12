# ENR312 pre-power checklist

> ## STATUS: COMPLETED BY OPERATOR — 2026-08-22
>
> The operator reports that hardware inspection, electrical checks, wiring
> verification and encoder/electrical verification are **complete**, and that the
> rig is ready for flashing.
>
> **The record fields below are still blank.** The individual measured values were
> not supplied to the repository, so this document remains the procedure and the
> evidence template, not the evidence. If the numbers are recorded later, fill them
> in here — particularly E1–E3, which is the check that protects the MCU.
>
> Nothing below was measured by the assistant.

Every check here is something **only a human at the bench can answer**, and each
is deliberately short. Nothing in this list is blocked on software — the ENR312
firmware is built and flashable. These are the electrical facts the repository
cannot obtain remotely.

**Do them in order. Do not skip to E4.**
Estimated total: ~15 minutes with a multimeter.

---

## Stage 0 — before anything is plugged in

| # | Check | Why | Record |
|---|---|---|---|
| P1 | Shield silkscreen reads **X-NUCLEO-IHM01A1**; driver IC marked **L6474** | The whole pin map assumes this shield. A different IHMxx board has a different map and a different driver. | model: ______ |
| P2 | Nucleo silkscreen reads **NUCLEO-F401RE** | 512 KB / 96 KB and the pin map both depend on it. | ______ |
| P3 | Encoder body reads **LPD3806-600BM-G5-24C** | 600 PPR is baked into `ENR312_ENCODER_PPR`. A 400 or 1024 PPR unit makes every reported angle wrong by a fixed ratio and nothing will flag it. | PPR: ______ |
| P4 | 12 V PSU output measured **unloaded, disconnected from the shield** | Confirms polarity and magnitude before it reaches a bridge driver. L6474 VS range is 8–45 V. | ______ V, polarity: ______ |

## Stage 1 — IHM01A1 resistor population (the SPI routing question)

`docs/hardware/SOURCE_RECONCILIATION.md` §4 established from UM1857 that CS and
SCK are **resistor-selectable**, and that the firmware is configured for the
**factory-default** population (CS = PB6, SCK = PA5). If this board was
re-populated, SPI will not work and `a` (ARM) will report `ARM FAILED`.

| # | Check | Expected (factory default) | Record |
|---|---|---|---|
| R1 | Is **R25** fitted and **R15** empty? (UM1857 Table 3; corrected 2026-10-12, this row had them reversed) | R25 fitted → CS on PB6/D10 (default); R15 fitted → CS on PA4/A2 | R15: ___ R25: ___ |
| R2 | Is **R23** fitted and **R24** empty? | R23 fitted → SCK on PA5/D13 | R23: ___ R24: ___ |

> If either is the *other* way round, **stop** and record it. The pin map in
> `firmware/enr312/target/inc/enr312_board.h` must be changed to match the
> board; the board must not be modified to match the firmware.

## Stage 2 — ENCODER ELECTRICAL SAFETY (hard gate)

**This is the one that can destroy the MCU. Do not shortcut it.**

The LPD3806 is a **5 V open-collector** device. The firmware enables STM32
internal pull-ups on PB4/PB5 (to 3.3 V), which is correct *provided nothing else
in the harness pulls those lines up to +5 V*. If an external pull-up to +5 V
exists, PB4/PB5 see 5 V.

Whether **PB4/PB5 are 5 V-tolerant on the STM32F401RET6 is recorded as UNKNOWN**
in `docs/hardware/SOURCE_RECONCILIATION.md:160`. It has not been resolved from
the datasheet in this repository.

| # | Check | Method | Pass condition |
|---|---|---|---|
| E1 | Obtain STM32F401xD/xE datasheet, Table 10 (pin definitions). Record whether PB4 and PB5 carry the **`FT`** (five-volt tolerant) marking. | datasheet | record `FT` / not `FT` |
| E2 | With the encoder powered from +5 V and **the encoder harness NOT connected to the Nucleo**, measure encoder output A and B to ground. Rotate the pendulum slowly by hand through a full turn and record the **maximum** voltage seen on each. | multimeter, DC | see below |
| E3 | Measure resistance from each encoder output to the +5 V rail with power off. | multimeter, Ω | records whether an external pull-up exists |

**Decision rule:**

* E2 max ≤ 3.6 V on both → safe to connect. Proceed.
* E2 max ≈ 5 V **and** E1 says PB4/PB5 are `FT` → safe to connect. Proceed.
* E2 max ≈ 5 V **and** E1 says not `FT` → **STOP.** Fit a level shifter or a
  divider. Connecting is destructive.
* E1 unresolved and E2 ≈ 5 V → **STOP.** Do not guess.

Record: E1 ______  E2 A: ______ V  B: ______ V  E3 A: ______ Ω  B: ______ Ω

## Stage 3 — motor phase conductor mapping

The operator has reported the expected mapping M1A=red, M1B=blue, M2A=yellow,
M2B=orange. **Do not trust colour alone** — the pairing matters, not the colours.

| # | Check | Method | Pass condition |
|---|---|---|---|
| M1 | With the motor **disconnected from the shield**, measure resistance between every pair of the four leads. | multimeter, Ω | exactly two low-resistance pairs (a few Ω); all other combinations open |
| M2 | Confirm the two low-resistance pairs are {red, blue} and {yellow, orange} | from M1 | if not, the colour convention differs — record the actual pairs |

Record pair 1: ______ / ______  pair 2: ______ / ______

> A **phase** is a coil. Swapping the two wires *within* one pair reverses the
> motor direction; swapping wires *between* pairs makes the motor buzz and not
> turn. Only the pairing has to be right before power — direction is confirmed
> non-destructively in the first-motion test.

## Stage 4 — the rotor gain question, and how it resolves itself

The pre-hardware audit (internal notes) records conflict **C-1**: the Edukit
manual implies **17.778 steps/degree**, the UCLA code implies **8.889**.

The firmware does **not** hard-code either. `enr312_rig_config.h` derives it from
named, cited constants:

```
ENR312_MOTOR_FULL_STEPS_PER_REV  200   x  ENR312_MOTOR_MICROSTEP_DIVISOR  16
  = 3200 microsteps/rev  =  8.889 microsteps/degree
```

so the value in use is **8.889**, with visible provenance rather than a magic
number. The `+`/`-` first-motion command is exactly the experiment that settles
it — see `docs/experiments/EXP001/FIRST_FLASH.md` step 12. If the arm moves 10°
when 5° was commanded, the manual is right and `ENR312_MOTOR_FULL_STEPS_PER_REV`
becomes 400. **Do not pre-emptively apply the ×2.**

---

## Summary gate

| Gate | Condition | Status |
|---|---|---|
| **SOFTWARE FLASH READY** | image builds, links, isolated, tests pass | **YES** |
| **HARDWARE POWER READY** | P1–P4, R1–R2, E1–E3, M1–M2 performed | **YES — OPERATOR-VERIFIED** (values not recorded here) |
| **FIRST MOTION READY** | above, plus `docs/experiments/EXP001/FIRST_FLASH.md` | **YES** — executed 2026-10-12 (`results/evidence/rig_sessions/`) |

Flashing the MCU over ST-LINK requires **only USB power** and is safe with the
12 V motor supply disconnected. See `FIRST_FLASH.md`.
